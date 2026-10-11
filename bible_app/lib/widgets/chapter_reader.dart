import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_database.dart';
import '../data/app_preferences.dart';
import '../data/book_catalog.dart';
import '../data/bym_update_service.dart';
import '../data/library_store.dart';
import '../data/note_reference_linker.dart';
import '../data/reference_parser.dart';
import '../data/share_text.dart';
import '../data/strong_lexicon.dart';
import '../data/theme_catalog.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../models/ati.dart';
import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/user_data.dart';
import '../models/verse.dart';
import '../screens/ati_note_screen.dart';
import '../screens/chapter_screen.dart';
import '../screens/ecran_comparer.dart';
import '../screens/etude_verset_screen.dart';
import '../screens/parallel_reading_screen.dart';
import '../screens/strong_detail_screen.dart';
import '../utils/hex_color.dart';
import 'fiche_text_settings.dart';
import 'loading_skeleton.dart';
import 'reader_actions_bar.dart';
import 'ati_word_sheet.dart';
import 'note_editor_sheet.dart';
import 'strong_extract_sheet.dart';
import 'study_sheet.dart';
import 'verse_tile.dart';
import 'bible_theme_scope.dart';
import 'premium_style.dart';

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

  /// Version already selected for this tab. When set, it wins over the global
  /// preference for the initial render of the tab so a new tab can inherit the
  /// previously active version instead of jumping back to BYM.
  final String? initialVersionCode;

  /// When set, persists the selected version on the owning tab.
  final ValueChanged<String>? onVersionChanged;

  /// When set, scrolls to and flashes the verse of a [VerseTarget] addressed
  /// to this chapter. Works both for newly-opened tabs (read in `initState`)
  /// and already-open ones (listened to live).
  final ValueListenable<VerseTarget?>? jumpToVerse;

  /// Restored reading position: the verse to scroll to on first load, without
  /// the gold flash (it is a position to resume, not a fresh jump). Null = top
  /// of the chapter.
  final int? initialVerse;

  /// Called when the reader settles on a verse (scroll or jump), so the owning
  /// tab can persist the reading position across restarts.
  final ValueChanged<int>? onVerseChanged;

  /// Optional way to open another chapter from the books navigation; when null
  /// the standalone [ChapterScreen] flow is used (push a new screen).
  final void Function(int bookIndex, int chapter)? onOpenChapter;

  /// Called with a [BibleReference] when the reader taps a reference embedded
  /// in a note. Null falls back to opening the referenced chapter via
  /// [onOpenChapter] / a pushed [ChapterScreen].
  final ValueChanged<BibleReference>? onReferenceTap;

  /// Opens the Bibliothèque destination. Null when the reader is shown outside
  /// the bottom-nav shell (tests, standalone [ChapterScreen]): the sheet then
  /// falls back to naming the Bibliothèque without offering to go there.
  final VoidCallback? onOpenLibrary;

  /// Opens the Réglages destination, where the display settings the ⋯ sheet does
  /// not carry are listed. Same null contract as [onOpenLibrary]: the row then
  /// names the destination instead of being an inert button.
  final VoidCallback? onOpenSettings;

  /// Where downloaded versions are read from. Injectable so a test can serve
  /// them from memory: a real read goes through `dart:io`, which never
  /// completes inside the `testWidgets` fake-async zone.
  final LibraryStore? store;

  const ChapterReader({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.initialVersionCode,
    this.onVersionChanged,
    this.jumpToVerse,
    this.initialVerse,
    this.onVerseChanged,
    this.onOpenChapter,
    this.onReferenceTap,
    this.onOpenLibrary,
    this.onOpenSettings,
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
  /// Verse number to scroll to and flash; null once a jump is fully done.
  int? _targetVerse;

  /// Le verset du dernier saut, épinglé comme position rapportée jusqu'à ce
  /// que l'utilisateur fasse défiler lui-même. L'estimateur « verset en haut
  /// du viewport » retombe sur un voisin (le verset visé se pose à 35 % de la
  /// hauteur, ses voisins le dépassent) : sans épingle, il écrase la position
  /// demandée quelques centaines de ms après l'atterrissage — et cette
  /// position dérivées ressuscite au prochain montage de l'onglet.
  int? _jumpedToVerse;

  /// Vrai dès que l'utilisateur tire la liste lui-même : l'épingle se lève et
  /// le rapporteur redevient une estimation honnête de la lecture.
  bool _userTookOverScroll = false;
  final GlobalKey _jumpKey = GlobalKey();

  /// Identifies the verse list itself, so position reporting in the
  /// continuous-paragraph layout can ask the list which verse sits near the
  /// viewport top — item math has no meaning there (one block can span the
  /// whole chapter).
  final GlobalKey<ChapterVerseListState> _listKey = GlobalKey();
  final ScrollController _verseScroll = ScrollController();
  Set<int> _flashingVerses = {};
  Timer? _flashTimer;

  /// The [widget.initialVerse] still waiting for the book to load. Cleared the
  /// first time the chapter is built so the restore runs exactly once per tab.
  int? _pendingRestore;

  /// Debounces verse reporting during scrolling: persisting the position on
  /// every scroll notification would hammer shared_preferences.
  Timer? _reportTimer;

  /// Last verse reported to [widget.onVerseChanged], to skip no-op writes.
  int? _lastReportedVerse;

  /// Neighbouring reading positions, resolved once the book is known: null
  /// while loading, and at the two ends of the Bible.
  (int, int)? _previous;
  (int, int)? _next;

  /// The chapter currently rendered by the [FutureBuilder], kept so the
  /// selection actions (copy a range) and the find-in-page scan work on the
  /// same data the reader displays.
  Chapter? _chapterData;

  /// Accumulated horizontal delta of the swipe in progress — chapter paging
  /// (see [_onChapterSwipe]).
  double? _swipeDx;

  // ---- Find in chapter (« trouver dans la page ») ----

  bool _findOpen = false;
  String _findQuery = '';
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  Timer? _findDebounce;

  /// Verse numbers of the current matches, in reading order.
  List<int> _findMatches = [];

  /// Index inside [_findMatches] the reader is parked on; -1 when none.
  int _findIndex = -1;

  @override
  void initState() {
    super.initState();
    _bookFuture = _bootstrap();
    _loadUserData();
    _loadNeighbours();
    _pendingRestore = widget.initialVerse;
    _verseScroll.addListener(_onScrollChanged);
    widget.jumpToVerse?.addListener(_onJumpChanged);
    _onJumpChanged(); // covers a chapter opened fresh with the target preset
    LibraryStore.revision.addListener(_onLibraryChanged);
    AppPreferences.revision.addListener(_onPreferencesChanged);
    BymUpdateService.textRevision.addListener(_onTextRevisionChanged);
  }

  @override
  void dispose() {
    _reportTimer?.cancel();
    _findDebounce?.cancel();
    _findController.dispose();
    _findFocus.dispose();
    widget.jumpToVerse?.removeListener(_onJumpChanged);
    LibraryStore.revision.removeListener(_onLibraryChanged);
    AppPreferences.revision.removeListener(_onPreferencesChanged);
    BymUpdateService.textRevision.removeListener(_onTextRevisionChanged);
    _flashTimer?.cancel();
    _verseScroll.removeListener(_onScrollChanged);
    _verseScroll.dispose();
    super.dispose();
  }

  /// A reading preference was saved somewhere in the app — this reader's own ⋯
  /// sheet, another tab's, the Réglages screen — so re-read them: size,
  /// alignment, notes, opacité and the rest are app-wide and must land live.
  ///
  /// Deliberately does NOT adopt `prefs.versionCode`. Every open tab lives in
  /// the shell's `IndexedStack`, so this listener fires on *all* of them at
  /// once: reading the shared code here made a version picked in tab 3 — or
  /// merely a font size changed there, since any save bumps the revision — drag
  /// tabs 1 and 2 onto that version too. The version being read belongs to the
  /// tab ([StudyTab.versionCode]); the preference is only the default a **new**
  /// tab starts from (« Version de lecture par défaut » in the Réglages).
  Future<void> _onPreferencesChanged() async {
    final prefs = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _prefsLoaded = true;
    });
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

  /// Le texte servi vient de changer sous le lecteur : une mise à jour installée
  /// depuis Réglages, ou le retour au texte embarqué. Les caches sont déjà vides
  /// — c'est la garantie d'ordre de [BymUpdateService.textRevision] — donc il
  /// suffit de redemander le livre pour que la correction apparaisse sans que
  /// l'onglet soit refermé puis rouvert.
  ///
  /// Seule la version embarquée est concernée : une traduction téléchargée ne
  /// bouge pas quand le texte BYM change.
  ///
  /// Remplacer le `Future` ne fait pas clignoter la page : `FutureBuilder` garde
  /// la donnée du snapshot précédent pendant l'attente (`inState` la conserve),
  /// donc le texte affiché et la position de lecture tiennent jusqu'à ce que le
  /// livre corrigé soit prêt, puis la page bascule d'un coup — pas de squelette
  /// de chargement, pas de remontage.
  ///
  /// Les voisins ne sont volontairement pas rechargés : un verset corrigé ne
  /// change pas le nombre de chapitres, et ce serait deux livres re-analysés
  /// pour rien.
  void _onTextRevisionChanged() {
    if (!mounted) return;
    if (_versionCode != VersionRepository.embeddedCode) return;
    setState(() {
      _bookFuture = _versions.loadBook(_versionCode, widget.bookIndex);
    });
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

  void _beginJump(int verseNumber, {bool flash = true}) {
    setState(() {
      _targetVerse = verseNumber;
      _flashingVerses = flash ? {verseNumber} : {};
    });
    _jumpedToVerse = verseNumber;
    _userTookOverScroll = false;
    // The flash is armed only once the verse is on screen (see
    // [_scrollToTarget]): clearing it on a timer started here would detach
    // [_jumpKey] mid-scroll on a long chapter.
    _flashTimer?.cancel();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToTarget(verseNumber, flash: flash),
    );
    _reportVerse(verseNumber);
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
  ///
  /// [flash] is false when restoring a persisted position: the verse scrolls
  /// into place without the gold flash — a place to resume, not a fresh jump.
  Future<void> _scrollToTarget(int verseNumber, {bool flash = true}) async {
    // A chapter opened fresh by a tap (note reference, search hit, picker)
    // starts on the loading spinner: the book is still being read and the
    // list does not exist yet, so [_verseScroll] has no client and every
    // scroll below would silently do nothing — the target stayed on verse 1
    // until a second, cache-warm attempt landed correctly. Wait for the list.
    var waitedFrames = 0;
    while (mounted && !_verseScroll.hasClients && waitedFrames < 120) {
      await WidgetsBinding.instance.endOfFrame;
      waitedFrames++;
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    // Near verses are already built — no need to move the list blindly.
    if (!await _revealBuiltTarget()) {
      final chapter = await _activeChapter();
      if (!mounted) return;

      // Layout-aware slot math: tiles count one item per verse; the
      // continuous layout counts blocks and their section titles. Must match
      // what [ChapterVerseList] actually built, or the offset estimate below
      // is off.
      final metrics = ChapterVerseList.jumpMetricsFor(
        chapter: chapter,
        layout: _layout,
        hasHeader: _showsBookHeader,
        verseNumber: verseNumber,
      );
      if (metrics != null && _verseScroll.hasClients) {
        for (var attempt = 0; attempt < 12; attempt++) {
          final position = _verseScroll.position;
          final fraction = metrics.itemCount <= 1
              ? 0.0
              : metrics.itemIndex / (metrics.itemCount - 1);
          final estimate = position.maxScrollExtent * fraction;
          _verseScroll.jumpTo(
            estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
          );
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted) return;
          if (_jumpKey.currentContext != null) break;
        }
      }
      await _revealBuiltTarget();
      if (!mounted) return;
    }

    if (!flash) {
      // Saut de restauration : pas de flash à éteindre, mais le target doit
      // partir quand même, sinon la clé de saut reste accrochée à la tuile
      // et les rapports suivants resteraient figés sur lui.
      setState(() => _targetVerse = null);
      return;
    }
    _flashTimer = Timer(kVerseFlashHold, () {
      if (!mounted) return;
      // Only the wash goes here. Dropping [_targetVerse] in the same breath
      // moved the tile's key off [_jumpKey] and onto its ValueKey, so the lazy
      // list built a fresh Element — and a fresh [AnimatedContainer] state
      // starts *at* its target colour: the wash vanished in one frame instead
      // of fading. The target is released just after, once the fade is over.
      setState(() => _flashingVerses = {});
      _flashTimer = Timer(kVerseFlashFadeOut, () {
        if (!mounted) return;
        setState(() => _targetVerse = null);
      });
    });
  }

  /// Scrolls the target verse into place, or returns false if it is not built.
  ///
  /// A plain tile answers to [Scrollable.ensureVisible]; a paragraph block
  /// implements [VerseAnchor] and reveals the exact verse inside flowing text
  /// via its own caret geometry.
  Future<bool> _revealBuiltTarget() async {
    final ctx = _jumpKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    if (ctx is StatefulElement) {
      final Object anchor = ctx.state;
      final target = _targetVerse;
      if (anchor is VerseAnchor && target != null) {
        await anchor.revealVerse(target, _verseScroll);
        return true;
      }
    }
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.35,
    );
    return true;
  }

  /// The scroll controller reports the reading position while the reader is
  /// idle (debounced): the owning tab persists it so a cold restart resumes
  /// where the reader stopped instead of the top of the chapter.
  void _onScrollChanged() {
    _reportTimer?.cancel();
    _reportTimer = Timer(
      const Duration(milliseconds: 400),
      _reportCurrentVerse,
    );
  }

  /// Estimates the verse currently at the top of the viewport from the scroll
  /// offset, then reports it. Deliberately an *estimate*: the tiles are a lazy
  /// `ListView.builder` of variable heights, so an exact mapping would need
  /// each tile to report its own geometry. The fraction is the same one
  /// [_scrollToTarget] inverts to jump, so restoring lands on the same verse.
  Future<void> _reportCurrentVerse() async {
    if (widget.onVerseChanged == null) return;
    // Un saut non encore « repris » par l'utilisateur fait foi : rapporter
    // le verset VISÉ plutôt qu'estimer le haut du viewport.
    if (!_userTookOverScroll && _jumpedToVerse != null) {
      _reportVerse(_jumpedToVerse!);
      return;
    }
    final position = _verseScroll.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      return;
    }

    // Continuous layout: ask the list itself — its blocks know their own
    // geometry, and one block can span the whole chapter so item fractions
    // carry no verse meaning.
    if (_layout == ReadingLayout.paragraph) {
      final verse = _listKey.currentState?.verseNearViewportTop();
      if (verse != null) {
        _reportVerse(verse);
        return;
      }
      return;
    }

    final chapter = await _activeChapter();
    if (!mounted || chapter.verses.isEmpty) return;

    final hasHeader = _showsBookHeader;
    final itemCount = chapter.verses.length + (hasHeader ? 1 : 0);
    if (itemCount <= 1) return;
    final fraction = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final itemIndex = (fraction * (itemCount - 1)).round();
    final verseIndex = itemIndex - (hasHeader ? 1 : 0);
    if (verseIndex < 0 || verseIndex >= chapter.verses.length) return;
    final verse = chapter.verses[verseIndex];
    _reportVerse(verse.number == 0 ? verseIndex + 1 : verse.number);
  }

  /// Fires [widget.onVerseChanged] when the verse actually changed, so the tab
  /// persists a position only when there is one to record.
  ///
  /// The call is deferred out of the current frame: a jump read in `initState`
  /// (chapter opened by a reference tap) reports BEFORE the first build ends,
  /// and notifying the TabManager then would mark an ancestor dirty mid-build
  /// (`markNeedsBuild called during build`) and abort the very jump that
  /// triggered it.
  void _reportVerse(int verseNumber) {
    if (verseNumber == _lastReportedVerse) return;
    _lastReportedVerse = verseNumber;
    final cb = widget.onVerseChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(verseNumber);
    });
  }

  /// Restores the persisted reading position once, the first time the chapter
  /// is laid out. Runs after the frame so the list has clients and the target
  /// tile's key is attached; the flash is off so the reader silently resumes
  /// instead of flashing a verse it was already on.
  ///
  /// A jump already begun wins and the restore is dropped. Every verse link
  /// outside the reader — occurrence Strong, référence d'une feuille d'étude,
  /// fiche de dictionnaire, note BYM, résultat de recherche — goes through the
  /// shell's `_openReading`, which sets BOTH the tab's `verse` (so the position
  /// survives in the tab) and the jump target. On a tab opened by that link the
  /// two arrive together: the restore aimed at the very same verse and, being
  /// silent by design, wiped the flash the jump had just armed a frame earlier.
  /// The link landed on the right verse — with nothing to show for it.
  void _consumePendingRestore() {
    final pending = _pendingRestore;
    if (pending == null) return;
    _pendingRestore = null;
    if (_jumpedToVerse != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _beginJump(pending, flash: false);
    });
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

  /// Whether the version being read embeds Strong codes per word (LSGS): their
  /// display becomes tappable and tapping one opens its French definition.
  bool get _hasStrong => versionByCode(_versionCode)?.hasStrong ?? false;

  /// Whether the version on screen is the ATI interlinear — a grid of word
  /// columns, dont « Texte continu » n'a aucun sens.
  bool get _interlinear => versionByCode(_versionCode)?.interlinear ?? false;

  /// The layout this reader actually renders.
  ///
  /// Deliberately a *display* read, like [_supportsNotes], never a write: the
  /// « Continu » choice stays in the preference for the versions that know
  /// what to do with it, and is found again when the reading leaves the ATI.
  ReadingLayout get _layout =>
      _interlinear ? ReadingLayout.tiles : _prefs.layout;

  /// Notes actually displayed. « Texte + notes » is enough: the disposition is
  /// a tiles-only choice.
  ///
  /// The continuous flow renders notes ONE way — woven into the sentence, in
  /// parentheses — because « sous le verset » cards would chop the printed-text
  /// feel. So there the disposition simply does not apply, and the flow reads
  /// the notes whatever it says. This used to gate on
  /// `disposition == inline` instead, which made the sheet lie: in the flow the
  /// « Notes à la suite » chip already draws itself as selected (the « sous le
  /// verset » chip isn't even offered), yet a reader whose stored disposition
  /// was still the default « sous le verset » saw a highlighted chip and no
  /// notes — and had to tap the chip that already looked active.
  ///
  /// Gating here rather than coercing the preference on the way in is what keeps
  /// « sous le verset » intact for when the reader goes back to the tiles.
  bool get _effectiveShowNotes => _prefs.notesMode && _supportsNotes;

  /// Reads the preferences and the library, *then* the book.
  ///
  /// In that order because the preferences carry the active version: loading
  /// the BYM first would flash the wrong translation on screen for a frame.
  Future<BibleBook> _bootstrap() async {
    final prefs = await AppPreferences.load();
    final installed = await _installedVersions();
    final preferred = widget.initialVersionCode ?? prefs.versionCode;
    // An embedded version (BYM, LSGS or LSS) is always readable. A downloaded
    // one deleted from the Bibliothèque since the last read would leave the
    // reader stuck on an error panel — fall back to the embedded BYM.
    final code =
        _versions.isEmbedded(preferred) ||
            installed[preferred]?.isEmpty == false
        ? preferred
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
        _versionCode,
        widget.bookIndex,
        widget.chapter,
      );
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
  ///
  /// The choice is recorded on the **owning tab** ([widget.onVersionChanged]),
  /// never in the shared preferences: writing there bumped
  /// `AppPreferences.revision`, which every other open tab listens to, so
  /// picking a version in one tab pulled all the already-open ones onto it.
  /// A standalone reader ([ChapterScreen]) has no tab to hold the choice — there
  /// the preference stays its store.
  void _switchVersion(String code) {
    if (code == _versionCode) return;
    setState(() {
      _versionCode = code;
      _bookFuture = _versions.loadBook(code, widget.bookIndex);
      _targetVerse = null;
      _jumpedToVerse = null;
      _flashingVerses = {};
    });
    final onVersionChanged = widget.onVersionChanged;
    if (onVersionChanged != null) {
      onVersionChanged(code);
      return;
    }
    _prefs.versionCode = code;
    _savePrefs();
  }

  /// Resolves the previous / next reading positions so the bar's arrows can be
  /// enabled or greyed. Crossing a book boundary parses the neighbour book,
  /// which the cache then keeps for the actual navigation.
  Future<void> _loadNeighbours() async {
    final previous = await _versions.previousChapter(
      widget.bookIndex,
      widget.chapter,
    );
    final next = await _versions.nextChapter(widget.bookIndex, widget.chapter);
    if (!mounted) return;
    setState(() {
      _previous = previous;
      _next = next;
    });
  }

  Future<void> _loadUserData() async {
    try {
      final highlights = await _db.highlightsInChapter(
        widget.bookIndex,
        widget.chapter,
      );
      final favorites = await _db.favoritesInChapter(
        widget.bookIndex,
        widget.chapter,
      );
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

  /// Layout, size, notes and the panel opacity are the preferences reachable
  /// from the ⋯ sheet; the rest (police, alignement, graisse, aération, couleur)
  /// are written by the Settings screen, which bumps [AppPreferences.revision] —
  /// the same signal this widget listens to. One writer per preference, so the
  /// two surfaces cannot disagree.
  Future<void> _setLayout(ReadingLayout value) async {
    if (_prefs.layout == value) return;
    // L'ATI n'a pas de texte continu : la feuille désactive déjà le segment,
    // et cette garde couvre une feuille ouverte pendant un changement de
    // version — la préférence ne s'écrit pas pour un rendu qui l'ignorera.
    if (_interlinear && value == ReadingLayout.paragraph) return;
    setState(() => _prefs.layout = value);
    await _savePrefs();
  }

  /// Live dial from the ⋯ sheet's slider: the reader rebuilds behind the open
  /// sheet so the text resizes while the thumb moves. The preference itself
  /// is written once, by [_savePrefs] when the drag ends — writing every tick
  /// would hammer the preferences a dozen times per gesture. The regime of
  /// [_setPanelOpacity] / the opacity dial, for the same reason.
  void _setFontSize(double value) {
    if (_prefs.fontSize == value) return;
    setState(() => _prefs.fontSize = value);
  }

  Future<void> _setNotesMode(bool value) async {
    if (_prefs.notesMode == value) return;
    setState(() => _prefs.notesMode = value);
    await _savePrefs();
  }

  Future<void> _setDisposition(NoteDisposition value) async {
    if (_prefs.disposition == value) return;
    setState(() => _prefs.disposition = value);
    await _savePrefs();
  }

  /// Live dial from the ⋯ sheet's slider: the reader rebuilds behind the open
  /// sheet so the panel fades while the thumb moves; [_savePanelOpacity]
  /// persists once the drag ends — writing every tick would hammer the
  /// preferences a dozen times per gesture.
  void _setPanelOpacity(double value) {
    if ((_prefs.panelOpacity - value).abs() < .001) return;
    setState(() => _prefs.panelOpacity = value);
  }

  Future<void> _savePanelOpacity() async {
    if (!_prefsLoaded) return;
    await _prefs.save();
  }

  /// The scoped theme with the « Couleur du texte » override applied — null
  /// preference (or an unparsable leftover) means the theme's own colour.
  /// Derived colours (notes, links) and the light/dark panel machinery
  /// recompute inside `withTextColor`, so any choice stays readable.
  BibleTheme _effectiveTheme(BuildContext context) {
    final theme = BibleThemeScope.of(context);
    final value = int.tryParse(_prefs.textColorOverride ?? '');
    return value == null ? theme : theme.withTextColor(Color(value));
  }

  /// The reader's ⋯ sheet: **what one reaches for while reading**, and one link
  /// to the rest.
  ///
  /// The split is deliberate and is not a division of labour between two teams of
  /// settings — it is a shortcut. Réglages holds the *complete* list (this sheet
  /// used to hold six settings that appeared nowhere else, which is how a reader
  /// hunting for « graisse » concluded the app had no such setting). What stays
  /// here is what changes mid-read: the layout, the size, the notes, the
  /// opacity and the parallel reading — plus immersion, which is an action
  /// rather than a preference and therefore has no row in Réglages: this sheet
  /// is its only address, and it closes the sheet when it turns on. The dials
  /// the two surfaces do share use the very same controls in both, so they
  /// cannot drift apart — changing one changes both.
  Future<void> _showDisplaySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // Fond crème comme les autres feuilles du lecteur : par défaut la
      // feuille prenait le blanc du thème, seule surface encore étrangère au
      // langage premium.
      backgroundColor: premiumBackground(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          return DisplaySettingsSheetLayout(
            // Exit on the « Affichage » title line, always at the top.
            onClose: () => Navigator.of(sheetContext).pop(),
            children: [
              // The immersion mode first: an action one reaches for, not a
              // styling dial to hunt at the bottom of the sheet. It closes
              // the sheet on activation.
              DisplayToggleCard(
                icon: Icons.fullscreen,
                title: 'Mode immersion',
                subtitle: 'Masquer les barres pour ne lire que le texte',
                value: _prefs.immersion,
                onChanged: (value) {
                  Navigator.of(sheetContext).pop();
                  _setImmersion(value);
                },
              ),
              const SizedBox(height: 12),
              DisplayLayoutSection(
                // L'ATI n'a pas de texte continu : le segment « Continu » se
                // lit délavé et ne se prend pas, et la barre annonce
                // « Séparés » — c'est ce que le lecteur est en train de montrer.
                layout: _layout,
                paragraphAvailable: !_interlinear,
                onChanged: (value) async {
                  await _setLayout(value);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 12),
              DisplaySizeSection(
                fontSize: _prefs.fontSize,
                // 100 % = la taille par défaut de la lecture (22 pt) :
                // « 136 % » est l'ancien « géant », et le curseur va au-delà.
                base: ReadingTextSize.extraLarge.fontSize,
                // Le texte grandit derrière la feuille à chaque tic — le
                // curseur est son propre sous-arbre, `setSheet` le suit, et
                // les préférences ne s'écrivent qu'au relâcher. Le régime
                // exact du panneau d'opacité dessous, pour la raison exacte
                // qui y est écrite.
                onChanged: (value) {
                  _setFontSize(value);
                  setSheet(() {});
                },
                onChangeEnd: (_) => _savePrefs(),
              ),
              const SizedBox(height: 12),
              // Notes, with their disposition. The continuous flow weaves the
              // notes into the sentence, so the bar then offers the single
              // disposition that applies: there is no room under a verse whose
              // notes are already inside it.
              if (_supportsNotes)
                DisplayNotesSection(
                  notesMode: _prefs.notesMode,
                  disposition: _prefs.disposition,
                  belowAvailable: _layout != ReadingLayout.paragraph,
                  onNotesMode: (value) async {
                    await _setNotesMode(value);
                    setSheet(() {});
                  },
                  onDisposition: (value) async {
                    await _setDisposition(value);
                    setSheet(() {});
                  },
                )
              else
                // A version that carries no notes: one card that says why,
                // rather than a switch toggling between two identical renderings.
                DisplayCard(
                  label: 'Notes',
                  icon: Icons.note_alt,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Texte BYM uniquement',
                          style: premiumText(
                            context,
                            12.5,
                            FontWeight.w500,
                            premiumPalette(context).textGrey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              // How much of the theme's background shows through behind the
              // verses — a per-reading comfort, worth a dial two taps away.
              DisplayOpacitySection(
                value: _prefs.panelOpacity,
                // The reader's `setState` alone is not enough here: the sheet is
                // its own subtree behind its own route, so it is not rebuilt by
                // it. Without this the panel faded while the thumb and the « 80 % »
                // label stayed put — the dial looked dead, and a later
                // `setSheet` from any other control snapped it back.
                onChanged: (value) {
                  _setPanelOpacity(value);
                  setSheet(() {});
                },
                onChangeEnd: (_) => _savePanelOpacity(),
              ),
              const SizedBox(height: 12),
              // The rest of the display lives in one place, and this says so
              // rather than leaving the reader to wonder where « graisse » went.
              _AllSettingsRow(
                onTap: widget.onOpenSettings == null
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        widget.onOpenSettings!();
                      },
              ),
              const SizedBox(height: 12),
              // Sur les écrans où l'icône a quitté la barre, « Trouver »
              // rejoint les actions de la feuille : cacher le bouton ne doit
              // jamais cacher la recherche.
              if (!_findIconInBar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      _openFind();
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Trouver dans le chapitre'),
                  ),
                ),
              // The two-versions side-by-side reading: a mode, not a display
              // knob — it lives at the bottom of the sheet and closes it.
              // À partir de 600 la barre en porte aussi un, sur la rangée de
              // la recherche ; cette entrée reste la voie des téléphones.
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _openParallel();
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  icon: const Icon(Icons.vertical_split, size: 18),
                  label: const Text('Lecture parallèle — deux versions'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read straight from the preference: the size slider stores any point of
    // its range, and rounding it back to the ladder's nearest step would put
    // the body one notch away from what the reader dialled. The narrow-screen
    // reduction rides on the ambient `textScaler` posed in `main.dart`, so
    // no second width-keyed ladder is applied here.
    final bodyFontSize = _prefs.fontSize;
    // Immersion: only the text remains. The find bar and the action bar are
    // the reader's own; the shells above hide theirs on the same preference.
    final immersive = _prefs.immersion;
    return Stack(
      children: [
        Column(
          children: [
            if (!immersive) ...[
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Caché sur les petits écrans (voir [_findIconInBar]) :
                    // la feuille ⋯ en propose l'accès à la place, la barre
                    // garde le bouton d'affichage seule.
                    if (_findIconInBar)
                      IconButton(
                        tooltip: 'Trouver dans le chapitre',
                        icon: const Icon(Icons.search),
                        onPressed: _openFind,
                        visualDensity: VisualDensity.compact,
                      ),
                    // La lecture parallèle a besoin de largeur : sur la même
                    // rangée que la recherche, mais seulement à partir de 600 —
                    // les tablettes et au-dessus. Les téléphones la gardent au
                    // fond de la feuille ⋯.
                    if (_parallelInBar)
                      IconButton(
                        tooltip: 'Lecture parallèle — deux versions',
                        icon: const Icon(Icons.vertical_split),
                        onPressed: _openParallel,
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      tooltip: 'Affichage du texte',
                      icon: const Icon(Icons.more_vert),
                      onPressed: _showDisplaySheet,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              if (_findOpen) _buildFindBar(),
            ],
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (_) => _swipeDx = 0,
                onHorizontalDragUpdate: (d) =>
                    _swipeDx = (_swipeDx ?? 0) + d.delta.dx,
                onHorizontalDragEnd: _onChapterSwipe,
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
                    // Squelette façonné comme la page qui arrive (en-tête de
                    // livre si le chapitre 1 d'une version riche va l'afficher,
                    // puis lignes de versets) : pas de saut de layout au
                    // chargement, et un repère visuel plutôt qu'un spinner.
                    return ChapterLoadingSkeleton(header: _showsBookHeader);
                  }
                  final book = snapshot.data!;
                  final chapter = book.chapters.firstWhere(
                    (c) => c.chapter == widget.chapter,
                    orElse: () => const Chapter(chapter: 0, verses: []),
                  );
                  if (chapter.verses.isEmpty && widget.chapter != 1) {
                    return const Center(child: Text('Chapitre vide.'));
                  }
                  // A persisted reading position resumes once the chapter is laid
                  // out: the list must exist for [_verseScroll] to have clients and
                  // for [_jumpKey] to attach to the target verse's tile.
                  _consumePendingRestore();
                  _chapterData = chapter;
                  // The scoped theme with the « Couleur du texte » override
                  // applied: the body style AND the whole verse list (notes,
                  // links, panels) read from the same effective theme.
                  final readingTheme = _effectiveTheme(context);
                  // THE shared verse-body style: one object for the flowing
                  // blocks, the tiles' bodyLarge override AND the header
                  // introduction. Whatever the layout, the body and its intro
                  // are size-identical by construction — they cannot drift.
                  // Its leading comes from the reading rhythm so large type
                  // keeps breathing room; [ChapterVerseList] re-applies the
                  // same rhythm to its own fallback style.
                  final readingRhythm = ReadingRhythm(
                    fontSize: bodyFontSize,
                    spacing: _prefs.spacing,
                  );
                  final flowBodyStyle = TextStyle(
                    fontSize: bodyFontSize,
                    color: readingTheme.textColor,
                    fontFamily: _prefs.readingFont.fontFamily,
                    fontWeight: _prefs.fontWeight.weight,
                    height: readingRhythm.lineHeight,
                    letterSpacing: readingRhythm.letterSpacing,
                  );
                  // L'utilisateur qui tire la liste lui-même lève l'épingle du
                  // dernier saut : les rapports redeviennent une estimation.
                  // `dragDetails` ne porte que sur un geste tactile — les
                  // sauts programmatiques (jumpTo/ensureVisible) passent ici
                  // sans jamais lever l'épingle.
                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification &&
                          notification.dragDetails != null) {
                        _userTookOverScroll = true;
                      }
                      return false;
                    },
                    child: ChapterVerseList(
                      key: _listKey,
                      // Pas de ValueKey incluant l'affichage ici : il recréerait le
                      // ListView + son ScrollController à chaque changement d'alignement
                      // et ramènerait Jean 3:16 au verset 1 (repro signalé).
                      theme: readingTheme,
                      panelOpacity: _prefs.panelOpacity,
                      chapter: chapter,
                      showNotes: _effectiveShowNotes,
                      disposition: _prefs.disposition,
                        layout: _layout,
                      fontWeight: _prefs.fontWeight.weight,
                      spacing: _prefs.spacing,
                      fontSize: bodyFontSize,
                      bodyStyle: flowBodyStyle,
                      readingFont: _prefs.readingFont,
                      textAlign: _prefs.textAlign.align,
                      header: _showsBookHeader
                          ? _BookHeader(
                              book: book,
                              // The intro inherits the rhythm's leading through
                              // flowBodyStyle — no fixed ratio on top of it.
                              introStyle: flowBodyStyle,
                            )
                          : null,
                      highlightOf: (vn) => _highlights[vn],
                      isFavoriteOf: (vn) => _favorites.contains(vn),
                      hasNoteOf: (vn) => _userNotes.contains(vn),
                      selectedVerses: _selected,
                      jumpVerse: _targetVerse,
                      jumpKey: _jumpKey,
                      controller: _verseScroll,
                      flashingVerses: _flashingVerses,
                      searchMatches: _findMatches.isEmpty
                          ? null
                          : Set<int>.from(_findMatches),
                      footer: immersive || _multiMode
                          ? null
                          : _buildContinueFooter(),
                      onVerseTap: _onVerseTap,
                      onVerseLongPress: _onVerseLongPress,
                      onStrongTap: _hasStrong ? _onStrongInText : null,
                        onAtiWordTap: _onAtiWordTap,
                      onReferenceTap: _onReferenceTap,
                    ),
                  );
                },
                ),
              ),
            ),
            if (_multiMode)
              _SelectionBar(
                key: const ValueKey('selection-bar'),
                count: _selected.length,
                onHighlight: _showSelectionColors,
                onFavorite: _bulkFavorite,
                onCopy: _copySelection,
                onShare: _shareSelection,
                onDone: () => setState(() => _selected.clear()),
              ),
          ],
        ),
        if (immersive)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
              heroTag: 'exit-immersion',
              tooltip: 'Quitter le mode immersion',
              onPressed: () => _setImmersion(false),
              child: const Icon(Icons.fullscreen_exit),
            ),
          ),
      ],
    );
  }

  /// The « continuer au chapitre suivant » tile at the end of the verse list —
  /// the end of the page is where a reader reaches for what comes next, and
  /// the top arrows sit off-screen by then. Null while [_next] is unresolved.
  Widget? _buildContinueFooter() {
    final next = _next;
    if (next == null) return null;
    return _ContinueChapterTile(
      label:
          '${bookDisplayLabel(next.$1, code: _versionCode, embeddedCode: VersionRepository.embeddedCode)} ${next.$2}',
      onTap: () => _openChapter(next.$1, next.$2),
    );
  }

  /// The inline find row: field, occurrence counter, prev/next, close.
  Widget _buildFindBar() {
    final p = premiumPalette(context);
    return Material(
      color: premiumBackground(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _findController,
                focusNode: _findFocus,
                onChanged: _onFindChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _stepFind(1),
                style: premiumText(context, 14, FontWeight.w500, p.textDark),
                decoration: InputDecoration(
                  hintText: 'Trouver dans le chapitre',
                  hintStyle: premiumText(
                    context,
                    14,
                    FontWeight.w400,
                    p.textGrey,
                  ),
                  isDense: true,
                  // Le champ prend la surface des cartes premium, cerclé d'un
                  // liseré **neutre** : l'or reste à l'icône de recherche, qui
                  // nomme la fonction.
                  filled: true,
                  fillColor: p.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: premiumCardBorder(context, opacity: .34),
                    ),
                  ),
                  prefixIcon: Icon(Icons.search, size: 20, color: p.primary),
                ),
              ),
            ),
            Text(
              _findCounter,
              style: premiumText(context, 13, FontWeight.w700, p.textGrey),
            ),
            IconButton(
              tooltip: 'Occurrence précédente',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _findMatches.isEmpty ? null : () => _stepFind(-1),
            ),
            IconButton(
              tooltip: 'Occurrence suivante',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _findMatches.isEmpty ? null : () => _stepFind(1),
            ),
            IconButton(
              tooltip: 'Fermer la recherche',
              icon: const Icon(Icons.close),
              onPressed: _closeFind,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onVerseTap(Verse verse) async {
    if (_multiMode) {
      setState(() {
        if (!_selected.remove(verse.number)) _selected.add(verse.number);
      });
      return;
    }
    // La feuille d'étude est fermée là où le texte se lit mot à mot : sur
    // l'ATI (colonnes de champs) et sur les deux Segond Strong, LSGS et LSS
    // (chaque code Strong déjà cliquable). Note, Comparer, Renvois, Copier,
    // Partager parlent d'un verset lu dans un texte continu ; ici la seule
    // porte est le mot lui-même — la fiche d'une cellule sur l'ATI, l'extrait
    // d'un code sur la LSGS ou la LSS. La sélection multiple, elle, est
    // décidée plus haut et reste servie : un long appui suffit toujours à la
    // lancer.
    if (_interlinear || _hasStrong) return;
    final vn = verse.number;
    // The Lexique button proposes the same verse in the embedded Strong
    // rendering — a property of the BYM canon, not of the notes the version
    // happens to carry, so the gate asks the FORMAT (the same predicate as the
    // book header and the notes toggle) rather than the code: a future
    // BYM-format version keeps the button where `code == 'BYM'` would drop it.
    // LSGS and LSS themselves no longer reach this sheet — the gate above
    // takes them out — what stays off here are the bare-text translations,
    // rather than offer a Strong verse that may not match their own
    // versification.
    final lexiqueEnabled = versionByCode(_versionCode)?.carriesNotes ?? false;
    final action = await showStudySheet(
      context,
      reference:
          '${catalogEntry(widget.bookIndex).abbreviation} ${verse.verse}',
      excerpt: verse.text,
      isFavorite: _favorites.contains(vn),
      currentHighlight: _highlights[vn],
      lexiqueEnabled: lexiqueEnabled,
      // Le même libellé dans les deux états : il nomme la *fonction*, et la
      // feuille dit la disponibilité — grisé, plus une ligne « Disponible depuis
      // le texte BYM. ». Le libellé désactivé disait « — version BYM », ce qui
      // répétait cette ligne et laissait le lecteur sans savoir ce que le bouton
      // ouvre.
      lexiqueLabel: 'Lexique & Dictionnaire — verset mot à mot',
      onHighlight: (color) => _applyHighlight(vn, color),
      onFavorite: (value) => _applyFavorite(vn, value),
    );
    if (action == null || !mounted) return;

    switch (action) {
      case StudyAction.lexicon:
        await _openLexique(vn);
        break;
      case StudyAction.note:
        await _editNote(verse);
        break;
      case StudyAction.copy:
        // The same formatter as the multi-verse copy, so a single verse and a
        // selection cannot drift apart — and both name a downloaded version.
        await Clipboard.setData(
          ClipboardData(
            text: formatCitation(
              _passageOf(verse),
              tag: versionTag(_versionCode, VersionRepository.embeddedCode),
            ),
          ),
        );
        _snack('Verset copié.');
        break;
      case StudyAction.compare:
        await _openComparer(vn);
        break;
      case StudyAction.references:
        await _showVerseReferences(verse);
        break;
      case StudyAction.share:
        await shareText(
          formatPassage(
            _passageOf(verse),
            tag: versionTag(_versionCode, VersionRepository.embeddedCode),
          ),
          origin: _originOf(context),
        );
        break;
    }
  }

  /// The rectangle of the tapped surface, so the share sheet has something to
  /// anchor to. Null is acceptable — `share_plus` falls back to the centre of the
  /// screen — but passing it is what keeps a tablet from positioning the sheet
  /// off-screen.
  Rect? _originOf(BuildContext source) {
    final box = source.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// The verse as the copy/share layer needs it: reference already resolved.
  PassageRef _passageOf(Verse verse) => PassageRef(
        reference: _referenceLabel(verse),
        verse: verse.number,
        text: verse.text,
      );

  /// The current selection in **reading order** — not selection order: a share
  /// must read top to bottom.
  List<PassageRef> _selectedPassages() {
    final chapter = _chapterData;
    if (chapter == null || _selected.isEmpty) return const [];
    final wanted = Set<int>.from(_selected);
    final out = <PassageRef>[];
    for (var i = 0; i < chapter.verses.length; i++) {
      final v = chapter.verses[i];
      final vn = v.number == 0 ? i + 1 : v.number;
      if (wanted.remove(vn)) out.add(_passageOf(v));
      if (wanted.isEmpty) break;
    }
    return out;
  }

  /// « Genèse 1:1 » on a translation, « Bereshit 1:1 » on the BYM — the label
  /// carried by the copied and shared verse. It follows the version being read,
  /// because a reference that named the wrong text would send the reader to a
  /// chapter that does not say what they just copied.
  String _referenceLabel(Verse verse) =>
      '${bookDisplayName(widget.bookIndex, code: _versionCode, embeddedCode: VersionRepository.embeddedCode)} ${verse.verse}';

  /// Applies a colour picked in the study sheet, or clears it when null.
  ///
  /// The map must **lose** the key rather than hold an empty string: an empty
  /// string is not null, so [VerseTile] would still read it as a highlight and
  /// `_parseColor('')` would fall back to amber — an un-highlighted verse
  /// repainted itself until the chapter was reloaded from SQLite.
  /// Persists one user-data row **without blocking** the on-screen state:
  /// the database opens through path_provider/sqflite, whose first answer can
  /// take a beat on a cold start — painting the highlight must not wait for
  /// it. Errors are swallowed, same contract as [_loadUserData].
  void _persist(Future<void> op) {
    op.then((_) {}, onError: (_) {});
  }

  Future<void> _applyHighlight(int verseNumber, String? color) async {
    _persist(
      _db.setHighlight(widget.bookIndex, widget.chapter, verseNumber, color),
    );
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
    _persist(
      _db.setFavorite(widget.bookIndex, widget.chapter, verseNumber, value),
    );
    if (!mounted) return;
    setState(() {
      if (value) {
        _favorites.add(verseNumber);
      } else {
        _favorites.remove(verseNumber);
      }
    });
  }

  /// Applies a color picked in the selection bar to every selected verse (or
  /// erases their highlights). One write per verse — the table is keyed on
  /// (book, chapter, verse), there is no range form.
  Future<void> _bulkHighlight(String? color) async {
    final targets = _selected.toList();
    if (targets.isEmpty) return;
    if (!mounted) return;
    setState(() {
      for (final vn in targets) {
        if (color == null || color.isEmpty) {
          _highlights.remove(vn);
        } else {
          _highlights[vn] = color;
        }
      }
    });
    for (final vn in targets) {
      _persist(_db.setHighlight(widget.bookIndex, widget.chapter, vn, color));
    }
    _snack(
      color == null || color.isEmpty
          ? 'Surlignage effacé sur ${targets.length} verset${targets.length > 1 ? 's' : ''}.'
          : '${targets.length} verset${targets.length > 1 ? 's' : ''} surligné${targets.length > 1 ? 's' : ''}.',
    );
  }

  /// Toggles favourite on the whole selection: any verse not yet starred adds
  /// all of them; only then does a second pass remove them.
  Future<void> _bulkFavorite() async {
    final targets = _selected.toList();
    if (targets.isEmpty) return;
    final add = targets.any((vn) => !_favorites.contains(vn));
    if (!mounted) return;
    setState(() {
      add ? _favorites.addAll(targets) : _favorites.removeAll(targets);
    });
    for (final vn in targets) {
      _persist(_db.setFavorite(widget.bookIndex, widget.chapter, vn, add));
    }
    _snack(add ? 'Ajouté aux favoris.' : 'Retiré des favoris.');
  }

  /// Copies the selection as one block, verses in reading order. Exits selection
  /// mode afterwards — copying is terminal, unlike colouring which invites more.
  Future<void> _copySelection() async {
    final passages = _selectedPassages();
    if (passages.isEmpty) return;
    final tag = versionTag(_versionCode, VersionRepository.embeddedCode);
    // Le nom de l'app en tête, une fois, puis une ligne par verset : la mise en
    // forme de la sélection est dans `share_text.dart` comme toutes les autres,
    // et non recopiée ici.
    await Clipboard.setData(
      ClipboardData(text: formatCitations(passages, tag: tag)),
    );
    if (!mounted) return;
    setState(_selected.clear);
    _snack(
      '${passages.length} verset${passages.length > 1 ? 's' : ''} copié${passages.length > 1 ? 's' : ''}.',
    );
  }

  /// Hands the selection to the system share sheet, in the same reading order
  /// and the same conventions as the single-verse share.
  ///
  /// The selection **stays**: the share sheet is its own visible feedback, and
  /// unlike the clipboard the reader may well have more to do with these verses.
  Future<void> _shareSelection() async {
    final passages = _selectedPassages();
    if (passages.isEmpty) return;
    await shareText(
      formatSelection(
        passages,
        tag: versionTag(_versionCode, VersionRepository.embeddedCode),
      ),
      origin: _originOf(context),
    );
  }

  /// The color row of the selection bar: same palette as the study sheet,
  /// applied to every selected verse at once.
  Future<void> _showSelectionColors() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Surligner ${_selected.length} verset${_selected.length > 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final color in highlightColors)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _bulkHighlight(color);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: hexToColor(color),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black26),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  _bulkHighlight(null);
                },
                icon: const Icon(Icons.format_color_reset),
                label: const Text('Effacer le surlignage'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onVerseLongPress(Verse verse) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selected.clear();
      _selected.add(verse.number);
    });
  }

  /// A horizontal swipe pages the chapter: left → next, right → previous, the
  /// same direction a photo pager uses. Two gates so an accidental graze never
  /// turns the page: a fast flick (velocity) or a deliberate long drag
  /// (distance). Disabled in multi-selection — there, horizontal moves are
  /// just imprecise taps.
  void _onChapterSwipe(DragEndDetails details) {
    final dx = _swipeDx ?? 0;
    _swipeDx = null;
    if (_multiMode) return;
    final velocity = details.primaryVelocity ?? 0;
    final isFlick = velocity.abs() > 400 && dx.abs() > 70;
    final isLongDrag = dx.abs() > 140;
    if (!isFlick && !isLongDrag) return;

    // Swipe left (dx < 0) reveals what follows; swipe right what precedes.
    final target = dx < 0 ? _next : _previous;
    if (target == null) return;
    HapticFeedback.lightImpact();
    _openChapter(target.$1, target.$2);
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

  /// A reference tapped inside a note (« Voir Es. 45:18. »): handed to the
  /// shell so it can open (or jump to) the referenced passage, or opened as a
  /// pushed [ChapterScreen] when reading standalone.
  void _onReferenceTap(BibleReference ref) {
    final cb = widget.onReferenceTap;
    if (cb != null) {
      cb(ref);
      return;
    }
    _openChapter(ref.bookIndex, ref.chapter ?? 1);
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

  /// The « Lecture parallèle » button: the current chapter across two
  /// versions, side by side. The left pane starts on the version being read.
  Future<void> _openParallel() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParallelReadingScreen(
          bookIndex: widget.bookIndex,
          chapter: widget.chapter,
          initialLeftCode: _versionCode,
          store: _library,
        ),
      ),
    );
  }

  // ---- Find in chapter ----

  /// La barre d'un téléphone en portrait n'a plus la place pour l'icône de
  /// recherche à côté du ⋯ : sous 480 de large elle quitte le `trailing` et
  /// « Trouver dans le chapitre » vit dans la feuille ⋯ à la place — la
  /// fonction ne part jamais, seul l'endroit change. Au-delà (grand
  /// téléphone en paysage, tablette, bureau) la barre reste intacte.
  bool get _findIconInBar => MediaQuery.sizeOf(context).width >= 480;

  /// La lecture parallèle side-by-side vit de la largeur : la barre ne
  /// propose son bouton direct qu'à partir de 600 de large — les tablettes et
  /// au-dessus. En deçà elle reste atteignable par la feuille ⋯, au fond, que
  /// son `SingleChildScrollView` ne coupe jamais.
  bool get _parallelInBar => MediaQuery.sizeOf(context).width >= 600;

  void _openFind() {
    setState(() => _findOpen = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _findDebounce?.cancel();
    setState(() {
      _findOpen = false;
      _findController.clear();
      _findMatches = const [];
      _findIndex = -1;
    });
  }

  /// Debounced: scanning every verse on each keystroke would stutter on long
  /// chapters (Psaume 119 = 176 versets).
  void _onFindChanged(String query) {
    _findDebounce?.cancel();
    _findDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _runFind(query);
    });
  }

  void _runFind(String query) {
    final chapter = _chapterData;
    final needle = normalizeForSearch(query);
    if (!mounted) return;
    if (needle.isEmpty || chapter == null) {
      setState(() {
        _findQuery = query;
        _findMatches = const [];
        _findIndex = -1;
      });
      return;
    }
    final matches = <int>[];
    for (var i = 0; i < chapter.verses.length; i++) {
      final v = chapter.verses[i];
      final vn = v.number == 0 ? i + 1 : v.number;
      final hay = normalizeForSearch('${v.section ?? ''} ${v.text}');
      if (hay.contains(needle)) matches.add(vn);
    }
    setState(() {
      _findQuery = query;
      _findMatches = matches;
      _findIndex = matches.isEmpty ? -1 : 0;
    });
    _jumpToCurrentMatch();
  }

  void _stepFind(int direction) {
    if (_findMatches.isEmpty) return;
    var next = _findIndex + direction;
    if (next < 0) next = _findMatches.length - 1;
    if (next >= _findMatches.length) next = 0;
    setState(() => _findIndex = next);
    _jumpToCurrentMatch();
  }

  void _jumpToCurrentMatch() {
    if (_findIndex < 0 || _findIndex >= _findMatches.length) return;
    _beginJump(_findMatches[_findIndex]);
  }

  /// The counter between the arrows — « 3/12 », or « 0 » while nothing matches.
  String get _findCounter => _findMatches.isEmpty || _findIndex < 0
      ? (_findQuery.trim().isEmpty ? '' : '0')
      : '${_findIndex + 1}/${_findMatches.length}';

  // ---- Cross references of a verse ----

  /// The « Références » action of the study sheet: every scripture reference
  /// carried by the verse's own BYM notes (« Voir Es. 45:18. »), listed in one
  /// sheet; tapping one jumps the reading to it through the same machinery as
  /// a reference tapped inline.
  Future<void> _showVerseReferences(Verse verse) async {
    final refs = <BibleReference>{
      for (final note in verse.notes)
        ...findNoteReferences(note.note).map((span) => span.reference),
    }.toList();
    if (!mounted) return;
    if (refs.isEmpty) {
      _snack('Aucune référence dans les notes de ce verset.');
      return;
    }
    refs.sort(
      (a, b) => Object.hash(
        a.bookIndex,
        a.chapter ?? 0,
        a.verse ?? 0,
      ).compareTo(Object.hash(b.bookIndex, b.chapter ?? 0, b.verse ?? 0)),
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final p = premiumPalette(sheetContext);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'Références — ${catalogEntry(widget.bookIndex).abbreviation} ${verse.verse}',
                style: premiumText(
                  sheetContext,
                  15,
                  FontWeight.w800,
                  p.textDark,
                ),
              ),
              const SizedBox(height: 8),
              for (final ref in refs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(Icons.link, color: p.primary, size: 20),
                  title: Text(ref.label),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _onReferenceTap(ref);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // ---- Immersion mode ----

  Future<void> _setImmersion(bool value) async {
    if (_prefs.immersion == value) return;
    setState(() => _prefs.immersion = value);
    // Entering immersion clears an open find: its bar is hidden anyway and
    // leftover match washes would outlive their controls.
    if (value && _findOpen) _closeFind();
    await _savePrefs();
  }

  Future<void> _editNote(Verse verse) async {
    final vn = verse.number;
    final outcome = await editVerseNotes(
      context: context,
      db: _db,
      bookIndex: widget.bookIndex,
      chapter: widget.chapter,
      verse: vn,
      reference: 'Note — ${verse.verse}',
      verseText: verse.text,
    );
    if (!mounted || outcome == null) return;
    // Several notes can share a verse now: refresh the chapter marks from
    // storage instead of adding/removing one number by hand.
    _userNotes = await _db.notesInChapter(widget.bookIndex, widget.chapter);
    if (!mounted) return;
    setState(() {});
    if (outcome == NoteEditorOutcome.saved) _snack('Note enregistrée.');
    if (outcome == NoteEditorOutcome.deleted) _snack('Note supprimée.');
  }

  /// The Lexique button of the study sheet: it always shows the *same verse*
  /// the reader is on, rendered word-by-word from the Strong corpus of the
  /// study ([EtudePreferences.versionCode] — the LSS of Biblia by default,
  /// whose anchors also number the particles the LSGS ignores) where every
  /// Strong code is tappable ([EtudeVersetScreen]) — the BYM text proposes
  /// its own equivalent verse in the Strong version. The study screen combines
  /// the Strong lexicon (hébreu/grec) and the Westphal dictionary, with
  /// prev/next verse navigation within the current chapter.
  Future<void> _openLexique(int verseNumber) async {
    final etude = await EtudePreferences.load();
    final corpus = etude.versionCode;
    final tokens = await _versions.tokensFor(
      corpus,
      widget.bookIndex,
      widget.chapter,
      verseNumber,
    );
    if (!mounted) return;
    final chapter = await _activeChapter();
    if (!mounted) return;
    final verseNumbers = [for (final v in chapter.verses) v.number];
    final returnToVerse = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EtudeVersetScreen(
          bookIndex: widget.bookIndex,
          chapter: widget.chapter,
          verseNumber: verseNumber,
          tokens: tokens,
          verseNumbers: verseNumbers,
          loadVerseTokens: (v) async {
            // Relue à chaque appel, non capturée à l'ouverture : le corpus se
            // choisit depuis l'écran d'étude lui-même, et la navigation
            // précédent / suivant doit suivre sans rouvrir l'écran.
            final etude = await EtudePreferences.load();
            return _versions.tokensFor(
              etude.versionCode,
              widget.bookIndex,
              widget.chapter,
              v,
            );
          },
          onOpenVerse: _openStrongOccurrence,
        ),
      ),
    );
    if (returnToVerse == true && mounted) _beginJump(verseNumber);
  }

  /// The Comparer button of the study sheet: it opens [ComparerScreen] on the
  /// verse the reader is on, showing it across every version present on the
  /// device (embedded BYM/LSGS/LSS + downloaded ones holding the book).
  Future<void> _openComparer(int verseNumber) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComparerScreen(
          bookIndex: widget.bookIndex,
          chapter: widget.chapter,
          verseNumber: verseNumber,
          store: _library,
        ),
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// Le tap sur un mot de l'interlinéaire ouvre sa fiche : les champs que le
  /// mot porte, et les deux liens qui en sortent — le Strong vers la fiche du
  /// lexique, le renvoi vers la page de `notes.json` qui le résout.
  ///
  /// Le Strong y est proposé **même quand [_hasStrong] est faux** : ce
  /// drapeau décrit le texte aplati de la LSGS, où les codes sont cherchés
  /// dans la chaîne (`VerseTile.strongCodePattern`); ici le code vient du mot
  /// lui-même, et le lexique le sert de la même façon. Le gate, c'est
  /// `StrongLexicon.contains`, tenu par la feuille avant d'offrir le lien.
  Future<void> _onAtiWordTap(Verse verse, AtiWord word) async {
    final reference =
        '${catalogEntry(widget.bookIndex).abbreviation} ${verse.verse}';
    await showAtiWordSheet(
      context,
      reference: reference,
      word: word,
      onStrongTap: (strong) => _onStrongTap(verse, strong),
      onNoteTap: (noteId) => AtiNoteScreen.push(
        context,
        noteId,
        onStrongTap: (strong) => _onStrongTap(verse, strong),
      ),
    );
  }

  /// Tapping a Strong code in the LSGS text opens the **extract** sheet first
  /// — the same gesture as a tap on an ATI word: what the entry is, on the
  /// spot, with the complete fiche one button away. Going straight to the full
  /// screen meant a whole route for a first look, where the reader only wanted
  /// to know which word this was.
  Future<void> _onStrongInText(Verse _, String strong) async {
    final definition = await StrongLexicon.instance.lookup(strong);
    if (!mounted) return;
    await showStrongExtractSheet(
      context,
      strong: definition,
      onOpenFull: () => _openStrongFiche(definition),
    );
  }

  /// Tapping a Strong code in a version that carries them (LSGS) opens the
  /// complete Strong word detail screen used by the rest of the app. Tapping
  /// an occurrence verse there targets that verse in the reading screen.
  Future<void> _onStrongTap(Verse _, String strong) async {
    final definition = await StrongLexicon.instance.lookup(strong);
    await _openStrongFiche(definition);
  }

  /// La fiche complète : la route que pousse tout lien Strong du lecteur —
  /// l'extrait de la LSGS, le Strong d'un mot ATI, le lien d'une note — au
  /// même endroit, avec les occurrences et leur retour au verset.
  Future<void> _openStrongFiche(StrongDefinition definition) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StrongDetailScreen(
          strong: definition,
          onOpenVerse: (bookIndex, chapter, verse) =>
              _openStrongOccurrence(bookIndex, chapter, verse),
        ),
      ),
    );
  }

  /// A Strong occurrence tapped inside the fiche: clear the fiches stacked on
  /// the shell (a code may have been reached through « Voir plus » or an
  /// etymology link, several routes deep), then open the verse through the same
  /// reference machinery as a note reference — the shell jumps the reading to
  /// it, standalone use falls back to a pushed chapter.
  void _openStrongOccurrence(int bookIndex, int chapter, int verse) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _onReferenceTap(
      BibleReference(bookIndex: bookIndex, chapter: chapter, verse: verse),
    );
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
    final p = premiumPalette(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          // Voile vertical + liseré net + deux ombres : le panneau rejoint la
          // langue des cartes premium au lieu d'un aplat à ombre unique.
          decoration: premiumSurface(context, radius: 20, depth: 1.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: p.primarySoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.cloud_download_outlined,
                  size: 32,
                  color: p.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                error.message,
                textAlign: TextAlign.center,
                style: premiumText(context, 17, FontWeight.w800, p.textDark),
              ),
              const SizedBox(height: 8),
              Text(
                error is BookNotInVersion
                    // Le canon vient du catalogue : « le Nouveau Testament »
                    // pour le NTI, « l'Ancien Testament » pour l'ATI et la
                    // SEF — écrit ici, un seul des deux aurait fini par
                    // mentir.
                    ? '${error.code} ne contient que '
                        '${versionByCode(error.code)?.canonOnly ?? 'son canon'} : '
                        'il n\'y a rien à télécharger pour ce livre.'
                    : 'Terminez le téléchargement depuis la Bibliothèque pour '
                        'lire ce livre en ${error.code}.',
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  13,
                  FontWeight.w500,
                  p.textGrey,
                  height: 1.5,
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
                  // Inutile pour un livre hors canon : la Bibliothèque n'a
                  // rien à télécharger non plus.
                  if (onOpenLibrary != null && error is! BookNotInVersion)
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
      ),
    );
  }
}

