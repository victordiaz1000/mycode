import 'chapter.dart';

class BookMetadata {
  final String signification;
  final String auteur;
  final String theme;
  final String date;

  const BookMetadata({
    required this.signification,
    required this.auteur,
    required this.theme,
    required this.date,
  });

  factory BookMetadata.fromJson(Map<String, dynamic> json) => BookMetadata(
        signification: json['signification'] as String? ?? '',
        auteur: json['auteur'] as String? ?? '',
        theme: json['theme'] as String? ?? '',
        date: json['date'] as String? ?? '',
      );
}

class BibleBook {
  /// 1-based numeric index in BYM file order (01..66).
  final int number;
  final String book;
  final String abbreviation;
  final BookMetadata metadata;
  final String introduction;
  final List<Chapter> chapters;

  const BibleBook({
    required this.number,
    required this.book,
    required this.abbreviation,
    required this.metadata,
    required this.introduction,
    this.chapters = const [],
  });

  /// Parses a book from its raw JSON map. [number] is the file index (01..66).
  factory BibleBook.fromJson(Map<String, dynamic> json, {required int number}) =>
      BibleBook(
        number: number,
        book: json['book'] as String? ?? '',
        abbreviation: json['abbreviation'] as String? ?? '',
        metadata: BookMetadata.fromJson(
            json['metadata'] as Map<String, dynamic>? ?? {}),
        introduction: json['introduction'] as String? ?? '',
        chapters: (json['chapters'] as List<dynamic>? ?? [])
            .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  bool get isLoaded => chapters.isNotEmpty;
}
