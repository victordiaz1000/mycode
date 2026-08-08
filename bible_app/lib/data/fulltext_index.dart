import '../models/bible_book.dart';
import 'reference_parser.dart';
import 'version_repository.dart';

/// A full-text match: a verse that contains the searched text.
class VerseMatch {
  final int bookIndex;
  final int chapter;
  final int verseNumber;
  final String text;

  /// Lower is better (see [FulltextIndex.search] ranking).
  final int score;

  const VerseMatch({
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.text,
    required this.score,
  });
}

/// The page of matches returned by [FulltextIndex.search], plus how many
/// verses matched in total (so the UI can print « 4 » next to a capped list).
class FulltextResults {
  final List<VerseMatch> matches;
  final int total;

  /// Books the index actually covers (66 for the BYM, less for a version still
  /// downloading). Carried on the results because « rien trouvé » in a partial
  /// version means « pas dans les livres présents », not « pas dans la Bible ».
  final int indexedBooks;

  const FulltextResults({
    required this.matches,
    required this.total,
    this.indexedBooks = 0,
  });

  bool get isEmpty => matches.isEmpty;

  /// True when [total] exceeded the requested limit.
  bool get truncated => total > matches.length;
}

/// In-memory, lazily-built index over one version's books.
///
/// The whole corpus is scanned once (parsing each book through
/// [VersionRepository], which caches it) and then kept as a list of normalized
/// verse texts. Queries are normalized the same way, so search is accent- and
/// case-insensitive ("evangile" finds « Évangile »).
///
/// One index per version code, reached through [of]; [instance] is the embedded
/// BYM one. A version whose download is partial indexes **what is on the
/// device** and reports it through [indexedBooks] — refusing to index it at all
/// would make the download useless until its last book landed.
class FulltextIndex {
  FulltextIndex._(this.code);

  /// Version this index covers ([VersionRepository.embeddedCode] for the BYM).
  final String code;

  static final Map<String, FulltextIndex> _indexes = {};

  /// Non-embedded indexes kept in memory at once. Each one is ~31 000
  /// normalized verses, so letting every version the reader tries pile up would
  /// grow without bound; the BYM never counts against the cap since it is the
  /// default source of every search.
  static const int _maxDownloadedIndexes = 2;

  static VersionRepository? _versionsOverride;

  /// The embedded BYM index — the default source of the search.
  static FulltextIndex get instance => of(VersionRepository.embeddedCode);

  /// The index for [code], built on first search.
  static FulltextIndex of(String code) {
    final existing = _indexes[code];
    if (existing != null) return existing;

    if (code != VersionRepository.embeddedCode) {
      final downloaded = _indexes.keys
          .where((k) => k != VersionRepository.embeddedCode)
          .toList();
      // Insertion order = age, so the first key is the oldest.
      while (downloaded.length >= _maxDownloadedIndexes) {
        _indexes.remove(downloaded.removeAt(0));
      }
    }
    return _indexes[code] = FulltextIndex._(code);
  }

  /// Serves every index from [versions] instead of the ambient repository.
  ///
  /// Same seam as [LocalRepository.useBundle] / `LibraryStore.useRoot`: reading
  /// a downloaded book goes through `dart:io`, mute inside the fake-async zone
  /// of `testWidgets`.
  static void useVersions(VersionRepository versions) {
    _versionsOverride = versions;
    _indexes.clear();
  }

  static void useAmbientVersions() {
    _versionsOverride = null;
    _indexes.clear();
  }

  /// Drops [code]'s index — to call when the Bibliothèque deletes a version,
  /// which would otherwise stay searchable from memory with no files left.
  static void forget(String code) => _indexes.remove(code);

  static const int _minQueryLength = 2;

  late final VersionRepository _versions =
      _versionsOverride ?? VersionRepository();

  List<_IndexedVerse> _verses = const [];
  int _indexedBooks = 0;
  bool _built = false;
  Future<void>? _building;

  bool get isBuilt => _built;

  /// Number of indexed verses (0 until built).
  int get size => _verses.length;

