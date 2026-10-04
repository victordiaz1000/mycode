import 'dart:async';

import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/book_catalog.dart';
import '../data/dictionary_catalog.dart';
import '../data/dictionary_reader.dart';
import '../data/dictionary_store.dart';
import '../data/fredaw_lexicon.dart';
import '../data/library_store.dart';
import '../data/reference_parser.dart';
import '../data/search_engine.dart';
import '../data/strong_lexicon.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/premium_style.dart';
import '../widgets/loading_skeleton.dart';
import 'dictionary_entry_screen.dart';
import 'fredaw_entry_screen.dart';
import 'strong_detail_screen.dart';

/// Icon and accent colour of a search category — the coloured glyphs of the
/// maquette (`rech/`). Backgrounds are derived from [color] so the chip row,
/// the row tiles and the count badges stay one family.
class _CategoryStyle {
  final IconData icon;
  final Color color;

  const _CategoryStyle(this.icon, this.color);
}

_CategoryStyle _styleOf(BuildContext context, SearchCategory category) {
  final p = premiumPalette(context);
  final icon = switch (category) {
    SearchCategory.passages => Icons.menu_book_outlined,
    SearchCategory.notes => Icons.description_outlined,
    SearchCategory.liens => Icons.link,
    SearchCategory.etudes => Icons.history_edu_outlined,
    SearchCategory.strong => Icons.translate,
    SearchCategory.dictionnaire => Icons.abc,
    SearchCategory.nave => Icons.hub_outlined,
  };
  final color = switch (category) {
    SearchCategory.passages => p.primary,
    SearchCategory.notes => p.hebrew,
    SearchCategory.liens => p.greek,
    SearchCategory.etudes => p.primaryDark,
    SearchCategory.strong => p.greek,
    SearchCategory.dictionnaire => p.hebrew,
    SearchCategory.nave => p.primaryDark,
  };
  return _CategoryStyle(icon, color);
}

/// The chip row and the result list build lazily, so tests have to scroll them
/// to reach the last chips and rows. These keys make the right list
/// addressable: a [TextField] owns a horizontal scrollable of its own, so
/// picking one by axis is not enough.
const Key categoryRowKey = ValueKey('search-category-row');
const Key resultListKey = ValueKey('search-result-list');

/// Unified search (maquette `rech/`), au goût premium : fond crème, champ
/// blanc à ombre douce, tuiles de résultats en cartes.
///
/// One field searches every source at once — scripture references, the
/// full text of the 66 embedded books, the user's notes, the chapters already
/// studied and the BYM dictionary — and groups the results by category. The
/// chip row filters which categories are queried; the four menus underneath
/// narrow the corpus (version, section, book) and the ordering.
///
/// Categories with no data source yet (Liens, Nave) are listed but disabled,
/// so the layout matches the design and only needs wiring later.
class SearchScreen extends StatefulWidget {
  /// Opens a chapter in a reading tab (and optionally jumps to a verse),
  /// then switches to the Lecture destination.
  final void Function(int bookIndex, int chapter, {int? verse}) onOpenReading;

  /// Engine to search with. Injectable for tests: the default one reaches
  /// [AppDatabase], whose path_provider call never completes inside the
  /// fake-async zone of `testWidgets` (same reason as
  /// [LocalRepository.useBundle]).
  final SearchEngine? engine;

  /// Registry of downloaded versions, for the « Version » menu. Injectable for
  /// the same reason as [engine]: the real one reads through path_provider.
  final LibraryStore? store;

  /// Downloaded dictionaries, so the Dictionnaire category can open a hit from
  /// a downloaded dictionary (Bailly, GBM…) in its own fiche. Injectable for
  /// the same reason as [store].
  final DictionaryStore? dictionaryStore;

  /// Switches to the Bibliothèque destination. Null when the screen stands
  /// alone (tests): the « Version » menu then still names what is missing, but
  /// its last row leads nowhere rather than to a dead end.
  final VoidCallback? onOpenLibrary;

  /// Requête demandée depuis l'extérieur (la puce « Jean 3.16 » de
  /// l'accueil). L'écran vit dans l'`IndexedStack` du shell : un simple
  /// paramètre de construction ne suffirait pas à atteindre une page déjà
  /// montée — le shell écrit dans ce notificateur et l'écran écoute, puis le
  /// remet à null une fois consommé. Null en usage isolé.
  final ValueNotifier<String?>? request;

