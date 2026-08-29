import 'package:flutter/material.dart';

import '../data/strong_lexicon.dart';
import '../widgets/premium_style.dart';
import '../widgets/loading_skeleton.dart';
import 'strong_detail_screen.dart';

/// Browse the whole French Strong lexicon: a search field (code, word,
/// transliteration), a Grec/Hébreu filter, and the entries as cards that open
/// the [StrongDetailScreen]. Mise au goût premium (maquette
/// `interfaces/ecran_listes_mots_strong.dart`).
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

  String _langue(StrongDefinition entry) => _isGreek(entry) ? 'Grec' : 'Hébreu';

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
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Dictionnaire Strong',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchField(context),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final filtre in _filtres) ...[
                    _buildFiltreChip(context, filtre),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              const _SourceMention(),
              const SizedBox(height: 12),
              Expanded(child: _buildList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.05,
          blur: 10,
          offset: const Offset(0, 4),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: p.primary),
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

  Widget _buildFiltreChip(BuildContext context, String label) {
    final p = premiumPalette(context);
    final actif = _filtre == label;
    return GestureDetector(
      onTap: () => setState(() => _filtre = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? null : p.surfaceAlt,
          gradient: actif ? p.heroGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif
                ? Colors.transparent
                : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: actif
              ? premiumShadow(
                  p.primary,
                  opacity: 0.3,
                  blur: 12,
                  offset: const Offset(0, 5),
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            actif ? p.onPrimary : p.textDark,
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final p = premiumPalette(context);
    final filtered = _filtered;
    if (_entries == null) {
      return const ListLoadingSkeleton();
    }
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: p.textGrey),
            const SizedBox(height: 8),
            Text(
              'Aucune entrée trouvée',
              style: premiumText(context, 14, FontWeight.w600, p.textGrey),
            ),
          ],
        ),
      );
    }
    return ListView(
      children: [
        Text(
          '${filtered.length} entrée${filtered.length > 1 ? 's' : ''}',
          style: premiumText(context, 13, FontWeight.w500, p.textGrey),
        ),
        const SizedBox(height: 12),
        for (final entry in filtered) ...[
          _EntryCard(
            entry: entry,
            isGreek: _isGreek(entry),
            onOpenVerse: widget.onOpenVerse,
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SourceMention extends StatelessWidget {
  const _SourceMention();

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: p.textGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Lexique Strong français · CrossWire/SWORD (hébreu & grec)',
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
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

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final couleurLangue = isGreek ? p.greek : p.hebrew;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.07,
            blur: 16,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: couleurLangue.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    entry.strong,
                    style: premiumText(
                      context,
                      13,
                      FontWeight.w800,
                      couleurLangue,
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
                          if (entry.lemma != null &&
                              entry.lemma!.isNotEmpty) ...[
                            Flexible(
                              child: Text(
                                entry.lemma!,
                                overflow: TextOverflow.ellipsis,
                                style: premiumText(
                                  context,
                                  16,
                                  FontWeight.w800,
                                  p.textDark,
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
                                style: premiumText(
                                  context,
                                  13,
                                  FontWeight.w500,
                                  p.textGrey,
                                  italic: FontStyle.italic,
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
                        style: premiumText(
                          context,
                          13,
                          FontWeight.w500,
                          p.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: p.textGrey, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
