/// How a dictionary can actually be consulted.
enum DictionaryAvailability {
  /// Shipped inside the app, readable offline — the Dictionnaire Strong
  /// français and Westphal 1932.
  embedded,

  /// Not bundled but servable from a direct URL (décision 7 — Filebase, or any
  /// public JSON host). Offered as a download in the Bibliothèque once a [url]
  /// is configured.
  downloadable,

  /// Listed for completeness but with no free source yet. Not offered anywhere
  /// it could not be honoured: the tile is greyed and explains itself.
  unavailable,
}

/// A dictionary offered by the Bibliothèque's « Dictionnaires » tab.
class DictionaryEntry {
  /// Short code shown in the tile (BYM, STRONG_FR, FREDAW…).
  final String code;

  final String name;

  /// The line under the name — licence / source / rights.
  final String rights;

  final String description;

  /// Whether we can serve it, and how.
  final DictionaryAvailability availability;

  /// Direct URL of the JSON file (`{entries: {...}}`) for
  /// [DictionaryAvailability.downloadable] entries. Null while the source is
  /// not published yet — the tile then says the URL is unconfigured instead of
  /// offering a download that would fail.
  final String? url;

  const DictionaryEntry({
    required this.code,
    required this.name,
    required this.rights,
    required this.description,
    this.availability = DictionaryAvailability.unavailable,
    this.url,
  });

  bool get embedded => availability == DictionaryAvailability.embedded;

  bool get downloadable => availability == DictionaryAvailability.downloadable;

  /// The download button is honest only once a URL exists.
  bool get configured => url != null && url!.isNotEmpty;
}

/// The dictionaries of the Bibliothèque.
///
/// Two are embedded — the Dictionnaire Strong français and Westphal 1932 :
/// le lexique « Notes BYM Lexique » a été débranché du catalogue comme de la
/// recherche (demande utilisateur), et le rang « Modules SWORD » n'affichait
/// rien d'ouvrable : retiré de l'interface. Nave has no source yet
/// (« À venir »). The downloadable entries appear when their
/// [DictionaryEntry.url] is filled in — the mechanism is wired, the hosting is
/// manual (décision 8).
const List<DictionaryEntry> dictionaryCatalog = [
  DictionaryEntry(
    code: 'STRONG_FR',
    name: 'Dictionnaire Strong français',
    rights: 'CrossWire/SWORD · libre',
    description: 'Lexique Strong français embarqué depuis CrossWire/SWORD.',
    availability: DictionaryAvailability.embedded,
  ),
  DictionaryEntry(
    code: 'FREDAW',
    name: 'Westphal 1932',
    rights: 'Dictionnaire encyclopédique de la Bible · A. Westphal · 1932 · libre',
    description:
        'Dictionnaire encyclopédique de la Bible A. Westphal (1932) embarqué localement.',
    availability: DictionaryAvailability.embedded,
  ),
  DictionaryEntry(
    code: 'GBM',
    name: 'Glossaire Martin 1744',
    rights: 'D. Martin · 1744 · libre',
    description: 'Glossaire de la Bible de David Martin (CrossWire FreGBM).',
    availability: DictionaryAvailability.downloadable,
    // Converti depuis le module SWORD FreGBM par appCodebar/sword_dict_to_json.py
    // (gbm.json, 1 074 entrées). À remplacer par l'URL de ton hébergement.
    url: 'https://raw.githubusercontent.com/victordiaz1000/-bym-dictionaries/main/gbm.json',
  ),
  DictionaryEntry(
    code: 'NAVE',
    name: 'Nave',
    rights: 'Catégorie thématique',
    description: 'Catégorie thématique sans source disponible pour l\'instant.',
    availability: DictionaryAvailability.unavailable,
  ),
];

/// Flat lookup by [DictionaryEntry.code].
DictionaryEntry? dictionaryByCode(String code) {
  for (final entry in dictionaryCatalog) {
    if (entry.code == code) return entry;
  }
  return null;
}