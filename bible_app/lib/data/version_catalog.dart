import 'book_catalog.dart';

/// The JSON layout the files of a version carry.
///
/// Independent of *where* the files live: the app conflated the two axes as
/// long as « embarquée » and « format BYM » named the same single version. A
/// BYM-format text served from elsewhere and downloaded onto the device is the
/// case that separates them.
///
/// What follows from it, beyond the parser: only [bym] carries the book header
/// (metadata + introduction), the section titles and the notes. Everything that
/// asks « is this the embedded version? » to answer « does it have notes? »
/// should ask [VersionEntry.carriesNotes] instead.
enum VersionFormat {
  /// The rich schema of `bym_json/` — `metadata`, `introduction`, per-verse
  /// `section`, `textWithNotes` and `notes`. Read by `BibleBook.fromJson`.
  bym,

  /// getbible.net's bare schema — `chapters[].verses[].text`, nothing else.
  /// Read by `bookFromGetbible`.
  getbible,

  /// The SEF schema: getbible's fields plus a Greek line (`grec`), a second
  /// French translation (`alexandrie`) and the source's section titles
  /// (`section`); the source's footnotes (`notes`) stay in the files, unread.
  /// Read by `bookFromSef`.
  sef,

  /// The ATI schema — tokenised word by word rather than verse by verse, the
  /// only format here that is not a line of text: each word carries its Strong
  /// number, transliteration, pointed Hebrew, morphological split, French
  /// gloss, grammatical analysis and glossary reference. Produced by
  /// `ATI/ati_to_json.py`, read by `bookFromAti`.
  ///
  /// Like LSGS it must be flattened to reach [BibleBook], whose `Verse.text` is
  /// a single String: `bookFromAti` joins the French glosses so that search,
  /// sharing and Comparer keep working on plain text. The full word data stays
  /// in the file for the interlinear rendering.
  ati,
}

/// How a version can actually be consulted from the reading « Version » sheet.
enum VersionAvailability {
  /// Shipped inside the app, readable offline — the BYM default (décision 3).
  embedded,

  /// Not bundled but servable from a free source (getbible.net, décision 9);
  /// offered as a download in the Bibliothèque.
  downloadable,

  /// Listed for completeness to match the maquette
  /// (`modif/resultat_vers_les_versions.jpg`) but under copyright / without a
  /// free source yet. Not offered anywhere it could not be honoured: the
  /// reading sheet and the search menu leave it out, the Bibliothèque names it.
  unavailable,
}

/// A Bible version offered by the reading « Version » sheet
/// (maquette `modif/resultat_vers_les_versions.jpg`).
class VersionEntry {
  /// Short code shown in the reading bar and above the name (BYM, LSG…).
  final String code;

  final String name;

  /// Date + licence line under the name.
  final String rights;

  /// Who translated the text, when that name deserves its own line under
  /// [rights] (SEF: the two French translations — the source names them, the
  /// copyright line doesn't). Null on every other version: shown only then.
  final String? attribution;

  /// Whether we can serve it, and how.
  final VersionAvailability availability;

  /// Which parser reads its files. Defaults to [VersionFormat.getbible]: every
  /// version we can serve today comes from there, and an unknown entry must
  /// fall on the poorer schema rather than look for fields that are not there.
  final VersionFormat format;

  /// getbible.net translation id for [VersionAvailability.downloadable] entries;
  /// null otherwise.
  final String? getbibleId;

  /// URL template for [VersionAvailability.downloadable] entries served from a
  /// direct host — GitHub raw (décision 7) or any public JSON host — instead of
  /// getbible.net. The `{book}` token is replaced by the **standard** 1..66
  /// book number (same numbering as getbible, cf. `bymToStandard`), one file
  /// per book. Null for getbible-served entries.
  final String? urlTemplate;

  /// Whether the embedded text carries Strong codes per word — the LSGS schema
  /// does, so the reading body can render each code clickable. BYM carries
  /// notes but no Strong; a getbible version carries neither.
  final bool hasStrong;

