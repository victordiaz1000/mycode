import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/bible_book.dart';
import '../models/chapter.dart';
import 'book_catalog.dart';

/// Loads the embedded BYM books from `assets/bible/bym/`.
///
/// Parsing is lazy and per-book: calling [loadBook] parses the whole file on
/// first request, then caches it in memory. [loadChapter] only loads the
/// requested book. This keeps startup fast (66 books would be heavy to parse
/// at once).
class LocalRepository {
  static const String assetPrefix = 'assets/bible/bym/';

  /// Shared across instances so a book is parsed at most once per app run
  /// (each screen used to parse the whole file on its first chapter).
  static final Map<int, BibleBook> _cache = {};

  static void clearCache() => _cache.clear();

  static AssetBundle _bundle = rootBundle;

  /// Where book JSON is read from. Defaults to [rootBundle].
  static AssetBundle get bundle => _bundle;

  /// Replaces the asset source and clears the cache. Widget tests use this to
  /// serve a synthetic book: real `rootBundle` I/O never completes inside the
  /// fake-async zone of `testWidgets`, so `pumpAndSettle` would hang forever.
  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    clearCache();
  }

  /// Restores the real asset bundle (call in `tearDown`).
  static void useRootBundle() => useBundle(rootBundle);

  String assetPath(int bookNumber) =>
      '$assetPrefix${catalogEntry(bookNumber).file}';

  bool isLoaded(int bookNumber) => _cache.containsKey(bookNumber);

  /// Loads and returns the book at [bookNumber] (1..66), caching it.
  Future<BibleBook> loadBook(int bookNumber) async {
    final cached = _cache[bookNumber];
    if (cached != null) return cached;

    final raw = await _bundle.loadString(assetPath(bookNumber));
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final book =
        BibleBook.fromJson(decoded, number: bookNumber);
    _cache[bookNumber] = book;
    return book;
  }

  /// Returns only the chapter [chapter] (1-based) of the book at [bookNumber].
  Future<Chapter> loadChapter(int bookNumber, int chapter) async {
    final book = await loadBook(bookNumber);
    return book.chapters.firstWhere(
      (c) => c.chapter == chapter,
      orElse: () => Chapter(chapter: chapter, verses: const []),
    );
  }

  /// Number of chapters in [bookNumber], without reading verses eagerly
  /// (the whole book is parsed on first load regardless).
  Future<int> chapterCount(int bookNumber) async {
    final book = await loadBook(bookNumber);
    return book.chapters.length;
  }

  /// The chapter *before* ([bookNumber], [chapter]) in BYM reading order,
  /// crossing into the last chapter of the previous book when [chapter] is the
  /// first one. Null at the very beginning (Genèse 1).
  Future<(int book, int chapter)?> previousChapter(
    int bookNumber,
    int chapter,
  ) async {
    if (chapter > 1) return (bookNumber, chapter - 1);
    if (bookNumber <= 1) return null;
    final previous = bookNumber - 1;
    return (previous, await chapterCount(previous));
  }

  /// The chapter *after* ([bookNumber], [chapter]) in BYM reading order,
  /// crossing into chapter 1 of the next book when [chapter] is the last one.
  /// Null at the very end (last chapter of Apocalypse).
  Future<(int book, int chapter)?> nextChapter(
    int bookNumber,
    int chapter,
  ) async {
    if (chapter < await chapterCount(bookNumber)) {
      return (bookNumber, chapter + 1);
    }
    if (bookNumber >= bookCatalog.length) return null;
    return (bookNumber + 1, 1);
  }
}
