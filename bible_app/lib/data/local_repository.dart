import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/bible_book.dart';
import '../models/chapter.dart';
import 'book_catalog.dart';
import 'bym_update_store.dart';

/// Loads the embedded BYM books from `assets/bible/bym/`, une mise à jour du
/// texte ayant la priorité quand elle existe.
///
/// Parsing is lazy and per-book: calling [loadBook] parses the whole file on
/// first request, then caches it in memory. [loadChapter] only loads the
/// requested book. This keeps startup fast (66 books would be heavy to parse
/// at once).
///
/// **Ce point d'entrée est le goulot de toute la BYM** : favoris, accueil,
/// notes, recherche, lexique, occurrences Strong et `VersionRepository` passent
/// tous par [loadBook]. C'est pourquoi la priorité de lecture est branchée ici
/// et nulle part ailleurs.
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
  ///
  /// Une mise à jour du texte l'emporte sur l'asset embarqué, mais **jamais au
  /// prix de la lisibilité** : un fichier mis à jour illisible est effacé et
  /// l'asset reprend la main. Sans ce filet, un JSON abîmé rendrait un livre
  /// définitivement inaccessible, sans aucun recours depuis l'interface.
  Future<BibleBook> loadBook(int bookNumber) async {
    final cached = _cache[bookNumber];
    if (cached != null) return cached;

    final book = await _readUpdated(bookNumber) ?? await _readAsset(bookNumber);
    _cache[bookNumber] = book;
    return book;
  }

  /// Le livre tel que la mise à jour le porte, null s'il n'y en a pas ou si le
  /// fichier ne tient pas.
  ///
  /// Le prédicat [BymUpdateStore.hasUpdate] est **synchrone** à dessein : sans
  /// lui, ce chemin appellerait `path_provider` à chaque lecture de livre et
  /// gèlerait `pumpAndSettle` dans la dizaine de tests widget qui passent par
  /// ici — le `path_provider` réel ne répond jamais dans la zone fake-async.
  Future<BibleBook?> _readUpdated(int bookNumber) async {
    final name = catalogEntry(bookNumber).file;
    if (!BymUpdateStore.hasUpdate(name)) return null;
    try {
      final raw = await BymUpdateStore().read(name);
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return BibleBook.fromJson(decoded, number: bookNumber);
    } catch (_) {
      // Retour au texte embarqué en entier plutôt qu'un panachage silencieux :
      // le numéro de version affiché ne décrirait plus ce qui est lu. La
      // prochaine vérification reproposera la mise à jour.
      try {
        await BymUpdateStore().clear();
      } catch (_) {
        // `clear` a déjà vidé l'état en mémoire de façon synchrone : l'asset
        // reprend la main même si le disque résiste.
      }
      return null;
    }
  }

  Future<BibleBook> _readAsset(int bookNumber) async {
    final raw = await _bundle.loadString(assetPath(bookNumber));
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return BibleBook.fromJson(decoded, number: bookNumber);
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
