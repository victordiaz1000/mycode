import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/lsgs.dart';
import '../models/verse.dart';
import 'book_catalog.dart';
import 'library_store.dart';
import 'local_repository.dart';
import 'lsgs_repository.dart';
import 'version_catalog.dart';

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

/// Le livre n'existe pas dans le canon de la version — pas un téléchargement
/// manquant : il n'y a rien à télécharger.
///
/// Sous-classe de [BookNotDownloaded] exprès : chaque écran qui sait gérer
/// « pas encore téléchargé » (lecteur, comparateur, recherche) comprend aussi
/// ce cas sans code supplémentaire — seul le libellé change, et il doit
/// changer : « Terminez le téléchargement » serait faux pour un livre que la
/// version ne contient jamais. Le seul cas actuel est SEF, dont le canon
/// s'arrête à l'Ancien Testament.
class BookNotInVersion extends BookNotDownloaded {
  const BookNotInVersion(super.code, super.bymIndex);

  @override
  String get message =>
      '${catalogEntry(bymIndex).shortName} n\'existe pas en $code '
      '(Ancien Testament uniquement).';
}

/// Lit un livre dans la version active : la BYM embarquée via
/// [LocalRepository], une version téléchargée via [LibraryStore].
///
/// Même API que [LocalRepository] avec un code de version en tête, pour que
/// l'écran de lecture n'ait pas deux chemins à connaître.
class VersionRepository {
  VersionRepository({LocalRepository? local, LibraryStore? store})
      : _local = local ?? LocalRepository(),
        _store = store ?? LibraryStore(),
        _lsgs = LsgsRepository();

  final LocalRepository _local;
  final LibraryStore _store;
  final LsgsRepository _lsgs;

  /// The embedded default version (decision 3).
  static const String embeddedCode = 'BYM';
  static const String lsgsCode = 'LSGS';

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

  bool isEmbedded(String code) => code == embeddedCode || code == lsgsCode;

  /// Le livre [bymIndex] (1..66) dans la version [code].
  ///
  /// Lève [BookNotDownloaded] si la version n'a pas ce livre sur l'appareil —
  /// le cas normal d'un téléchargement encore partiel.
  Future<BibleBook> loadBook(String code, int bymIndex) async {
    if (code == embeddedCode) return _local.loadBook(bymIndex);
    if (code == lsgsCode) {
      final lsgsBook = await _lsgs.loadBook(bymIndex);
      final book = LsgsRepository.toBibleBook(lsgsBook);
      _cache['$code|$bymIndex'] = book;
      return book;
    }

    final key = '$code|$bymIndex';
    final cached = _cache[key];
    if (cached != null) return cached;

    // Hors canon de la version : lever « pas téléchargé » laisserait croire à
    // un téléchargement possible (Bibliothèque, reprise) alors que le livre
    // n'existe pas dans cette version — SEF s'arrête à Malachie.
    final entry = versionByCode(code);
    if (entry != null && !entry.containsBook(bymIndex)) {
      throw BookNotInVersion(code, bymIndex);
    }

    final raw = await _store.loadBook(code, bymIndex);
    if (raw == null) throw BookNotDownloaded(code, bymIndex);

    // Deux axes distincts : *où* vit le fichier (assets / disque) et *quel*
    // schéma il porte. La BYM embarquée les confondait, étant seule à porter le
    // format riche ; une version au format BYM servie d'ailleurs les sépare.
    // Défaut prudent : format inconnu → getbible, le schéma le plus pauvre.
    final book = switch (entry?.format ?? VersionFormat.getbible) {
      VersionFormat.bym => BibleBook.fromJson(raw, number: bymIndex),
      VersionFormat.sef => bookFromSef(raw, bymIndex: bymIndex),
      _ => bookFromGetbible(raw, bymIndex: bymIndex),
    };
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

  /// Les tokens Strong du verset LSGS, pour le rendu cliquable dans la lecture.
  ///
  /// La BYM et les versions téléchargées n'en ont pas : `toBibleBook` aplatit
  /// les tokens en texte nu, et seule la LSGS embarquée porte les numéros.
  Future<List<LsgsToken>> lsgsTokens(
      int bymIndex, int chapter, int verseNumber) async {
    final book = await _lsgs.loadBook(bymIndex);
    for (final ch in book.chapters) {
      if (ch.chapter != chapter) continue;
      for (final verse in ch.verses) {
        if (verse.verse == verseNumber) return verse.tokens;
      }
    }
    return const [];
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
}) =>
    _bookFromChapters(
      json,
      bymIndex: bymIndex,
      buildVerse: (chapter, raw) {
        final text = (raw['text'] as String? ?? '').trim();
        if (text.isEmpty) return null;
        // `textWithNotes` = le texte nu : les notes et le lexique viennent des
        // fichiers BYM, une traduction téléchargée n'en a aucune.
        return Verse(
          verse: '$chapter:${_asInt(raw['verse'])}',
          text: text,
          textWithNotes: text,
        );
      },
    );

/// Convertit un livre SEF (Septuaginta) vers le modèle de l'application.
///
/// Schéma d'entrée : celui de getbible enrichi — `verses[].text` porte le
/// français affiché (Giguet), `grec` la ligne grecque affichée au-dessus,
/// `alexandrie` la seconde traduction française affichée dessous (le
/// convertisseur ne l'écrit que lorsqu'elle diffère du `text` — jamais de
/// doublon), `notes` les pieds de page de la source — restés en données
/// dans les fichiers, jamais montrés à l'écran — et `section` le titre de
/// section de la source.
///
/// Un verset sans français comme sans grec est ignoré ; un verset sans
/// français garde sa ligne grecque, seule à l'écran (trous du corpus bleu :
/// Jérémie, Esdras, 1 Rois…).
BibleBook bookFromSef(
  Map<String, dynamic> json, {
  required int bymIndex,
}) =>
    _bookFromChapters(
      json,
      bymIndex: bymIndex,
      buildVerse: (chapter, raw) {
        final text = (raw['text'] as String? ?? '').trim();
        final grec = (raw['grec'] as String? ?? '').trim();
        if (text.isEmpty && grec.isEmpty) return null;
        final alexandrie = (raw['alexandrie'] as String? ?? '').trim();
        final section = (raw['section'] as String? ?? '').trim();
        return Verse(
          verse: '$chapter:${_asInt(raw['verse'])}',
          text: text,
          textWithNotes: text,
          grec: grec.isEmpty ? null : grec,
          alexandrie: alexandrie.isEmpty ? null : alexandrie,
          section: section.isEmpty ? null : section,
        );
      },
    );

/// Le corps commun des parseurs de versions téléchargées : chapitres triés,
/// versets construits par [buildVerse] (`null` = verset ignoré), nom de livre
/// pris au catalogue BYM — la version fournit le texte, pas le vocabulaire.
BibleBook _bookFromChapters(
  Map<String, dynamic> json, {
  required int bymIndex,
  required Verse? Function(int chapter, Map raw) buildVerse,
}) {
  final entry = catalogEntry(bymIndex);
  final chapters = <Chapter>[];

  for (final rawChapter in json['chapters'] as List<dynamic>? ?? const []) {
    if (rawChapter is! Map) continue;
    final number = _asInt(rawChapter['chapter']);
    final verses = <Verse>[];

    for (final rawVerse in rawChapter['verses'] as List<dynamic>? ?? const []) {
      if (rawVerse is! Map) continue;
      final verse = buildVerse(number, rawVerse);
      if (verse != null) verses.add(verse);
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
