import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/app_preferences.dart';
import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/verse.dart';
import '../screens/chapter_screen.dart';
import '../screens/lexique_screen.dart';
import 'reader_actions_bar.dart';
import 'study_sheet.dart';
import 'verse_tile.dart';

/// A reading position to jump to (book, chapter, verse number).
class VerseTarget {
  final int bookIndex;
  final int chapter;
  final int verse;

  const VerseTarget({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
  });
}

/// The reading body of a chapter (toggle bar + verse list + interactions).
///
/// Designed to be embedded anywhere (tab content, standalone screen) without
/// depending on an outer Scaffold: multi-select mode renders its own bottom bar.
class ChapterReader extends StatefulWidget {
  final int bookIndex;
  final int chapter;

  /// When set, scrolls to and flashes the verse of a [VerseTarget] addressed
  /// to this chapter. Works both for newly-opened tabs (read in `initState`)
  /// and already-open ones (listened to live).
  final ValueListenable<VerseTarget?>? jumpToVerse;

  /// Optional way to open another chapter from the books navigation; when null
  /// the standalone [ChapterScreen] flow is used (push a new screen).
  final void Function(int bookIndex, int chapter)? onOpenChapter;

  /// Opens the Bibliothèque destination. Null when the reader is shown outside
  /// the bottom-nav shell (tests, standalone [ChapterScreen]): the sheet then
  /// falls back to naming the Bibliothèque without offering to go there.
  final VoidCallback? onOpenLibrary;

  /// Where downloaded versions are read from. Injectable so a test can serve
  /// them from memory: a real read goes through `dart:io`, which never
  /// completes inside the `testWidgets` fake-async zone.
  final LibraryStore? store;

  const ChapterReader({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.jumpToVerse,
    this.onOpenChapter,
    this.onOpenLibrary,
    this.store,
  });

  @override
  State<ChapterReader> createState() => _ChapterReaderState();
}

class _ChapterReaderState extends State<ChapterReader> {
  late final LibraryStore _library = widget.store ?? LibraryStore();
  late final VersionRepository _versions = VersionRepository(store: _library);
  final AppDatabase _db = AppDatabase();

  late Future<BibleBook> _bookFuture;
  AppPreferences _prefs = AppPreferences();
  bool _prefsLoaded = false;

  /// Version being read; BYM until the preferences answer.
  String _versionCode = VersionRepository.embeddedCode;

  /// What the device holds, for the « Version » sheet.
  Map<String, InstalledVersion> _installed = const {};

  Map<int, String> _highlights = {};
  Set<int> _favorites = {};
  Set<int> _userNotes = {};

  final Set<int> _selected = {};
  bool get _multiMode => _selected.isNotEmpty;

  /// Verse to scroll to (matching this chapter), exposed via [_jumpKey].
  int? _targetVerse;
  final GlobalKey _jumpKey = GlobalKey();
  final ScrollController _verseScroll = ScrollController();
  Set<int> _flashingVerses = {};
  Timer? _flashTimer;

  /// Neighbouring reading positions, resolved once the book is known: null
  /// while loading, and at the two ends of the Bible.
  (int, int)? _previous;
  (int, int)? _next;

  @override
  void initState() {
    super.initState();
    _bookFuture = _bootstrap();
    _loadUserData();
    _loadNeighbours();
    widget.jumpToVerse?.addListener(_onJumpChanged);
    _onJumpChanged(); // covers a chapter opened fresh with the target preset
    LibraryStore.revision.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    widget.jumpToVerse?.removeListener(_onJumpChanged);
    LibraryStore.revision.removeListener(_onLibraryChanged);
    _flashTimer?.cancel();
    _verseScroll.dispose();
    super.dispose();
  }

  /// A download finished or a version was deleted while this reader was alive.
  ///
  /// The reader sits in the tab shell's `IndexedStack`, so it is never rebuilt
  /// from scratch: without this the « Version » sheet kept the map read at
  /// `initState` and answered « à télécharger » for a version the Bibliothèque
  /// had just installed.
  Future<void> _onLibraryChanged() async {
    final installed = await _installedVersions();
    if (!mounted) return;

    final reading = _versionCode;
    final embedded = reading == VersionRepository.embeddedCode;
    // Deliberately compared before and after: `saveBook` bumps the revision on
    // every one of the 66 books, and re-reading the file each time would hit the
    // disk 65 times for nothing.
    final had = _installed[reading]?.has(widget.bookIndex) ?? false;
    final has = installed[reading]?.has(widget.bookIndex) ?? false;

    setState(() => _installed = installed);
    if (embedded) return;

    // The version being read just lost its files → fall back instead of serving
    // a text whose files are gone (`VersionRepository.forget` dropped the cache,
    // so the next read would throw).
    if (installed[reading]?.isEmpty != false) {
      _switchVersion(VersionRepository.embeddedCode);
      return;
    }
    // This book just landed: retry so the « non téléchargé » panel gives way.
    if (!had && has) {
      setState(() {
        _bookFuture = _versions.loadBook(reading, widget.bookIndex);
      });
    }
  }

