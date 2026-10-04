/// Le modèle de l'Ancien Testament Interlinéaire, mot à mot.
///
/// Même forme que `models/lsgs.dart`, pour la même raison : un corpus tokenisé
/// mot par mot ne tient pas dans un [Verse], dont `text` est une chaîne. Le
/// modèle garde la donnée complète ; `bookFromAti` l'aplatit pour la recherche,
/// le partage et Comparer.
///
/// Produit par `ATI/ati_to_json.py` depuis l'ATI.xml de Biblia Universalis 3.
/// Les clés du JSON sont courtes exprès : le corpus compte 309 972 mots, et
/// chaque octet par mot y pèse 0,3 Mo.
library;

/// Un mot hébreu et ce que la source en dit.
///
/// Tous les champs sont facultatifs : la source ne les porte pas tous pour tous
/// les mots (un mot d'un seul morphème n'a pas de découpage, une particule n'a
/// pas toujours de glose). Un champ absent se lit `null` ou vide, jamais un
/// substitut inventé.
class AtiWord {
  /// Numéro Strong préfixé, `H7225`. La glose n'est pas embarquée : elle vient
  /// de `StrongLexicon.instance.lookup()`, qui la sert déjà pour la LSGS.
  final String? strong;

  /// Translittération, `bə·rê·šîṯ`.
  final String? translit;

  /// Hébreu vocalisé, points-voyelles compris — à rendre en
  /// [TextDirection.rtl] et dans la police Cardo, seule embarquée à le couvrir.
  final String? hebrew;

  /// Découpage morphologique, `בְּ • רֵאשִׁ֖ית`.
  final String? split;

  /// Glose française, `En un commencement`. Parfois `*` ou `-` : la source
  /// marque ainsi les particules sans équivalent français (l'accusatif `אֵת`).
  final String? gloss;

  /// Étiquette grammaticale courte, `Nom` — déjà résolue contre la table `cg`
  /// du livre, de sorte que personne ici ne manipule un index.
  final String? grammar;

  /// Analyse développée, `Nom commun· féminin singulier· état absolu` —
  /// résolue contre la table `ca`.
  final String? analysis;

  /// Renvoi à une page de glossaire, sous l'identifiant court que Biblia
  /// affiche lui-même : `n12` (Note 12), `d12` (Difficulté 12), `r2`
  /// (Remarque 2), `abr` (Abréviations). Résolu contre `notes.json`.
  final String? note;

  /// La glose lisible, marqueurs de la source retirés — `null` quand il ne
  /// reste rien.
  ///
  /// Trois nettoyages, et seulement ceux-là :
  ///
  /// - **Les marqueurs typographiques sautent.** L'ATI écrit `*` en face des
  ///   particules sans équivalent français (le marqueur d'accusatif `אֵת`,
  ///   7 073 fois) et `-` en face des morphèmes rattachés au mot suivant
  ///   (3 173 fois). Gardés, ils donneraient « En un commencement créa Dieu *
  ///   les cieux et - la terre. »
  /// - **Le marqueur isolé saute aussi au milieu d'une glose** (« et - » → « et »,
  ///   14 cas dans le corpus). Le découpage par blancs protège les traits d'union
  ///   internes : « Ramoth-de - » donne « Ramoth-de », pas « Ramothde ».
  /// - **Une glose réduite à des marqueurs devient `null`** : le mot reste à
  ///   l'écran avec son hébreu et son étiquette, sans ligne de glose vide.
  ///
  /// Seul nettoyage de la glose dans l'app : c'est ce que joint
  /// `joinAtiGlosses` et que pose l'interlinéaire sous chaque mot, de sorte
  /// que les deux ne peuvent pas diverger.
  String? get readableGloss {
    final gloss = this.gloss;
    if (gloss == null) return null;
    final kept = gloss
        .split(RegExp(r'\s+'))
        .where((part) => part != '*' && part != '-' && part.isNotEmpty)
        .join(' ');
    return kept.isEmpty ? null : kept;
  }

