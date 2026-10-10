import '../models/ati.dart';
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
        _lsgs = LsgsRepository(),
        _lss = LsgsRepository.strong();

  final LocalRepository _local;
  final LibraryStore _store;
  final LsgsRepository _lsgs;
  final LsgsRepository _lss;

  /// The embedded default version (decision 3).
  static const String embeddedCode = 'BYM';
  static const String lsgsCode = 'LSGS';

  /// Le corpus Strong de Biblia (« Segond Louis + Strong »), embarqué dans
  /// `assets/bible/lss/` : même schéma que la LSGS, ancres plus denses — il
  /// numérote les particules que la LSGS ignore (waw, article, préfixes), ce
  /// qui lui vaut 116 567 codes sans mot français. C'est lui que lit le
  /// lexique de l'étude de verset, et c'est aussi une version de lecture :
  /// [loadBook] sert les deux corpus par le même chemin, et le catalogue le
  /// propose à côté de la LSGS.
  static const String lssCode = 'LSS';

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

  /// Les trois textes qui vivent dans l'APK : la BYM, la LSGS et la LSS.
  ///
  /// Une version embarquée est toujours lisible, quel que soit l'état du
  /// registre : le lecteur n'a rien à télécharger pour elle.
  bool isEmbedded(String code) =>
      code == embeddedCode || code == lsgsCode || code == lssCode;

  /// Le livre [bymIndex] (1..66) dans la version [code].
  ///
  /// Lève [BookNotDownloaded] si la version n'a pas ce livre sur l'appareil —
  /// le cas normal d'un téléchargement encore partiel.
  Future<BibleBook> loadBook(String code, int bymIndex) async {
    if (code == embeddedCode) return _local.loadBook(bymIndex);
    // Les deux corpus Strong partagent schéma et parseur : seul le dossier
    // change, d'où une seule branche pour deux codes. `toBibleBook` y joint les
    // tokens avec leurs numéros (« Dieu H0430 ») — c'est ce qui rend les codes
    // cliquables dans la lecture, pour la LSGS comme pour la LSS.
    if (code == lsgsCode || code == lssCode) {
      final book = LsgsRepository.toBibleBook(
          await (code == lssCode ? _lss : _lsgs).loadBook(bymIndex));
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
      VersionFormat.ati => bookFromAti(raw, bymIndex: bymIndex),
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

  /// Les tokens Strong du verset LSGS — le corpus que [tokensFor] sert par
  /// défaut.
  ///
  /// La BYM et les versions téléchargées n'en ont pas : leurs fichiers ne
  /// portent aucun numéro. La LSS a les siens, mais dans son propre dossier et
  /// sous ses propres jetons : c'est [tokensFor] qui choisit le corpus.
  Future<List<LsgsToken>> lsgsTokens(
          int bymIndex, int chapter, int verseNumber) =>
      _verseTokens(_lsgs, bymIndex, chapter, verseNumber);

  /// Les tokens du verset dans [repo], `const []` quand ce verset n'y est pas.
  Future<List<LsgsToken>> _verseTokens(LsgsRepository repo, int bymIndex,
      int chapter, int verseNumber) async {
    final book = await repo.loadBook(bymIndex);
    for (final ch in book.chapters) {
      if (ch.chapter != chapter) continue;
      for (final verse in ch.verses) {
        if (verse.verse == verseNumber) return verse.tokens;
      }
    }
    return const [];
  }

  /// Les tokens du verset dans la corpus [code] (`lssCode` ou `lsgsCode`) —
  /// ceux que rend le lexique de l'étude de verset.
  ///
  /// Le repli sur la LSGS est la règle plutôt que l'exception : LSS manque
  /// trois versets à la source (Ex 28.42, Nb 25.19, Ac 19.41), et un actif
  /// absent ou illisible ne doit pas vider d'un coup la fiche — le lexique
  /// retombe sur le texte que l'on lit.
  Future<List<LsgsToken>> tokensFor(
      String code, int bymIndex, int chapter, int verseNumber) async {
    if (code != lssCode) return lsgsTokens(bymIndex, chapter, verseNumber);
    try {
      final tokens = await _verseTokens(_lss, bymIndex, chapter, verseNumber);
      if (tokens.isNotEmpty) return tokens;
    } catch (_) {
      // Actif non embarqué ou illisible : le repli ci-dessous suffit.
    }
    return lsgsTokens(bymIndex, chapter, verseNumber);
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

/// Convertit un livre ATI (Ancien Testament Interlinéaire) vers le modèle de
/// l'application, en portant chaque verset sur ses gloses françaises **et** sur
/// ses mots.
///
/// Passe par [AtiBook] plutôt que de lire le JSON directement, exactement comme
/// [LsgsRepository.toBibleBook] passe par `LsgsBook` : le modèle porte les sept
/// champs de chaque mot, dont le rendu interlinéaire a besoin. Faire servir ce
/// qu'on a chargé une fois l'éprouve au lieu de le laisser attendre, non
/// exercé, d'être utilisé un jour.
///
/// [Verse.text] reste une chaîne — sept champs par mot n'y tiennent pas — et
/// c'est elle que lisent la recherche, le partage et Comparer : une ligne de
/// gloses jointes. [Verse.mots] garde la donnée complète à côté pour
/// `verse_tile`, qui pose les colonnes interlinéaires quand elle est là.
BibleBook bookFromAti(
  Map<String, dynamic> json, {
  required int bymIndex,
}) =>
    _bookFromAtiBook(AtiBook.fromJson(json), bymIndex: bymIndex);

BibleBook _bookFromAtiBook(AtiBook book, {required int bymIndex}) {
  final entry = catalogEntry(bymIndex);
  final chapters = book.chapters
      .map((chapter) => Chapter(
            chapter: chapter.chapter,
            verses: chapter.verses.map((verse) {
              final text = joinAtiGlosses(verse.words);
              return Verse(
                verse: '${chapter.chapter}:${verse.verse}',
                text: text,
                textWithNotes: text,
                // Les colonnes interlinéaires lisent les mots ici, jamais la
                // chaîne : sept champs ne tiennent pas dans un texte.
                mots: verse.words,
              );
            }).toList(),
          ))
      .toList()
    ..sort((a, b) => a.chapter.compareTo(b.chapter));

  // Le nom vient du catalogue BYM, comme pour les autres formats téléchargés :
  // la version fournit le texte, pas le vocabulaire.
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

/// Joint les gloses françaises d'un verset en une ligne lisible.
///
/// Le nettoyage lui-même vit sur [AtiWord.readableGloss] : les marqueurs `*` et
/// `-` de la source y sautent, l'interlinéaire posant sous chaque mot exactement
/// ce que cette ligne joint. Un mot dont la glose n'est qu'un marqueur disparaît
/// de la ligne — il reste entier dans le fichier, avec son hébreu.
///
/// Restent les quatre mots dont la source ne porte aucune glose — cellule rouge
/// vide ou absente (Genèse 9:11, Lévitique 14:27, Nombres 1:18 et 1:52) : ils
/// sont absents de la ligne par construction, comme les marqueurs, et restent
/// entiers dans le fichier. Aucun verset n'en est entièrement privé — le
/// convertisseur en ferait une anomalie.
String joinAtiGlosses(List<AtiWord> words) {
  final pieces = <String>[];
  for (final word in words) {
    final kept = word.readableGloss;
    if (kept == null) continue;
    pieces.add(kept);
  }
  return pieces.join(' ');
}

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
