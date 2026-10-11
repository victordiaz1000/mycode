/// How a work can actually be read.
///
/// Un ouvrage n'est jamais embarqué : les PDF pèsent, l'app en visera une
/// quarantaine, et le JSON est hébergé puis téléchargé — à la différence des
/// dictionnaires, dont deux voyagent dans l'APK.
enum WorkAvailability {
  /// Servable from a direct URL. Offered as a download in the Bibliothèque once
  /// a [WorkEntry.url] is configured.
  downloadable,

  /// Listed for completeness but with no published source yet. The tile is
  /// greyed and explains itself rather than offering a download that would
  /// fail.
  unavailable,
}

/// A work (livre d'édification) offered by the Bibliothèque's « Livres » tab.
///
/// Le préfixe est `work_` et non `book_` : `book_catalog.dart` désigne déjà les
/// 66 **livres bibliques**. L'étiquette reste « Livres » à l'écran, où il n'y a
/// pas d'ambiguïté.
class WorkEntry {
  /// Short code, also the file name on the device (MINISTERE…).
  final String code;

  /// Titre de l'ouvrage, tel qu'il s'affichera dans la pastille gauche de
  /// l'écran Lecture.
  final String title;

  final String author;

  /// The line under the title — licence / éditeur / droits. Pour le pilote,
  /// elle porte l'interdiction de vente en clair, parce que la licence de
  /// l'ouvrage autorise la diffusion gratuite **et rien d'autre**.
  final String rights;

  final String description;

  /// Chemin de l'asset de pochette — l'image de couverture extraite de la
  /// page 1 du PDF par `pdf_book_to_json.py --cover`. Embarquée alors que le
  /// livre, lui, se télécharge : la tuile de la Bibliothèque doit montrer la
  /// pochette **avant** le téléchargement, et une vignette pèse 40 Ko. Null
  /// quand la page 1 n'en portait pas : la tuile retombe alors sur son icône.
  final String? cover;

  /// Whether we can serve it, and how.
  final WorkAvailability availability;

  /// Direct URL of the JSON file produced by `appCodebar/pdf_book_to_json.py`.
  /// Null while the source is not published yet — la tuile dit alors que l'URL
  /// n'est pas configurée au lieu d'offrir un téléchargement voué à l'échec.
  final String? url;

  const WorkEntry({
    required this.code,
    required this.title,
    required this.author,
    required this.rights,
    required this.description,
    this.cover,
    this.availability = WorkAvailability.unavailable,
    this.url,
  });

  bool get downloadable => availability == WorkAvailability.downloadable;

  /// The download button is honest only once a URL exists.
  bool get configured => url != null && url!.isNotEmpty;
}

/// Les ouvrages de la Bibliothèque.
///
/// Le convertisseur est écrit pour être général, mais chaque PDF demande d'être
/// relu à l'œil avant d'entrer ici. L'`url` reste nulle tant que le JSON n'a pas
/// été publié — l'hébergement est manuel, comme pour les corpus bibliques et
/// les dictionnaires — et la tuile annonce alors que l'URL n'est pas
/// configurée, plutôt qu'un téléchargement voué à l'échec.
///
/// Le pilote `MINISTERE` est servi par `github.com/victordiaz1000/pdf-bym`,
/// dépôt **public** : l'app interroge l'URL en clair, sans jeton, et un dépôt
/// privé renverrait 404. `WorkDownloadService` refuse par ailleurs un JSON sans
/// `chapters` ni `title` : un fichier poussé à moitié donne un lien cassé, pas
/// un livre corrompu.
const List<WorkEntry> workCatalog = [
  WorkEntry(
    code: 'MINISTERE',
    title: 'LE MINISTÈRE OU LE SEIGNEUR',
    author: 'Trésor Koufounda',
    rights: '© 2024 Vases de Terre les Éditions · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description:
        'QUE PRÉFÈRES-TU ? — 11 chapitres sur le service du Seigneur, '
        'ses notes et son tableau des noms.',
    cover: 'assets/covers/ministere.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis
    // LE-MINISTERE-OU-LE-SEIGNEUR.pdf (668 blocs, 46 notes).
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'ministere.json',
  ),
];

/// Flat lookup by [WorkEntry.code].
WorkEntry? workByCode(String code) {
  for (final entry in workCatalog) {
    if (entry.code == code) return entry;
  }
  return null;
}
