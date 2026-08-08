import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/local_repository.dart';
import '../data/version_catalog.dart';
import '../models/chapter.dart';

const Color _gold = Color(0xFFD3A94F);

/// Bottom padding a scrolling sheet needs to clear the system navigation.
///
/// The sheets are sized as a fraction of the screen, which includes the area
/// the Android gesture bar (or the 3-button bar) sits over: with a flat 24 the
/// last row of the list — KJV in « Version », the last chapter tile in
/// « Livres » — was drawn underneath it and could not be tapped.
///
/// `viewPadding` rather than `padding`: inside a sheet the latter is already
/// consumed by the route, and reads 0.
double sheetBottomInset(BuildContext context) =>
    24 + MediaQuery.viewPaddingOf(context).bottom;

/// The reading action bar (maquette `modif/3boutons.jpg`): a joined pill group
/// showing the **current reference** (`Genèse 1`) and the **active version code**
/// (`BYM`), followed by a **double-chevron** that jumps to a verse of the chapter.
///
/// Each element opens a bottom sheet:
/// - reference → « Livres » (accordion of the 5 sections, inline chapter grid),
/// - version → « Version » (grouped translations),
/// - chevron → « Aller au verset » (grid of verse numbers).
///
/// On the right, ‹ › step one chapter back / forward in reading order.
///
/// [bookIndex]/[chapter] are null when no chapter is open (e.g. the no-tab home):
/// the pill then reads « Livres » and the chevron and arrows are disabled.
/// [trailing] hosts the ⋯ menu of the caller (reading display options).
class ReaderActionsBar extends StatelessWidget {
  final int? bookIndex;
  final int? chapter;

  /// Code of the version being read, shown on the second pill.
  final String versionCode;

  /// What the device holds, from `LibraryStore.installed()` — the « Version »
  /// sheet only offers what can actually be read.
  final Map<String, InstalledVersion> installedVersions;

  /// Called with the code picked in the « Version » sheet. Null disables
  /// switching (no chapter open to switch).
  final ValueChanged<String>? onSelectVersion;

  /// Opens the Bibliothèque destination — what the « Version » sheet points at
  /// when a translation still has to be downloaded.
  final VoidCallback? onOpenLibrary;

  /// Called with the book + chapter picked in the « Livres » sheet.
  final void Function(int bookIndex, int chapter) onOpenChapter;

  /// Null disables the verse chevron (no chapter to jump inside).
  final VoidCallback? onVerses;

  /// Steps one chapter back / forward in BYM reading order (crossing books).
  /// Null disables the arrow: no chapter open, or an end of the Bible.
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;

  final Widget? trailing;

  const ReaderActionsBar({
    super.key,
    this.bookIndex,
    this.chapter,
    this.versionCode = 'BYM',
    this.installedVersions = const {},
    this.onSelectVersion,
    this.onOpenLibrary,
    required this.onOpenChapter,
    this.onVerses,
    this.onPreviousChapter,
    this.onNextChapter,
    this.trailing,
  });

  /// Pill label: `Genèse 1`, or « Livres » with no open chapter.
  String get reference {
    final book = bookIndex;
    final number = chapter;
    if (book == null || number == null) return 'Livres';
    return '${catalogEntry(book).shortName} $number';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              children: [
                _Pill(
                  label: reference,
                  side: _PillSide.left,
                  onTap: () => showBooksSheet(
                    context,
                    currentBook: bookIndex,
                    currentChapter: chapter,
                    onSelect: onOpenChapter,
                  ),
                ),
                const SizedBox(width: 2),
                _Pill(
                  label: versionCode,
                  side: _PillSide.right,
                  onTap: () => showVersionSheet(
                    context,
                    activeCode: versionCode,
                    installed: installedVersions,
                    onSelect: onSelectVersion,
                    onOpenLibrary: onOpenLibrary,
                  ),
                ),
                IconButton(
                  tooltip: 'Aller au verset',
                  onPressed: onVerses,
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.outline,
                  icon: const Icon(Icons.keyboard_double_arrow_down),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Chapitre précédent',
                  onPressed: onPreviousChapter,
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.outline,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Chapitre suivant',
                  onPressed: onNextChapter,
                  visualDensity: VisualDensity.compact,
                  color: theme.colorScheme.outline,
                  icon: const Icon(Icons.chevron_right),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: theme.dividerColor),
        ],
      ),
    );
  }
}

enum _PillSide { left, right }

/// One half of the joined pill group: fully rounded on its outer edge, barely
/// rounded on the edge facing the other half.
class _Pill extends StatelessWidget {
  final String label;
  final _PillSide side;
  final VoidCallback onTap;

