import 'dart:convert';

/// Conversion d'un livre BYM du Markdown amont vers le JSON servi par
/// [LocalRepository].
///
/// C'est un port **fidèle** de `appCodebar/md_to_json.py`. Depuis que les mises
/// à jour de texte viennent des `.md` du dépôt GitLab officiel, l'application
/// fabrique elle-même le JSON : les deux implémentations doivent donc rendre
/// exactement les mêmes octets, sinon un livre mis à jour n'aurait plus la même
/// forme qu'un livre embarqué. Ce n'est pas une relecture qui garde cette
/// équivalence mais `test/bym_markdown_converter_golden_test.dart`, qui convertit
/// les 66 livres et compare octet pour octet à la sortie de Python.
///
/// Trois pièges du portage, à ne pas « nettoyer » :
///
/// - `\w` est unicode en Python et **ASCII seul** en Dart. Le motif des mots est
///   donc écrit `[\p{L}\p{N}_'’-]` avec `unicode: true` : avec `\w`, tout mot
///   accentué décalerait `notes.position` et les notes se rattacheraient au
///   mauvais mot.
/// - `str.splitlines()` coupe aussi sur `\r\n` et `\r`, là où `split('\n')`
///   laisserait un `\r` en fin de ligne, donc dans le texte des versets.
/// - l'ordre d'insertion des clés est celui de la sortie JSON. Les versets
///   passent volontairement par une clé temporaire `raw` retirée à la fin, ce
///   qui reproduit le `pop("raw")` de Python et place `text` après `section`.
class BymMarkdownConverter {
  /// Structure d'un livre à partir de son Markdown. Lève une [FormatException]
  /// si la première ligne n'est pas un titre `# …` : mieux vaut refuser la mise
  /// à jour que servir un livre vide.
  static Map<String, Object?> convert(String markdown) => _parseBook(markdown);

  /// Encode comme `json.dumps(book, ensure_ascii=False, indent=2)` — même
  /// indentation, mêmes échappements, pas de saut de ligne final.
  static String encode(Map<String, Object?> book) => _encoder.convert(book);

  /// Markdown → JSON encodé, le chemin utilisé par la mise à jour.
  static String convertToJson(String markdown) => encode(convert(markdown));

  /// Nombre de versets d'un livre converti, pour les contrôles de structure.
  static int verseCount(Map<String, Object?> book) {
    final chapters = book['chapters'];
    if (chapters is! List) return 0;
    var total = 0;
    for (final chapter in chapters) {
      if (chapter is Map && chapter['verses'] is List) {
        total += (chapter['verses'] as List).length;
      }
    }
    return total;
  }
}

// --- Nettoyage du texte -----------------------------------------------------

final RegExp _reNote = RegExp(r'<!--(.*?)-->', dotAll: true);
// Garde le texte, retire la balise.
final RegExp _reWTag = RegExp(r'<w\b[^>]*>(.*?)</w>', dotAll: true);
// Toute autre balise résiduelle.
final RegExp _reTag = RegExp(r'</?[a-zA-Z][^>]*>');
final RegExp _reSpaces = RegExp(r'[ \t]{2,}');

/// Équivalent unicode du `\w` de Python — voir la note de portage en tête.
final RegExp _reWord = RegExp(r"[\p{L}\p{N}_'’-]+", unicode: true);

/// Marque l'emplacement des notes pendant le nettoyage. Absent du corpus, et il
/// ne survit pas au découpage : aucun texte servi ne le contient.
const String _placeholder = '\x00';

final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

/// Texte propre, texte avec les notes inline, et les notes elles-mêmes.
class _Extraction {
  final String text;
  final String withNotes;
  final List<Map<String, Object?>> notes;

  const _Extraction(this.text, this.withNotes, this.notes);
}

/// Retire les balises et les commentaires `<!--…-->`.
///
/// Chaque note est rattachée au mot qui la précède (`{word, position, note}`),
/// `position` étant l'index du début de ce mot dans le texte propre.
_Extraction _extractNotes(String input) {
  // Retirer d'abord les balises, pour que le mot précédant la note soit propre.
  var text = input.replaceAllMapped(_reWTag, (m) => m.group(1)!);
  text = text.replaceAll(_reTag, '');

  final rawNotes = <String>[];
  for (final m in _reNote.allMatches(text)) {
    rawNotes.add(m.group(1)!.trim());
  }
  text = text.replaceAll(_reNote, _placeholder);
  text = text.replaceAll(_reSpaces, ' ').trim();

  final segments = text.split(_placeholder);
  final clean = segments.join();

  final notes = <Map<String, Object?>>[];
  final withNotes = StringBuffer(segments.first);
  var pos = 0;
  for (var k = 0; k < rawNotes.length; k++) {
    final note = rawNotes[k];
    // Index d'insertion de la note dans le texte propre.
    pos += segments[k].length;
    // Le dernier mot qui commence avant l'insertion : découper la chaîne
    // reproduit l'`endpos` de `finditer` en Python, y compris pour un mot que
    // la note coupe en deux.
    RegExpMatch? last;
    for (final m in _reWord.allMatches(clean.substring(0, pos))) {
      last = m;
    }
    notes.add(<String, Object?>{
      'word': last == null ? '' : last.group(0),
      'position': last == null ? pos : last.start,
      'note': note,
    });
    withNotes.write('[$note]');
    withNotes.write(segments[k + 1]);
  }

  return _Extraction(clean, withNotes.toString(), notes);
}

// --- Analyse d'un livre -----------------------------------------------------

