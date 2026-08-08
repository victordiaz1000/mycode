import 'local_repository.dart';
import 'reference_parser.dart';

/// A dictionary entry built from a BYM note anchor: the French word and the
/// definition attached to it, plus where it was first met.
class DictionaryEntry {
  /// The anchor word, as written in the text ("Yod", "Apollyon"…).
  final String word;

  /// The note content (Wikidata definition).
  final String definition;

  final int bookIndex;
  final int chapter;
  final int verseNumber;

  /// How many verses carry a note on this same word.
  final int occurrences;

  const DictionaryEntry({
    required this.word,
    required this.definition,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.occurrences,
  });
}

/// In-memory dictionary over every note anchor of the 66 embedded BYM books.
///
/// Built the same way as the full-text index: the corpus is walked once
/// through [LocalRepository.loadBook] (which caches each parsed book, so the
/// two indexes share the parsing cost) and notes are collapsed by normalized
/// word, keeping the longest definition met for that word.
class LexiconIndex {
  LexiconIndex._();

  static final LexiconIndex _instance = LexiconIndex._();

  /// The shared index.
  static LexiconIndex get instance => _instance;

  static const int _minQueryLength = 2;

  List<DictionaryEntry> _entries = const [];
  bool _built = false;
  Future<void>? _building;

  bool get isBuilt => _built;

  /// Number of distinct words in the dictionary (0 until built).
  int get size => _entries.length;

  /// Drops the index so the next search rebuilds from the books' cache.
  /// Widget tests swap the asset bundle and must call this in `setUp`.
  void clearIndex() {
    _entries = const [];
    _built = false;
    _building = null;
  }

  /// Builds the index once, returning when it is ready.
  Future<void> ensureIndexed() {
    if (_built) return Future.value();
    return _building ??= _build();
  }

  Future<void> _build() async {
    final repository = LocalRepository();
    final byWord = <String, _Accumulator>{};

    for (var book = 1; book <= 66; book++) {
      final loaded = await repository.loadBook(book);
      for (final chapter in loaded.chapters) {
        for (final verse in chapter.verses) {
          for (final note in verse.notes) {
            final key = normalizeForSearch(note.word);
            final definition = note.note.trim();
            if (key.isEmpty || definition.isEmpty) continue;

            final existing = byWord[key];
            if (existing == null) {
              byWord[key] = _Accumulator(
                word: note.word,
                definition: definition,
                bookIndex: book,
                chapter: chapter.chapter,
                verseNumber: verse.number == 0 ? 1 : verse.number,
              );
            } else {
              existing.occurrences++;
              // Keep the richest wording met for that anchor.
              if (definition.length > existing.definition.length) {
                existing.definition = definition;
              }
            }
          }
        }
      }
    }

    _entries = [
      for (final a in byWord.values)
        DictionaryEntry(
          word: a.word,
          definition: a.definition,
          bookIndex: a.bookIndex,
          chapter: a.chapter,
          verseNumber: a.verseNumber,
          occurrences: a.occurrences,
        ),
    ]..sort((a, b) =>
        normalizeForSearch(a.word).compareTo(normalizeForSearch(b.word)));
    _built = true;
  }

  /// Entries matching [query], best first, capped at [limit].
  ///
  /// Ranking: exact word (0) > word prefix (1) > word substring (2) >
  /// the definition mentions the query (3). Ties keep alphabetical order.
  Future<List<DictionaryEntry>> search(String query, {int limit = 30}) async {
    await ensureIndexed();
    final q = normalizeForSearch(query);
    if (q.length < _minQueryLength) return const [];

    final results = <({int score, int rank, DictionaryEntry entry})>[];
    for (var i = 0; i < _entries.length; i++) {
      final entry = _entries[i];
      final word = normalizeForSearch(entry.word);
      int? score;
      if (word == q) {
        score = 0;
      } else if (word.startsWith(q)) {
        score = 1;
      } else if (word.contains(q)) {
        score = 2;
      } else if (normalizeForSearch(entry.definition).contains(q)) {
        score = 3;
      }
      if (score == null) continue;
      results.add((score: score, rank: i, entry: entry));
    }

    // `_entries` is alphabetical, so breaking ties on the original position
    // keeps equally-scored words in alphabetical order (List.sort is not
    // stable in Dart).
    results.sort((a, b) =>
        a.score != b.score ? a.score - b.score : a.rank - b.rank);
    return [for (final r in results.take(limit)) r.entry];
  }
}

class _Accumulator {
  final String word;
  String definition;
  final int bookIndex;
  final int chapter;
  final int verseNumber;
  int occurrences = 1;

  _Accumulator({
    required this.word,
    required this.definition,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
  });
}
