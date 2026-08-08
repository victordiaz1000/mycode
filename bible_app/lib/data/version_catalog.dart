/// How a version can actually be consulted from the reading « Version » sheet.
enum VersionAvailability {
  /// Shipped inside the app, readable offline — the BYM default (décision 3).
  embedded,

  /// Not bundled but servable from a free source (getbible.net, décision 9);
  /// offered as a download in the Bibliothèque.
  downloadable,

  /// Listed for completeness to match the maquette
  /// (`modif/resultat_vers_les_versions.jpg`) but under copyright / without a
  /// free source yet — shown greyed, « bientôt disponible » when tapped.
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

  /// getbible.net translation id for [VersionAvailability.downloadable] entries;
  /// null otherwise.
  final String? getbibleId;

  /// The maquette prints a 🔊 next to versions that also ship an audio reading.
  final bool hasAudio;

  const VersionEntry({
    required this.code,
    required this.name,
    required this.rights,
    this.availability = VersionAvailability.unavailable,
    this.getbibleId,
    this.hasAudio = false,
  });

  /// True for the version shipped inside the app (readable offline, no download).
  bool get embedded => availability == VersionAvailability.embedded;

  /// True when the version can be fetched from a free source right now.
  bool get downloadable => availability == VersionAvailability.downloadable;
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
/// - **embedded** : BYM, the default reading version (décision 3) ;
/// - **downloadable** : the public-domain getbible.net translations we can
///   actually serve — LSG (ls1910), Darby, Martin, KJV (décision 9) ;
/// - **unavailable** : copyright / sourceless versions shown greyed for parity
///   with the maquette (LSGS, NBS, NEG79, NVS78P, S21, INT, KJF).
///
/// « Segond 1910 with Strong » (LSGS) stays unavailable on purpose: getbible's
/// ls1910 JSON does not carry the Strong numbers (cf. AGENTS.md, décision 9).
const List<VersionGroup> versionCatalog = [
  VersionGroup('Version intégrée', [
    VersionEntry(
      code: 'BYM',
      name: 'Bible de Yehoshoua Ha Mashiah',
      rights: 'Traduction BYM · embarquée, hors ligne',
      availability: VersionAvailability.embedded,
    ),
  ]),
  VersionGroup('Versions Louis Segond', [
    VersionEntry(
      code: 'LSG',
      name: 'Bible Segond 1910',
      rights: '1910 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'ls1910',
      hasAudio: true,
    ),
    VersionEntry(
      code: 'LSGS',
      name: 'Bible Segond 1910 + Strongs',
      rights: '1910 · Libre de droit',
      hasAudio: true,
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
      code: 'KJV',
      name: 'King James Version (anglais)',
      rights: '1611 · Libre de droit',
      availability: VersionAvailability.downloadable,
      getbibleId: 'kjv',
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
