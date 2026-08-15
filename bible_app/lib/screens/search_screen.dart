import 'dart:async';

import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/book_catalog.dart';
import '../data/fredaw_lexicon.dart';
import '../data/library_store.dart';
import '../data/reference_parser.dart';
import '../data/search_engine.dart';
import '../data/strong_lexicon.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../widgets/bible_theme_scope.dart';
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

const Map<SearchCategory, _CategoryStyle> _categoryStyles = {
  SearchCategory.passages:
      _CategoryStyle(Icons.menu_book_outlined, Color(0xFF2FA9A0)),
  SearchCategory.notes:
      _CategoryStyle(Icons.description_outlined, Color(0xFFE4694F)),
  SearchCategory.liens: _CategoryStyle(Icons.link, Color(0xFFE2A32B)),
  SearchCategory.etudes:
      _CategoryStyle(Icons.history_edu_outlined, Color(0xFF6F6390)),
  SearchCategory.strong: _CategoryStyle(Icons.translate, Color(0xFFC56B9B)),
  SearchCategory.dictionnaire: _CategoryStyle(Icons.abc, Color(0xFFDFA51F)),
  SearchCategory.nave: _CategoryStyle(Icons.hub_outlined, Color(0xFF4F5FA6)),
};

_CategoryStyle _styleOf(SearchCategory category) =>
    _categoryStyles[category] ?? const _CategoryStyle(Icons.search, Colors.grey);

/// The chip row and the result list build lazily, so tests have to scroll them
/// to reach the last chips and rows. These keys make the right list
/// addressable: a [TextField] owns a horizontal scrollable of its own, so
/// picking one by axis is not enough.
const Key categoryRowKey = ValueKey('search-category-row');
const Key resultListKey = ValueKey('search-result-list');

/// Unified search (maquette `rech/`).
///
/// One field searches every source at once — scripture references, the
/// full text of the 66 embedded books, the user's notes, the chapters already
/// studied and the BYM dictionary — and groups the results by category. The
/// chip row filters which categories are queried; the four menus underneath
/// narrow the corpus (version, section, book) and the ordering.
///
/// Categories with no data source yet (Liens, Strong, Nave) are listed but
/// disabled, so the layout matches the design and only needs wiring later.
class SearchScreen extends StatefulWidget {
  /// Opens a chapter in a reading tab (and optionally jumps to a verse),
  /// then switches to the Lecture destination.
  final void Function(int bookIndex, int chapter, {int? verse}) onOpenReading;

  /// Opens a dictionary entry in a new reader tab.
  final void Function(String term, String definition)? onOpenDictionary;

  /// Engine to search with. Injectable for tests: the default one reaches
  /// [AppDatabase], whose path_provider call never completes inside the
  /// fake-async zone of `testWidgets` (same reason as
  /// [LocalRepository.useBundle]).
  final SearchEngine? engine;

  /// Registry of downloaded versions, for the « Version » menu. Injectable for
  /// the same reason as [engine]: the real one reads through path_provider.
  final LibraryStore? store;

  /// Switches to the Bibliothèque destination. Null when the screen stands
  /// alone (tests): the « Version » menu then still names what is missing, but
  /// its last row leads nowhere rather than to a dead end.
  final VoidCallback? onOpenLibrary;

