import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/theme_catalog.dart';
import '../data/version_repository.dart';
import '../models/bible_book.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import '../widgets/reader_actions_bar.dart';
import '../widgets/verse_tile.dart';

enum _Side { left, right }

/// Two translations of the same chapter, side by side, kept verse-aligned.
///
/// Where [ComparerScreen] answers « how does THIS verse read elsewhere », the
/// parallel screen reads a whole chapter across two versions: pick a verse on
/// one side and the other side scrolls to it. Chapter stepping is shared —
/// the pair moves together through the BYM reading order.
class ParallelReadingScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;

  /// Version already being read (becomes the left pane).
  final String initialLeftCode;

  /// Right pane version; when null the other embedded one is picked
  /// (LSGS next to BYM), falling back to the left code.
  final String? initialRightCode;

  /// Injectable for tests: a real store reads files through `dart:io`, which
  /// never completes inside `testWidgets` fake-async.
  final LibraryStore? store;

  const ParallelReadingScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.initialLeftCode = VersionRepository.embeddedCode,
    this.initialRightCode,
    this.store,
  });

  @override
  State<ParallelReadingScreen> createState() => _ParallelReadingScreenState();
}

class _ParallelReadingScreenState extends State<ParallelReadingScreen> {
  late String _leftCode = widget.initialLeftCode;
  late String _rightCode = widget.initialRightCode ?? _pickRightDefault();
  late int _chapter = widget.chapter;

  final ScrollController _leftScroll = ScrollController();
  final ScrollController _rightScroll = ScrollController();
  final Map<String, Future<BibleBook?>> _futures = {};

