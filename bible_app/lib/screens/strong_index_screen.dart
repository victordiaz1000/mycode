import 'package:flutter/material.dart';

import '../data/strong_lexicon.dart';
import '../data/theme_catalog.dart';
import '../widgets/bible_theme_scope.dart';
import 'strong_detail_screen.dart';

/// Browse the whole French Strong lexicon: a search field (code, word,
/// transliteration), a Grec/Hébreu filter, and the entries as cards that open
/// the [StrongDetailScreen].
class StrongIndexScreen extends StatefulWidget {
  /// Opens a Strong occurrence verse in a reader tab. Null when the screen
  /// stands alone (tests): the fiche's occurrence cards then just state their
  /// reference.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const StrongIndexScreen({super.key, this.onOpenVerse});

  @override
  State<StrongIndexScreen> createState() => _StrongIndexScreenState();
}

class _StrongIndexScreenState extends State<StrongIndexScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _filtre = 'Tous';
  List<StrongDefinition>? _entries;

  static const List<String> _filtres = ['Tous', 'Grec', 'Hébreu'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await StrongLexicon.instance.all();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  bool _isGreek(StrongDefinition entry) =>
      entry.language == 'greek' || entry.strong.startsWith('G');

  String _langue(StrongDefinition entry) =>
      _isGreek(entry) ? 'Grec' : 'Hébreu';

  List<StrongDefinition> get _filtered {
    final entries = _entries ?? const [];
    final query = _query.trim().toLowerCase();
    return [
      for (final entry in entries)
        if (_filtre == 'Tous' || _langue(entry) == _filtre)
          if (query.isEmpty ||
              entry.strong.toLowerCase().contains(query) ||
              (entry.lemma?.toLowerCase().contains(query) ?? false) ||
              (entry.transliteration?.toLowerCase().contains(query) ?? false) ||
              entry.definition.toLowerCase().contains(query))
            entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dictionnaire Strong')),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(theme),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final filtre in _filtres) ...[
                    _FiltreChip(
                      label: filtre,
                      active: _filtre == filtre,
                      accent: bibleTheme.accentColor,
                      onTap: () => setState(() => _filtre = filtre),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              const _SourceMention(),
              const SizedBox(height: 12),
              Expanded(child: _buildList(theme, bibleTheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Numéro, mot, translittération…',
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Effacer',
              icon: const Icon(Icons.clear_rounded, size: 20),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme, BibleTheme bibleTheme) {
    final filtered = _filtered;
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('Aucune entrée trouvée',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8),
          child: Text(
            '${filtered.length} entrée${filtered.length > 1 ? 's' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final entry in filtered) ...[
          _EntryCard(
            entry: entry,
            isGreek: _isGreek(entry),
            onOpenVerse: widget.onOpenVerse,
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _FiltreChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _FiltreChip({
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? accent : theme.dividerColor),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: active
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SourceMention extends StatelessWidget {
  const _SourceMention();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.info_outline,
            size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Lexique Strong français · CrossWire/SWORD (hébreu & grec)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final StrongDefinition entry;
  final bool isGreek;
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const _EntryCard({
    required this.entry,
    required this.isGreek,
    this.onOpenVerse,
  });

  static const Color _grec = Color(0xFF1A73E8);
  static const Color _hebreu = Color(0xFFD95300);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final couleurLangue = isGreek ? _grec : _hebreu;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                StrongDetailScreen(strong: entry, onOpenVerse: onOpenVerse),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: couleurLangue.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  entry.strong,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: couleurLangue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (entry.lemma != null && entry.lemma!.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              entry.lemma!,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (entry.transliteration != null &&
                            entry.transliteration!.isNotEmpty)
                          Expanded(
                            child: Text(
                              entry.transliteration!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.definition,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}