  void _onJumpChanged() {
    final target = widget.jumpToVerse?.value;
    if (target == null) return;
    if (target.bookIndex != widget.bookIndex ||
        target.chapter != widget.chapter) {
      return;
    }
    _beginJump(target.verse);
  }

  void _beginJump(int verseNumber) {
    setState(() {
      _targetVerse = verseNumber;
      _flashingVerses = {verseNumber};
    });
    // The flash is armed only once the verse is on screen (see
    // [_scrollToTarget]): clearing it on a timer started here would detach
    // [_jumpKey] mid-scroll on a long chapter.
    _flashTimer?.cancel();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToTarget(verseNumber));
  }

  /// Brings the target verse into view, building it first if needed.
  ///
  /// [ChapterVerseList] is a lazy `ListView.builder`, so [_jumpKey] only exists
  /// once the target tile has been built — which for a far verse ("Jean 3:16"
  /// opened from the search, or the verse picker on a long chapter) it has not.
  /// Waiting on the key alone silently did nothing beyond the cache extent.
  ///
  /// So the list is first driven to the verse's estimated offset. That estimate
  /// comes from `maxScrollExtent`, which a lazy list refines as more tiles get
  /// measured, hence the loop: each jump improves the next guess. As soon as
  /// the tile exists, [Scrollable.ensureVisible] does the precise placement.
  Future<void> _scrollToTarget(int verseNumber) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // Near verses are already built — no need to move the list blindly.
    if (!await _revealBuiltTarget()) {
      final chapter = await _activeChapter();
      if (!mounted) return;

      // Must match what [ChapterVerseList] actually built, or the offset
      // estimate below is off by one tile on a downloaded version.
      final hasHeader = _showsBookHeader;
      // Mirrors the numbering ChapterVerseList uses when a verse carries no
      // explicit number.
      var verseIndex = -1;
      for (var i = 0; i < chapter.verses.length; i++) {
        final v = chapter.verses[i];
        if ((v.number == 0 ? i + 1 : v.number) == verseNumber) {
          verseIndex = i;
          break;
        }
      }
      if (verseIndex >= 0 && _verseScroll.hasClients) {
        final itemCount = chapter.verses.length + (hasHeader ? 1 : 0);
        final itemIndex = verseIndex + (hasHeader ? 1 : 0);

        for (var attempt = 0; attempt < 12; attempt++) {
          final position = _verseScroll.position;
          final fraction = itemCount <= 1 ? 0.0 : itemIndex / (itemCount - 1);
          final estimate = position.maxScrollExtent * fraction;
          _verseScroll.jumpTo(estimate.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ));
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          if (_jumpKey.currentContext != null) break;
        }
      }
      await _revealBuiltTarget();
      if (!mounted) return;
    }

    _flashTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() {
        _flashingVerses = {};
        _targetVerse = null;
      });
    });
  }

  /// Scrolls the target verse into place, or returns false if it is not built.
  Future<bool> _revealBuiltTarget() async {
    final ctx = _jumpKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.35,
    );
    return true;
  }

  /// Whether chapter 1 opens on the book header (metadata grid + introduction).
  ///
  /// Keyed on the **format**, not on the code: those fields come from the BYM
  /// schema, and a version downloaded from getbible carries text and nothing
  /// else, so `bookFromGetbible` fills them with empty strings. Rendering the
  /// card anyway showed a title over four blank cells — the reader reads that as
  /// a bug, not as an absence. A BYM-format version served from elsewhere would
  /// have them, and gets the header.
  bool get _showsBookHeader => widget.chapter == 1 && _supportsNotes;

  /// Whether the version being read carries notes at all.
  ///
  /// Same source as [_showsBookHeader]: `bookFromGetbible` sets `textWithNotes`
  /// to the bare text and leaves `notes` empty, so « Texte + notes » on a
  /// downloaded getbible version toggled between two identical renderings — a
  /// menu that answers nothing reads as broken.
  ///
  /// Deliberately a *display* guard, not a write to the preference: the choice
  /// belongs to the reader and is found again when the reading returns to a
  /// version that has notes.
  bool get _supportsNotes => versionByCode(_versionCode)?.carriesNotes ?? false;

  /// Reads the preferences and the library, *then* the book.
  ///
  /// In that order because the preferences carry the active version: loading
  /// the BYM first would flash the wrong translation on screen for a frame.
  Future<BibleBook> _bootstrap() async {
    final prefs = await AppPreferences.load();
    final installed = await _installedVersions();
    // A version deleted from the Bibliothèque since the last read would leave
    // the reader stuck on an error panel — fall back to the embedded BYM.
    final code = prefs.versionCode == VersionRepository.embeddedCode ||
            installed[prefs.versionCode]?.isEmpty == false
        ? prefs.versionCode
        : VersionRepository.embeddedCode;

    if (mounted) {
      setState(() {
        _prefs = prefs;
        _prefsLoaded = true;
        _installed = installed;
        _versionCode = code;
      });
    }
    return _versions.loadBook(code, widget.bookIndex);
  }

  /// The chapter on screen, in the active version. Empty rather than throwing
  /// when the version lacks the book: the callers (verse jump, verse picker)
  /// only need something to count, and the body already says what is missing.
  Future<Chapter> _activeChapter() async {
    try {
      return await _versions.loadChapter(
          _versionCode, widget.bookIndex, widget.chapter);
    } on BookNotDownloaded {
      return Chapter(chapter: widget.chapter, verses: const []);
    }
  }

  Future<Map<String, InstalledVersion>> _installedVersions() async {
    try {
      return await _library.installed();
    } catch (_) {
      // No registry available → reading stays on the embedded BYM.
      return const {};
    }
  }

  /// Switches the version being read, keeping book and chapter.
  void _switchVersion(String code) {
    if (code == _versionCode) return;
    setState(() {
      _versionCode = code;
      _bookFuture = _versions.loadBook(code, widget.bookIndex);
      _targetVerse = null;
      _flashingVerses = {};
    });
    _prefs.versionCode = code;
    _savePrefs();
  }

  /// Resolves the previous / next reading positions so the bar's arrows can be
  /// enabled or greyed. Crossing a book boundary parses the neighbour book,
  /// which the cache then keeps for the actual navigation.
  Future<void> _loadNeighbours() async {
    final previous =
        await _versions.previousChapter(widget.bookIndex, widget.chapter);
    final next =
        await _versions.nextChapter(widget.bookIndex, widget.chapter);
    if (!mounted) return;
    setState(() {
      _previous = previous;
      _next = next;
    });
  }

  Future<void> _loadUserData() async {
    try {
      final highlights = await _db.highlightsInChapter(
          widget.bookIndex, widget.chapter);
      final favorites = await _db.favoritesInChapter(
          widget.bookIndex, widget.chapter);
      final notes = await _db.notesInChapter(widget.bookIndex, widget.chapter);
      if (!mounted) return;
      setState(() {
        _highlights = highlights;
        _favorites = favorites;
        _userNotes = notes;
      });
    } catch (_) {
      // DB unavailable (e.g. web) → reading stays functional without user data.
    }
  }

  Future<void> _savePrefs() async {
    if (!_prefsLoaded) return;
    await _prefs.save();
  }

  void _setNotesMode(bool value) {
    if (_prefs.notesMode == value) return;
    setState(() => _prefs.notesMode = value);
    _savePrefs();
  }

  void _setDisposition(NoteDisposition value) {
    if (_prefs.disposition == value) return;
    setState(() => _prefs.disposition = value);
    _savePrefs();
  }

  void _setFontSize(double value) {
    if (_prefs.fontSize == value) return;
    setState(() => _prefs.fontSize = value);
    _savePrefs();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ReaderActionsBar(
          bookIndex: widget.bookIndex,
          chapter: widget.chapter,
          versionCode: _versionCode,
          installedVersions: _installed,
          onSelectVersion: _switchVersion,
          onOpenLibrary: widget.onOpenLibrary,
          onOpenChapter: _openChapter,
          onVerses: _openVersePicker,
          onPreviousChapter: _stepTo(_previous),
          onNextChapter: _stepTo(_next),
          trailing: _DisplayMenu(
            notesMode: _prefs.notesMode,
            notesAvailable: _supportsNotes,
            disposition: _prefs.disposition,
            fontSize: _prefs.fontSize,
            onNotesMode: _setNotesMode,
            onDisposition: _setDisposition,
            onFontSize: _setFontSize,
          ),
        ),
        Expanded(
          child: FutureBuilder<BibleBook>(
            future: _bookFuture,
            builder: (context, snapshot) {
              final error = snapshot.error;
              if (error is BookNotDownloaded) {
                return _MissingBookPanel(
                  error: error,
                  onReadEmbedded: () =>
                      _switchVersion(VersionRepository.embeddedCode),
                  onOpenLibrary: widget.onOpenLibrary,
                );
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erreur : $error'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final book = snapshot.data!;
              final chapter = book.chapters.firstWhere(
                (c) => c.chapter == widget.chapter,
                orElse: () => const Chapter(chapter: 0, verses: []),
              );
              if (chapter.verses.isEmpty && widget.chapter != 1) {
                return const Center(child: Text('Chapitre vide.'));
              }
              return ChapterVerseList(
                chapter: chapter,
                showNotes: _prefs.notesMode && _supportsNotes,
                disposition: _prefs.disposition,
                fontSize: _prefs.fontSize,
                header: _showsBookHeader ? _BookHeader(book: book) : null,
                highlightOf: (vn) => _highlights[vn],
                isFavoriteOf: (vn) => _favorites.contains(vn),
                hasNoteOf: (vn) => _userNotes.contains(vn),
                selectedVerses: _selected,
                jumpVerse: _targetVerse,
                jumpKey: _jumpKey,
                controller: _verseScroll,
                flashingVerses: _flashingVerses,
                onVerseTap: _onVerseTap,
                onVerseLongPress: _onVerseLongPress,
              );
            },
          ),
        ),
        if (_multiMode)
          _EndSelectionBar(
            count: _selected.length,
            onDone: () => setState(() => _selected.clear()),
          ),
      ],
    );
  }

  Future<void> _onVerseTap(Verse verse) async {
    if (_multiMode) {
      setState(() {
        if (!_selected.remove(verse.number)) _selected.add(verse.number);
      });
      return;
    }
    final vn = verse.number;
    final action = await showStudySheet(
      context,
      reference:
          '${catalogEntry(widget.bookIndex).abbreviation} ${verse.verse}',
      excerpt: verse.text,
      isFavorite: _favorites.contains(vn),
      currentHighlight: _highlights[vn],
      hasNotes: verse.notes.isNotEmpty,
      noteCount: verse.notes.length,
      onHighlight: (color) => _applyHighlight(vn, color),
      onFavorite: (value) => _applyFavorite(vn, value),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case StudyAction.lexicon:
        _openLexique(vn);
        break;
      case StudyAction.note:
        await _editNote(verse);
        break;
      case StudyAction.copy:
        await Clipboard.setData(
            ClipboardData(text: '${verse.verse} ${verse.text}'));
        _snack('Versets copiés.');
        break;
      case StudyAction.compare:
        _snack('Comparaison — bientôt disponible.');
        break;
      case StudyAction.references:
        _snack('Références — bientôt disponible.');
        break;
      case StudyAction.listen:
        _snack('Audio — bientôt disponible.');
        break;
      case StudyAction.share:
        _snack('Partage — bientôt disponible.');
        break;
    }
  }

  /// Applies a colour picked in the study sheet, or clears it when null.
  ///
  /// The map must **lose** the key rather than hold an empty string: an empty
  /// string is not null, so [VerseTile] would still read it as a highlight and
  /// `_parseColor('')` would fall back to amber — an un-highlighted verse
  /// repainted itself until the chapter was reloaded from SQLite.
  Future<void> _applyHighlight(int verseNumber, String? color) async {
    await _db.setHighlight(
        widget.bookIndex, widget.chapter, verseNumber, color);
    if (!mounted) return;
    setState(() {
      if (color == null || color.isEmpty) {
        _highlights.remove(verseNumber);
      } else {
        _highlights[verseNumber] = color;
      }
    });
  }

  Future<void> _applyFavorite(int verseNumber, bool value) async {
    await _db.setFavorite(
        widget.bookIndex, widget.chapter, verseNumber, value);
    if (!mounted) return;
    setState(() {
      if (value) {
        _favorites.add(verseNumber);
      } else {
        _favorites.remove(verseNumber);
      }
    });
  }

  void _onVerseLongPress(Verse verse) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selected.clear();
      _selected.add(verse.number);
    });
  }

  /// Opens the chapter picked in the « Livres » sheet: inside the tab system
  /// when hosted there, as a pushed [ChapterScreen] otherwise.
  void _openChapter(int bookIndex, int chapter) {
    final cb = widget.onOpenChapter;
    if (cb != null) {
      cb(bookIndex, chapter);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChapterScreen(bookIndex: bookIndex, chapter: chapter),
      ),
    );
  }

  /// Callback for one of the bar's arrows, or null when [position] is null —
  /// which greys the button out at the two ends of the Bible (and while the
  /// neighbours are still being resolved).
  VoidCallback? _stepTo((int, int)? position) {
    if (position == null) return null;
    return () => _openChapter(position.$1, position.$2);
  }

  Future<void> _openVersePicker() async {
    final chapter = await _activeChapter();
    if (!mounted) return;
    await showVersePickerSheet(
      context,
      chapter,
      currentVerse: _targetVerse,
      onSelect: _beginJump,
    );
  }

  Future<void> _editNote(Verse verse) async {
    final vn = verse.number;
    final existing = await _db.getNote(widget.bookIndex, widget.chapter, vn);
    if (!mounted) return;
    final controller = TextEditingController(text: existing?.text ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Note — ${verse.verse}'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Écrire une note…'),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final nav = Navigator.of(context);
                await _db.deleteNote(widget.bookIndex, widget.chapter, vn);
                if (!mounted) return;
                _userNotes.remove(vn);
                setState(() {});
                nav.pop(true);
              },
              child: const Text('Supprimer'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                Navigator.of(context).pop();
              } else {
                Navigator.of(context).pop(true);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (save == true && controller.text.trim().isNotEmpty) {
      await _db.saveNote(
          widget.bookIndex, widget.chapter, vn, controller.text.trim());
      _userNotes.add(vn);
      setState(() {});
      _snack('Note enregistrée.');
    } else if (save == true) {
      _userNotes.remove(vn);
      setState(() {});
    }
    controller.dispose();
  }

  void _openLexique(int verseNumber) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LexiqueScreen(
          bookIndex: widget.bookIndex,
          chapter: widget.chapter,
          verseNumber: verseNumber,
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
  }
}

