/// User-generated data bound to a verse (book, chapter, verse).
///
/// Stored in the local SQLite database. All fields are nullable-safe defaults.
class VerseMark {
  final int bookIndex;
  final int chapter;
  final int verse;

  const VerseMark({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
  });
}

class UserHighlight extends VerseMark {
  final String colorId; // one of the 4 highlight colors
  final String? legacyNote;

  const UserHighlight({
    required super.bookIndex,
    required super.chapter,
    required super.verse,
    required this.colorId,
    this.legacyNote,
  });

  Map<String, Object?> toMap() => {
        'book': bookIndex,
        'chapter': chapter,
        'verse': verse,
        'color': colorId,
      };
}

class UserNote extends VerseMark {
  final String text;
  final int updatedAt;
  final int? createdAt;

  const UserNote({
    required super.bookIndex,
    required super.chapter,
    required super.verse,
    required this.text,
    required this.updatedAt,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'book': bookIndex,
        'chapter': chapter,
        'verse': verse,
        'text': text,
        'updated_at': updatedAt,
        'created_at': createdAt,
      };

  static UserNote fromMap(Map<String, Object?> m) => UserNote(
        bookIndex: m['book'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        text: m['text'] as String,
        updatedAt: (m['updated_at'] as int?) ?? 0,
        createdAt: m['created_at'] as int?,
      );
}

class UserFavorite extends VerseMark {
  const UserFavorite({
    required super.bookIndex,
    required super.chapter,
    required super.verse,
  });

  Map<String, Object?> toMap() => {
        'book': bookIndex,
        'chapter': chapter,
        'verse': verse,
      };
}

const List<String> highlightColors = [
  '#fff3b0', // ambre
  '#c9f0d2', // vert
  '#d4e4ff', // bleu
  '#f7d4e0', // rose
];