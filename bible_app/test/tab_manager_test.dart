import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/tab_manager.dart';

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
}
