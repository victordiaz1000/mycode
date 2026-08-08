import 'verse.dart';

class Chapter {
  final int chapter;
  final List<Verse> verses;

  const Chapter({
    required this.chapter,
    required this.verses,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        chapter: (json['chapter'] as num?)?.toInt() ?? 0,
        verses: (json['verses'] as List<dynamic>? ?? [])
            .map((e) => Verse.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