  /// Langue d'affichage du texte ('FR', 'EN'…) — une étiquette de carte
  /// (Comparer), pas une donnée de parsing. Défaut FR : toutes les versions
  /// servables aujourd'hui sont françaises sauf la KJV.
  final String languageCode;

  /// Whether the version only carries the Old Testament (BYM indexes 1..39).
  ///
  /// SEF is the Septuagint: its canon ends at Malachie, Matthieu does not
  /// exist in it. Everything that counts books — the Bibliothèque progress,
  /// the download loop, « is this install complete? » — asks this instead of
  /// assuming the 66, and reading a New Testament book in it says the book is
  /// absent from the version rather than offering a download that could never
  /// land.
  final bool otOnly;

  const VersionEntry({
    required this.code,
    required this.name,
    required this.rights,
    this.attribution,
    this.availability = VersionAvailability.unavailable,
    this.format = VersionFormat.getbible,
    this.getbibleId,
    this.urlTemplate,
    this.hasStrong = false,
    this.languageCode = 'FR',
    this.otOnly = false,
  });

  /// True for the version shipped inside the app (readable offline, no download).
  bool get embedded => availability == VersionAvailability.embedded;

  /// True when the version can be fetched from a free source right now.
  bool get downloadable => availability == VersionAvailability.downloadable;

  /// True when « Télécharger » can actually fetch something: downloadable and
  /// at least one source is configured — a getbible id or a direct URL
  /// template. The catalogue lists some downloadable entries whose source is
  /// not published yet; they must not offer a download that would fail.
  bool get fetchable =>
      downloadable && (getbibleId != null || urlTemplate != null);

  /// Whether its files carry notes, sections and book metadata.
  ///
  /// The reader keys the book header, the « Texte + notes » toggle and the note
  /// dispositions on this. Asking the format rather than the code is what lets
  /// a BYM-format version downloaded from elsewhere keep its notes.
  bool get carriesNotes => format == VersionFormat.bym;

  /// True when the version reads as a grid of words instead of prose — the ATI
  /// interlinear, where a verse is a stack of columns.
  ///
  /// C'est la clé de « Texte continu » : une colonne de sept champs ne coule
  /// pas, et `Verse.text` d'une telle version n'est que la glose française
  /// posée de bout en bout — la ligne que chercher et partager utilisent,
  /// jamais un texte fait pour se lire d'un trait. L'option se désactive donc
  /// sur cette version plutôt que de faire semblant.
  bool get interlinear => format == VersionFormat.ati;

  /// BYM indexes (1..66) the version can hold: all of them, or 1..39 for an
  /// Old Testament-only version (the BYM order puts Malachie at 39 and
  /// Matthieu at 40).
  bool containsBook(int bymIndex) =>
      bymIndex >= 1 &&
      (otOnly ? bymIndex <= 39 : bymIndex <= bookCatalog.length);

  /// How many books a complete install holds — the denominator of the
  /// Bibliothèque progress bar and of the download outcome.
  int get bookCount => otOnly ? 39 : bookCatalog.length;
}

class VersionGroup {
  final String title;
  final List<VersionEntry> versions;

  const VersionGroup(this.title, this.versions);
}

/// Versions grouped as in the maquette (`modif/resultat_vers_les_versions.jpg`).
///
/// The full reference list is reproduced for the design, but only three states
/// are real:
/// - **embedded** : BYM, the default reading version (décision 3), and **LSGS**,
///   the embedded Segond 1910 text with Strong codes (décision 10) ;
/// - **downloadable** : the translations we can actually serve — LSG (ls1910),
///   Darby, Martin, KJV via getbible.net (décision 9), and Ostervald,
///   néo-Crampon Libre, Chouraqui + King James Française via a direct GitHub
///   host ([VersionEntry.urlTemplate], produced by
///   `appCodebar/ostervald_to_json.py` and `appCodebar/html_verses_to_json.py`),
///   plus the Septuaginta (SEF: grec + deux traductions françaises, Ancien
///   Testament seul, produced by `sef/sef_to_json.py`) and the Ancien Testament
///   Interlinéaire (ATI: sept champs par mot hébreu, Ancien Testament seul,
///   produced by `ATI/ati_to_json.py`) ;
/// - **unavailable** : copyright / sourceless versions shown greyed for parity
///   with the maquette (NBS, NEG79, NVS78P, S21).

