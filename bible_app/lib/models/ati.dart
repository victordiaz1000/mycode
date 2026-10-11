/// Le modèle des interlinéaires de Biblia Universalis, mot à mot.
///
/// Deux corpus le produisent, avec la même forme et les mêmes clés : l'ATI
/// (Ancien Testament, hébreu — `ATI/ati_to_json.py`) et le NTI (Nouveau
/// Testament, grec — `NTI/nti_to_json.py`). Ils n'ont ni le même canon ni la
/// même mise en page, mais le même besoin : un corpus tokenisé mot par mot ne
/// tient pas dans un [Verse], dont `text` est une chaîne. Le modèle garde la
/// donnée complète ; `bookFromAti` l'aplatit pour la recherche, le partage et
/// Comparer.
///
/// Les champs hébreux et les champs grecs ne se recouvrent pas : l'un a
/// `translit` / `hebrew` / `split`, l'autre `modern` / `lemma` / `koine`.
/// [AtiWord.greek] les distingue, et c'est sur lui que le rendu décide — un
/// mot hébreu et un mot grec ne s'affichent pas dans le même sens.
///
/// Les clés du JSON sont courtes exprès : 309 972 mots pour l'ATI, 138 099 pour
/// le NTI, et sur le premier des deux chaque octet par mot pèse 0,3 Mo.
library;

/// Un mot d'interlinéaire et ce que la source en dit.
///
/// Les deux schémas de Biblia cohabitent ici, parce qu'ils n'en font qu'un du
/// point de vue de l'app : un mot, son Strong, sa glose, son étiquette. Ce
/// qu'ils n'ont **pas** en commun tient dans trois champs, et dans trois
/// seulement — le reste ne change pas de nom.
///
/// | | ATI (hébreu) | NTI (grec) |
/// |---|---|---|
/// | le mot | `hebrew`, vocalisé | `modern`, tel qu'imprimé |
/// | sa forme | `split` (découpage) | `lemma` (lemme), `koine` (sans accents) |
/// | sa translittération | `translit` | — |
///
/// [greek] dit lequel des deux schémas porte le mot, et le rendu s'y tient :
/// le grec se lit de gauche à droite, l'hébreu de droite à gauche.
///
/// Tous les champs sont facultatifs : la source ne les porte pas tous pour tous
/// les mots (un mot d'un seul morphème n'a pas de découpage, une particule n'a
/// pas toujours de glose, 34 mots du NTI sont « non réf. » et sans Strong).
/// Un champ absent se lit `null` ou vide, jamais un substitut inventé.
class AtiWord {
  /// Numéro Strong préfixé, `H7225` pour l'ATI, `G976` pour le NTI. La glose
  /// n'est pas embarquée : elle vient de `StrongLexicon.instance.lookup()`,
  /// qui la sert déjà pour la LSGS.
  final String? strong;

  // — Le mot hébreu, ses trois traits — l'ATI seulement.

  /// Translittération, `bə·rê·šîṯ`.
  final String? translit;

  /// Hébreu vocalisé, points-voyelles compris — à rendre en
  /// [TextDirection.rtl] et dans la police Cardo, seule embarquée à le couvrir.
  final String? hebrew;

  /// Découpage morphologique, `בְּ • רֵאשִׁ֖ית`.
  final String? split;

  // — Le mot grec, ses trois traits — le NTI seulement.

  /// La rangée « Moderne » : le mot **tel qu'imprimé dans le texte**, avec
  /// l'accentuation de contexte qu'il y prend, `κλητὸς` pour une forme qui au
  /// dictionnaire s'écrit `κλητός`. C'est elle qui fait la grande ligne de la
  /// cellule, comme l'hébreu en fait la sienne.
  ///
  /// Le `˚` que la source prépose à certains mots (`˚Χριστοῦ`, 6 % du corpus)
  /// est conservé : c'est le marqueur Biblia des formes construites, et la
  /// maquette l'imprime lui-même.
  final String? modern;

  /// La rangée « Lemme » : la forme-lemme, celle du dictionnaire, `βίβλος`.
  final String? lemma;

  /// La rangée « Koinè » : le mot sans accents ni esprits, `βιβλοσ` — et,
  /// pour les mots composés, la crase qu'il subit sous sa forme abrégée
  /// (`=χυ` pour Χριστοῦ). C'est la graphie de base, celle dont part le lexique.
  final String? koine;

  // — Ce que les deux schémas partagent.

  /// Glose française, `En un commencement` pour l'ATI, `Livre` pour le NTI.
  /// Parfois `*` ou `-` : la source marque ainsi les particules sans équivalent
  /// français (l'accusatif `אֵת`), et au grec les mots dont elle n'a que la
  /// variante à proposer (« - / or »).
  final String? gloss;

  /// Variante de la glose, proposée par le NTI à la suite de la principale et
  /// séparée d'elle par un « / » : « de genèse **/ de généalogie** »,
  /// 39 375 fois dans le corpus. La source l'italise parfois (une fois sur
  /// 39 375, en Matthieu 1), nous la mettons toujours en italique : c'est la
  /// seule façon de distinguer les deux à l'œil.
  final String? variant;

