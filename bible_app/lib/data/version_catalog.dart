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

  const VersionEntry({
    required this.code,
    required this.name,
    required this.rights,
    this.availability = VersionAvailability.unavailable,
    this.format = VersionFormat.getbible,
    this.getbibleId,
    this.urlTemplate,
    this.hasStrong = false,
    this.languageCode = 'FR',
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
/// - **downloadable** : the public-domain translations we can actually serve —
///   LSG (ls1910), Darby, Martin, KJV via getbible.net (décision 9), and
///   Ostervald + néo-Crampon Libre via a direct GitHub host
///   ([VersionEntry.urlTemplate]) ;
/// - **unavailable** : copyright / sourceless versions shown greyed for parity
///   with the maquette (NBS, NEG79, NVS78P, S21, INT, KJF).
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
      code: 'INT',
      name: 'Bible Interlinéaire',
      rights: '©',
    ),
    VersionEntry(
      code: 'KJF',
      name: 'King James Française',
      rights: '© 1611 · Bible des réformateurs 2006',
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
