import '../models/verse.dart';

/// What one block of a work is, typographically.
///
/// Les types viennent du JSON produit par `appCodebar/pdf_book_to_json.py`.
/// Un type inconnu — un convertisseur plus récent que l'app — retombe en
/// [paragraph] : rendre un titre en prose est le moindre mal devant un blanc.
enum WorkBlockKind {
  paragraph,
  quote,
  item,
  heading2,
  heading3,
  heading4,

  /// Une ligne du tableau des noms : [WorkBlock.text] porte l'hébreu ou le
  /// grec, [WorkBlock.gloss] le français.
  pair;

  static WorkBlockKind fromJson(String? type) => switch (type) {
        'quote' => WorkBlockKind.quote,
        'li' => WorkBlockKind.item,
        'h2' => WorkBlockKind.heading2,
        'h3' => WorkBlockKind.heading3,
        'h4' => WorkBlockKind.heading4,
        'pair' => WorkBlockKind.pair,
        _ => WorkBlockKind.paragraph,
      };

  bool get isHeading =>
      this == heading2 || this == heading3 || this == heading4;
}

/// One block of a work's chapter: a paragraph, a quote, a heading…
class WorkBlock {
  final WorkBlockKind kind;

  /// Le texte nu, sans marqueur de note — c'est lui que `notes.position`
  /// indexe.
  final String text;

  /// Le même texte, chaque note entre [crochets] après son mot. Vide quand le
  /// bloc n'a pas de note.
  final String textWithNotes;

  final List<VerseNote> notes;

  /// La référence biblique qui clôt une citation (« 1 Corinthiens 9:16 »),
  /// isolée pour être tapable. Null sur tout autre bloc.
  final String? reference;

  /// Le français d'une paire du tableau des noms. Null ailleurs.
  final String? gloss;

  const WorkBlock({
    required this.kind,
    required this.text,
    this.textWithNotes = '',
    this.notes = const [],
    this.reference,
    this.gloss,
  });

  factory WorkBlock.fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String? ?? '';
    return WorkBlock(
      kind: WorkBlockKind.fromJson(json['type'] as String?),
      text: text,
      textWithNotes: json['textWithNotes'] as String? ?? '',
      notes: [
        for (final item in json['notes'] as List<dynamic>? ?? const [])
          if (item is Map<String, dynamic>) VerseNote.fromJson(item),
      ],
      reference: json['reference'] as String?,
      gloss: json['gloss'] as String?,
    );
  }

  /// Le bloc vu comme un verset, pour le rendre avec `NoteAwareVerseText`.
  ///
  /// L'ouvrage et la Bible partagent la convention de notes de la BYM
  /// (`text` / `textWithNotes` / `notes`, invariant
  /// `text[position : position + word.length] == word`) : le widget qui sait
  /// déjà afficher une note au tap n'a donc rien à apprendre de la prose. Le
  /// champ `verse` reste vide — un ouvrage n'a pas de numérotation de verset,
  /// et aucun appelant ne l'affiche.
  Verse asVerse() => Verse(
        verse: '',
        text: text,
        textWithNotes: textWithNotes.isEmpty ? text : textWithNotes,
        notes: notes,
      );
}

/// One chapter of a work, as the extractor cut it: the sommaire's level-0
/// entries (introduction, chapitres, conclusion, annexes).
class WorkChapter {
  final int number;
  final String title;
  final List<WorkBlock> blocks;

  const WorkChapter({
    required this.number,
    required this.title,
    required this.blocks,
  });

  factory WorkChapter.fromJson(Map<String, dynamic> json) => WorkChapter(
        number: (json['number'] as num?)?.toInt() ?? 0,
        title: json['title'] as String? ?? '',
        blocks: [
          for (final item in json['blocks'] as List<dynamic>? ?? const [])
            if (item is Map<String, dynamic>) WorkBlock.fromJson(item),
        ],
      );
}

/// One line of the printed sommaire, which is also the chapter picker.
class WorkTocItem {
  final String title;

  /// 0 for a chapter heading, 1.. for a section nested under it — l'indentation
  /// à l'écran.
  final int level;

  /// Numéro du chapitre où mène cette ligne, 1-based. **0 signifie « aucune
  /// destination »** : une section imprimée avant le premier chapitre n'ouvre
  /// rien plutôt que d'ouvrir l'introduction par erreur.
  final int chapter;

  const WorkTocItem({
    required this.title,
    required this.level,
    required this.chapter,
  });

  factory WorkTocItem.fromJson(Map<String, dynamic> json) => WorkTocItem(
        title: json['title'] as String? ?? '',
        level: (json['level'] as num?)?.toInt() ?? 0,
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
      );

  bool get hasDestination => chapter >= 1;
}

/// In-memory view of a downloaded work.
///
/// **Le sommaire n'est pas un chapitre stocké** : il est rendu depuis [toc], et
/// occupe l'index 0 de la lecture — les chapitres suivent à partir de 1, ce qui
/// est exactement la numérotation que porte [WorkTocItem.chapter].
class Work {
  final String code;
  final String title;
  final String subtitle;
  final String author;
  final String publisher;
  final String isbn;

  /// La ligne de droits, telle que l'extracteur l'a composée depuis les pages
  /// de garde. Affichée en pied de sommaire : la licence du pilote autorise la
  /// diffusion gratuite et interdit la vente, ce qui doit rester lisible.
  final String rights;

  final List<WorkTocItem> toc;
  final List<WorkChapter> chapters;

  const Work({
    required this.code,
    required this.title,
    this.subtitle = '',
    this.author = '',
    this.publisher = '',
    this.isbn = '',
    this.rights = '',
    this.toc = const [],
    this.chapters = const [],
  });

  /// Builds a work from a stored payload, or null when the file is not a work.
  ///
  /// Deux exigences, les mêmes que le service de téléchargement : des
  /// `chapters` non vides **et** un `title`. Un fichier tronqué ou un lien
  /// cassé s'installerait sinon comme un livre vide, dont la pastille de
  /// l'écran Lecture n'aurait rien à porter.
  static Work? parse(Map<String, dynamic> json) {
    final title = (json['title'] as String? ?? '').trim();
    final rawChapters = json['chapters'];
    if (title.isEmpty || rawChapters is! List || rawChapters.isEmpty) {
      return null;
    }
    final chapters = [
      for (final item in rawChapters)
        if (item is Map<String, dynamic>) WorkChapter.fromJson(item),
    ];
    if (chapters.isEmpty) return null;
    return Work(
      code: json['code'] as String? ?? '',
      title: title,
      subtitle: json['subtitle'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publisher: json['publisher'] as String? ?? '',
      isbn: json['isbn'] as String? ?? '',
      rights: json['rights'] as String? ?? '',
      toc: [
        for (final item in json['toc'] as List<dynamic>? ?? const [])
          if (item is Map<String, dynamic>) WorkTocItem.fromJson(item),
      ],
      chapters: chapters,
    );
  }

  /// Index de lecture le plus élevé : 0 est le sommaire, [chapters].length le
  /// dernier chapitre.
  int get lastIndex => chapters.length;

  /// Le chapitre à cet index de lecture, ou null pour le sommaire (0) et pour
  /// tout index hors du livre.
  WorkChapter? chapterAt(int index) {
    if (index < 1 || index > chapters.length) return null;
    return chapters[index - 1];
  }

  /// Le titre à afficher pour cet index de lecture.
  String labelAt(int index) => chapterAt(index)?.title ?? 'Sommaire';
}