  /// Books covered once built — 66 for the BYM, fewer for a partial download.
  int get indexedBooks => _indexedBooks;

  /// Drops the index so the next search rebuilds from the books' cache.
  /// Widget tests swap the asset bundle and must call this in `setUp`.
  void clearIndex() {
    _verses = const [];
    _indexedBooks = 0;
    _built = false;
    _building = null;
  }

  /// Builds the index once, returning when it is ready.
  Future<void> ensureIndexed() {
    if (_built) return Future.value();
    return _building ??= _build();
  }

  Future<void> _build() async {
    final verses = <_IndexedVerse>[];
    var books = 0;
    for (var book = 1; book <= 66; book++) {
      final BibleBook loaded;
      try {
        loaded = await _versions.loadBook(code, book);
      } on BookNotDownloaded {
        continue; // partial download: index what the device holds
      }
      books++;
      for (final chapter in loaded.chapters) {
        for (final verse in chapter.verses) {
          final normalized = normalizeForSearch(verse.text);
          if (normalized.isEmpty) continue;
          verses.add(_IndexedVerse(
            book: book,
            chapter: chapter.chapter,
            verseNumber: verse.number,
            text: verse.text,
            normalized: normalized,
          ));
        }
      }
    }
    _verses = verses;
    _indexedBooks = books;
    _built = true;
  }

  /// Verses matching [query], best first, capped at [limit].
  ///
  /// Ranking: the whole phrase starts the verse (0) > the phrase is a
  /// substring (1) > every word of the query is present (2). Ties are broken
  /// by book order, then chapter, then verse. An empty or too-short query
  /// returns nothing.
  ///
  /// [bookFilter], when given, restricts the scan to the book indices it
  /// accepts (the « Section » and « Livre » filters of the search screen).
  /// With [biblicalOrder] the results are sorted by position only, ignoring
  /// the relevance score.
  ///
  /// [total] on the result reports how many verses matched before [limit].
  Future<FulltextResults> search(
    String query, {
    int limit = 60,
    bool Function(int bookIndex)? bookFilter,
    bool biblicalOrder = false,
  }) async {
    await ensureIndexed();
    final q = normalizeForSearch(query);
    if (q.length < _minQueryLength) {
      return FulltextResults(
          matches: const [], total: 0, indexedBooks: _indexedBooks);
    }

    final tokens = q.split(' ');
    final results = <({int score, _IndexedVerse verse})>[];

    for (final v in _verses) {
      if (bookFilter != null && !bookFilter(v.book)) continue;
      int? score;
      if (v.normalized.startsWith(q)) {
        score = 0;
      } else if (v.normalized.contains(q)) {
        score = 1;
      } else if (_containsAllTokens(v.normalized, tokens)) {
        score = 2;
      }
      if (score == null) continue;
      results.add((score: score, verse: v));
    }

    results.sort((a, b) {
      if (!biblicalOrder && a.score != b.score) return a.score - b.score;
      if (a.verse.book != b.verse.book) return a.verse.book - b.verse.book;
      if (a.verse.chapter != b.verse.chapter) {
        return a.verse.chapter - b.verse.chapter;
      }
      return a.verse.verseNumber - b.verse.verseNumber;
    });

    return FulltextResults(
      total: results.length,
      indexedBooks: _indexedBooks,
      matches: [
        for (final r in results.take(limit))
          VerseMatch(
            bookIndex: r.verse.book,
            chapter: r.verse.chapter,
            verseNumber: r.verse.verseNumber,
            text: r.verse.text,
            score: r.score,
          ),
      ],
    );
  }

  bool _containsAllTokens(String normalized, List<String> tokens) {
    for (final token in tokens) {
      if (!normalized.split(' ').contains(token)) return false;
    }
    return true;
  }
}

class _IndexedVerse {
  final int book;
  final int chapter;
  final int verseNumber;
  final String text;
  final String normalized;

  const _IndexedVerse({
    required this.book,
    required this.chapter,
    required this.verseNumber,
    required this.text,
    required this.normalized,
  });
}
