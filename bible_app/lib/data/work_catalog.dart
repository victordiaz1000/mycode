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
  WorkEntry(
    code: 'ANIMALITE',
    title: 'L’ANIMALITÉ DE L’ÊTRE HUMAIN',
    author: 'Shora Kuetu',
    rights: '© 2022 ANJC PRODUCTIONS · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: 'L’ÊTRE HUMAIN, CET ANIMAL — 13 chapitres sur l’esprit, '
        'l’âme et le corps, puis sur l’animalité des dirigeants.',
    cover: 'assets/covers/animalite.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis
    // LANIMALITE_DE_LETRE_HUMAIN.pdf (1063 blocs, sans note de bas de page :
    // les quatre blocs qui ouvrent sur un chiffre sont des paragraphes de
    // corps, écartés au marqueur comme à la ligne vide).
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'animalite.json',
  ),
  WorkEntry(
    code: 'CHATIMENT',
    title: 'LE CHÂTIMENT DU PÈRE',
    author: 'Trésor Koufounda',
    rights: '© 2021 Vases de Terre les Éditions · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: 'POURQUOI LE PÈRE CHÂTIE — 11 chapitres sur le châtiment, '
        'ses raisons, la façon dont il s’exerce et l’épreuve de la foi.',
    cover: 'assets/covers/chatiment.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis
    // LE-CHATIMENT-DU-PERE-VFINALE-AVEC-COUVERTURE.pdf (2094 blocs). Le seul
    // des sept dont l'appareil de notes reste dans le corps : sa note
    // d'ouverture ne renvoie à aucun mot de sa page, le compteur ne démarre
    // donc pas. Aucun texte ne manque, il n'est pas balisé en notes.
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'chatiment.json',
  ),
  WorkEntry(
    code: 'OMBRE',
    title: 'DE L’OMBRE À LA LUMIÈRE',
    author: 'Morgane M.A',
    rights: '© 2026 Vases de Terre les Éditions · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: 'CECI EST MON TÉMOIGNAGE — 4 chapitres : une enfance '
        'blessée, la rencontre qui change tout, puis la marche dans la '
        'lumière.',
    cover: 'assets/covers/ombre.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis
    // De-lombre-a-la-lumiere-_M.MA_format-poche.cover_.pdf (255 blocs,
    // 7 notes). Son sommaire imprime l'étiquette du chapitre et son titre sur
    // deux entrées de même page, recollées à la conversion.
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'ombre.json',
  ),
  WorkEntry(
    code: 'CROIX',
    title: 'LA CROIX',
    author: 'Shora Kuetu',
    rights: '© 2024 ANJC PRODUCTIONS · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: '7 chapitres sur la croix du Mashiah : sa préfiguration '
        'dans les Écritures, ses conséquences spirituelles, porter sa croix '
        'et les ennemis de la croix.',
    cover: 'assets/covers/croix.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis La_croix_-_2024v1.pdf
    // (631 blocs, 98 notes sur 99 ancrées). Sa pochette est la page de titre
    // rendue à la fonte : le PDF n'embarque aucune image.
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'croix.json',
  ),
  WorkEntry(
    code: 'NOMDUPERE',
    title: 'LE NOM DU PÈRE',
    author: 'Shora Kuetu',
    rights: '© 2025 ANJC PRODUCTIONS · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: '6 chapitres sur la révélation du Nom du Créateur, le '
        'Tétragramme, et les faits historiques qui ont concouru à le '
        'modifier.',
    cover: 'assets/covers/nomdupere.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis LE-NOM-DU-PERE.pdf
    // (338 blocs, 64 notes). Pochette rendue à la fonte, comme La Croix.
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'nomdupere.json',
  ),
  WorkEntry(
    code: 'VOLEURS',
    title: 'LES VOLEURS DE TEMPS',
    author: 'Shora Kuetu',
    rights: '© 2025 ANJC PRODUCTIONS · diffusion gratuite '
        'autorisée · STRICTEMENT INTERDIT À LA VENTE',
    description: '18 chapitres en quatre parties : ce qu’est le temps, qui '
        'le vole, la fin des temps, et comment le racheter.',
    cover: 'assets/covers/voleurs.jpg',
    availability: WorkAvailability.downloadable,
    // Produit par appCodebar/pdf_book_to_json.py depuis
    // VERSION_LES_VOLEURS_DE_TEMPS_EN_CHAPITRE_VERSION_FINALE.pdf (562 blocs,
    // 99 notes). Les quatre pages de garde de partie sont des chapitres à
    // part entière : deux d'entre elles ne portent que leur titre.
    url: 'https://raw.githubusercontent.com/victordiaz1000/pdf-bym/main/'
        'voleurs.json',
  ),
];

/// Flat lookup by [WorkEntry.code].
WorkEntry? workByCode(String code) {
  for (final entry in workCatalog) {
    if (entry.code == code) return entry;
  }
  return null;
}
