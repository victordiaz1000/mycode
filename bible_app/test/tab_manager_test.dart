import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/models/study_tab.dart';
import 'package:bible_app/models/tab_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('openReading opens a tab and focuses it', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(12, 40);

    expect(m.count, 2);
    expect(m.activeIndex, 1);
    expect(m.active!.title, 'És. 40');
    expect(m.tabs.first.title, 'Ge. 1');
  });

  test('openReading focuses an existing tab instead of duplicating', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(12, 40);
    m.openReading(1, 1);

    expect(m.count, 2);
    expect(m.activeIndex, 0);
  });

  test('openHome adds a home tab', () {
    final m = TabManager();
    final idx = m.openHome();
    expect(idx, 0);
    expect(m.active!.isHome, isTrue);
    expect(m.active!.title, 'Nouvel onglet');
  });

  test('close moves tab into recently-closed queue (max 8)', () {
    final m = TabManager();
    for (var b = 1; b <= 10; b++) {
      m.openReading(b, 1);
    }
    // close 9 tabs: queue 8, the oldest one is dropped.
    for (var i = 0; i < 9; i++) {
      m.close(m.activeIndex);
    }
    expect(m.count, 1);
    expect(m.recentlyClosed.length, 8);
    // Most recently closed first.
    expect(m.recentlyClosed.first.bookIndex, 2);
    expect(m.recentlyClosed.last.bookIndex, 9);
  });

  test('closing active tab focuses the next one', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(2, 1);
    m.openReading(3, 1);
    m.close(2);
    expect(m.activeIndex, 1);
    expect(m.active!.bookIndex, 2);
  });

  test('reopen restores a closed tab and focuses it', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.close(0);
    expect(m.count, 0);
    final idx = m.reopen();
    expect(idx, 0);
    expect(m.count, 1);
    expect(m.active!.bookIndex, 1);
    expect(m.recentlyClosed, isEmpty);
  });

  test('duplicate copies the tab and focuses the copy', () {
    final m = TabManager();
    m.openReading(1, 1);
    final idx = m.duplicate(0);
    expect(idx, 1);
    expect(m.count, 2);
    expect(m.tabs[1].bookIndex, 1);
    expect(m.tabs[1].id, isNot(m.tabs[0].id));
  });

  test('replaceActiveReading moves the active tab without adding one', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(12, 40);
    final id = m.active!.id;

    final idx = m.replaceActiveReading(43, 3);

    expect(idx, 1);
    expect(m.count, 2, reason: 'no tab is created');
    expect(m.activeIndex, 1);
    expect(m.active!.bookIndex, 43);
    expect(m.active!.chapter, 3);
    expect(m.active!.title, 'Jn. 3');
    expect(m.active!.id, id, reason: 'same tab, moved');
    // The other tab is untouched.
    expect(m.tabs[0].title, 'Ge. 1');
  });

  test('replaceActiveReading keeps the pin and turns a home tab into reading',
      () {
    final m = TabManager();
    m.openHome();
    m.togglePin(0);

    m.replaceActiveReading(1, 2);

    expect(m.count, 1);
    expect(m.active!.isReading, isTrue);
    expect(m.active!.pinned, isTrue);
    expect(m.active!.title, 'Ge. 2');
  });

  test('replaceActiveReading opens a tab when none is active', () {
    final m = TabManager();
    expect(m.activeIndex, -1);

    final idx = m.replaceActiveReading(1, 1);

    expect(idx, 0);
    expect(m.count, 1);
    expect(m.active!.title, 'Ge. 1');
  });

  test('replaceActiveReading may land on an already-open chapter', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(1, 2);

    // Stepping back from Ge. 2 to Ge. 1 duplicates the position on purpose:
    // the reader stays in its own tab instead of jumping to the other one.
    m.replaceActiveReading(1, 1);

    expect(m.count, 2);
    expect(m.activeIndex, 1);
    expect(m.tabs.map((t) => t.title), ['Ge. 1', 'Ge. 1']);
  });

  test('togglePin flips the pinned flag', () {
    final m = TabManager();
    m.openReading(1, 1);
    expect(m.tabs[0].pinned, isFalse);
    m.togglePin(0);
    expect(m.tabs[0].pinned, isTrue);
    m.togglePin(0);
    expect(m.tabs[0].pinned, isFalse);
  });

  test('updateTabVerse records the reading position on the tab', () {
    final m = TabManager();
    final idx = m.openReading(1, 1);
    final id = m.tabs[idx].id;

    m.updateTabVerse(id, 24);
    expect(m.tabs[idx].verse, 24);

    // Unknown tab → ignored, no crash.
    m.updateTabVerse('ghost', 5);
    expect(m.tabs[idx].verse, 24);
  });

  test('openReading carries a restored verse into a fresh tab', () {
    final m = TabManager();
    final idx = m.openReading(12, 40, verse: 16);
    expect(m.tabs[idx].verse, 16);
    // The tab title stays the chapter reference, the verse is positional.
    expect(m.tabs[idx].title, 'És. 40');
  });

  test('replaceActiveReading keeps the verse unless a new one is given', () {
    final m = TabManager();
    final idx = m.openReading(1, 1, verse: 10);
    final id = m.tabs[idx].id;

    // Stepping to the next chapter without a verse: the position resets (a new
    // chapter has no "last verse" yet — the reader reports it on first scroll).
    m.replaceActiveReading(1, 2);
    expect(m.tabs[idx].verse, isNull);
    expect(m.tabs[idx].id, id);

    // Replacing with a verse records it straight away.
    m.replaceActiveReading(1, 3, verse: 7);
    expect(m.tabs[idx].verse, 7);
  });

  test('duplicate copies the verse and the version', () {
    final m = TabManager();
    m.openReading(1, 1, verse: 5);
    m.updateTabVersion(m.tabs[0].id, 'LSGS');

    final idx = m.duplicate(0);

    expect(m.tabs[idx].verse, 5);
    expect(m.tabs[idx].versionCode, 'LSGS');
  });

  test('a persisted verse survives a reload', () async {
    final m = TabManager();
    m.openReading(43, 3, verse: 16);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await m.load();

    expect(m.count, 1);
    expect(m.tabs[0].bookIndex, 43);
    expect(m.tabs[0].verse, 16);
  });

  test('closeAll moves every tab to recently closed', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(2, 1);
    m.closeAll();
    expect(m.count, 0);
    expect(m.activeIndex, -1);
    expect(m.recentlyClosed.length, 2);
  });

  test('persists and restores tabs + active index', () async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(43, 3);
    m.activate(0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await m.load();

    expect(m.count, 2);
    expect(m.activeIndex, 0);
    expect(m.tabs[1].bookIndex, 43);
    expect(m.tabs[1].chapter, 3);
  });

  test('a persisted dictionary tab is restored as a home tab, never crashes', () {
    // A build that still hosted dictionary tabs in the reader could have saved
    // one: reading tabs no longer hold dictionary content, so the tab must come
    // back as a home tab instead of a reading tab with no book.
    final tab = StudyTab.fromJson(const {
      'id': 'd1',
      'kind': 'dictionary',
      'title': 'ABBA',
      'dictionaryTerm': 'ABBA',
      'dictionaryDefinition': 'Définition.',
      'versionCode': 'BYM',
      'pinned': false,
    });

    expect(tab.isHome, isTrue);
    expect(tab.bookIndex, isNull);
    expect(tab.title, 'ABBA');
  });

  // ---- Groups (maquette v2) ----

  test('createGroup + assignTabToGroup tag tabs with the group id', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(12, 40);

    final group = m.createGroup(name: 'Lecture du soir', color: TabGroupColor.violet);
    m.assignTabToGroup(0, group.id);

    expect(m.tabs[0].groupId, group.id);
    expect(m.tabs[1].groupId, isNull);
    expect(m.groups.single.name, 'Lecture du soir');
  });

  test('assigning a dangling group id is normalized to ungrouped', () {
    final m = TabManager();
    m.openReading(1, 1);

    m.assignTabToGroup(0, 'g-ghost');

    expect(m.tabs[0].groupId, isNull);
  });

  test('ungrouping clears the membership', () {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'G', color: TabGroupColor.bleu);
    m.assignTabToGroup(0, g.id);

    m.assignTabToGroup(0, null);

    expect(m.tabs[0].groupId, isNull);
    // Empty and unreferenced → pruned.
    expect(m.groups, isEmpty);
  });

  test('rename / recolor / collapse update the group in place', () {
    final m = TabManager();
    final g = m.createGroup(name: 'Étude', color: TabGroupColor.bleu);

    m.renameGroup(g.id, 'Le berger');
    m.setGroupColor(g.id, TabGroupColor.vert);
    m.toggleGroupCollapsed(g.id);

    expect(m.groups.single.name, 'Le berger');
    expect(m.groups.single.color, TabGroupColor.vert);
    expect(m.groups.single.collapsed, isTrue);
  });

  test('closeGroup sends members to recently closed keeping their group', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(19, 23);
    m.openReading(40, 1); // active, ungrouped
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);
    m.assignTabToGroup(1, g.id);

    m.closeGroup(g.id);

    expect(m.count, 1);
    expect(m.active!.bookIndex, 40);
    expect(m.recentlyClosed.length, 2);
    // The queue keeps the group id so each tab can be restored into it.
    expect(m.recentlyClosed.every((t) => t.groupId == g.id), isTrue);
    // Still referenced by the closed tabs → not dissolved yet.
    expect(m.groups.single.id, g.id);
  });

  test('reopen restores a tab into its original group', () {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);
    m.closeGroup(g.id);

    m.reopen();

    expect(m.active!.groupId, g.id);
    expect(m.groups.single.id, g.id);
  });

  test('clearing the recently-closed queue dissolves dead groups', () {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);
    m.close(0);
    expect(m.groups, isNotEmpty); // kept for restore

    m.clearRecentlyClosed();

    expect(m.groups, isEmpty);
  });

  test('closing the active grouped tab refocuses a surviving tab', () {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(2, 1);
    final g = m.createGroup(name: 'G', color: TabGroupColor.rose);
    m.assignTabToGroup(0, g.id);
    m.assignTabToGroup(1, g.id);
    m.activate(0); // active inside the doomed group

    m.closeGroup(g.id);

    expect(m.count, 0);
    expect(m.activeIndex, -1);
  });

  test('groups persist across a reload', () async {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'Psaumes', color: TabGroupColor.vert);
    m.assignTabToGroup(0, g.id);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await m.load();

    expect(m.groups.single.name, 'Psaumes');
    expect(m.groups.single.color, TabGroupColor.vert);
    expect(m.tabs.single.groupId, g.id);
  });

  test('duplicate keeps the source tab group', () {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'G', color: TabGroupColor.rouge);
    m.assignTabToGroup(0, g.id);

    final idx = m.duplicate(0);

    expect(m.tabs[idx].groupId, g.id);
  });
}
