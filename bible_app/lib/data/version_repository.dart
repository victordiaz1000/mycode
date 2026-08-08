import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/verse.dart';
import 'book_catalog.dart';
import 'library_store.dart';
import 'local_repository.dart';

/// Le livre demandé n'est pas sur l'appareil dans cette version.
///
/// Levé plutôt que de retomber sur la BYM : afficher un texte BYM sous
/// l'étiquette « DBY » serait un mensonge silencieux, et le lecteur n'aurait
/// aucun moyen de s'en apercevoir.
class BookNotDownloaded implements Exception {
  final String code;
  final int bymIndex;

  const BookNotDownloaded(this.code, this.bymIndex);

  String get message =>
      '${catalogEntry(bymIndex).shortName} n\'est pas téléchargé en $code.';

  @override
  String toString() => message;
}

/// Lit un livre dans la version active : la BYM embarquée via
/// [LocalRepository], une version téléchargée via [LibraryStore].
///
/// Même API que [LocalRepository] avec un code de version en tête, pour que
/// l'écran de lecture n'ait pas deux chemins à connaître.
class VersionRepository {
  VersionRepository({LocalRepository? local, LibraryStore? store})
      : _local = local ?? LocalRepository(),
        _store = store ?? LibraryStore();

  final LocalRepository _local;
  final LibraryStore _store;

  /// La seule version embarquée (décision 3).
  static const String embeddedCode = 'BYM';

  /// Livres téléchargés déjà convertis, par `code|index`. [LocalRepository]
  /// garde le même genre de cache pour la BYM : un chapitre est relu plusieurs
  /// fois (liste, saut au verset, sélecteur de versets) et reparser le fichier
  /// à chaque fois se voit à l'écran.
  static final Map<String, BibleBook> _cache = {};

  static void clearCache() => _cache.clear();

  /// Oublie une version — à appeler quand la Bibliothèque la supprime, sinon
  /// elle resterait lisible en mémoire alors que les fichiers ont disparu.
  static void forget(String code) =>
      _cache.removeWhere((key, _) => key.startsWith('$code|'));

  bool isEmbedded(String code) => code == embeddedCode;

  /// Le livre [bymIndex] (1..66) dans la version [code].
  ///
  /// Lève [BookNotDownloaded] si la version n'a pas ce livre sur l'appareil —
  /// le cas normal d'un téléchargement encore partiel.
  Future<BibleBook> loadBook(String code, int bymIndex) async {
    if (isEmbedded(code)) return _local.loadBook(bymIndex);

    final key = '$code|$bymIndex';
    final cached = _cache[key];
    if (cached != null) return cached;

    final raw = await _store.loadBook(code, bymIndex);
    if (raw == null) throw BookNotDownloaded(code, bymIndex);

    final book = bookFromGetbible(raw, bymIndex: bymIndex);
    _cache[key] = book;
    return book;
  }

  Future<Chapter> loadChapter(String code, int bymIndex, int chapter) async {
    final book = await loadBook(code, bymIndex);
    return book.chapters.firstWhere(
      (c) => c.chapter == chapter,
      orElse: () => Chapter(chapter: chapter, verses: const []),
    );
  }

  Future<int> chapterCount(String code, int bymIndex) async =>
      (await loadBook(code, bymIndex)).chapters.length;

  /// Chapitre précédent / suivant dans l'ordre de lecture BYM.
  ///
  /// Volontairement calculés sur la **BYM**, quelle que soit la version lue :
  /// le découpage en chapitres est le même d'une traduction protestante à
  /// l'autre, et les flèches continuent ainsi de fonctionner au-dessus d'un
  /// livre non encore téléchargé — c'est justement là qu'il faut pouvoir
  /// avancer.
  Future<(int book, int chapter)?> previousChapter(int bymIndex, int chapter) =>
      _local.previousChapter(bymIndex, chapter);

  Future<(int book, int chapter)?> nextChapter(int bymIndex, int chapter) =>
      _local.nextChapter(bymIndex, chapter);
}

/// Convertit un livre servi par getbible vers le modèle de l'application.
///
/// Schéma d'entrée : `{nr, name, chapters: [{chapter: int, verses: [{chapter:
/// "1", verse: "1", text}]}]}`. **Types mixtes assumés** : `chapter` est un int
/// au niveau chapitre mais une String au niveau verset, d'où [_asInt].
BibleBook bookFromGetbible(
  Map<String, dynamic> json, {
  required int bymIndex,
}) {
  final entry = catalogEntry(bymIndex);
  final chapters = <Chapter>[];

  for (final rawChapter in json['chapters'] as List<dynamic>? ?? const []) {
    if (rawChapter is! Map) continue;
    final number = _asInt(rawChapter['chapter']);
    final verses = <Verse>[];

    for (final rawVerse in rawChapter['verses'] as List<dynamic>? ?? const []) {
      if (rawVerse is! Map) continue;
      final text = (rawVerse['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;
      // `textWithNotes` = le texte nu : les notes et le lexique viennent des
      // fichiers BYM, une traduction téléchargée n'en a aucune.
      verses.add(Verse(
        verse: '$number:${_asInt(rawVerse['verse'])}',
        text: text,
        textWithNotes: text,
      ));
    }
    chapters.add(Chapter(chapter: number, verses: verses));
  }
  chapters.sort((a, b) => a.chapter.compareTo(b.chapter));

  // Le nom vient du catalogue BYM, pas du JSON : getbible répond dans la langue
  // de la traduction (« Psalms » pour la KJV) alors que toute la navigation de
  // l'application est en français et dans l'ordre BYM (décision 2). La version
  // fournit le texte, pas le vocabulaire.
  return BibleBook(
    number: bymIndex,
    book: entry.shortName,
    abbreviation: entry.abbreviation,
    metadata: const BookMetadata(
        signification: '', auteur: '', theme: '', date: ''),
    introduction: '',
    chapters: chapters,
  );
}

int _asInt(dynamic value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      String v => int.tryParse(v) ?? 0,
      _ => 0,
    };
