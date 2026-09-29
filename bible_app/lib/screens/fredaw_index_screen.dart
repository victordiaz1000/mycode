import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import '../widgets/lexicon_index_widgets.dart';
import '../widgets/premium_style.dart';
import '../widgets/loading_skeleton.dart';
import 'fredaw_entry_screen.dart';

/// Browse the whole Westphal 1932 dictionary: a search field, an alphabetical
/// index (first-letter chips, accents folded: « ÂGE » lives under « A »), and
/// the entries grouped by letter.
class FredawIndexScreen extends StatefulWidget {
  /// Ouvre la référence biblique d'un article dans la lecture. Null hors
  /// coquille (tests) : les fiches restent consultables sans navigation,
  /// comme pour les index BYM et Strong.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const FredawIndexScreen({super.key, this.onOpenVerse});

  @override
  State<FredawIndexScreen> createState() => _FredawIndexScreenState();
}

class _FredawIndexScreenState extends State<FredawIndexScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _letter;
  List<FreDawEntry>? _entries;

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
    final entries = await FreDawLexicon.instance.all();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  /// Group key for [entry]: the folded first letter (Â → A, É → E).
  static String _groupLetter(FreDawEntry entry) {
    final folded = normalizeForSearch(entry.term);
    if (folded.isEmpty) return '#';
    final first = folded[0];
    return (first.compareTo('a') >= 0 && first.compareTo('z') <= 0)
        ? first.toUpperCase()
        : '#';
  }

  List<FreDawEntry> get _filtered {
    final entries = _entries ?? const [];
    final letter = _letter;
    final query = _query.trim().toLowerCase();
    return [
      for (final entry in entries)
        if (letter == null || _groupLetter(entry) == letter)
          if (query.isEmpty ||
              entry.term.toLowerCase().contains(query) ||
              entry.definition.toLowerCase().contains(query))
            entry,
    ];
  }

  List<String> get _letters {
    final letters = <String>{
      for (final e in _entries ?? const <FreDawEntry>[]) _groupLetter(e),
    };
    final sorted = letters.toList()..sort();
    return sorted;
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
          'Westphal 1932',
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
                hint: 'Rechercher dans ce dictionnaire…',
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
                text:
                    'Dictionnaire encyclopédique de la Bible · Auguste Westphal, 1932',
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
      return const ListLoadingSkeleton();
    }
    if (filtered.isEmpty) {
      return const LexiconEmptyState();
    }

    final grouped = <String, List<FreDawEntry>>{};
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
              title: entry.term,
              subtitle: entry.definition,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FredawEntryScreen(
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
