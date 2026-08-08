import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../data/lexicon_service.dart';
import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/verse.dart';

/// Lexique v8 : the verse shown word-by-word; each annotated word is
/// underlined (dotted, gold) and opens its fiche built from the BYM note.
class LexiqueScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;
  final int verseNumber;

  const LexiqueScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    this.verseNumber = 1,
  });

  @override
  State<LexiqueScreen> createState() => _LexiqueScreenState();
}

class _LexiqueScreenState extends State<LexiqueScreen> {
  final LocalRepository _repository = LocalRepository();
  final LexiconService _lexicon = LexiconService();
  late Future<BibleBook> _bookFuture;
  List<LexiconEntry> _entries = [];
  LexiconEntry? _targetIndex; // displayed fiche for the currently selected word

  @override
  void initState() {
    super.initState();
    _bookFuture = _load();
  }

  Future<BibleBook> _load() async {
    final book = await _repository.loadBook(widget.bookIndex);
    _entries = _lexicon.forBook(book)
        .where((e) =>
            e.chapter == widget.chapter && e.verseNumber == widget.verseNumber)
        .toList();
    return book;
  }

  @override
  Widget build(BuildContext context) {
    final entry = catalogEntry(widget.bookIndex);
    return Scaffold(
      appBar: AppBar(
        title: Text('Lexique — ${entry.abbreviation} ${widget.chapter}.${widget.verseNumber}'),
      ),
      body: FutureBuilder<BibleBook>(
        future: _bookFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final book = snapshot.data!;
          final chapter = book.chapters.firstWhere(
              (c) => c.chapter == widget.chapter,
              orElse: () => Chapter(chapter: widget.chapter, verses: []));
          final verse = chapter.verses.isEmpty
              ? null
              : chapter.verses.firstWhere(
                  (v) => (v.number == 0 ? 1 : v.number) == widget.verseNumber,
                  orElse: () => chapter.verses.first);
          return verse == null
              ? const Center(child: Text('Verset introuvable.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _WordCloudVerse(
                      verse: verse,
                      entries: _entries,
                      onTap: (entry) => setState(() => _targetIndex = entry),
                    ),
                    const SizedBox(height: 16),
                    if (_targetIndex != null)
                      _FicheCard(entry: _targetIndex!),
                    if (_entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 24),
                        child: Center(
                            child: Text(
                                'Aucun mot annoté dans ce verset pour le lexique.')),
                      ),
                  ],
                );
        },
      ),
    );
  }
}

/// Renders the verse splitting annotated words into tappable spans.
class _WordCloudVerse extends StatelessWidget {
  final Verse verse;
  final List<LexiconEntry> entries;
  final void Function(LexiconEntry) onTap;

  const _WordCloudVerse({
    required this.verse,
    required this.entries,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = verse.text;
    final accent = theme.colorScheme.primary;

    // Build ranges for the annotated words.
    final spans = <InlineSpan>[];
    final sorted = [...entries]..sort((a, b) => a.position.compareTo(b.position));
    var cursor = 0;
    for (final e in sorted) {
      final word = e.word;
      var start = e.position;
      if (start < 0 || start + word.length > text.length) {
        final found = text.indexOf(word);
        if (found < 0) continue;
        start = found;
      }
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => onTap(e),
          child: Text.rich(TextSpan(
            text: word,
            style: TextStyle(
              color: accent,
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              fontWeight: FontWeight.w600,
            ),
            children: const [TextSpan(text: '  ')],
          )),
        ),
      ));
      cursor = start + word.length;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text.rich(
          TextSpan(children: spans),
          style: theme.textTheme.bodyLarge!.copyWith(height: 1.6, fontSize: 18),
        ),
      ),
    );
  }
}

/// Fiche du mot : mot, translittération (reprise de la note), Strong si précisé,
/// définition (note) comme source.
class _FicheCard extends StatelessWidget {
  final LexiconEntry entry;
  const _FicheCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.word,
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold, color: accent),
                ),
                const Spacer(),
                Text(entry.ref,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
            const Divider(height: 20),
            Text('Définition (note de traduction)',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: accent)),
            const SizedBox(height: 4),
            Text(entry.note, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(
              'Module · Lexique des notes de traduction',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}