  const _Pill({required this.label, required this.side, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const outer = Radius.circular(18);
    const inner = Radius.circular(5);
    final radius = side == _PillSide.left
        ? const BorderRadius.horizontal(left: outer, right: inner)
        : const BorderRadius.horizontal(left: inner, right: outer);
    return Material(
      color: theme.colorScheme.secondaryContainer.withValues(alpha: .8),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Centered sheet title with the maquette's drag-handle layout, plus an optional
/// overflow menu aligned right.
class _SheetHeader extends StatelessWidget {
  final String title;
  final Widget? menu;

  const _SheetHeader({required this.title, this.menu});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            SizedBox(width: 48, child: menu),
          ],
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// « Livres » sheet
// ---------------------------------------------------------------------------

/// Books navigation as a bottom sheet (maquette
/// `modif/resultat_vers_les_leslivres_et_chapitres.jpg`): one row per book,
/// tapping it unfolds the chapter grid in place. The BYM order and the five
/// sections are kept (décision 2).
Future<void> showBooksSheet(
  BuildContext context, {
  int? currentBook,
  int? currentChapter,
  required void Function(int bookIndex, int chapter) onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .85,
      child: _BooksSheet(
        currentBook: currentBook,
        currentChapter: currentChapter,
        onSelect: onSelect,
      ),
    ),
  );
}

class _BooksSheet extends StatefulWidget {
  final int? currentBook;
  final int? currentChapter;
  final void Function(int bookIndex, int chapter) onSelect;

  const _BooksSheet({
    this.currentBook,
    this.currentChapter,
    required this.onSelect,
  });

  @override
  State<_BooksSheet> createState() => _BooksSheetState();
}

class _BooksSheetState extends State<_BooksSheet> {
  /// Single open book at a time (accordion), starting on the one being read.
  int? _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.currentBook;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _SheetHeader(
          title: 'Livres',
          menu: PopupMenuButton<void>(
            tooltip: 'Options des livres',
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: () => setState(() => _expanded = null),
                child: const Text('Replier tout'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
            children: [
              for (final section in bibleSections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    section.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: .4,
                    ),
                  ),
                ),
                for (var i = section.from; i <= section.to; i++) _bookRow(i),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _bookRow(int bymIndex) {
    final theme = Theme.of(context);
    final active = bymIndex == widget.currentBook;
    final expanded = bymIndex == _expanded;
    return Column(
      children: [
        Material(
          color: active
              ? theme.colorScheme.primaryContainer.withValues(alpha: .35)
              : Colors.transparent,
          child: InkWell(
            onTap: () =>
                setState(() => _expanded = expanded ? null : bymIndex),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      catalogEntry(bymIndex).shortName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: active ? theme.colorScheme.primary : null,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded)
          _ChapterGrid(
            bookIndex: bymIndex,
            currentChapter: active ? widget.currentChapter : null,
            onSelect: (chapter) {
              Navigator.of(context).pop();
              widget.onSelect(bymIndex, chapter);
            },
          ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Chapter numbers of one book, unfolded under its row.
class _ChapterGrid extends StatefulWidget {
  final int bookIndex;
  final int? currentChapter;
  final ValueChanged<int> onSelect;

  const _ChapterGrid({
    required this.bookIndex,
    this.currentChapter,
    required this.onSelect,
  });

  @override
  State<_ChapterGrid> createState() => _ChapterGridState();
}

class _ChapterGridState extends State<_ChapterGrid> {
  late final Future<int> _count =
      LocalRepository().chapterCount(widget.bookIndex);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _count,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Erreur : ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var c = 1; c <= snapshot.data!; c++)
                _NumberTile(
                  number: c,
                  current: c == widget.currentChapter,
                  onTap: () => widget.onSelect(c),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A square-ish number tile used by both the chapter grid and the verse grid.
class _NumberTile extends StatelessWidget {
  final int number;
  final bool current;
  final VoidCallback onTap;

  const _NumberTile({
    required this.number,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 52,
      height: 46,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .7),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: current
              ? const BorderSide(color: _gold, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              '$number',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// « Version » sheet
// ---------------------------------------------------------------------------

/// Translations grouped as in the maquette
/// (`modif/resultat_vers_les_versions.jpg`): a code line, the name (with a 🔊
/// when an audio reading exists), then the date + licence. BYM is the embedded
/// default; a version downloaded through the Bibliothèque can be picked here,
/// the others answer « à télécharger » or « bientôt disponible ».
///
/// [installed] comes from `LibraryStore.installed()`; a version absent from it
/// cannot be selected, whatever the catalogue promises. [onSelect] null means
/// the caller has no chapter open to switch (the « Nouvel onglet » bars).
/// [onOpenLibrary] turns the « à télécharger » snackbar into a way out: without
/// it the row names the Bibliothèque without leading anywhere.
Future<void> showVersionSheet(
  BuildContext context, {
  String activeCode = 'BYM',
  Map<String, InstalledVersion> installed = const {},
  ValueChanged<String>? onSelect,
  VoidCallback? onOpenLibrary,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .8,
      child: Column(
        children: [
          const _SheetHeader(title: 'Version'),
          Expanded(
            child: ListView(
              key: const Key('versionSheetList'),
              padding: EdgeInsets.only(bottom: sheetBottomInset(sheetContext)),
              children: [
                for (final group in versionCatalog) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          group.title,
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                  for (final version in group.versions)
                    _VersionRow(
                      version: version,
                      active: version.code == activeCode,
                      state: installed[version.code],
                      onSelect: onSelect,
                      onOpenLibrary: onOpenLibrary,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _VersionRow extends StatelessWidget {
  final VersionEntry version;
  final bool active;

  /// What the device holds of this version; null when nothing was downloaded.
  final InstalledVersion? state;

  final ValueChanged<String>? onSelect;

  /// Opens the Bibliothèque tab, when the shell offers one.
  final VoidCallback? onOpenLibrary;

  const _VersionRow({
    required this.version,
    required this.active,
    this.state,
    this.onSelect,
    this.onOpenLibrary,
  });

  /// Readable now: the embedded BYM, or a version with books on the device.
  /// A partial download counts — its books read, the missing ones say so.
  bool get _readable => version.embedded || (state?.isEmpty == false);

  /// The extra line under the licence, for what is on the device.
  String? get _installedLine {
    final s = state;
    if (s == null || s.isEmpty) return null;
    if (s.isComplete) return 'Téléchargée · ${s.bookCount} livres';
    return 'Téléchargée en partie · ${s.bookCount}/${bookCatalog.length} livres';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final accent = theme.colorScheme.primary;
    final unavailable = version.availability == VersionAvailability.unavailable;

    // Faithful to the maquette: available rows read at full strength, the ones
    // we cannot serve yet are dimmed; the active version is tinted with the
    // primary colour.
    final codeColor = active
        ? accent.withValues(alpha: .7)
        : onSurface.withValues(alpha: unavailable ? .32 : .5);
    final nameColor = active
        ? accent
        : onSurface.withValues(alpha: unavailable ? .45 : 1);
    final rightsColor = onSurface.withValues(alpha: unavailable ? .3 : .5);
    final installedLine = _installedLine;

    return InkWell(
      onTap: () => _select(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              version.code,
              style: theme.textTheme.labelMedium?.copyWith(
                color: codeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(
                    version.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: nameColor,
                    ),
                  ),
                ),
                if (version.hasAudio) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.volume_up_outlined,
                    size: 18,
                    color: active ? accent : onSurface.withValues(alpha: .55),
                  ),
                ],
                if (active) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, color: _gold, size: 20),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              version.rights,
              style: theme.textTheme.bodySmall?.copyWith(color: rightsColor),
            ),
            if (installedLine != null)
              Text(
                installedLine,
                style: theme.textTheme.bodySmall?.copyWith(color: accent),
              ),
          ],
        ),
      ),
    );
  }

  void _select(BuildContext context) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    if (active) return;

    if (_readable) {
      // Nothing to switch without an open chapter (the « Nouvel onglet » bars).
      if (onSelect == null) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Ouvrez un chapitre pour changer de version.'),
          duration: Duration(seconds: 2),
        ));
        return;
      }
      onSelect!(version.code);
      return;
    }

    // Downloadable but absent: name the way out instead of only naming the
    // Bibliothèque. Deliberately an action rather than an immediate jump —
    // browsing the list should not throw the reader out of their chapter.
    final open = onOpenLibrary;
    if (version.downloadable && open != null) {
      messenger.showSnackBar(SnackBar(
        content: Text('${version.code} — à télécharger depuis la Bibliothèque.'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Ouvrir', onPressed: open),
      ));
      return;
    }

    final message = version.downloadable
        ? '${version.code} — à télécharger depuis la Bibliothèque.'
        : '${version.code} — bientôt disponible.';
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// « Aller au verset » sheet
// ---------------------------------------------------------------------------

/// Grid of the chapter's verse numbers (maquette
/// `modif/resultat_vers_les_versetdu_chapitre.jpg`); the picked number is
/// reported through [onSelect] once the sheet is closed.
Future<void> showVersePickerSheet(
  BuildContext context,
  Chapter chapter, {
  int? currentVerse,
  required ValueChanged<int> onSelect,
}) async {
  final selected = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _SheetHeader(title: 'Aller au verset'),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < chapter.verses.length; i++)
                    _verseTile(sheetContext, chapter, i, currentVerse),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  if (selected != null) onSelect(selected);
}

Widget _verseTile(
  BuildContext context,
  Chapter chapter,
  int index,
  int? currentVerse,
) {
  final verse = chapter.verses[index];
  final number = verse.number == 0 ? index + 1 : verse.number;
  return _NumberTile(
    number: number,
    current: number == currentVerse,
    onTap: () => Navigator.of(context).pop(number),
  );
}
