import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/local_repository.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../models/chapter.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';

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
    this.versionCode = VersionRepository.embeddedCode,
    this.installedVersions = const {},
    this.onSelectVersion,
    this.onOpenLibrary,
    required this.onOpenChapter,
    this.onVerses,
    this.onPreviousChapter,
    this.onNextChapter,
    this.trailing,
  });

  /// Pill label: `Bereshit 1` on the BYM, `Genèse 1` on any translation, or
  /// « Livres » with no open chapter. Uses the compact form so a long name never
  /// overflows the bar — and takes the *reader's* version, because that pill is
  /// where « which text am I in? » is answered without asking.
  String get reference {
    final book = bookIndex;
    final number = chapter;
    if (book == null || number == null) return 'Livres';
    return '${bookDisplayLabel(book, code: versionCode, embeddedCode: VersionRepository.embeddedCode)} $number';
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      color: premiumBackground(context),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: _Pill(
                          label: reference,
                          side: _PillSide.left,
                          onTap: () => showBooksSheet(
                            context,
                            currentBook: bookIndex,
                            currentChapter: chapter,
                            onSelect: onOpenChapter,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _Pill(
                        label: versionCode,
                        side: _PillSide.right,
                        filled: true,
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
                        color: p.primary,
                        disabledColor: p.textGrey,
                        icon: const Icon(Icons.keyboard_double_arrow_down),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Chapitre précédent',
                  onPressed: onPreviousChapter,
                  visualDensity: VisualDensity.compact,
                  color: p.primary,
                  disabledColor: p.textGrey,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Chapitre suivant',
                  onPressed: onNextChapter,
                  visualDensity: VisualDensity.compact,
                  color: p.primary,
                  disabledColor: p.textGrey,
                  icon: const Icon(Icons.chevron_right),
                ),
                ?trailing,
              ],
            ),
          ),
          // Filet d'accent : un dégradé horizontal (transparent → accent →
          // transparent) plutôt qu'un trait plein — le trait pleine largeur
          // coupait la barre d'un trait monotone, le dégradé la fait s'éteindre
          // vers les bords.
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.primary.withValues(alpha: 0),
                  p.primary.withValues(alpha: .22),
                  p.primary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PillSide { left, right }

