import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/study_tab.dart';
import 'book_catalog.dart';
import 'reading_history.dart';

/// Chrome-style tab manager (maquette v1.1).
///
/// Holds the open study tabs, the active tab, and a "recently closed" queue
/// (max [maxClosed]). State is persisted via shared_preferences so that all
/// open tabs are restored on next launch.
class TabManager extends ChangeNotifier {
  static const int maxClosed = 8;
  static const String _kTabsKey = 'tabs.open';
  static const String _kActiveKey = 'tabs.active';

  /// Visited chapters, fed by [openReading] and read by the home screen.
  TabManager({ReadingHistory? history})
      : history = history ?? ReadingHistory();

  final ReadingHistory history;

  List<StudyTab> _tabs = [];
  int _activeIndex = -1;
  final List<StudyTab> _recentlyClosed = [];

  List<StudyTab> get tabs => List.unmodifiable(_tabs);
  int get count => _tabs.length;
  int get activeIndex => _activeIndex;
  bool get hasTabs => _tabs.isNotEmpty;
  List<StudyTab> get recentlyClosed => List.unmodifiable(_recentlyClosed);

  StudyTab? get active =>
      _activeIndex >= 0 && _activeIndex < _tabs.length
          ? _tabs[_activeIndex]
          : null;

  /// True when a tab for this reading position already exists.
  bool isOpenReading(int bookIndex, int chapter) =>
      _tabs.any((t) =>
          t.isReading && t.bookIndex == bookIndex && t.chapter == chapter);

  /// Opens (or focuses) a reading tab for [bookIndex]/[chapter].
  /// Returns the index of the tab to show.
  int openReading(int bookIndex, int chapter) {
    history.record(bookIndex, chapter);
    final existing = _tabs.indexWhere((t) =>
        t.isReading && t.bookIndex == bookIndex && t.chapter == chapter);
    if (existing >= 0) {
      _activeIndex = existing;
      notifyListeners();
      return existing;
    }
    final entry = catalogEntry(bookIndex);
    final tab = StudyTab(
      id: _nextId(),
      kind: StudyTabKind.reading,
      title: '${entry.abbreviation} $chapter',
      bookIndex: bookIndex,
      chapter: chapter,
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _persist();
    notifyListeners();
    return _activeIndex;
  }

  /// Replaces the reading position of the **active** tab in place, without
  /// adding one: the « Livres » pill and the previous/next chapter arrows
  /// navigate the current tab, only the ＋ button of the strip creates a new
  /// one. Falls back to [openReading] when no tab is active.
  ///
  /// The tab keeps its id and its pinned flag — it is the same tab, moved.
  int replaceActiveReading(int bookIndex, int chapter) {
    final index = _activeIndex;
    if (index < 0 || index >= _tabs.length) {
      return openReading(bookIndex, chapter);
    }
    history.record(bookIndex, chapter);
    final current = _tabs[index];
    _tabs[index] = StudyTab(
      id: current.id,
      kind: StudyTabKind.reading,
      title: '${catalogEntry(bookIndex).abbreviation} $chapter',
      bookIndex: bookIndex,
      chapter: chapter,
      pinned: current.pinned,
    );
    _persist();
    notifyListeners();
    return index;
  }

  /// Adds a home ("new tab") tab and makes it active.
  int openHome() {
    final tab = StudyTab(
      id: _nextId(),
      kind: StudyTabKind.home,
      title: 'Nouvel onglet',
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _persist();
    notifyListeners();
    return _activeIndex;
  }

  void activate(int index) {
    if (index < 0 || index >= _tabs.length || index == _activeIndex) return;
    _activeIndex = index;
    _persist();
    notifyListeners();
  }

  /// Closes the tab at [index], moving it into the recently-closed queue
  /// (max [maxClosed]). If it was active, focus the next tab.
  void close(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs.removeAt(index);
    _recentlyClosed.insert(0, tab);
    if (_recentlyClosed.length > maxClosed) _recentlyClosed.removeLast();
    if (_activeIndex >= _tabs.length) _activeIndex = _tabs.length - 1;
    if (index < _activeIndex) _activeIndex--;
    if (_tabs.isEmpty) _activeIndex = -1;
    _persist();
    notifyListeners();
  }

  /// Reopens the most recently closed tab, or the tab at [closedIndex].
  int reopen({int closedIndex = 0}) {
    if (closedIndex < 0 || closedIndex >= _recentlyClosed.length) return -1;
    final tab = _recentlyClosed.removeAt(closedIndex);
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _persist();
    notifyListeners();
    return _activeIndex;
  }

  void closeAll() {
    for (final t in _tabs.reversed) {
      _recentlyClosed.insert(0, t);
    }
    if (_recentlyClosed.length > maxClosed) {
      _recentlyClosed.removeRange(maxClosed, _recentlyClosed.length);
    }
    _tabs.clear();
    _activeIndex = -1;
    _persist();
    notifyListeners();
  }

  void clearRecentlyClosed() {
    _recentlyClosed.clear();
    _persist();
    notifyListeners();
  }

  /// Duplicates the tab at [index] right after it and focuses the copy.
  int duplicate(int index) {
    if (index < 0 || index >= _tabs.length) return -1;
    final src = _tabs[index];
    final copy = StudyTab(
      id: _nextId(),
      kind: src.kind,
      title: src.title,
      bookIndex: src.bookIndex,
      chapter: src.chapter,
      pinned: src.pinned,
    );
    _tabs.insert(index + 1, copy);
    _activeIndex = index + 1;
    _persist();
    notifyListeners();
    return _activeIndex;
  }

  void togglePin(int index) {
    if (index < 0 || index >= _tabs.length) return;
    _tabs[index] = _tabs[index].copyWith(pinned: !_tabs[index].pinned);
    _persist();
    notifyListeners();
  }

  // ---- Persistence ----

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kTabsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _tabs = list
            .map((e) => StudyTab.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _tabs = [];
      }
    } else {
      _tabs = [];
    }
    _activeIndex = sp.getInt(_kActiveKey) ?? -1;
    if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.isEmpty ? -1 : _tabs.length - 1;
    }
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        _kTabsKey, jsonEncode([for (final t in _tabs) t.toJson()]));
    await sp.setInt(_kActiveKey, _activeIndex);
  }

  String _nextId() => 't-${DateTime.now().microsecondsSinceEpoch}-${_tabs.length}';
}
