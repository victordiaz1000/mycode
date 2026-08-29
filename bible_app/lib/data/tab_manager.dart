import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/study_tab.dart';
import '../models/tab_group.dart';
import 'book_catalog.dart';
import 'reading_history.dart';
import 'version_repository.dart';

/// Chrome-style tab manager (maquette v2).
///
/// Holds the open study tabs, the active tab, named/color [TabGroup]s and a
/// "recently closed" queue (max [maxClosed]). State is persisted via
/// shared_preferences so that all open tabs are restored on next launch.
class TabManager extends ChangeNotifier {
  static const int maxClosed = 8;
  static const String _kTabsKey = 'tabs.open';
  static const String _kActiveKey = 'tabs.active';
  static const String _kGroupsKey = 'tabs.groups';

  /// Visited chapters, fed by [openReading] and read by the home screen.
  TabManager({ReadingHistory? history})
      : history = history ?? ReadingHistory();

  final ReadingHistory history;

  List<StudyTab> _tabs = [];
  int _activeIndex = -1;
  final List<StudyTab> _recentlyClosed = [];
  List<TabGroup> _groups = [];

  List<StudyTab> get tabs => List.unmodifiable(_tabs);
  int get count => _tabs.length;
  int get activeIndex => _activeIndex;
  bool get hasTabs => _tabs.isNotEmpty;
  List<StudyTab> get recentlyClosed => List.unmodifiable(_recentlyClosed);

  /// Open group definitions. A group survives with zero members only while a
  /// recently-closed tab still references it — that is what lets « Rouvrir »
  /// restore the original group (maquette v2 rule), while a group closed as a
  /// whole is dissolved once nothing refers to it anymore.
  List<TabGroup> get groups => List.unmodifiable(_groups);

  TabGroup? groupById(String? id) =>
      id == null ? null : _groups.where((g) => g.id == id).firstOrNull;

  StudyTab? get active =>
      _activeIndex >= 0 && _activeIndex < _tabs.length
          ? _tabs[_activeIndex]
          : null;

  /// True when a tab for this reading position already exists.
  bool isOpenReading(int bookIndex, int chapter) =>
      _tabs.any((t) =>
          t.isReading && t.bookIndex == bookIndex && t.chapter == chapter);

  String _preferredVersionCode(String? explicitCode) {
    if (explicitCode != null && explicitCode.isNotEmpty) return explicitCode;
    return active?.versionCode ?? VersionRepository.embeddedCode;
  }

