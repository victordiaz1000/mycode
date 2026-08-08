import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'book_catalog.dart';

/// One visited reading position, most recent first in [ReadingHistory].
class ReadingEntry {
  final int bookIndex;
  final int chapter;

  /// Epoch milliseconds of the visit.
  final int at;

  const ReadingEntry({
    required this.bookIndex,
    required this.chapter,
    required this.at,
  });

  /// "Ge. 1" — same label as the tab title.
  String get label => '${catalogEntry(bookIndex).abbreviation} $chapter';

  String get bookName => catalogEntry(bookIndex).name;

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(at);

  bool samePosition(int book, int chapterNumber) =>
      bookIndex == book && chapter == chapterNumber;

  Map<String, dynamic> toJson() =>
      {'book': bookIndex, 'chapter': chapter, 'at': at};

  static ReadingEntry? fromJson(Map<String, dynamic> json) {
    final book = (json['book'] as num?)?.toInt();
    final chapter = (json['chapter'] as num?)?.toInt();
    if (book == null || chapter == null || book < 1 || book > 66) return null;
    return ReadingEntry(
      bookIndex: book,
      chapter: chapter,
      at: (json['at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Recently visited chapters, newest first — feeds the home screen's
/// « Reprendre la lecture » card and « Études récentes » list.
///
/// Stored in shared_preferences (a single JSON list, [maxEntries] max).
/// Revisiting a chapter moves it back to the top instead of duplicating it.
class ReadingHistory {
  static const String key = 'history.recent';
  static const int maxEntries = 12;

  Future<List<ReadingEntry>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          ?ReadingEntry.fromJson(e as Map<String, dynamic>),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// The position to resume from, or null on a fresh install.
  Future<ReadingEntry?> last() async {
    final entries = await load();
    return entries.isEmpty ? null : entries.first;
  }

  /// Records a visit to [bookIndex]/[chapter] at [now] (defaults to the clock).
  Future<void> record(int bookIndex, int chapter, {DateTime? now}) async {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final entries = List<ReadingEntry>.from(await load())
      ..removeWhere((e) => e.samePosition(bookIndex, chapter))
      ..insert(0,
          ReadingEntry(bookIndex: bookIndex, chapter: chapter, at: stamp));
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString(key, jsonEncode([for (final e in entries) e.toJson()]));
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(key);
  }
}
