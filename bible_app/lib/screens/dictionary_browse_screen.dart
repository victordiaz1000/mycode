import 'package:flutter/material.dart';

import '../data/dictionary_catalog.dart';
import '../data/dictionary_reader.dart';
import '../data/dictionary_store.dart';
import '../data/reference_parser.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/lexicon_index_widgets.dart';
import '../widgets/premium_style.dart';
import 'dictionary_entry_screen.dart';

/// Browse a downloaded dictionary: a search field, an alphabetical index
/// (first-letter chips, accents folded) and the entries as cards. The content
/// is read from [DictionaryStore] — the same `{entries: {...}}` shape as the
/// embedded lexicons, whatever the source (décision 7: direct URL).
class DictionaryBrowseScreen extends StatefulWidget {
  final DictionaryEntry entry;

  /// Where the downloaded file lives. Injected by tests; the app takes the
  /// real store.
  final DictionaryStore? store;

  /// Ouvre une référence biblique d'une fiche dans la lecture. Null hors
  /// coquille : les références des fiches restent du texte plat.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const DictionaryBrowseScreen({
    super.key,
    required this.entry,
    this.store,
    this.onOpenVerse,
  });

  @override
  State<DictionaryBrowseScreen> createState() => _DictionaryBrowseScreenState();
}

class _DictionaryBrowseScreenState extends State<DictionaryBrowseScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String? _letter;
  DictionaryReader? _reader;

  DictionaryStore get _store => widget.store ?? DictionaryStore();

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
    final json = await _store.load(widget.entry.code);
    if (!mounted) return;
    setState(() {
      _reader = json == null ? null : DictionaryReader.fromJson(json);
    });
  }

  /// Group key for [article]: the folded first letter (Â → A, É → E).
  static String _groupLetter(DictionaryArticle article) {
    final folded = normalizeForSearch(article.term);
    if (folded.isEmpty) return '#';
    final first = folded[0];
    return (first.compareTo('a') >= 0 && first.compareTo('z') <= 0)
        ? first.toUpperCase()
        : '#';
  }

  List<DictionaryArticle> get _filtered {
    final entries = _reader?.all() ?? const [];
    final letter = _letter;
    final query = _query.trim().toLowerCase();
    return [
      for (final article in entries)
        if (letter == null || _groupLetter(article) == letter)
          if (query.isEmpty ||
              article.term.toLowerCase().contains(query) ||
              article.definition.toLowerCase().contains(query))
            article,
    ];
  }

  List<String> get _letters {
    final letters = <String>{
      for (final article in _reader?.all() ?? const <DictionaryArticle>[])
        _groupLetter(article),
    };
    final sorted = letters.toList()..sort();
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final reader = _reader;
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          widget.entry.name,
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: reader == null
            ? const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: DictionaryBrowseLoadingSkeleton(),
              )
            : Padding(
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
        color: p.surface,
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
                hintStyle: premiumText(
                  context,
                  14,
                  FontWeight.w500,
                  p.textGrey,
                ),
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
    final reader = _reader!;
    if (reader.size == 0) {
      return Center(
        child: Text(
          'Dictionnaire vide.',
          style: premiumText(context, 14, FontWeight.w600, p.textGrey),
        ),
      );
    }

    final filtered = _filtered;
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

    final grouped = <String, List<DictionaryArticle>>{};
    for (final article in filtered) {
      grouped.putIfAbsent(_groupLetter(article), () => []).add(article);
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
                  child: Divider(color: p.textGrey.withValues(alpha: .25)),
                ),
              ],
            ),
          ),
          for (final article in grouped[letter]!) ...[
            LexiconEntryCard(
              title: article.term,
              subtitle: article.definition,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DictionaryEntryScreen(
                    entry: widget.entry,
                    article: article,
                    reader: reader,
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
