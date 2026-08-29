import '../data/version_repository.dart';
import 'tab_group.dart';

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

  /// Reading tabs only: the last verse the reader was on, so a restored tab
  /// comes back at the reading position instead of verse 1. Null when the tab
  /// was opened but never scrolled past the top.
  final int? verse;

  /// Version active in that tab. Each tab keeps its own reading version so a new
  /// tab can inherit the previous one instead of silently resetting to BYM.
  final String versionCode;

  /// Pinned tabs stay at the head of the switcher grid (maquette ⋯ menu).
  bool pinned;

  /// Id of the [TabGroup] this tab belongs to (maquette v2), or null when
  /// ungrouped. The group itself lives in [TabManager]; a dangling id is
  /// tolerated and treated as ungrouped.
  final String? groupId;

  StudyTab({
    required this.id,
    required this.kind,
    required this.title,
    this.bookIndex,
    this.chapter,
    this.verse,
    this.versionCode = VersionRepository.embeddedCode,
    this.pinned = false,
    this.groupId,
  });

  bool get isReading => kind == StudyTabKind.reading;
  bool get isHome => kind == StudyTabKind.home;

  StudyTab copyWith({
    String? title,
    int? verse,
    bool? pinned,
    String? versionCode,
    String? groupId,
  }) => StudyTab(
        id: id,
        kind: kind,
        title: title ?? this.title,
        bookIndex: bookIndex,
        chapter: chapter,
        verse: verse ?? this.verse,
        versionCode: versionCode ?? this.versionCode,
        pinned: pinned ?? this.pinned,
        groupId: groupId ?? this.groupId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'book': bookIndex,
        'chapter': chapter,
        'verse': verse,
        'versionCode': versionCode,
        'pinned': pinned,
        'groupId': groupId,
      };

  factory StudyTab.fromJson(Map<String, dynamic> json) {
    var kind = StudyTabKind.values.asNameMap()[json['kind']] ??
        StudyTabKind.reading;
    final book = (json['book'] as num?)?.toInt();
    // A tab persisted by an older build could be a dictionary entry — that
    // content no longer lives in the reading tabs, so it is restored as a
    // home tab rather than a reading tab with no book (which would crash).
    if (kind == StudyTabKind.reading && book == null) kind = StudyTabKind.home;
    return StudyTab(
      id: json['id'] as String,
      kind: kind,
      title: json['title'] as String? ?? '',
      bookIndex: book,
      chapter: (json['chapter'] as num?)?.toInt(),
      verse: (json['verse'] as num?)?.toInt(),
      versionCode: json['versionCode'] as String? ??
          VersionRepository.embeddedCode,
      pinned: json['pinned'] as bool? ?? false,
      groupId: json['groupId'] as String?,
    );
  }
}
