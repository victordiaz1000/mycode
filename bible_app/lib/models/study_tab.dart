/// Kind of content hosted in a tab (Chrome-style study tab).
enum StudyTabKind { reading, home }

/// A single open study tab (maquette v1.1 — gestion d'onglets).
///
/// - [StudyTabKind.reading] : a book/chapter reading session.
/// - [StudyTabKind.home] : the Chrome-style new-tab page.
class StudyTab {
  final String id;
  final StudyTabKind kind;
  final String title;

  /// Reading tabs only: BYM book index (1..66) and chapter (1-based).
  final int? bookIndex;
  final int? chapter;

  /// Pinned tabs stay at the head of the switcher grid (maquette ⋯ menu).
  bool pinned;

  StudyTab({
    required this.id,
    required this.kind,
    required this.title,
    this.bookIndex,
    this.chapter,
    this.pinned = false,
  });

  bool get isReading => kind == StudyTabKind.reading;
  bool get isHome => kind == StudyTabKind.home;

  StudyTab copyWith({String? title, bool? pinned}) => StudyTab(
        id: id,
        kind: kind,
        title: title ?? this.title,
        bookIndex: bookIndex,
        chapter: chapter,
        pinned: pinned ?? this.pinned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'book': bookIndex,
        'chapter': chapter,
        'pinned': pinned,
      };

  factory StudyTab.fromJson(Map<String, dynamic> json) => StudyTab(
        id: json['id'] as String,
        kind: StudyTabKind.values.asNameMap()[json['kind']] ??
            StudyTabKind.reading,
        title: json['title'] as String? ?? '',
        bookIndex: (json['book'] as num?)?.toInt(),
        chapter: (json['chapter'] as num?)?.toInt(),
        pinned: json['pinned'] as bool? ?? false,
      );
}