///
/// **A version under rights carries its copyright on the card.** CHO and KJF
/// are served because their corpus is published, not because they are free :
/// the `rights` line is the condition, and it is never shortened to look
/// tidier.
///
/// « Segond 1910 with Strong » (LSGS) is embedded because a Strong-tagged
/// French text could not be served from getbible.net (its ls1910 JSON does not
/// carry the Strong numbers, cf. décision 9) — the embedded corpus was built
/// from a dedicated source (cf. `plan-strong-fr.md`).
const List<VersionGroup> versionCatalog = [
  VersionGroup('Version intégrée', [
    VersionEntry(
      code: 'BYM',
      name: 'Bible de Yehoshoua Ha Mashiah',
      rights: 'Traduction BYM · embarquée, hors ligne',
      availability: VersionAvailability.embedded,
      format: VersionFormat.bym,
    ),
  ]),
  VersionGroup('Versions Louis Segond', [
    VersionEntry(
      code: 'LSG',
      name: 'Bible Segond 1910',
      rights: '1910 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'ls1910',
    ),
    VersionEntry(
      code: 'LSGS',
      name: 'Bible Segond 1910 + Strongs',
      rights: '1910 · Libre de droit',
      availability: VersionAvailability.embedded,
      format: VersionFormat.getbible,
      hasStrong: true,
    ),
    VersionEntry(
      code: 'NBS',
      name: 'Nouvelle Bible Segond',
      rights: '© 2002 Société Biblique Française',
    ),
    VersionEntry(
      code: 'NEG79',
      name: 'Nouvelle Edition de Genève 1979',
      rights: '© 1979 Société Biblique de Genève',
    ),
    VersionEntry(
      code: 'NVS78P',
      name: 'Nouvelle Segond révisée',
      rights: '© Alliance Biblique Française',
    ),
    VersionEntry(
      code: 'S21',
      name: 'Bible Segond 21',
      rights: '© 2007 Société Biblique de Genève',
    ),
  ]),
  VersionGroup('Autres versions', [
    VersionEntry(
      code: 'ATI',
      name: 'Ancien Testament Interlinéaire',
      // Le corpus vient de Biblia Universalis 3, qui le signe : même mention
      // que les traductions françaises de la SEF, qui sortent du même logiciel.
      rights: '© Biblia Universalis',
      availability: VersionAvailability.downloadable,
      // Même hébergement que OST / NCL / SEF, sous-dossier propre — produit par
      // `ATI/ati_to_json.py` depuis l'ATI.xml de Biblia Universalis 3. Chaque
      // mot hébreu porte sept champs, d'où un format à part.
      //
      // Ancien Testament seul, et c'est définitif : un interlinéaire hébreu
      // n'a pas de Nouveau Testament. `otOnly` fait compter la Bibliothèque
      // sur 39 et évite d'offrir le téléchargement d'un Matthieu inexistant.
      format: VersionFormat.ati,
      otOnly: true,
      // `hasStrong` reste faux, bien que le corpus porte un numéro Strong par
      // mot : le drapeau ne décrit pas le corpus mais le **texte aplati**, où
      // `verse_tile` va chercher des codes insérés dans la chaîne à la façon de
      // la LSGS (« AA H7225 », cf. `LsgsRepository.joinTokens`). `bookFromAti`
      // n'y joint que les gloses françaises : l'activer ferait chercher des
      // codes qui n'y sont pas. Les numéros deviendront cliquables avec le
      // rendu interlinéaire, qui lira les mots directement au lieu d'une
      // chaîne.
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/ati/{book}.json',
    ),
    VersionEntry(
      code: 'CHO',
      name: 'Bible Chouraqui',
      // Le copyright est porté sur la carte : c'est une traduction sous droits,
      // servie parce que son corpus est publié — la mention est la condition.
      rights: '© 1987 Desclée de Brouwer · André Chouraqui',
      availability: VersionAvailability.downloadable,
      // Même hébergement que OST / NCL : un JSON par livre, numérotation
      // standard 1=Genèse … 66=Apocalypse, produit par
      // `appCodebar/html_verses_to_json.py`. Canon ramené aux 66 livres
      // (Tobie, Judith, Maccabées… retirés, Daniel 14 ch. → 12).
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/chouraqui/{book}.json',
    ),
    VersionEntry(
      code: 'KJF',
      name: 'King James Française',
      // Même chaîne que CHO : corpus HTML, converti par
      // `appCodebar/html_verses_to_json.py`. Le copyright vient de l'index du
      // corpus source (Nadine L. Stratford, 2006).
      rights: '© 2006 Nadine L. Stratford · Bible des réformateurs',
      availability: VersionAvailability.downloadable,
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/kjf/{book}.json',
    ),
    VersionEntry(
      code: 'DBY',
      name: 'Bible Darby',
      rights: '1890 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'darby',
    ),
    VersionEntry(
      code: 'MAR',
      name: 'Bible Martin',
      rights: '1744 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'martin',
    ),
    VersionEntry(
      code: 'OST',
      name: 'Bible Ostervald',
      rights: '1744 · Libre de droit',
      availability: VersionAvailability.downloadable,
      // Servie depuis GitHub (décision 7) : un JSON par livre, numérotation
      // standard 1=Genèse … 66=Apocalypse. Le jeton {book} est remplacé par le
      // numéro standard (cf. DownloadService.bookUri).
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/ostervald/{book}.json',
    ),
    VersionEntry(
      code: 'NCL',
      name: 'Bible néo-Crampon Libre',
      rights: '© 2022 Fraternité de Tibériade · CC BY-SA 4.0',
      availability: VersionAvailability.downloadable,
      // Même hébergement GitHub, sous-dossier propre. Canon ramené aux
      // 66 livres de l'app ; numérotation des chapitres catholique (Joël 4,
      // Malachie 3), alignée sur la BYM.
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/neocrampon/{book}.json',
    ),
    VersionEntry(
      code: 'SEF',
      name: 'Septuaginta — la Septante en français',
      // Le copyright de la source porte sur la carte : le grec de Rahlfs est
      // sous droits Deutsche Bibelgesellschaft (meta/header.xml), et les deux
      // traductions françaises (Giguet, Alexandrie) portent le nom du
      // logiciel, Biblia Universalis 3 — même mention dans les fichiers.
      rights:
          '© 1935, 1979 Deutsche Bibelgesellschaft (grec) · '
          '© Biblia Universalis 3 (traductions)',
      // Les traducteurs tels que la source les nomme elle-même : Pierre
      // Giguet d'après son introduction (« GIGUET_INTRODUCTION »), et
      // l'équipe de la Bible d'Alexandrie d'après l'Avertissement du corpus
      // (Éditions du Cerf, direction Marguerite Harl, Gilles Dorival,
      // Olivier Munnich, concours Cécile Dogniez). Ligne affichée sous le
      // copyright sur la carte de la Bibliothèque.
      attribution:
          'Traductions : Pierre Giguet (1794-1883) · '
          'La Bible d\'Alexandrie (Éditions du Cerf), sous la direction de '
          'Marguerite Harl, Gilles Dorival, Olivier Munnich et '
          'Cécile Dogniez',
      availability: VersionAvailability.downloadable,
      // Hébergement GitHub identique à OST / NCL, sous-dossier propre —
      // produit par `sef/sef_to_json.py`. Grec + deux traductions françaises,
      // donc un format au-delà du texte nu. Ancien Testament seulement (39
      // livres) : la Septante n'a pas de Nouveau Testament.
      format: VersionFormat.sef,
      otOnly: true,
      urlTemplate:
          'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/sef/{book}.json',
    ),
    VersionEntry(
      code: 'KJV',
      name: 'King James Version (anglais)',
      rights: '1611 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'kjv',
      languageCode: 'EN',
    ),
  ]),
];

/// Flat lookup by [VersionEntry.code].
VersionEntry? versionByCode(String code) {
  for (final group in versionCatalog) {
    for (final version in group.versions) {
      if (version.code == code) return version;
    }
  }
  return null;
}
