import 'ati.dart';

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

  /// Second French translation the Septuagint version carries (SEF: the
  /// Bible d'Alexandrie, only where it differs from [text]), rendered under
  /// the main translation in the same muted line as [grec].
  final String? alexandrie;

  /// The words of an interlinear verse, kept whole (ATI: seven fields per
  /// Hebrew word; NTI: eight per Greek word — either way, one column per word
  /// with its lines stacked).
  ///
  /// Null on every version but the interlinear ones, and on any verse rebuilt
  /// from JSON — a favourite or a history entry carries no words, so the
  /// reader falls back to [text], the joined glosses, which every consumer
  /// (search, share, Comparer) already reads.
  final List<AtiWord>? mots;

  /// Whether [mots] holds Greek words — the NTI grid, read left to right,
  /// against the ATI's Hebrew grid, read right to left.
  ///
  /// Asked by whatever lays the verse out, which would otherwise have to guess
  /// the direction of a verse it only ever receives as data. It reads the
  /// first word that has one: a Greek word keeps its three Greek lines even
  /// when it has neither Strong nor glose, and an empty verse direction is
  /// meaningless.
  bool get motsGrecs => mots?.any((mot) => mot.greek) ?? false;

  const Verse({
    required this.verse,
    this.section,
    required this.text,
    required this.textWithNotes,
    this.notes = const [],
    this.grec,
    this.alexandrie,
    this.mots,
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
        alexandrie: json['alexandrie'] as String?,
        // No schema carries the words: they are built from the source file by
        // `bookFromAti`, and a restored verse renders its [text].
      );

  /// Position (1-based) of this verse within its chapter.
  int get number {
    final idx = verse.indexOf(':');
    if (idx < 0) return 0;
    return int.tryParse(verse.substring(idx + 1)) ?? 0;
  }
}