  const SearchScreen({
    super.key,
    required this.onOpenReading,
    this.engine,
    this.store,
    this.dictionaryStore,
    this.onOpenLibrary,
    this.request,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  late final SearchEngine _engine = widget.engine ?? SearchEngine();
  late final LibraryStore _library = widget.store ?? LibraryStore();
  late final DictionaryStore _dictStore =
      widget.dictionaryStore ?? DictionaryStore();

  /// What the device holds — read once, refreshed when the screen is shown
  /// again (a download can have landed since).
  Map<String, InstalledVersion> _installed = const {};

  Timer? _debounce;
  String _query = '';
  SearchFilters _filters = const SearchFilters();

  /// Categories the user restricted the search to. Empty = every available one.
  final Set<SearchCategory> _selected = {};

  /// Categories unfolded with « Voir plus ».
  final Set<SearchCategory> _expanded = {};

  SearchOutcome? _outcome;
  bool _searching = false;

  /// Guards against a slow request overwriting a newer one.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
    LibraryStore.revision.addListener(_onLibraryChanged);
    // Un dictionnaire peut atterrir pendant que l'écran est monté (le shell
    // garde la page dans un IndexedStack) : sans cet abonnement, la requête en
    // cours continuerait de répondre sans lui.
    DictionaryStore.revision.addListener(_onDictionariesChanged);
    // Requête déjà posée avant la première construction (le shell écrit la
    // valeur puis crée la page) : consommée ici, hors setState — le champ et
    // l'état se remplissent en silence, la recherche part à la frame suivante.
    final pending = widget.request?.value;
    if (pending != null && pending.trim().isNotEmpty) {
      widget.request!.value = null;
      _controller.text = pending;
      _controller.selection = TextSelection.collapsed(offset: pending.length);
      _query = pending;
      _searching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    } else {
      widget.request?.addListener(_onExternalRequest);
    }
  }

  /// La puce « Jean 3.16 » de l'accueil a demandé une recherche sur un écran
  /// déjà monté : même traitement qu'une suggestion tapée.
  void _onExternalRequest() {
    final q = widget.request?.value;
    if (q == null || q.trim().isEmpty) return;
    widget.request!.value = null; // consommée — une relance identique re-tirera
    if (!mounted) return;
    _submit(q);
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onLibraryChanged);
    DictionaryStore.revision.removeListener(_onDictionariesChanged);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The Bibliothèque saved or deleted something. The screen stays alive in the
  /// shell's `IndexedStack`, so without this the « Version » menu would keep
  /// showing whatever the registry held when the tab was first opened.
  void _onLibraryChanged() => _loadInstalled();

  /// Un dictionnaire vient d'atterrir ou d'être supprimé depuis la
  /// Bibliothèque : les résultats affichés ont été construits sans lui, donc
  /// la requête en cours repart — sinon il faudrait retaper le mot pour le
  /// voir apparaître.
  void _onDictionariesChanged() {
    if (_query.trim().isEmpty) return;
    _rerun();
  }

  /// Re-reads the registry into [_installed].
  Future<void> _loadInstalled() async {
    Map<String, InstalledVersion> installed;
    try {
      installed = await _library.installed();
    } catch (_) {
      installed = const {}; // no registry → the BYM alone, as before
    }
    if (!mounted) return;
    // A version deleted from the Bibliothèque must not stay selected.
    final code = _filters.versionCode;
    final gone =
        code != VersionRepository.embeddedCode &&
        installed[code]?.isEmpty != false;
    setState(() {
      _installed = installed;
      if (gone) {
        _filters = _filters.copyWith(
          versionCode: VersionRepository.embeddedCode,
        );
      }
    });
  }

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _expanded.clear();
      if (value.trim().isEmpty) {
        _outcome = null;
        _searching = false;
      }
    });
    _debounce?.cancel();
    if (value.trim().isEmpty) return;
    setState(() => _searching = true);
    _debounce = Timer(_debounceDelay, _run);
  }

  /// Re-runs the current query immediately (filter change, « Voir plus »).
  void _rerun() {
    _debounce?.cancel();
    if (_query.trim().isEmpty) return;
    setState(() => _searching = true);
    _run();
  }

  Future<void> _run() async {
    final id = ++_requestId;
    final query = _query.trim();
    final outcome = await _engine.search(
      _query,
      filters: _filters,
      categories: _selected.isEmpty ? null : _selected,
      expanded: _expanded,
    );
    // The id alone is not enough: clearing the field does not start a new
    // request, so a search left in flight would otherwise resurrect its
    // results over the empty state the user just asked for.
    if (!mounted || id != _requestId || _query.trim() != query) return;
    setState(() {
      _outcome = outcome;
      _searching = false;
    });
  }

  void _submit(String suggestion) {
    _controller.text = suggestion;
    _controller.selection = TextSelection.collapsed(offset: suggestion.length);
    _onChanged(suggestion);
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
  }

  void _toggleCategory(SearchCategory category) {
    if (!category.available) {
      _notify(category.unavailableReason);
      return;
    }
    setState(() {
      if (!_selected.remove(category)) _selected.add(category);
      _expanded.clear();
    });
    _rerun();
  }

  void _applyFilters(SearchFilters filters) {
    setState(() {
      _filters = filters;
      _expanded.clear();
    });
    _rerun();
  }

  void _expand(SearchCategory category) {
    setState(() => _expanded.add(category));
    _rerun();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _openHit(SearchHit hit) async {
    if (hit.category == SearchCategory.dictionnaire) {
      // A row from a downloaded dictionary opens in the generic fiche of its
      // own dictionary; a Westphal row opens the embedded FreDAW fiche. (Le
      // lexique « Notes BYM Lexique » est débranché de la recherche.)
      final code = hit.dictionaryCode;
      if (code != null) {
        await _openDownloadedDictionary(hit, code);
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FredawEntryScreen(
            entry: FreDawEntry(term: hit.title, definition: hit.subtitle),
            onOpenVerse: (bookIndex, chapter, verse) {
              // Same contract as the Strong fiche: clear the stacked fiche
              // chain before switching to the reading tab.
              Navigator.of(context).popUntil((route) => route.isFirst);
              widget.onOpenReading(bookIndex, chapter, verse: verse);
            },
          ),
        ),
      );
      return;
    }
    if (hit.category == SearchCategory.strong) {
      final strong = await StrongLexicon.instance.lookup(hit.title);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StrongDetailScreen(
            strong: strong,
            onOpenVerse: (bookIndex, chapter, verse) {
              // Clear the whole stacked chain of fiches (a code may have been
              // reached through « Voir plus » or an etymology link, several
              // routes deep) before switching to the reading tab: a single pop
              // would leave an intermediate route covering the reader, landing
              // the user one screen back instead of on the opened verse.
              Navigator.of(context).popUntil((route) => route.isFirst);
              widget.onOpenReading(bookIndex, chapter, verse: verse);
            },
          ),
        ),
      );
      return;
    }
    if (!hit.canOpen) return;
    widget.onOpenReading(hit.bookIndex!, hit.chapter!, verse: hit.verse);
  }

  /// Opens a downloaded dictionary hit in the generic fiche of its dictionary.
  ///
  /// The row only carries the code, the term and the definition; the fiche
  /// needs the full reader for its cross-links, so the file is re-read here.
  Future<void> _openDownloadedDictionary(SearchHit hit, String code) async {
    final entry = dictionaryByCode(code);
    if (entry == null) return;
    final payload = await _dictStore.load(code);
    if (!mounted || payload == null) return;
    final reader = DictionaryReader.fromJson(payload);
    final article = reader.lookup(hit.title) ??
        DictionaryArticle(term: hit.title, definition: hit.subtitle);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DictionaryEntryScreen(
          entry: entry,
          article: article,
          reader: reader,
          onOpenVerse: (bookIndex, chapter, verse) {
            // Same contract as the Strong fiche: clear the stacked fiche
            // chain before switching to the reading tab.
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onOpenReading(bookIndex, chapter, verse: verse);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rechercher',
                    style: premiumText(
                      context,
                      20,
                      FontWeight.w800,
                      bibleTheme.titleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Filet d'accent sous le titre : la page a un point de
                  // départ net avant le champ.
                  Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          bibleTheme.accentColor,
                          bibleTheme.accentColor.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SearchField(
                    controller: _controller,
                    onChanged: _onChanged,
                    onClear: _clear,
                    // The keyboard's « Rechercher » key must not sit through
                    // the 300 ms debounce: flush and run now.
                    onSubmitted: _rerun,
                    hasText: _query.isNotEmpty,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CategoryChipRow(
              selected: _selected,
              counts: {
                for (final g in _outcome?.groups ?? const <SearchGroup>[])
                  g.category: g.total,
              },
              onToggle: _toggleCategory,
            ),
            const SizedBox(height: 8),
            _FilterBar(
              filters: _filters,
              onChanged: _applyFilters,
              installed: _installed,
              onOpenLibrary: widget.onOpenLibrary,
            ),
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: .5)),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    final query = _query.trim();
    if (query.isEmpty) {
      return _EmptyState(onPick: _submit);
    }
    // Below the engine's minimum, no source is queried at all — say so instead
    // of dressing the silence up as « aucun résultat ».
    if (query.length < SearchEngine.minQueryLength) {
      return _NoResults(
        query: query,
        message:
            'Saisissez au moins ${SearchEngine.minQueryLength} lettres.',
      );
    }
    final outcome = _outcome;
    if (_searching && outcome == null) {
      return const ListLoadingSkeleton(itemCount: 5);
    }
    if (outcome == null) {
      return _NoResults(
        query: query,
        message: 'Saisissez au moins ${SearchEngine.minQueryLength} lettres.',
      );
    }
    if (outcome.isEmpty) {
      final coverage = outcome.coverageNote;
      return _NoResults(
        query: outcome.query,
        message: coverage != null
            ? '$coverage\nTerminez le téléchargement depuis la Bibliothèque, '
                  'ou revenez à la BYM.'
            : _filters.isNarrowed
            ? 'Aucun résultat avec ces filtres — élargissez la section '
                  'ou le livre.'
            : 'Aucun résultat dans les sources disponibles.',
      );
    }
    return _Results(
      outcome: outcome,
      searching: _searching,
      expanded: _expanded,
      onOpenHit: _openHit,
      onOpenReference: (reference) => widget.onOpenReading(
        reference.bookIndex,
        reference.chapter,
        verse: reference.verse,
      ),
      onExpand: _expand,
    );
  }
}

/// The rounded, filled query field of the maquette, carte blanche à ombre
/// douce — le liseré s'allume à la focus, l'ombre prend la couleur de
/// l'accent : le champ dit qu'il écoute.
class _SearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onSubmitted;
  final bool hasText;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onSubmitted,
    required this.hasText,
  });

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final accent = bibleTheme.accentColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: bibleTheme.panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused
              ? accent.withValues(alpha: .55)
              : premiumCardBorder(context, opacity: .22),
          width: _focused ? 1.4 : 1,
        ),
        boxShadow: premiumShadow(
          _focused ? accent : bibleTheme.accentColor,
          opacity: _focused ? 0.22 : 0.06,
          blur: _focused ? 18 : 10,
          offset: Offset(0, _focused ? 6 : 4),
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focus,
        onChanged: widget.onChanged,
        onSubmitted: (_) => widget.onSubmitted(),
        textInputAction: TextInputAction.search,
        style: premiumText(context, 16, FontWeight.w500, bibleTheme.textColor),
        decoration: InputDecoration(
          hintText: 'Mot, verset ou référence',
          hintStyle: premiumText(
            context,
            14,
            FontWeight.w500,
            bibleTheme.textColor.withValues(alpha: .62),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _focused ? accent : bibleTheme.accentColor,
            size: 24,
          ),
          suffixIcon: widget.hasText
              ? IconButton(
                  tooltip: 'Effacer',
                  icon: Icon(Icons.close, color: bibleTheme.textColor),
                  onPressed: widget.onClear,
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

/// The horizontally scrollable row of coloured category chips.
///
/// No selection means « everything »; tapping a chip narrows the search to it,
/// tapping it again releases the filter. Unavailable categories are greyed and
/// explain themselves in a snackbar instead of toggling.
class _CategoryChipRow extends StatelessWidget {
  final Set<SearchCategory> selected;

  /// Result count per category for the current query, for the chip badge.
  final Map<SearchCategory, int> counts;

  final ValueChanged<SearchCategory> onToggle;

  const _CategoryChipRow({
    required this.selected,
    required this.counts,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        key: categoryRowKey,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: SearchCategory.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = SearchCategory.values[index];
          return _CategoryChip(
            category: category,
            active: selected.contains(category),
            count: counts[category],
            onTap: () => onToggle(category),
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final SearchCategory category;
  final bool active;
  final int? count;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.category,
    required this.active,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final style = _styleOf(context, category);
    final enabled = category.available;

    final foreground = enabled ? p.onSurface : p.onSurfaceMuted;
    final iconColor = enabled
        ? style.color
        : style.color.withValues(alpha: .35);

    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      child: Material(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: premiumShadow(
              style.color,
              opacity: active ? 0.16 : 0.06,
              blur: active ? 12 : 8,
              offset: const Offset(0, 4),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                // La sélection se peint en dégradé léger plutôt qu'en aplat :
                // la pastille garde sa lisibilité sur toutes les palettes.
                gradient: active
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          style.color.withValues(alpha: .20),
                          style.color.withValues(alpha: .08),
                        ],
                      )
                    : null,
                border: Border.all(
                  color: active
                      ? style.color
                      : p.textGrey.withValues(alpha: .3),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(style.icon, size: 19, color: iconColor),
                  const SizedBox(width: 7),
                  Text(
                    category.label,
                    style: premiumText(
                      context,
                      13,
                      active ? FontWeight.w700 : FontWeight.w600,
                      foreground,
                    ),
                  ),
                  if (count != null && count! > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count!, color: style.color),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small pill printing a result count, next to a chip or a group header.
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge(this.count, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: premiumText(
          context,
          11,
          FontWeight.w700,
          Color.alphaBlend(
            color.withValues(alpha: .85),
            premiumPalette(context).onSurface,
          ),
        ),
      ),
    );
  }
}

/// The « Tout » choice of the « Section » menu, as a non-null sentinel.
///
/// [PopupMenuButton] cannot express it with a null item value: the menu route
/// pops with null, which the button reads as a dismissal — [PopupMenuButton.onSelected]
/// is then never called and the filter never goes back to « Tout ». Every
/// option therefore carries a real value, and this one stands outside
/// [bibleSections]' own range (0..4).
const _allSections = -1;

/// The « Version · Section · Livre · Ordre » row under the chips.
class _FilterBar extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  /// Versions with books on the device — searchable alongside the BYM.
  final Map<String, InstalledVersion> installed;

  /// Switches to the Bibliothèque, for the last row of the « Version » menu.
  final VoidCallback? onOpenLibrary;

  const _FilterBar({
    required this.filters,
    required this.onChanged,
    this.installed = const {},
    this.onOpenLibrary,
  });

  /// The versions that can actually be searched.
  ///
  /// Searchable = indexable offline: the bundled BYM, or a version whose books
  /// are on the device. A partial download counts — its books are searched, and
  /// the passages header says how many are covered.
  ///
  /// The rest used to be listed, greyed, answering a snackbar. Twelve rows for
  /// one usable choice, in a menu whose only job is to choose.
  List<VersionEntry> get _searchable => [
    for (final group in versionCatalog)
      for (final version in group.versions)
        if (version.embedded || installed[version.code]?.isEmpty == false)
          version,
  ];

  @override
  Widget build(BuildContext context) {
    final searchable = _searchable;
    final missing =
        versionCatalog.fold<int>(
          0,
          (total, group) => total + group.versions.length,
        ) -
        searchable.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          _FilterMenu<String>(
            label: 'Version',
            value: filters.versionCode,
            options: [
              for (final version in searchable)
                _FilterOption(
                  value: version.code,
                  label: version.code,
                  detail: _detailFor(version),
                ),
            ],
            // What is left out has to stay reachable, or nothing on this screen
            // says the other translations exist at all.
            footer: missing == 0
                ? null
                : _FilterFooter(
                    label: 'Bibliothèque',
                    detail: '$missing autres versions à télécharger',
                    onTap: onOpenLibrary,
                  ),
            onSelected: (code) =>
                onChanged(filters.copyWith(versionCode: code)),
          ),
          const SizedBox(width: 22),
          _FilterMenu<int>(
            label: 'Section',
            value: filters.sectionIndex ?? _allSections,
            valueLabel: filters.sectionLabel,
            options: [
              const _FilterOption(value: _allSections, label: 'Tout'),
              for (var i = 0; i < bibleSections.length; i++)
                _FilterOption(
                  value: i,
                  label: bibleSections[i].name,
                  detail: bibleSections[i].subtitle,
                ),
            ],
            // Picking a section releases the single-book restriction.
            onSelected: (index) => onChanged(
              index == _allSections
                  ? filters.copyWith(clearSection: true, clearBook: true)
                  : filters.copyWith(sectionIndex: index, clearBook: true),
            ),
          ),
          const SizedBox(width: 22),
          _BookFilterMenu(filters: filters, onChanged: onChanged),
          const SizedBox(width: 22),
          _FilterMenu<SearchOrder>(
            label: 'Ordre',
            value: filters.order,
            valueLabel: filters.order.label,
            options: [
              for (final order in SearchOrder.values)
                _FilterOption(value: order, label: order.label),
            ],
            onSelected: (order) => onChanged(filters.copyWith(order: order)),
          ),
        ],
      ),
    );
  }

  /// The version name, plus what the device holds when it is a download —
  /// « 12/66 livres » is what explains a short result list.
  String _detailFor(VersionEntry version) {
    final state = installed[version.code];
    if (state == null || state.isEmpty) return version.name;
    if (state.isComplete) return '${version.name} · téléchargée';
    return '${version.name} · ${state.bookCount}/${version.bookCount} livres';
  }
}

class _FilterOption<T> {
  final T value;
  final String label;
  final String? detail;

  const _FilterOption({required this.value, required this.label, this.detail});
}

/// The last row of a [_FilterMenu]: not an option, but the way out towards what
/// the list leaves off.
///
/// Selects nothing — its `PopupMenuItem` carries no value, so `onSelected` is
/// never called and the filter keeps whatever was picked before.
class _FilterFooter {
  final String label;
  final String detail;

  /// Null when there is no destination to switch to (standalone screen, tests):
  /// the row then states the fact instead of pretending to be a button.
  final VoidCallback? onTap;

  const _FilterFooter({required this.label, required this.detail, this.onTap});
}

/// A small « label / bold value ⌄ » control opening a popup menu.
class _FilterMenu<T> extends StatelessWidget {
  final String label;
  final T value;

  /// Text under [label]; defaults to the selected option's label.
  final String? valueLabel;

  final List<_FilterOption<T>> options;
  final ValueChanged<T> onSelected;

  /// Optional last row, under a divider — see [_FilterFooter].
  final _FilterFooter? footer;

  const _FilterMenu({
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.valueLabel,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final current = options.where((o) => o.value == value).firstOrNull;
    return PopupMenuButton<T>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in options)
          PopupMenuItem<T>(
            value: option.value,
            child: Row(
              children: [
                Icon(
                  option.value == value
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 17,
                  color: bibleTheme.accentColor,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.label),
                      if (option.detail != null)
                        Text(
                          option.detail!,
                          style: premiumText(
                            context,
                            12,
                            FontWeight.w500,
                            bibleTheme.textColor.withValues(alpha: .72),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (footer != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem<T>(
            // No value: picking it must not change the filter.
            onTap: footer!.onTap,
            child: Row(
              children: [
                Icon(
                  Icons.library_books_outlined,
                  size: 17,
                  color: bibleTheme.textColor.withValues(alpha: .72),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(footer!.label),
                      Text(
                        footer!.detail,
                        style: premiumText(
                          context,
                          12,
                          FontWeight.w500,
                          bibleTheme.textColor.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      child: _FilterLabel(
        label: label,
        value: valueLabel ?? current?.label ?? '—',
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String label;
  final String value;

  const _FilterLabel({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: premiumText(
            context,
            11,
            FontWeight.w600,
            bibleTheme.textColor.withValues(alpha: .72),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: premiumText(
                  context,
                  14,
                  FontWeight.w800,
                  bibleTheme.accentColor,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: bibleTheme.accentColor,
            ),
          ],
        ),
      ],
    );
  }
}

/// « Livre » needs a scrollable sheet rather than a popup: 66 entries plus
/// « Tout », grouped by the five BYM sections.
class _BookFilterMenu extends StatelessWidget {
  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  const _BookFilterMenu({required this.filters, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        maxChildSize: .92,
        builder: (context, controller) => ListView(
          controller: controller,
          // The sheet is sized as a fraction of the screen with the gesture
          // bar over it: without the view padding the last book (Apocalypse)
          // is drawn under it and cannot be tapped.
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
          ),
          children: [
            ListTile(
              leading: const Icon(Icons.clear_all),
              title: const Text('Tout'),
              subtitle: const Text('Les 66 livres'),
              selected: filters.bookIndex == null,
              // 0 is the sentinel for « Tout » (book indices start at 1).
              onTap: () => Navigator.of(context).pop(0),
            ),
            for (final section in bibleSections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  section.name,
                  style: premiumText(
                    context,
                    13,
                    FontWeight.w700,
                    BibleThemeScope.of(context).accentColor,
                  ),
                ),
              ),
              for (var book = section.from; book <= section.to; book++)
                ListTile(
                  dense: true,
                  title: Text(catalogEntry(book).shortName),
                  trailing: Text(
                    catalogEntry(book).abbreviation,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w500,
                      BibleThemeScope.of(
                        context,
                      ).textColor.withValues(alpha: .62),
                    ),
                  ),
                  selected: filters.bookIndex == book,
                  onTap: () => Navigator.of(context).pop(book),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    onChanged(
      picked == 0
          ? filters.copyWith(clearBook: true)
          : filters.copyWith(bookIndex: picked, clearSection: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: _FilterLabel(label: 'Livre', value: filters.bookLabel),
    );
  }
}

/// What the screen shows before anything is typed: the big magnifier of the
/// maquette and four groups of tappable example queries.
class _EmptyState extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _EmptyState({required this.onPick});

  /// Les exemples disent les registres que le champ accepte vraiment :
  /// français, nom BYM (hébreu pour l'Ancien Testament, grec pour le Nouveau)
  /// et abréviation — chacun des groupes « référence » et « livre » en porte un.
  static const List<({String title, List<String> queries})> _suggestions = [
    (
      title: 'Chercher une référence',
      queries: ['Jean 3:16', 'Mattithyah 5', 'Ps 23'],
    ),
    (title: 'Chercher un verset', queries: ['Jésus pleura', 'Au commencement']),
    (title: 'Chercher un mot', queries: ['amour', 'grâce', 'alliance']),
    (title: 'Chercher un mot Strong', queries: ['H0430', 'G2316', 'agapao']),
    (title: 'Chercher un livre', queries: ['Genèse', 'Bereshit', 'Mattithyah']),
  ];

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        // Le grand magnifier du maquette posé dans un halo de la couleur
        // d'accent : l'état vide a un centre, pas seulement un vide.
        Center(
          child: Container(
            width: 156,
            height: 156,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  bibleTheme.accentColor.withValues(alpha: .16),
                  bibleTheme.accentColor.withValues(alpha: .03),
                ],
              ),
              border: Border.all(
                color: bibleTheme.accentColor.withValues(alpha: .22),
              ),
            ),
            child: Icon(
              Icons.search,
              size: 64,
              color: bibleTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Que cherchez-vous ?',
            style: premiumText(
              context,
              20,
              FontWeight.w800,
              bibleTheme.titleColor,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Le champ dit d'avance ce qu'il comprend : les trois registres que
        // `searchBooks` accepte, exemples à l'appui, et que la faute de
        // frappe ne ferme pas la porte.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'En français, en abrégé (« Ps 23 ») ou sous les noms de la BYM '
            '(« Mattithyah 5 ») — même mal orthographié.',
            textAlign: TextAlign.center,
            style: premiumText(
              context,
              13,
              FontWeight.w500,
              bibleTheme.textColor.withValues(alpha: .72),
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 24),
        for (final group in _suggestions) ...[
          Text(
            group.title,
            style: premiumText(
              context,
              15,
              FontWeight.w800,
              bibleTheme.titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in group.queries)
                ActionChip(
                  label: Text(
                    query,
                    style: premiumText(
                      context,
                      13,
                      FontWeight.w600,
                      bibleTheme.titleColor,
                    ),
                  ),
                  onPressed: () => onPick(query),
                  backgroundColor: bibleTheme.accentColor.withValues(
                    alpha: .30,
                  ),
                  side: BorderSide(
                    color: bibleTheme.accentColor.withValues(alpha: .50),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  final String query;
  final String message;

  const _NoResults({required this.query, required this.message});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 24),
      children: [
        Center(
          child: Container(
            width: 116,
            height: 116,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  bibleTheme.accentColor.withValues(alpha: .14),
                  bibleTheme.accentColor.withValues(alpha: .03),
                ],
              ),
              border: Border.all(
                color: bibleTheme.accentColor.withValues(alpha: .20),
              ),
            ),
            child: Icon(
              Icons.search_off,
              size: 52,
              color: bibleTheme.accentColor,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '« $query »',
          textAlign: TextAlign.center,
          style: premiumText(
            context,
            18,
            FontWeight.w800,
            bibleTheme.titleColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: premiumText(
            context,
            14,
            FontWeight.w500,
            bibleTheme.textColor.withValues(alpha: .88),
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The results list: the reference card first (when the query read as one),
/// then one section per category with its header, count badge and rows.
class _Results extends StatelessWidget {
  final SearchOutcome outcome;
  final bool searching;
  final Set<SearchCategory> expanded;
  final ValueChanged<SearchHit> onOpenHit;
  final ValueChanged<ReferenceHit> onOpenReference;
  final ValueChanged<SearchCategory> onExpand;

  const _Results({
    required this.outcome,
    required this.searching,
    required this.expanded,
    required this.onOpenHit,
    required this.onOpenReference,
    required this.onExpand,
  });

  @override
  Widget build(BuildContext context) {
    final reference = outcome.reference;
    final coverage = outcome.coverageNote;
    return Stack(
      children: [
        ListView(
          key: resultListKey,
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            if (coverage != null) _CoverageNote(text: coverage),
            if (reference != null) ...[
              _GroupHeader(
                title: 'Référence biblique',
                count: 1,
                color: _styleOf(context, SearchCategory.passages).color,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _ReferenceCard(
                  reference: reference,
                  onTap: () => onOpenReference(reference),
                ),
              ),
            ],
            for (final group in outcome.groups) ...[
              _GroupHeader(
                title: group.category.label,
                count: group.total,
                color: _styleOf(context, group.category).color,
              ),
              for (final hit in group.hits)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: _HitTile(
                    hit: hit,
                    query: outcome.query,
                    onTap: () => onOpenHit(hit),
                  ),
                ),
              if (group.truncated && !expanded.contains(group.category))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      label: Text(
                        'Voir plus',
                        style: premiumText(
                          context,
                          13,
                          FontWeight.w700,
                          _styleOf(context, group.category).color,
                        ),
                      ),
                      onPressed: () => onExpand(group.category),
                      backgroundColor: _styleOf(
                        context,
                        group.category,
                      ).color.withValues(alpha: .14),
                      side: BorderSide(
                        color: _styleOf(
                          context,
                          group.category,
                        ).color.withValues(alpha: .40),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
        if (searching)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: BibleThemeScope.of(context).accentColor
                  .withValues(alpha: .12),
              valueColor: AlwaysStoppedAnimation<Color>(
                BibleThemeScope.of(context).accentColor,
              ),
            ),
          ),
      ],
    );
  }
}

/// A quiet banner above the results: the active version only holds part of the
/// Bible, so the list is short for a reason that is not the query.
class _CoverageNote extends StatelessWidget {
  final String text;

  const _CoverageNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bibleTheme.accentColor.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bibleTheme.accentColor.withValues(alpha: .30),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_download_outlined,
            size: 18,
            color: bibleTheme.titleColor.withValues(alpha: .85),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: premiumText(
                context,
                13,
                FontWeight.w500,
                bibleTheme.textColor.withValues(alpha: .85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Dictionnaire ③" — a grey category title with its count badge.
class _GroupHeader extends StatelessWidget {
  final String title;
  final int count;
  final Color color;

  const _GroupHeader({
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          // Un filet de la couleur de la section titille l'intitulé : les
          // groupes se lisent d'un coup d'œil, même en filet.
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: premiumText(
                context,
                16,
                FontWeight.w800,
                bibleTheme.titleColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _CountBadge(count, color: color),
        ],
      ),
    );
  }
}

/// The full verse a reference query resolved to, printed in full.
class _ReferenceCard extends StatelessWidget {
  final ReferenceHit reference;
  final VoidCallback onTap;

  const _ReferenceCard({required this.reference, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Material(
      color: bibleTheme.panelColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bibleTheme.panelColor,
              bibleTheme.panelColor.withValues(
                alpha: bibleTheme.panelColor.a * .80,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: premiumCardBorder(context, opacity: .18)),
          boxShadow: [
            ...premiumShadow(
              bibleTheme.accentColor,
              opacity: 0.07,
              blur: 16,
              offset: const Offset(0, 6),
            ),
            ...premiumShadow(
              bibleTheme.accentColor,
              opacity: 0.05,
              blur: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      reference.label,
                      style: premiumText(
                        context,
                        17,
                        FontWeight.w800,
                        bibleTheme.titleColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Badge(reference.versionCode),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reference.text,
                  style: premiumText(
                    context,
                    15,
                    FontWeight.w500,
                    bibleTheme.textColor,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One result row: a coloured square glyph, a bold title with its badge, and
/// the matching text with the query highlighted.
class _HitTile extends StatelessWidget {
  final SearchHit hit;
  final String query;
  final VoidCallback onTap;

  const _HitTile({required this.hit, required this.query, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final style = _styleOf(context, hit.category);
    return Material(
      color: bibleTheme.panelColor,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              bibleTheme.panelColor,
              bibleTheme.panelColor.withValues(
                alpha: bibleTheme.panelColor.a * .80,
              ),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: premiumCardBorder(context, opacity: .16)),
          boxShadow: [
            ...premiumShadow(
              style.color,
              opacity: 0.07,
              blur: 14,
              offset: const Offset(0, 6),
            ),
            ...premiumShadow(
              bibleTheme.accentColor,
              opacity: 0.05,
              blur: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: (hit.category == SearchCategory.strong || hit.canOpen)
              ? onTap
              : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        style.color.withValues(alpha: .20),
                        style.color.withValues(alpha: .08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: style.color.withValues(alpha: .28),
                    ),
                  ),
                  child: Icon(style.icon, size: 21, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: hit.category == SearchCategory.strong
                      ? _StrongHitBody(
                          hit: hit,
                          query: query,
                          color: style.color,
                        )
                      : _StandardHitBody(hit: hit, query: query),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StrongHitBody extends StatelessWidget {
  final SearchHit hit;
  final String query;
  final Color color;

  const _StrongHitBody({
    required this.hit,
    required this.query,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final isGreek = hit.title.toUpperCase().startsWith('G');
    final lemma = hit.lemma?.trim() ?? '';
    final transliteration = hit.transliteration?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 5,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: color.withValues(alpha: .34)),
              ),
              child: Text(
                hit.title,
                style: premiumText(context, 12, FontWeight.w800, color),
              ),
            ),
            Text(
              isGreek ? 'Grec' : 'Hébreu',
              style: premiumText(
                context,
                11,
                FontWeight.w700,
                bibleTheme.textColor.withValues(alpha: .58),
              ),
            ),
          ],
        ),
        if (lemma.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            lemma,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: isGreek ? TextDirection.ltr : TextDirection.rtl,
            style: premiumText(
              context,
              18,
              FontWeight.w800,
              bibleTheme.titleColor,
            ),
          ),
        ],
        if (transliteration.isNotEmpty) ...[
          const SizedBox(height: 5),
          Wrap(
            spacing: 6,
            runSpacing: 3,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'translitéré',
                style: premiumText(
                  context,
                  10,
                  FontWeight.w700,
                  bibleTheme.textColor.withValues(alpha: .55),
                ),
              ),
              Text(
                transliteration,
                style: premiumText(
                  context,
                  13,
                  FontWeight.w600,
                  color,
                  italic: FontStyle.italic,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        _HighlightedText(text: hit.subtitle, query: query, maxLines: 3),
      ],
    );
  }
}

class _StandardHitBody extends StatelessWidget {
  final SearchHit hit;
  final String query;

  const _StandardHitBody({required this.hit, required this.query});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                hit.title,
                overflow: TextOverflow.ellipsis,
                style: premiumText(
                  context,
                  15,
                  FontWeight.w800,
                  bibleTheme.titleColor,
                ),
              ),
            ),
            if (hit.badge != null) ...[
              const SizedBox(width: 8),
              _Badge(hit.badge!),
            ],
          ],
        ),
        if (hit.transliteration != null && hit.transliteration!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            hit.transliteration!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: premiumText(
              context,
              13,
              FontWeight.w600,
              bibleTheme.accentColor,
              italic: FontStyle.italic,
            ),
          ),
        ],
        if (hit.lemma != null && hit.lemma!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            hit.lemma!,
            overflow: TextOverflow.ellipsis,
            style: premiumText(
              context,
              13,
              FontWeight.w700,
              bibleTheme.textColor.withValues(alpha: .72),
            ),
          ),
        ],
        const SizedBox(height: 2),
        _HighlightedText(text: hit.subtitle, query: query, maxLines: 2),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bibleTheme.accentColor.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: premiumText(
          context,
          10,
          FontWeight.w700,
          bibleTheme.textColor.withValues(alpha: .9),
        ),
      ),
    );
  }
}

/// Renders [text] with the first occurrence of [query] highlighted, matching
/// through accents ("grace" highlights « grâce »).
class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final int maxLines;

  const _HighlightedText({
    required this.text,
    required this.query,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final baseStyle = premiumText(
      context,
      13,
      FontWeight.w500,
      bibleTheme.textColor.withValues(alpha: .78),
    );
    final range = findIgnoringAccents(text, query.trim());
    if (range == null) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: text.substring(0, range.start)),
          TextSpan(
            text: text.substring(range.start, range.end),
            style: TextStyle(
              color: bibleTheme.textColor,
              backgroundColor: bibleTheme.accentColor.withValues(alpha: .24),
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(range.end)),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}
