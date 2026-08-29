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
  /// Row id (SQLite autoincrement). Null until the note is written; several
  /// notes may share the same verse, so identity lives here, not on the verse.
  final int? id;

  /// Optional heading shown above the body in lists and fiches.
  final String title;
  final String text;
  final int updatedAt;
  final int? createdAt;

  const UserNote({
    required super.bookIndex,
    required super.chapter,
    required super.verse,
    this.id,
    this.title = '',
    required this.text,
    required this.updatedAt,
    this.createdAt,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'book': bookIndex,
        'chapter': chapter,
        'verse': verse,
        'title': title,
        'text': text,
        'updated_at': updatedAt,
        'created_at': createdAt,
      };

  /// A copy with [id]/[createdAt] filled from storage, keeping the draft's
  /// editable fields ([title], [text]).
  UserNote withId(int rowId, {int? createdAt}) => UserNote(
        bookIndex: bookIndex,
        chapter: chapter,
        verse: verse,
        id: rowId,
        title: title,
        text: text,
        updatedAt: updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );

  UserNote copyWith({
    int? id,
    String? title,
    String? text,
    int? updatedAt,
    int? createdAt,
  }) =>
      UserNote(
        bookIndex: bookIndex,
        chapter: chapter,
        verse: verse,
        id: id ?? this.id,
        title: title ?? this.title,
        text: text ?? this.text,
        updatedAt: updatedAt ?? this.updatedAt,
        createdAt: createdAt ?? this.createdAt,
      );

  static UserNote fromMap(Map<String, Object?> m) => UserNote(
        id: m['id'] as int?,
        bookIndex: m['book'] as int,
        chapter: m['chapter'] as int,
        verse: m['verse'] as int,
        title: (m['title'] as String?) ?? '',
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
  '#ffe0b3', // orange
  '#e6d9f5', // violet
  '#c9ecf0', // turquoise
  '#e5e5e5', // gris
  '#ffd1d1', // rouge clair
  '#fff59d', // jaune vif
  '#b3e0ff', // bleu ciel
  '#e1bee7', // mauve
  '#ffccbc', // saumon
  '#b2dfdb', // menthe
  '#dcedc8', // lime
  '#cfd8dc', // ardoise
];