  const SearchScreen({
    super.key,
    required this.onOpenReading,
    this.onOpenDictionary,
    this.engine,
    this.store,
    this.onOpenLibrary,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const Duration _debounceDelay = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  late final SearchEngine _engine = widget.engine ?? SearchEngine();
  late final LibraryStore _library = widget.store ?? LibraryStore();

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
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onLibraryChanged);
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// The Bibliothèque saved or deleted something. The screen stays alive in the
  /// shell's `IndexedStack`, so without this the « Version » menu would keep
  /// showing whatever the registry held when the tab was first opened.
  void _onLibraryChanged() => _loadInstalled();

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
    final gone = code != VersionRepository.embeddedCode &&
        installed[code]?.isEmpty != false;
    setState(() {
      _installed = installed;
      if (gone) {
        _filters =
            _filters.copyWith(versionCode: VersionRepository.embeddedCode);
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
    final outcome = await _engine.search(
      _query,
      filters: _filters,
      categories: _selected.isEmpty ? null : _selected,
      expanded: _expanded,
    );
    if (!mounted || id != _requestId) return;
    setState(() {
      _outcome = outcome;
      _searching = false;
    });
  }

  void _submit(String suggestion) {
    _controller.text = suggestion;
    _controller.selection =
        TextSelection.collapsed(offset: suggestion.length);
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FredawEntryScreen(
          entry: FreDawEntry(term: hit.title, definition: hit.subtitle),
          onOpenDictionary: widget.onOpenDictionary,
          onOpenVerse: (bookIndex, chapter, verse) =>
              widget.onOpenReading(bookIndex, chapter, verse: verse),
        ),
      ));
      return;
    }
    if (hit.category == SearchCategory.strong) {
      final strong = await StrongLexicon.instance.lookup(hit.title);
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
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
      ));
      return;
    }
    if (!hit.canOpen) return;
    widget.onOpenReading(hit.bookIndex!, hit.chapter!, verse: hit.verse);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Scaffold(
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
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: bibleTheme.titleColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SearchField(
                    controller: _controller,
                    onChanged: _onChanged,
                    onClear: _clear,
                    hasText: _query.isNotEmpty,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CategoryChipRow(
              selected: _selected,
              counts: {
                for (final g in _outcome?.groups ?? const <SearchGroup>[])
                  g.category: g.total,
              },
              onToggle: _toggleCategory,
            ),
            const SizedBox(height: 6),
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
    if (_query.trim().isEmpty) {
      return _EmptyState(onPick: _submit);
    }
    final outcome = _outcome;
    if (_searching && outcome == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (outcome == null) {
      return _NoResults(
        query: _query,
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

/// The rounded, filled query field of the maquette.
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasText;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.hasText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyLarge,
      decoration: InputDecoration(
        hintText: 'Mot, verset ou référence',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: bibleTheme.textColor.withValues(alpha: .62),
        ),
        prefixIcon: Icon(Icons.search,
            color: bibleTheme.accentColor, size: 24),
        suffixIcon: hasText
            ? IconButton(
                tooltip: 'Effacer',
                icon: Icon(Icons.close, color: bibleTheme.textColor),
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: .7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
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
    final theme = Theme.of(context);
    final style = _styleOf(category);
    final enabled = category.available;

    final background = !enabled
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: .35)
        : active
            ? style.color.withValues(alpha: .26)
            : style.color.withValues(alpha: .10);
    final foreground = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: .38);
    final iconColor =
        enabled ? style.color : style.color.withValues(alpha: .35);

    return Semantics(
      button: true,
      selected: active,
      enabled: enabled,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active ? style.color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.icon, size: 19, color: iconColor),
                const SizedBox(width: 7),
                Text(
                  category.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: Color.alphaBlend(
                color.withValues(alpha: .85),
                Theme.of(context).colorScheme.onSurface,
              ),
            ),
      ),
    );
  }
}
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
    final missing = versionCatalog.fold<int>(
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
          _FilterMenu<int?>(
            label: 'Section',
            value: filters.sectionIndex,
            valueLabel: filters.sectionLabel,
            options: [
              const _FilterOption(value: null, label: 'Tout'),
              for (var i = 0; i < bibleSections.length; i++)
                _FilterOption(
                  value: i,
                  label: bibleSections[i].name,
                  detail: bibleSections[i].subtitle,
                ),
            ],
            // Picking a section releases the single-book restriction.
            onSelected: (index) => onChanged(index == null
                ? filters.copyWith(clearSection: true, clearBook: true)
                : filters.copyWith(sectionIndex: index, clearBook: true)),
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
    return '${version.name} · ${state.bookCount}/${bookCatalog.length} livres';
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

  const _FilterFooter({
    required this.label,
    required this.detail,
    this.onTap,
  });
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
    final theme = Theme.of(context);
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: bibleTheme.textColor.withValues(alpha: .72),
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
                Icon(Icons.library_books_outlined,
                    size: 17, color: bibleTheme.textColor.withValues(alpha: .72)),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(footer!.label),
                      Text(
                        footer!.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: bibleTheme.textColor.withValues(alpha: .72),
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: bibleTheme.textColor.withValues(alpha: .72)),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: bibleTheme.accentColor,
                ),
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 18, color: bibleTheme.accentColor),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: BibleThemeScope.of(context).accentColor,
                      ),
                ),
              ),
              for (var book = section.from; book <= section.to; book++)
                ListTile(
                  dense: true,
                  title: Text(catalogEntry(book).shortName),
                  trailing: Text(
                    catalogEntry(book).abbreviation,
                    style: Theme.of(context).textTheme.labelSmall,
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
    onChanged(picked == 0
        ? filters.copyWith(clearBook: true)
        : filters.copyWith(bookIndex: picked, clearSection: true));
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

  static const List<({String title, List<String> queries})> _suggestions = [
    (
      title: 'Chercher une référence',
      queries: ['Jean 3:16', 'Psaume 23', 'Exode 4:5']
    ),
    (
      title: 'Chercher un verset',
      queries: ['Jésus pleura', 'Au commencement']
    ),
    (title: 'Chercher un mot', queries: ['amour', 'grâce', 'alliance']),
    (
      title: 'Chercher un mot Strong',
      queries: ['H0430', 'G2316', 'agapao']
    ),
    (title: 'Chercher un livre', queries: ['Apocalypse', 'Bereshit']),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Icon(
          Icons.search,
          size: 110,
          color: bibleTheme.titleColor.withValues(alpha: .35),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Que cherchez-vous ?',
            style: theme.textTheme.titleMedium?.copyWith(
              color: bibleTheme.titleColor,
            ),
          ),
        ),
        const SizedBox(height: 28),
        for (final group in _suggestions) ...[
          Text(
            group.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: BibleThemeScope.of(context).titleColor,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final query in group.queries)
                ActionChip(
                  label: Text(query),
                  onPressed: () => onPick(query),
                  backgroundColor: bibleTheme.accentColor.withValues(alpha: .35),
                  side: BorderSide.none,
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 60, 28, 24),
      children: [
        Icon(Icons.search_off,
            size: 76,
            color: bibleTheme.titleColor.withValues(alpha: .35)),
        const SizedBox(height: 16),
        Text(
          '« $query »',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: bibleTheme.textColor.withValues(alpha: .88)),
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
                color: _styleOf(SearchCategory.passages).color,
              ),
              _ReferenceCard(
                reference: reference,
                onTap: () => onOpenReference(reference),
              ),
            ],
            for (final group in outcome.groups) ...[
              _GroupHeader(
                title: group.category.label,
                count: group.total,
                color: _styleOf(group.category).color,
              ),
              for (final hit in group.hits)
                _HitTile(
                  hit: hit,
                  query: outcome.query,
                  onTap: () => onOpenHit(hit),
                ),
              if (group.truncated && !expanded.contains(group.category))
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      label: Text(
                        'Voir plus',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _styleOf(group.category).color,
                        ),
                      ),
                      onPressed: () => onExpand(group.category),
                      backgroundColor: _styleOf(group.category)
                          .color
                          .withValues(alpha: .14),
                      side: BorderSide.none,
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
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bibleTheme.accentColor.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_download_outlined,
              size: 18, color: bibleTheme.titleColor.withValues(alpha: .85)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: bibleTheme.textColor.withValues(alpha: .85)),
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: bibleTheme.textColor.withValues(alpha: .82),
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  reference.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: bibleTheme.titleColor,
                  ),
                ),
                const SizedBox(width: 8),
                _Badge(reference.versionCode),
              ],
            ),
            const SizedBox(height: 8),
            Text(reference.text, style: theme.textTheme.bodyLarge),
          ],
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

  const _HitTile({
    required this.hit,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    final style = _styleOf(hit.category);
    return InkWell(
      onTap: (hit.category == SearchCategory.strong || hit.canOpen) ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor.withValues(alpha: .5),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(style.icon, size: 21, color: style.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hit.title,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: bibleTheme.titleColor,
                          ),
                        ),
                      ),
                      if (hit.badge != null) ...[
                        const SizedBox(width: 8),
                        _Badge(hit.badge!),
                      ],
                      if (hit.transliteration != null &&
                          hit.transliteration!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flex(
                          direction: Axis.horizontal,
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _Badge('translitéré'),
                            const SizedBox(width: 2),
                            _Badge(hit.transliteration!, strong: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                  if (hit.lemma != null && hit.lemma!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hit.lemma!,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: bibleTheme.textColor.withValues(alpha: .72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  _HighlightedText(
                    text: hit.subtitle,
                    query: query,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;

  /// When true, renders as the highlighted "translitéré" value in italics.
  final bool strong;
  const _Badge(this.text, {this.strong = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: strong
            ? bibleTheme.accentColor.withValues(alpha: .28)
            : bibleTheme.accentColor.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: strong
            ? theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontStyle: FontStyle.italic,
                color: bibleTheme.accentColor,
              )
            : theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: bibleTheme.textColor.withValues(alpha: .9),
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
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: bibleTheme.textColor.withValues(alpha: .78),
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
              backgroundColor:
                  bibleTheme.accentColor.withValues(alpha: .24),
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





