import '../models/bible_book.dart';

/// A word entry in the lexicon, built from a note anchor.
class LexiconEntry {
  final String word; // French anchor word (notes[].word)
  final int position; // character index into verse.text
  final String note; // Wikidata note content (definition)
  final String ref; // e.g. "Ge. 1:26"
  final int bookIndex;
  final int chapter;
  final int verseNumber;

  const LexiconEntry({
    required this.word,
    required this.position,
    required this.note,
    required this.ref,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
  });
}

/// Builds a lexicon from the BYM notes (maquette v8): every verse note whose
/// anchor is a real word becomes an entry keyed by the anchor word. No external
/// Strong module required — but the app stays compatible with one later.
class LexiconService {
  /// All entries for [book] (one per note), in verse order.
  List<LexiconEntry> forBook(BibleBook book) {
    final entries = <LexiconEntry>[];
    for (final chapter in book.chapters) {
      for (final verse in chapter.verses) {
        for (final note in verse.notes) {
          entries.add(LexiconEntry(
            word: note.word,
            position: note.position,
            note: note.note,
            ref: '${book.abbreviation} ${verse.verse}',
            bookIndex: book.number,
            chapter: chapter.chapter,
            verseNumber: verse.number == 0 ? 1 : verse.number,
          ));
        }
      }
    }
    return entries;
  }
}