  late final VersionRepository _versions =
      VersionRepository(store: widget.store ?? LibraryStore());
  Map<String, InstalledVersion> _installed = const {};
  AppPreferences? _prefs;
  (int, int)? _previous;
  (int, int)? _next;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _leftScroll.dispose();
    _rightScroll.dispose();
    super.dispose();
  }

  String _pickRightDefault() =>
      widget.initialLeftCode == VersionRepository.lsgsCode
          ? VersionRepository.embeddedCode
          : VersionRepository.lsgsCode;

  Future<void> _load() async {
    try {
      _installed = await (widget.store ?? LibraryStore()).installed();
    } catch (_) {
      _installed = const {};
    }
    final prefs = await AppPreferences.load();
    final previous = await _versions.previousChapter(
      widget.bookIndex,
      _chapter,
    );
    final next = await _versions.nextChapter(widget.bookIndex, _chapter);
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _previous = previous;
      _next = next;
    });
  }

  Future<BibleBook?> _book(String code) {
    return _futures.putIfAbsent(code, () async {
      try {
        return await _versions.loadBook(code, widget.bookIndex);
      } catch (_) {
        // Missing download or unreadable file: the pane says so.
        return null;
      }
    });
  }

  void _switchPane(_Side side, String code) {
    setState(() {
      if (side == _Side.left) {
        _leftCode = code;
      } else {
        _rightCode = code;
      }
    });
  }

  void _stepChapter(int delta) {
    setState(() => _chapter += delta);
    _load();
    _resetPanes();
  }

  void _resetPanes() {
    for (final c in [_leftScroll, _rightScroll]) {
      if (c.hasClients) c.jumpTo(0);
    }
  }

  /// Scrolls the [side] pane so [verseNumber] sits near its top — the inverse
  /// of the reader's own jump estimation, with a short convergence loop since
  /// a lazy list refines its extent while it reveals tiles.
  Future<void> _sync(_Side side, int verseNumber) async {
    final controller = side == _Side.left ? _rightScroll : _leftScroll;
    final book = await _book(side == _Side.left ? _leftCode : _rightCode);
    if (book == null || !controller.hasClients) return;
    final chapter = book.chapters.firstWhere(
      (c) => c.chapter == _chapter,
      orElse: () => book.chapters.first,
    );
    var index = -1;
    for (var i = 0; i < chapter.verses.length; i++) {
      final v = chapter.verses[i];
      if ((v.number == 0 ? i + 1 : v.number) == verseNumber) {
        index = i;
        break;
      }
    }
    if (index < 0 || !mounted) return;
    for (var attempt = 0; attempt < 6; attempt++) {
      if (!mounted || !controller.hasClients) return;
      final p = controller.position;
      final fraction =
          chapter.verses.length <= 1 ? 0.0 : index / (chapter.verses.length - 1);
      controller.jumpTo(
        (p.maxScrollExtent * fraction)
            .clamp(p.minScrollExtent, p.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = BibleThemeScope.of(context);
    final entry = catalogEntry(widget.bookIndex);
    // Half-width panes: keep the reader's chosen size, then ease off — two
    // columns of 22 pt read like shouting. The narrow-screen reduction itself
    // comes from the ambient `textScaler` (`main.dart`), so it is NOT re-applied
    // here; feeding a half-width into a second ladder cut these panes by up to
    // 29 % of the size the reader picked.
    final baseSize =
        ReadingTextSize.nearest(_prefs?.fontSize ?? 22).fontSize * .88;
    // Same rhythm as the single reader: gaps and leading follow the size so
    // the half-width panes stay as airy as the full one.
    final rhythm = ReadingRhythm(
      fontSize: baseSize,
      spacing: _prefs?.spacing ?? ReadingSpacing.normal,
    );
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: premiumBackground(context),
        foregroundColor: premiumPalette(context).primary,
        title: Text(
          '${entry.barLabel} $_chapter',
          style: premiumText(context, 16, FontWeight.w800,
              premiumPalette(context).primary),
        ),
        actions: [
          IconButton(
            tooltip: 'Chapitre précédent',
            onPressed: _previous == null ? null : () => _stepChapter(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Chapitre suivant',
            onPressed: _next == null ? null : () => _stepChapter(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _Pane(
                side: _Side.left,
                code: _leftCode,
                chapter: _chapter,
                installed: _installed,
                future: _book(_leftCode),
                theme: theme,
                fontSize: baseSize,
                rhythm: rhythm,
                textAlign: _prefs?.textAlign.align ?? TextAlign.left,
                scrollController: _leftScroll,
                onSelectVersion: (code) => _switchPane(_Side.left, code),
                onVerseTap: (vn) => _sync(_Side.left, vn),
              ),
            ),
            VerticalDivider(width: 1, color: premiumPalette(context).primary.withValues(alpha: .15)),
            Expanded(
              child: _Pane(
                side: _Side.right,
                code: _rightCode,
                chapter: _chapter,
                installed: _installed,
                future: _book(_rightCode),
                theme: theme,
                fontSize: baseSize,
                rhythm: rhythm,
                textAlign: _prefs?.textAlign.align ?? TextAlign.left,
                scrollController: _rightScroll,
                onSelectVersion: (code) => _switchPane(_Side.right, code),
                onVerseTap: (vn) => _sync(_Side.right, vn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One half of the parallel view: a version pill above its own verse list.
class _Pane extends StatelessWidget {
  final _Side side;
  final String code;
  final int chapter;
  final Map<String, InstalledVersion> installed;
  final Future<BibleBook?> future;
  final BibleTheme theme;
  final double fontSize;
  final ReadingRhythm rhythm;
  final TextAlign textAlign;
  final ScrollController scrollController;
  final ValueChanged<String> onSelectVersion;
  final ValueChanged<int> onVerseTap;

  const _Pane({
    required this.side,
    required this.code,
    required this.chapter,
    required this.installed,
    required this.future,
    required this.theme,
    required this.fontSize,
    required this.rhythm,
    required this.textAlign,
    required this.scrollController,
    required this.onSelectVersion,
    required this.onVerseTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: p.surface,
          child: InkWell(
            onTap: () => showVersionSheet(
              context,
              activeCode: code,
              installed: installed,
              onSelect: onSelectVersion,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: p.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      code,
                      style: premiumText(context, 13, FontWeight.w800, p.textDark),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.expand_more, size: 18, color: p.textGrey),
                ],
              ),
            ),
          ),
        ),
        Container(height: 1, color: p.primary.withValues(alpha: .10)),
        Expanded(
          child: FutureBuilder<BibleBook?>(
            future: future,
            builder: (context, snapshot) {
              final error = snapshot.error;
              if (error is BookNotDownloaded) {
                return _MissingPane(message: error.message);
              }
              if (!snapshot.hasData) {
                if (snapshot.hasError) {
                  return _MissingPane(message: 'Erreur : ${snapshot.error}');
                }
                // Lignes de versets fantômes (sans en-tête de livre : le
                // panneau n'en montre jamais) plutôt qu'un spinner nu au
                // centre d'un panneau qui a déjà son chrome.
                return const Padding(
                  padding: EdgeInsets.all(14),
                  child: ChapterLoadingSkeleton(
                    header: false,
                    verseCount: 9,
                  ),
                );
              }
              final book = snapshot.data!;
              final chapter = book.chapters.firstWhere(
                (c) => c.chapter == this.chapter,
                orElse: () => book.chapters.first,
              );
              // Same bodyLarge override as [ChapterVerseList]: the verse body
              // follows the chosen size, the numbers stay compact.
              final materialTheme = Theme.of(context);
              final scoped = materialTheme.copyWith(
                textTheme: materialTheme.textTheme.copyWith(
                  bodyLarge: (materialTheme.textTheme.bodyLarge ??
                          const TextStyle())
                      .copyWith(
                    fontSize: fontSize,
                    color: theme.textColor,
                    height: rhythm.lineHeight,
                    letterSpacing: rhythm.letterSpacing,
                  ),
                  bodySmall:
                      (materialTheme.textTheme.bodySmall ?? const TextStyle())
                          .copyWith(color: theme.textColor),
                  titleMedium:
                      (materialTheme.textTheme.titleMedium ?? const TextStyle())
                          .copyWith(color: theme.titleColor),
                ),
              );
              return Theme(
                data: scoped,
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                  itemCount: chapter.verses.length,
                  itemBuilder: (context, i) {
                    final verse = chapter.verses[i];
                    final vn = verse.number == 0 ? i + 1 : verse.number;
                    return VerseTile(
                      key: ValueKey('${side.name}_${code}_$vn'),
                      verse: verse,
                      showNotes: false,
                      verseNumber: vn,
                      rhythm: rhythm,
                      onTap: () => onVerseTap(vn),
                      theme: theme,
                      textAlign: textAlign,
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A pane whose version does not hold this book: said plainly, no silent BYM.
class _MissingPane extends StatelessWidget {
  final String message;
  const _MissingPane({required this.message});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 32, color: p.textGrey),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: premiumText(context, 13, FontWeight.w600, p.textGrey,
                  height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}