  const AtiWord({
    this.strong,
    this.translit,
    this.hebrew,
    this.split,
    this.gloss,
    this.grammar,
    this.analysis,
    this.note,
  });

  /// [grammarTable] et [analysisTable] sont les tables `cg` / `ca` du livre :
  /// le JSON y stocke des index, parce que le même libellé d'analyse revient
  /// des milliers de fois. Un index hors table donne `null` plutôt qu'une
  /// exception — un fichier abîmé doit se lire en partie, pas faire tomber le
  /// livre entier.
  factory AtiWord.fromJson(
    Map<String, dynamic> json, {
    List<String> grammarTable = const [],
    List<String> analysisTable = const [],
  }) =>
      AtiWord(
        strong: _text(json['s']),
        translit: _text(json['t']),
        hebrew: _text(json['h']),
        split: _text(json['d']),
        gloss: _text(json['f']),
        grammar: _fromTable(json['g'], grammarTable),
        analysis: _fromTable(json['a'], analysisTable),
        note: _text(json['n']),
      );

  static String? _text(dynamic value) {
    final text = value is String ? value.trim() : null;
    return (text == null || text.isEmpty) ? null : text;
  }

  static String? _fromTable(dynamic value, List<String> table) {
    final index = (value as num?)?.toInt();
    if (index == null || index < 0 || index >= table.length) return null;
    final text = table[index].trim();
    return text.isEmpty ? null : text;
  }
}

class AtiVerse {
  final int verse;
  final List<AtiWord> words;

  const AtiVerse({required this.verse, this.words = const []});

  factory AtiVerse.fromJson(
    Map<String, dynamic> json, {
    List<String> grammarTable = const [],
    List<String> analysisTable = const [],
  }) =>
      AtiVerse(
        verse: (json['verse'] as num?)?.toInt() ?? 0,
        words: (json['words'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((w) => AtiWord.fromJson(
                  w,
                  grammarTable: grammarTable,
                  analysisTable: analysisTable,
                ))
            .toList(),
      );
}

class AtiChapter {
  final int chapter;
  final List<AtiVerse> verses;

  const AtiChapter({required this.chapter, this.verses = const []});

  factory AtiChapter.fromJson(
    Map<String, dynamic> json, {
    List<String> grammarTable = const [],
    List<String> analysisTable = const [],
  }) =>
      AtiChapter(
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
        verses: (json['verses'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((v) => AtiVerse.fromJson(
                  v,
                  grammarTable: grammarTable,
                  analysisTable: analysisTable,
                ))
            .toList(),
      );
}

class AtiBook {
  /// Index BYM (1..39) — l'ordre du canon hébreu, celui de la navigation de
  /// l'app. Le fichier, lui, est nommé par le numéro standard : c'est le jeton
  /// `{book}` de `urlTemplate`.
  final int bymIndex;
  final String book;
  final String osisId;
  final List<AtiChapter> chapters;

  const AtiBook({
    required this.bymIndex,
    required this.book,
    required this.osisId,
    this.chapters = const [],
  });

  /// Les tables `cg` / `ca` sont lues ici et passées aux mots : elles vivent au
  /// niveau du livre, et les résoudre une fois à la lecture évite que le reste
  /// de l'app ait à les connaître.
  factory AtiBook.fromJson(Map<String, dynamic> json) {
    final grammarTable = _table(json['cg']);
    final analysisTable = _table(json['ca']);
    return AtiBook(
      bymIndex: (json['bym_index'] as num?)?.toInt() ?? 0,
      book: json['book'] as String? ?? '',
      osisId: json['osis_id'] as String? ?? '',
      chapters: (json['chapters'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((c) => AtiChapter.fromJson(
                c,
                grammarTable: grammarTable,
                analysisTable: analysisTable,
              ))
          .toList(),
    );
  }

  static List<String> _table(dynamic value) =>
      (value as List<dynamic>? ?? const [])
          .map((e) => e is String ? e : '')
          .toList();
}