  /// Opens (or focuses) a reading tab for [bookIndex]/[chapter].
  /// Returns the index of the tab to show.
  int openReading(int bookIndex, int chapter,
      {String? versionCode, int? verse}) {
    history.record(bookIndex, chapter);
    final existing = _tabs.indexWhere((t) =>
        t.isReading && t.bookIndex == bookIndex && t.chapter == chapter);
    if (existing >= 0) {
      // Réutiliser ≠ ignorer la demande : un verset explicitement demandé
      // (référence de note, résultat de recherche, occurrence Strong)
      // REMPLACE la vieille position de l'onglet, sinon elle ressuscite au
      // prochain montage/restauration. Null (focus simple) ne touche à rien.
      final current = _tabs[existing];
      if (verse != null && current.verse != verse) {
        _tabs[existing] = current.copyWith(verse: verse);
        _persist();
      }
      _activeIndex = existing;
      notifyListeners();
      return existing;
    }
    final entry = catalogEntry(bookIndex);
    final resolvedCode = _preferredVersionCode(versionCode);
    final tab = StudyTab(
      id: _nextId(),
      kind: StudyTabKind.reading,
      title: '${entry.abbreviation} $chapter',
      bookIndex: bookIndex,
      chapter: chapter,
      verse: verse,
      versionCode: resolvedCode,
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
  int replaceActiveReading(int bookIndex, int chapter,
      {String? versionCode, int? verse}) {
    final index = _activeIndex;
    if (index < 0 || index >= _tabs.length) {
      return openReading(bookIndex, chapter,
          versionCode: versionCode, verse: verse);
    }
    history.record(bookIndex, chapter);
    final current = _tabs[index];
    _tabs[index] = StudyTab(
      id: current.id,
      kind: StudyTabKind.reading,
      title: '${catalogEntry(bookIndex).abbreviation} $chapter',
      bookIndex: bookIndex,
      chapter: chapter,
      verse: verse,
      versionCode: versionCode ?? current.versionCode,
      pinned: current.pinned,
      groupId: current.groupId,
    );
    _persist();
    notifyListeners();
    return index;
  }

  /// Adds a home ("new tab") tab and makes it active.
  int openHome({String? versionCode}) {
    final tab = StudyTab(
      id: _nextId(),
      kind: StudyTabKind.home,
      title: 'Nouvel onglet',
      versionCode: _preferredVersionCode(versionCode),
    );
    _tabs.add(tab);
    _activeIndex = _tabs.length - 1;
    _persist();
    notifyListeners();
    return _activeIndex;
  }

  void updateTabVersion(String tabId, String versionCode) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    _tabs[index] = _tabs[index].copyWith(versionCode: versionCode);
    _persist();
    notifyListeners();
  }

  /// Records the verse the reader is on for the tab [tabId], so the position
  /// survives a cold restart. Silently ignored for unknown tabs (a tab closed
  /// while its reader widget was still mounted).
  void updateTabVerse(String tabId, int verse) {
    final index = _tabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    if (_tabs[index].verse == verse) return;
    _tabs[index] = _tabs[index].copyWith(verse: verse);
    _persist();
    notifyListeners();
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
    // Groups kept alive only by the queue are now unreferenced.
    _pruneGroups();
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
      verse: src.verse,
      versionCode: src.versionCode,
      pinned: src.pinned,
      groupId: src.groupId,
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

  // ---- Groups (maquette v2) ----

  /// Creates a group and returns it. Empty groups are allowed transiently
  /// (the dialog creates the group, then the caller assigns a tab); a group
  /// left empty and unreferenced is pruned on the next mutation.
  TabGroup createGroup({required String name, required TabGroupColor color}) {
    final group = TabGroup(id: _nextGroupId(), name: name, color: color);
    _groups.add(group);
    _persist();
    notifyListeners();
    return group;
  }

  void renameGroup(String groupId, String name) {
    final g = _groups.where((g) => g.id == groupId).firstOrNull;
    if (g == null || g.name == name) return;
    g.name = name;
    _persist();
    notifyListeners();
  }

  void setGroupColor(String groupId, TabGroupColor color) {
    final g = _groups.where((g) => g.id == groupId).firstOrNull;
    if (g == null || g.color == color) return;
    g.color = color;
    _persist();
    notifyListeners();
  }

  void toggleGroupCollapsed(String groupId) {
    final g = _groups.where((g) => g.id == groupId).firstOrNull;
    if (g == null) return;
    g.collapsed = !g.collapsed;
    _persist();
    notifyListeners();
  }

  /// Puts the tab at [index] in [groupId], or removes it from its group when
  /// [groupId] is null. A dangling id (group already dissolved) is normalized
  /// to ungrouped.
  void assignTabToGroup(int index, String? groupId) {
    if (index < 0 || index >= _tabs.length) return;
    final resolved =
        groupId == null || _groups.any((g) => g.id == groupId) ? groupId : null;
    if (_tabs[index].groupId == resolved) return;
    // Rebuilt by hand rather than copyWith: copyWith cannot set a field back
    // to null (« ?? » pattern), and leaving here means leaving the group.
    final t = _tabs[index];
    _tabs[index] = StudyTab(
      id: t.id,
      kind: t.kind,
      title: t.title,
      bookIndex: t.bookIndex,
      chapter: t.chapter,
      verse: t.verse,
      versionCode: t.versionCode,
      pinned: t.pinned,
      groupId: resolved,
    );
    _pruneGroups();
    _persist();
    notifyListeners();
  }

  /// Closes every tab of the group at once: they join « Fermés récemment »
  /// keeping their group id (so each one can be restored into the group), and
  /// the group definition dissolves unless recently-closed tabs still
  /// reference it (maquette v2 rule).
  void closeGroup(String groupId) {
    final members = <int>[
      for (var i = 0; i < _tabs.length; i++)
        if (_tabs[i].groupId == groupId) i,
    ];
    if (members.isEmpty) return;
    final activeTabId =
        (_activeIndex >= 0 && _activeIndex < _tabs.length)
            ? _tabs[_activeIndex].id
            : null;
    for (final i in members.reversed) {
      final tab = _tabs.removeAt(i);
      _recentlyClosed.insert(0, tab);
    }
    while (_recentlyClosed.length > maxClosed) {
      _recentlyClosed.removeLast();
    }
    if (_tabs.isEmpty) {
      _activeIndex = -1;
    } else if (activeTabId != null) {
      // Follow the same tab when it survived, otherwise focus the tail.
      final kept = _tabs.indexWhere((t) => t.id == activeTabId);
      _activeIndex = kept >= 0 ? kept : _tabs.length - 1;
    }
    _pruneGroups();
    _persist();
    notifyListeners();
  }

  /// Drops group definitions with no open tab and no recently-closed tab
  /// referring to them — this is what makes a closed group's color and name
  /// available again while preserving restore-with-group.
  void _pruneGroups() {
    final referenced = <String>{
      for (final t in _recentlyClosed)
        if (t.groupId != null) t.groupId!,
    };
    _groups = [
      for (final g in _groups)
        if (_tabs.any((t) => t.groupId == g.id) || referenced.contains(g.id))
          g,
    ];
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
    final rawGroups = sp.getString(_kGroupsKey);
    if (rawGroups != null && rawGroups.isNotEmpty) {
      try {
        final list = jsonDecode(rawGroups) as List<dynamic>;
        _groups = list
            .map((e) => TabGroup.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _groups = [];
      }
    } else {
      _groups = [];
    }
    // Tabs restored from an older build may reference dissolved groups.
    _tabs = [
      for (final t in _tabs)
        t.groupId == null || _groups.any((g) => g.id == t.groupId)
            ? t
            : StudyTab(
                id: t.id,
                kind: t.kind,
                title: t.title,
                bookIndex: t.bookIndex,
                chapter: t.chapter,
                verse: t.verse,
                versionCode: t.versionCode,
                pinned: t.pinned,
              ),
    ];
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
    await sp.setString(_kGroupsKey,
        jsonEncode([for (final g in _groups) g.toJson()]));
  }

  String _nextId() => 't-${DateTime.now().microsecondsSinceEpoch}-${_tabs.length}';
  String _nextGroupId() =>
      'g-${DateTime.now().microsecondsSinceEpoch}-${_groups.length}';
}