/// Shown instead of the verses when the active version has not downloaded this
/// book — the normal state of a partial install.
///
/// Says which book and which version, and offers the two things that resolve
/// it: read it in the embedded BYM now, or go finish the download. Falling back
/// silently would print BYM text under the other version's label.
class _MissingBookPanel extends StatelessWidget {
  final BookNotDownloaded error;
  final VoidCallback onReadEmbedded;

  /// Null outside the bottom-nav shell — the Bibliothèque is then only named.
  final VoidCallback? onOpenLibrary;

  const _MissingBookPanel({
    required this.error,
    required this.onReadEmbedded,
    this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download_outlined,
                size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              error.message,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Terminez le téléchargement depuis la Bibliothèque pour lire ce '
              'livre en ${error.code}.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: .7),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: onReadEmbedded,
                  child: const Text('Lire en BYM'),
                ),
                if (onOpenLibrary != null)
                  TextButton.icon(
                    onPressed: onOpenLibrary,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Bibliothèque'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _DisplayChoice { textOnly, textWithNotes, inline, below }

/// The ⋯ menu of the reading bar (maquette `modif/3boutons.jpg`): the v4
/// « Texte seul / Texte + notes » toggle, the note disposition and the reading
/// text size, folded into the single action row instead of a second bar.
///
/// The size ladder is not made of menu values — it is the chip row of
/// [_TextSizeRow], which pops the menu itself.
class _DisplayMenu extends StatelessWidget {
  final bool notesMode;

  /// False on a downloaded version, which carries no notes: the four note
  /// entries collapse into one disabled line naming the reason. Greying them out
  /// in place would leave five dead rows in a popup that then holds nothing but
  /// the size ladder.
  final bool notesAvailable;
  final NoteDisposition disposition;
  final double fontSize;
  final ValueChanged<bool> onNotesMode;
  final ValueChanged<NoteDisposition> onDisposition;
  final ValueChanged<double> onFontSize;

  const _DisplayMenu({
    required this.notesMode,
    required this.notesAvailable,
    required this.disposition,
    required this.fontSize,
    required this.onNotesMode,
    required this.onDisposition,
    required this.onFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final currentSize = ReadingTextSize.nearest(fontSize);
    return PopupMenuButton<_DisplayChoice>(
      tooltip: 'Affichage du texte',
      icon: const Icon(Icons.more_vert),
      onSelected: (choice) {
        switch (choice) {
          case _DisplayChoice.textOnly:
            onNotesMode(false);
            break;
          case _DisplayChoice.textWithNotes:
            onNotesMode(true);
            break;
          case _DisplayChoice.inline:
            onDisposition(NoteDisposition.inline);
            break;
          case _DisplayChoice.below:
            onDisposition(NoteDisposition.below);
            break;
        }
      },
      itemBuilder: (context) => [
        if (notesAvailable) ...[
          CheckedPopupMenuItem<_DisplayChoice>(
            value: _DisplayChoice.textOnly,
            checked: !notesMode,
            child: const Text('Texte seul'),
          ),
          CheckedPopupMenuItem<_DisplayChoice>(
            value: _DisplayChoice.textWithNotes,
            checked: notesMode,
            child: const Text('Texte + notes'),
          ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem<_DisplayChoice>(
            value: _DisplayChoice.inline,
            checked: disposition == NoteDisposition.inline,
            child: const Text('Notes à la suite'),
          ),
          CheckedPopupMenuItem<_DisplayChoice>(
            value: _DisplayChoice.below,
            checked: disposition == NoteDisposition.below,
            child: const Text('Notes sous le verset'),
          ),
        ] else
          PopupMenuItem<_DisplayChoice>(
            // One line that says why, rather than four greyed entries the
            // reader would try before concluding the menu is broken.
            enabled: false,
            child: Text(
              'Notes — BYM uniquement',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_DisplayChoice>(
          // Not selectable itself: the chips inside carry the taps.
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: _TextSizeRow(current: currentSize, onFontSize: onFontSize),
        ),
      ],
    );
  }
}

/// The reading-size ladder, as one compact row of preview chips.
///
/// Six full-height menu entries pushed the largest option off the screen —
/// precisely the option a reader with failing eyesight would have had to scroll
/// to find. Each chip shows an « A » drawn at the size it selects (capped so a
/// 30 pt chip does not tower over the row).
class _TextSizeRow extends StatelessWidget {
  final ReadingTextSize current;
  final ValueChanged<double> onFontSize;

  const _TextSizeRow({required this.current, required this.onFontSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Taille du texte',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final size in ReadingTextSize.values)
              _SizeChip(
                size: size,
                selected: size == current,
                onTap: () {
                  onFontSize(size.fontSize);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _SizeChip extends StatelessWidget {
  final ReadingTextSize size;
  final bool selected;
  final VoidCallback onTap;

  const _SizeChip({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Tooltip(
      message: 'Texte ${size.label}',
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Texte ${size.label}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: selected ? accent.withValues(alpha: .15) : null,
              border: Border.all(
                color: selected ? accent : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              'A',
              style: TextStyle(
                fontSize: size.fontSize > 24 ? 24 : size.fontSize,
                color: selected ? accent : theme.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.bold : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EndSelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onDone;

  const _EndSelectionBar({required this.count, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('$count sélectionné${count > 1 ? 's' : ''}'),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: onDone,
                icon: const Icon(Icons.close),
                label: const Text('Terminer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Book metadata + introduction, shown at the top of chapter 1 (repliable).
class _BookHeader extends StatefulWidget {
  final BibleBook book;
  const _BookHeader({required this.book});

  @override
  State<_BookHeader> createState() => _BookHeaderState();
}

class _BookHeaderState extends State<_BookHeader> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;
    final m = book.metadata;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    book.book,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: _collapsed ? 'Déplier' : 'Replier',
                  onPressed: () =>
                      setState(() => _collapsed = !_collapsed),
                  icon: Icon(_collapsed
                      ? Icons.expand_more
                      : Icons.expand_less),
                ),
              ],
            ),
            if (!_collapsed) ...[
              const SizedBox(height: 8),
              Text(
                '${book.abbreviation} · Traduction BYM',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const Divider(height: 20),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 3.2,
                children: [
                  _metaCell('Signification', m.signification),
                  _metaCell('Auteur', m.auteur),
                  _metaCell('Thème', m.theme),
                  _metaCell('Datation', m.date),
                ],
              ),
              if (book.introduction.isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  book.introduction,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaCell(String label, String value) => _metaBlock(label, value);

  Widget _metaBlock(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 2),
          ),
        ],
      ),
    );
  }
}