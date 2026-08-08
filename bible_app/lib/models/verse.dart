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

  const Verse({
    required this.verse,
    this.section,
    required this.text,
    required this.textWithNotes,
    this.notes = const [],
  });

  factory Verse.fromJson(Map<String, dynamic> json) => Verse(
        verse: json['verse'] as String? ?? '',
        section: json['section'] as String?,
        text: json['text'] as String? ?? '',
        textWithNotes: json['textWithNotes'] as String? ?? '',
        notes: (json['notes'] as List<dynamic>? ?? [])
            .map((e) => VerseNote.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// Position (1-based) of this verse within its chapter.
  int get number {
    final idx = verse.indexOf(':');
    if (idx < 0) return 0;
    return int.tryParse(verse.substring(idx + 1)) ?? 0;
  }
}
