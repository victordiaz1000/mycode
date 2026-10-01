class VerseNote {
  final String word;
  final int position;
  final String note;

  const VerseNote({
    required this.word,
    required this.position,
    required this.note,
  });

  factory VerseNote.fromJson(Map<String, dynamic> json) => VerseNote(
        word: json['word'] as String? ?? '',
        position: (json['position'] as num?)?.toInt() ?? 0,
        note: json['note'] as String? ?? '',
      );
}

class Verse {
  final String verse;
  final String? section;
  final String text;
  final String textWithNotes;
  final List<VerseNote> notes;

  /// Greek source line of a Septuagint version (SEF), rendered above the
  /// translation. Null on every other version.
  final String? grec;

  /// Footnotes the version attaches to this verse without anchoring them to a
  /// word (SEF: the source's `•` footnote paragraphs, unlike [notes] which
  /// are word-anchored). Rendered as a small line under the verse.
  final String? note;

  const Verse({
    required this.verse,
    this.section,
    required this.text,
    required this.textWithNotes,
    this.notes = const [],
    this.grec,
    this.note,
  });

  factory Verse.fromJson(Map<String, dynamic> json) => Verse(
        verse: json['verse'] as String? ?? '',
        section: json['section'] as String?,
        text: json['text'] as String? ?? '',
        textWithNotes: json['textWithNotes'] as String? ?? '',
        notes: (json['notes'] as List<dynamic>? ?? [])
            .map((e) => VerseNote.fromJson(e as Map<String, dynamic>))
            .toList(),
        grec: json['grec'] as String?,
        note: json['note'] as String?,
      );

  /// Position (1-based) of this verse within its chapter.
  int get number {
    final idx = verse.indexOf(':');
    if (idx < 0) return 0;
    return int.tryParse(verse.substring(idx + 1)) ?? 0;
  }
}
