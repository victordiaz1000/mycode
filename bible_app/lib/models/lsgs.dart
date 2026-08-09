class LsgsToken {
  final String text;
  final String? strong;

  const LsgsToken({required this.text, this.strong});

  factory LsgsToken.fromJson(Map<String, dynamic> json) => LsgsToken(
        text: json['text'] as String? ?? '',
        strong: json['strong'] as String?,
      );
}

class LsgsVerse {
  final int verse;
  final List<LsgsToken> tokens;

  const LsgsVerse({required this.verse, this.tokens = const []});

  factory LsgsVerse.fromJson(Map<String, dynamic> json) => LsgsVerse(
        verse: (json['verse'] as num?)?.toInt() ?? 0,
        tokens: (json['tokens'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LsgsToken.fromJson)
            .toList(),
      );
}

class LsgsChapter {
  final int chapter;
  final List<LsgsVerse> verses;

  const LsgsChapter({required this.chapter, this.verses = const []});

  factory LsgsChapter.fromJson(Map<String, dynamic> json) => LsgsChapter(
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
        verses: (json['verses'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LsgsVerse.fromJson)
            .toList(),
      );
}

class LsgsBook {
  final int bymIndex;
  final String book;
  final String abbreviation;
  final String osisId;
  final List<LsgsChapter> chapters;

  const LsgsBook({
    required this.bymIndex,
    required this.book,
    required this.abbreviation,
    required this.osisId,
    this.chapters = const [],
  });

  factory LsgsBook.fromJson(Map<String, dynamic> json) => LsgsBook(
        bymIndex: (json['bym_index'] as num?)?.toInt() ?? 0,
        book: json['book'] as String? ?? '',
        abbreviation: json['abbreviation'] as String? ?? '',
        osisId: json['osis_id'] as String? ?? '',
        chapters: (json['chapters'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(LsgsChapter.fromJson)
            .toList(),
      );
}