  /// Étiquette grammaticale courte, `Nom` pour l'ATI, `N-NFS` pour le NTI
  /// (Nature-Déclinaison-Genre-Nombre) — déjà résolue contre la table `cg` du
  /// livre, de sorte que personne ici ne manipule un index.
  final String? grammar;

  /// Analyse développée, `Nom commun· féminin singulier· état absolu` pour
  /// l'ATI, `Nature : Nom · Déclinaison : Nominatif · …` pour le NTI —
  /// résolue contre la table `ca`.
  final String? analysis;

  /// Renvoi à une page de glossaire, sous l'identifiant court que Biblia
  /// affiche lui-même : `n12` (Note 12), `d12` (Difficulté 12), `r2`
  /// (Remarque 2), `abr` (Abréviations). Résolu contre `notes.json`.
  ///
  /// L'ATI seul en porte : aucun mot du NTI ne renvoie à son glossaire —
  /// les 138 066 liens `g*NTI*Analyses` pointent tous vers la page qui
  /// développe l'étiquette, et cette analyse est déjà dans [analysis].
  final String? note;

  /// Le mot vient-il du corpus grec du NTI ?
  ///
  /// Le discriminateur de tout le rendu, et il est posé sur les trois champs
  /// grecs plutôt que sur un seul : un mot sans Strong ni glose garde ses
  /// trois lignes grecques, et c'est bien le grec qu'il faut y afficher.
  bool get greek => modern != null || lemma != null || koine != null;

  /// La glose lisible, marqueurs de la source retirés — `null` quand il ne
  /// reste rien.
  ///
  /// Trois nettoyages, et seulement ceux-là :
  ///
  /// - **Les marqueurs typographiques sautent.** L'ATI écrit `*` en face des
  ///   particules sans équivalent français (le marqueur d'accusatif `אֵת`,
  ///   7 073 fois) et `-` en face des morphèmes rattachés au mot suivant
  ///   (3 173 fois). Le NTI écrit `-` en face des mots dont il n'a que la
  ///   variante à donner (« - / or », 183 fois). Gardés, ils donneraient
  ///   « En un commencement créa Dieu * les cieux et - la terre. »
  /// - **Le marqueur isolé saute aussi au milieu d'une glose** (« et - » → « et »,
  ///   14 cas dans le corpus). Le découpage par blancs protège les traits d'union
  ///   internes : « Ramoth-de - » donne « Ramoth-de », pas « Ramothde ».
  /// - **Une glose réduite à des marqueurs devient `null`** : le mot reste à
  ///   l'écran avec son texte et son étiquette, sans ligne de glose vide.
  ///
  /// Seul nettoyage de la glose dans l'app : c'est ce que joint
  /// `joinAtiGlosses` et que pose l'interlinéaire sous chaque mot, de sorte
  /// que les deux ne peuvent pas diverger.
  String? get readableGloss => _lisible(gloss);

  /// La variante de glose, nettoyée par les mêmes règles que la glose —
  /// voir [readableGloss]. Elle complète la glose, elle ne la double pas :
  /// un mot « - / or » n'a de glose que par elle.
  String? get readableVariant => _lisible(variant);

  /// Le découpage par blancs qui rend un marqueur invisible sans toucher à ce
  /// qui lui ressemble : « - » saute, « -d' » ne saute pas.
  static String? _lisible(String? brut) {
    if (brut == null) return null;
    final kept = brut
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
    this.modern,
    this.lemma,
    this.koine,
    this.gloss,
    this.variant,
    this.grammar,
    this.analysis,
    this.note,
  });

  /// [grammarTable] et [analysisTable] sont les tables `cg` / `ca` du livre :
  /// le JSON y stocke des index, parce que le même libellé d'analyse revient
  /// des milliers de fois. Un index hors table donne `null` plutôt qu'une
  /// exception — un fichier abîmé doit se lire en partie, pas faire tomber le
  /// livre entier.
  ///
  /// Les clés du grec (`m`, `l`, `k`, `f2`) cohabitent avec celles de l'hébreu
  /// (`t`, `h`, `d`, `n`) : un fichier n'en porte que l'une des deux sortes,
  /// et un mot hébreu ressort de là avec des `null` aux trois lignes grecques.
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
        modern: _text(json['m']),
        lemma: _text(json['l']),
        koine: _text(json['k']),
        gloss: _text(json['f']),
        variant: _text(json['f2']),
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
  /// Index BYM (1..66) — l'ordre du canon, celui de la navigation de l'app.
  /// L'ATI couvre 1..39, le NTI 40..66. Le fichier, lui, est nommé par le
  /// numéro **standard** : c'est le jeton `{book}` de `urlTemplate`, et les
  /// deux ordres ne coïncident pas pour les Épîtres (Jacques est 45 en BYM,
  /// 59 en standard).
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
