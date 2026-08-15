import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import '../widgets/premium_style.dart';
import 'fredaw_entry_screen.dart';

/// Browse the whole Westphal 1932 dictionary: a search field, an alphabetical
/// index (first-letter chips, accents folded: « ÂGE » lives under « A »), and
/// the entries grouped by letter.
class FredawIndexScreen extends StatefulWidget {
  /// Opens a Bible reference of an article in a reader tab. Null when the
  /// screen stands alone (tests): references then stay plain text.
  final void Function(int bookIndex, int chapter, int? verse)? onOpenVerse;

  /// Opens the entry in a reading tab instead of the fiche. Null when the
  /// screen stands alone (tests): the fiche then shows no « Ouvrir onglet ».
  final void Function(String term, String definition)? onOpenDictionary;

  const FredawIndexScreen({
    super.key,
    this.onOpenVerse,
    this.onOpenDictionary,
  });

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
    final letters = <String>{for (final e in _entries ?? const <FreDawEntry>[]) _groupLetter(e)};
    final sorted = letters.toList()..sort();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: kPremiumBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
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
              _buildSearchField(context),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _LetterChip(
                      label: 'Toutes',
                      active: _letter == null,
                      accent: p.primary,
                      onTap: () => setState(() => _letter = null),
                    ),
                    for (final letter in _letters) ...[
                      const SizedBox(width: 8),
                      _LetterChip(
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.06,
          blur: 14,
          offset: const Offset(0, 4),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(Icons.search_rounded, color: p.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Rechercher dans ce dictionnaire…',
                hintStyle: premiumText(context, 14, FontWeight.w500, p.textGrey),
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

  Widget _buildList(BuildContext context) {
    final p = premiumPalette(context);
    final filtered = _filtered;
    if (_entries == null) {
      return const Center(child: CircularProgressIndicator());
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
                Expanded(child: Divider(color: p.textGrey.withValues(alpha: .25))),
              ],
            ),
          ),
          for (final entry in grouped[letter]!) ...[
            _EntryCard(
              entry: entry,
              onOpenVerse: widget.onOpenVerse,
              onOpenDictionary: widget.onOpenDictionary,
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LetterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const _LetterChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? p.heroGradient : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? Colors.transparent : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: active
              ? premiumShadow(accent, opacity: .2, blur: 12, offset: const Offset(0, 4))
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            active ? Colors.white : p.textDark,
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
    final p = premiumPalette(context);
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: p.textGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Dictionnaire encyclopédique de la Bible · Auguste Westphal, 1932',
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  final FreDawEntry entry;
  final void Function(int bookIndex, int chapter, int? verse)? onOpenVerse;
  final void Function(String term, String definition)? onOpenDictionary;

  const _EntryCard({
    required this.entry,
    required this.onOpenVerse,
    this.onOpenDictionary,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => FredawEntryScreen(
              entry: entry,
              onOpenVerse: onOpenVerse,
              onOpenDictionary: onOpenDictionary,
            ),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: premiumShadow(
              p.primaryDark,
              opacity: 0.05,
              blur: 12,
              offset: const Offset(0, 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.term,
                      style: premiumText(context, 15, FontWeight.w800, p.textDark),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.definition,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: premiumText(context, 12, FontWeight.w500, p.textGrey, height: 1.4),
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
    );
  }
}