/// One half of the joined pill group: fully rounded on its outer edge, barely
/// rounded on the edge facing the other half.
///
/// The reference half is a surface card with the **neutral** liseré of the
/// premium cards (an accent border here read as a coloured outline on every
/// warm palette); the version half is filled with the theme gradient so the
/// two read as one segmented control.
class _Pill extends StatelessWidget {
  final String label;
  final _PillSide side;
  final bool filled;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.side,
    this.filled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    const outer = Radius.circular(16);
    const inner = Radius.circular(5);
    final radius = side == _PillSide.left
        ? const BorderRadius.horizontal(left: outer, right: inner)
        : const BorderRadius.horizontal(left: inner, right: outer);
    return Material(
      color: filled ? null : p.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: filled ? p.heroGradient : null,
          borderRadius: radius,
          border: filled
              ? null
              : Border.all(
                  color: premiumCardBorder(context, opacity: .28),
                ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 360 ? 8 : 14,
              vertical: 8,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: premiumText(
                context,
                13,
                FontWeight.w700,
                filled ? p.onPrimary : p.primary,
              ),
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
    final p = premiumPalette(context);
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 48),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: premiumText(context, 16, FontWeight.w800, p.primary),
              ),
            ),
            SizedBox(width: 48, child: menu),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: p.primary.withValues(alpha: .12)),
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
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: premiumBackground(context),
    builder: (sheetContext) => Padding(
      // Android 3-button and gesture navigation can overlay modal routes.
      // Reserve that physical system area around the sheet itself, not merely
      // at the end of its scrollable content (same guard as the study sheet).
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(sheetContext).bottom,
      ),
      // Panneau « premium affirmé » : voile vertical `surface → surfaceAlt`,
      // liseré net et deux ombres (ambiante large + serrée de contact), sous
      // la poignée de traction que la feuille dessine déjà.
      child: Container(
        decoration: premiumSurface(sheetContext, radius: 24, depth: 1.3),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .85,
          child: _BooksSheet(
            currentBook: currentBook,
            currentChapter: currentChapter,
            onSelect: onSelect,
          ),
        ),
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
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final section in bibleSections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                  child: Text(
                    section.name,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w800,
                      premiumPalette(context).primary,
                      spacing: .9,
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
    final p = premiumPalette(context);
    final active = bymIndex == widget.currentBook;
    final expanded = bymIndex == _expanded;
    return Column(
      children: [
        Material(
          color: active ? p.primarySoft : Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _expanded = expanded ? null : bymIndex),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // Le nom BYM complet (« Bereshit (Genèse) »), pas le
                      // raccourci français : cette feuille est la table des
                      // matières DE LA VERSION BYM, ses intitulés font partie
                      // du texte. `bilingualName` complète les livres que le
                      // catalogue ne portait qu'en français — tout Évangiles
                      // et Testament de Yehoshoua, Amos → Daniel — de leur
                      // tête BYM (« Mattithyah (Matthieu) », « Roma
                      // (Romains) »). La pilule de référence, elle, garde le
                      // compact [BookEntry.barLabel] pour ne pas déborder.
                      catalogEntry(bymIndex).bilingualName,
                      style: premiumText(
                        context,
                        15,
                        active ? FontWeight.w800 : FontWeight.w600,
                        active ? p.primary : p.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? p.primary.withValues(alpha: .16)
                          : p.primarySoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      catalogEntry(bymIndex).abbreviation,
                      style: premiumText(
                        context,
                        11.5,
                        FontWeight.w800,
                        p.primary,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: active ? p.primary : p.textGrey,
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
        Divider(
          height: 1,
          indent: 20,
          endIndent: 20,
          color: p.textGrey.withValues(alpha: .18),
        ),
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
  late final Future<int> _count = LocalRepository().chapterCount(
    widget.bookIndex,
  );

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
          // Tuiles fantômes à la taille exacte des _NumberTile (52×46) : la
          // grille se matérialise sans saut de layout.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            child: LoadingSkeleton(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < 18; i++)
                    const SkeletonBox(width: 52, height: 46, radius: 10),
                ],
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
    final p = premiumPalette(context);
    return SizedBox(
      width: 52,
      height: 46,
      child: Material(
        color: p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: current
              ? BorderSide(color: p.primary, width: 2)
              : BorderSide(color: p.textGrey.withValues(alpha: .22)),
        ),
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              '$number',
              style: premiumText(
                context,
                15,
                current ? FontWeight.w800 : FontWeight.w600,
                current ? p.primary : p.textDark,
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
/// (`modif/resultat_vers_les_versions.jpg`): a code line, the name, then the
/// date + licence — but only the ones this device can read: the embedded BYM,
/// and what the Bibliothèque has downloaded.
///
/// The rest of the catalogue used to sit here too, greyed, answering « à
/// télécharger depuis la Bibliothèque » when tapped — a dozen rows the reader
/// could not use, and a second place where downloads were half-managed. Picking
/// a version belongs here; getting one belongs to the Bibliothèque, which the
/// footer row leads to.
///
/// [installed] comes from `LibraryStore.installed()`. [onSelect] null means
/// the caller has no chapter open to switch (the « Nouvel onglet » bars).
/// [onOpenLibrary] null leaves the footer naming the Bibliothèque without
/// leading anywhere (screens used on their own).
Future<void> showVersionSheet(
  BuildContext context, {
  String activeCode = 'BYM',
  Map<String, InstalledVersion> installed = const {},
  ValueChanged<String>? onSelect,
  VoidCallback? onOpenLibrary,
}) {
  /// Readable now: the embedded BYM, or a version with books on the device.
  /// A partial download counts — its books read, the missing ones say so.
  bool readable(VersionEntry version) =>
      version.embedded || installed[version.code]?.isEmpty == false;

  /// The catalogue reduced to what can be opened, groups included: a heading
  /// with nothing under it reads as a broken list.
  final groups = [
    for (final group in versionCatalog)
      if (group.versions.any(readable))
        (title: group.title, versions: group.versions.where(readable).toList()),
  ];

  /// How many the Bibliothèque still has to offer — the footer says it rather
  /// than leaving the reader to wonder where the other translations went.
  final elsewhere = versionCatalog
      .expand((group) => group.versions)
      .where((version) => !readable(version))
      .length;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: premiumBackground(context),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(sheetContext).bottom,
      ),
      // Même panneau que la feuille « Livres » : voile, liseré net, deux
      // ombres — les trois feuilles du lecteur parlent le même langage.
      child: Container(
        decoration: premiumSurface(sheetContext, radius: 24, depth: 1.3),
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .8,
          child: Column(
            children: [
              const _SheetHeader(title: 'Version'),
              Expanded(
                child: ListView(
                  key: const Key('versionSheetList'),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    for (final group in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              group.title,
                              style: premiumText(
                                sheetContext,
                                13,
                                FontWeight.w800,
                                premiumPalette(sheetContext).textGrey,
                                spacing: .4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 1,
                              color: premiumPalette(
                                sheetContext,
                              ).primary.withValues(alpha: .12),
                            ),
                          ],
                        ),
                      ),
                      for (final version in group.versions)
                        _VersionRow(
                          version: version,
                          active: version.code == activeCode,
                          state: installed[version.code],
                          onSelect: onSelect,
                        ),
                    ],
                    if (elsewhere > 0)
                      _LibraryFooter(count: elsewhere, onOpen: onOpenLibrary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Last row of the « Version » sheet: the way to the translations the device
/// does not hold yet.
///
/// The sheet lists only what can be read, so without this the other versions
/// would simply be invisible — the reader would have no reason to suspect the
/// Bibliothèque had more.
class _LibraryFooter extends StatelessWidget {
  final int count;

  /// Null when the screen has no Bibliothèque to switch to (standalone use):
  /// the row then names it rather than pretending to be a button.
  final VoidCallback? onOpen;

  const _LibraryFooter({required this.count, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final open = onOpen;
    final label =
        '$count autre${count > 1 ? 's' : ''} '
        'version${count > 1 ? 's' : ''} à télécharger';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Container(height: 1, color: p.textGrey.withValues(alpha: .18)),
        ),
        InkWell(
          onTap: open == null
              ? null
              : () {
                  Navigator.of(context).pop();
                  open();
                },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.library_books_outlined,
                    size: 20,
                    color: p.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bibliothèque',
                        style: premiumText(
                          context,
                          15,
                          FontWeight.w800,
                          p.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: premiumText(
                          context,
                          12,
                          FontWeight.w500,
                          p.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                if (open != null) Icon(Icons.chevron_right, color: p.textGrey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VersionRow extends StatelessWidget {
  final VersionEntry version;
  final bool active;

  /// What the device holds of this version; null when nothing was downloaded.
  final InstalledVersion? state;

  final ValueChanged<String>? onSelect;

  const _VersionRow({
    required this.version,
    required this.active,
    this.state,
    this.onSelect,
  });

  /// The extra line under the licence, for what is on the device.
  String? get _installedLine {
    final s = state;
    if (s == null || s.isEmpty) return null;
    if (s.isComplete) return 'Téléchargée · ${s.bookCount} livres';
    return 'Téléchargée en partie · ${s.bookCount}/${bookCatalog.length} livres';
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final installedLine = _installedLine;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: active ? p.primarySoft : p.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _select(context),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? p.primary.withValues(alpha: .35)
                    : p.textGrey.withValues(alpha: .15),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      version.code,
                      style: premiumText(
                        context,
                        11,
                        FontWeight.w800,
                        active ? p.primary : p.textGrey,
                        spacing: .6,
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check, color: p.primary, size: 18),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  version.name,
                  style: premiumText(
                    context,
                    15,
                    FontWeight.w800,
                    active ? p.primary : p.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  version.rights,
                  style: premiumText(context, 12, FontWeight.w500, p.textGrey),
                ),
                if (installedLine != null)
                  Text(
                    installedLine,
                    style: premiumText(context, 12, FontWeight.w700, p.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Every row of the sheet is readable, so a tap either switches or explains
  /// there is nothing to switch — the « à télécharger » and « bientôt
  /// disponible » answers left with the rows that carried them.
  void _select(BuildContext context) {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    if (active) return;

    // Nothing to switch without an open chapter (the « Nouvel onglet » bars).
    if (onSelect == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Ouvrez un chapitre pour changer de version.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    onSelect!(version.code);
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
    backgroundColor: premiumBackground(context),
    builder: (sheetContext) => SafeArea(
      child: Container(
        decoration: premiumSurface(sheetContext, radius: 24, depth: 1.3),
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