/// « Tous les réglages » — the way out of the ⋯ sheet toward the complete
/// display list. It is a **row, not a button**, and it says what it leads to:
/// a bare chevron at the bottom of a settings sheet reads as « and then? ».
class _AllSettingsRow extends StatelessWidget {
  final VoidCallback? onTap;

  const _AllSettingsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        // Liseré neutre : l'accent ne borde jamais une carte (voir
        // [premiumCardBorder]) — il reste aux filets, pastilles et icônes.
        border: Border.all(color: premiumCardBorder(context, opacity: .14)),
      ),
      child: ListTile(
        // Absent outside the shell (isolated reader, tests): the row then names
        // the destination instead of pretending to be a button.
        onTap: onTap,
        enabled: onTap != null,
        leading: Icon(Icons.tune, size: 20, color: p.primary),
        title: Text(
          'Tous les réglages',
          style: premiumText(context, 14, FontWeight.w700, p.textDark),
        ),
        subtitle: Text(
          'Police, alignement, graisse, aération, couleur, notes, thème…',
          style: premiumText(
            context,
            11.5,
            FontWeight.w500,
            p.textGrey,
            height: 1.3,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: p.textGrey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onHighlight;
  final VoidCallback onFavorite;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onDone;

  const _SelectionBar({
    super.key,
    required this.count,
    required this.onHighlight,
    required this.onFavorite,
    required this.onCopy,
    required this.onShare,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Icons only: a labelled « Terminer » button next to the actions pushed the
    // row 42 px past a 360 px screen. The bare count keeps the « combien » without
    // its sentence; closing is the ✕ at the end like everywhere else.
    //
    // Five actions now, and the row still has to fit a 320-px phone: the
    // buttons take a compact density and share the width evenly, so the *count*
    // gives way rather than the actions. 40 px is the floor — not 48, but not
    // smaller either, and the row is already only 40 px tall.
    return Material(
      elevation: 8,
      color: p.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: p.primary, size: 20),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: premiumText(context, 14, FontWeight.w700, p.textDark),
              ),
              const SizedBox(width: 6),
              Container(
                width: 1,
                height: 22,
                color: p.primary.withValues(alpha: .2),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _action(
                      Icons.format_color_fill,
                      'Surligner la sélection',
                      onHighlight,
                    ),
                    _action(
                      Icons.star_border,
                      'Favoris sur la sélection',
                      onFavorite,
                    ),
                    _action(Icons.copy_all, 'Copier les versets', onCopy),
                    _action(Icons.ios_share, 'Partager les versets', onShare),
                    _action(Icons.close, 'Terminer la sélection', onDone),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      // At the default 48 px the five buttons ask for 240 px and overflow a
      // 320-px screen.
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// End-of-chapter tile: names what comes next and moves the current tab (or
/// pushes a chapter when reading standalone). Shown only outside selection
/// mode and immersion.
class _ContinueChapterTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ContinueChapterTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = BibleThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: theme.panelBorderColor),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Fin du chapitre',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: theme.verseNumColor),
                  ),
                ),
              Expanded(
                child: Container(height: 1, color: theme.panelBorderColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              // Liseré neutre plutôt que la tranche d'accent : le libellé et
              // l'icône gardent l'or, le contour rejoint les cartes premium.
              side: BorderSide(color: premiumCardBorder(context, opacity: .45)),
              foregroundColor: theme.accentColor,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.arrow_downward, size: 18),
            label: Text('Continuer — $label'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Book metadata + introduction, shown at the top of chapter 1 (repliable).
class _BookHeader extends StatefulWidget {
  final BibleBook book;

  /// The resolved verse-body style (same object the flowing blocks and tiles
  /// use): the introduction is body prose and must be size-identical to the
  /// text that follows, in every layout.
  final TextStyle introStyle;
  const _BookHeader({required this.book, required this.introStyle});

  @override
  State<_BookHeader> createState() => _BookHeaderState();
}

class _BookHeaderState extends State<_BookHeader> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final m = book.metadata;
    final readingTheme = BibleThemeScope.of(context);
    final accent = readingTheme.accentColor;
    final dark = readingTheme.textColor;
    return Card(
      // Halo d'accent discret sous la carte (l'accent reste autorisé en halo),
      // et voile de surface neutralisé pour que le panneau du thème de lecture
      // ne soit pas teinté par l'élévation Material.
      elevation: 2,
      shadowColor: accent.withValues(alpha: .16),
      surfaceTintColor: readingTheme.panelColor.withValues(alpha: 0),
      color: readingTheme.panelColor,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: readingTheme.panelBorderColor, width: 1),
      ),
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
                    style: premiumText(context, 20, FontWeight.w800, dark),
                  ),
                ),
                IconButton(
                  tooltip: _collapsed ? 'Déplier' : 'Replier',
                  onPressed: () => setState(() => _collapsed = !_collapsed),
                  icon: Icon(
                    _collapsed ? Icons.expand_more : Icons.expand_less,
                    color: accent,
                  ),
                ),
              ],
            ),
            if (!_collapsed) ...[
              const SizedBox(height: 6),
              Text(
                '${book.abbreviation} · Traduction BYM',
                style: premiumText(
                  context,
                  12,
                  FontWeight.w700,
                  accent,
                  spacing: .2,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Container(
                  height: 1,
                  color: accent.withValues(alpha: .18),
                ),
              ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: MediaQuery.sizeOf(context).width < 600
                    ? 2.65
                    : 3.2,
                children: [
                  _metaCell('Signification', m.signification),
                  _metaCell('Auteur', m.auteur),
                  _metaCell('Thème', m.theme),
                  _metaCell('Datation', m.date),
                ],
              ),
              if (book.introduction.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Container(
                    height: 1,
                    color: accent.withValues(alpha: .18),
                  ),
                ),
                Text(book.introduction, style: widget.introStyle),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _metaCell(String label, String value) => _metaBlock(label, value);

  Widget _metaBlock(String label, String value) {
    final readingTheme = BibleThemeScope.of(context);
    final accent = readingTheme.accentColor;
    final dark = readingTheme.textColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: premiumText(
              context,
              9.5,
              FontWeight.w800,
              accent,
              spacing: .5,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: premiumText(
                context,
                10.5,
                FontWeight.w600,
                dark,
                height: 1.25,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
