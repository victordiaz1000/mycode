import 'package:flutter/material.dart';

import '../data/lexicon_index.dart';
import '../data/reference_parser.dart';
import '../widgets/lexicon_index_widgets.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import 'bym_lexicon_entry_screen.dart';

/// Browse the whole BYM lexicon: a search field, an alphabetical index
/// (first-letter chips, accents folded: « Éternel » lives under « E »), and
/// the entries grouped by letter. Tapping an entry opens its fiche.
class BymLexiconIndexScreen extends StatefulWidget {
  /// Opens the referenced verse in a reader tab. Null when the screen stands
  /// alone (tests): the fiche's button then just states the reference.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const BymLexiconIndexScreen({super.key, this.onOpenVerse});

  @override
  State<BymLexiconIndexScreen> createState() => _BymLexiconIndexScreenState();
}

class _BymLexiconIndexScreenState extends State<BymLexiconIndexScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _letter;
  List<DictionaryEntry>? _entries;

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
    final entries = await LexiconIndex.instance.all();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// Group key for [entry]: the folded first letter (Â → A, É → E).
  static String _groupLetter(DictionaryEntry entry) {
    final folded = normalizeForSearch(entry.word);
    if (folded.isEmpty) return '#';
    final first = folded[0];
    return (first.compareTo('a') >= 0 && first.compareTo('z') <= 0)
        ? first.toUpperCase()
        : '#';
  }

  List<DictionaryEntry> get _filtered {
    final entries = _entries ?? const [];
    final letter = _letter;
    final query = _query.trim().toLowerCase();
    return [
      for (final entry in entries)
        if (letter == null || _groupLetter(entry) == letter)
          if (query.isEmpty ||
              entry.word.toLowerCase().contains(query) ||
              entry.definition.toLowerCase().contains(query))
            entry,
    ];
  }

  List<String> get _letters {
    final letters = <String>{
      for (final e in _entries ?? const <DictionaryEntry>[]) _groupLetter(e),
    };
    return letters.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                p.primary.withValues(alpha: .12),
                p.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        title: Text(
          'Notes BYM Lexique',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LexiconSearchField(
                hint: 'Rechercher dans le lexique BYM…',
                controller: _controller,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    LexiconLetterChip(
                      label: 'Toutes',
                      active: _letter == null,
                      accent: p.primary,
                      onTap: () => setState(() => _letter = null),
                    ),
                    for (final letter in _letters) ...[
                      const SizedBox(width: 8),
                      LexiconLetterChip(
                        key: Key('letter-chip-$letter'),
                        label: letter,
                        active: _letter == letter,
                        accent: p.primary,
                        onTap: () => setState(() => _letter = letter),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const LexiconSourceMention(
                text: 'Notes internes de la BYM · une entrée par mot noté',
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildList(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final p = premiumPalette(context);
    final filtered = _filtered;
    if (_entries == null) {
      // Même squelette que les index Westphal et Strong : une liste de
      // cartes, pas un spinner nu.
      return const ListLoadingSkeleton(padding: EdgeInsets.zero);
    }
    if (filtered.isEmpty) {
      return const LexiconEmptyState();
    }

    final grouped = <String, List<DictionaryEntry>>{};
    for (final entry in filtered) {
      grouped.putIfAbsent(_groupLetter(entry), () => []).add(entry);
    }
    final letters = grouped.keys.toList()..sort();

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 8),
          child: Text(
            '${filtered.length} entrée${filtered.length > 1 ? 's' : ''}',
            style: premiumText(context, 12, FontWeight.w600, p.textGrey),
          ),
        ),
        const SizedBox(height: 8),
        for (final letter in letters) ...[
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              children: [
                Text(
                  letter,
                  style: premiumText(context, 20, FontWeight.w800, p.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  // Filet d'accent qui se perd vers la droite : la lettre de
                  // groupe porte la division, pas un trait gris.
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          p.primary.withValues(alpha: .45),
                          p.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final entry in grouped[letter]!) ...[
            LexiconEntryCard(
              title: entry.word,
              subtitle: entry.definition,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BymLexiconEntryScreen(
                    entry: entry,
                    onOpenVerse: widget.onOpenVerse,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}