final RegExp _reTitle = RegExp(r'^#\s+(.*)$');
final RegExp _reChapter = RegExp(r'^##\s+Chapitre\s+(\d+)');
final RegExp _reSection = RegExp(r'^###\s+(.*)$');
final RegExp _reVerse = RegExp(r'^(\d+):(\d+)\t(.*)$');
final RegExp _reAbbreviation = RegExp(r'^(.*)\s+\(([^()]*)\)\s*$');
final RegExp _reMetaBlock = RegExp(r'<h>(.*?)</h>', dotAll: true);
final RegExp _reLineBreak = RegExp(r'\r\n|\r|\n');

/// Clés des métadonnées du bloc `<h>…</h>`.
const Map<String, String> _metaKeys = {
  'signification': 'signification',
  'auteur': 'auteur',
  'auteurs': 'auteur',
  'thème': 'theme',
  'theme': 'theme',
  'date de rédaction': 'date',
};

/// Équivalent de `str.splitlines()` : coupe aussi sur `\r\n` et `\r`, et
/// n'ajoute pas de ligne vide finale quand le texte termine par un saut.
List<String> _splitLines(String text) {
  if (text.isEmpty) return const <String>[];
  final lines = text.split(_reLineBreak);
  if (lines.last.isEmpty) return lines.sublist(0, lines.length - 1);
  return lines;
}

/// `'# Bereshit (Genèse) (Ge.)'` → `('Bereshit (Genèse)', 'Ge.')`
({String name, String abbreviation}) _parseTitle(String line) {
  final head = _reTitle.firstMatch(line);
  if (head == null) {
    throw const FormatException('titre de livre absent (première ligne « # … »)');
  }
  final title = head.group(1)!.trim();
  final m = _reAbbreviation.firstMatch(title);
  if (m != null) {
    return (name: m.group(1)!.trim(), abbreviation: m.group(2)!.trim());
  }
  return (name: title, abbreviation: '');
}

Map<String, String> _parseMetadata(String block) {
  final meta = <String, String>{};
  for (final raw in _splitLines(block)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final cut = line.indexOf(':');
    if (cut < 0) continue;
    final key = _metaKeys[line.substring(0, cut).trim().toLowerCase()];
    if (key != null) meta[key] = line.substring(cut + 1).trim();
  }
  return meta;
}

Map<String, Object?> _parseBook(String markdown) {
  var raw = markdown;

  // Titre.
  final firstLines = _splitLines(raw.trimLeft());
  if (firstLines.isEmpty) throw const FormatException('livre vide');
  final title = _parseTitle(firstLines.first);

  // Bloc de métadonnées `<h>…</h>`.
  var metadata = const <String, String>{};
  final meta = _reMetaBlock.firstMatch(raw);
  if (meta != null) {
    metadata = _parseMetadata(meta.group(1)!);
    raw = raw.replaceFirst(meta.group(0)!, '');
  }

  final introParts = <String>[];
  final chapters = <Map<String, Object?>>[];
  Map<String, Object?>? currentChapter;
  String? currentSection;
  Map<String, Object?>? currentVerse;

  void finishVerse() {
    if (currentVerse != null) {
      (currentChapter!['verses'] as List<Map<String, Object?>>)
          .add(currentVerse!);
      currentVerse = null;
    }
  }

  for (final line in _splitLines(raw)) {
    // Ligne de titre, déjà traitée.
    if (_reTitle.hasMatch(line) && !line.startsWith('##')) continue;

    final chapter = _reChapter.firstMatch(line);
    if (chapter != null) {
      finishVerse();
      currentChapter = <String, Object?>{
        'chapter': int.parse(chapter.group(1)!),
        'verses': <Map<String, Object?>>[],
      };
      chapters.add(currentChapter);
      currentSection = null;
      continue;
    }

    final section = _reSection.firstMatch(line);
    if (section != null) {
      finishVerse();
      // Les notes des titres de section sont ignorées.
      currentSection = _extractNotes(section.group(1)!).text;
      continue;
    }

    final verse = _reVerse.firstMatch(line);
    if (verse != null && currentChapter != null) {
      finishVerse();
      currentVerse = <String, Object?>{
        'verse': '${verse.group(1)}:${verse.group(2)}',
        'raw': verse.group(3),
      };
      if (currentSection != null && currentSection.isNotEmpty) {
        currentVerse!['section'] = currentSection;
      }
      // La section n'est attachée qu'au premier verset qui la suit.
      currentSection = null;
      continue;
    }

    // Ligne de continuation d'un verset (rare) ou paragraphe d'introduction.
    if (currentVerse != null && line.trim().isNotEmpty) {
      currentVerse!['raw'] = '${currentVerse!['raw']} ${line.trim()}';
    } else if (currentChapter == null && line.trim().isNotEmpty) {
      final text = _extractNotes(line.trim()).text;
      if (text.isNotEmpty) introParts.add(text);
    }
  }

  finishVerse();

  // Nettoyage final : extraction des notes et des balises.
  for (final chapter in chapters) {
    for (final verse in chapter['verses'] as List<Map<String, Object?>>) {
      final extracted = _extractNotes(verse.remove('raw') as String);
      verse['text'] = extracted.text;
      if (extracted.notes.isNotEmpty) {
        verse['textWithNotes'] = extracted.withNotes;
        verse['notes'] = extracted.notes;
      }
    }
  }

  return <String, Object?>{
    'book': title.name,
    'abbreviation': title.abbreviation,
    'metadata': metadata,
    'introduction': introParts.join('\n\n'),
    'chapters': chapters,
  };
}
