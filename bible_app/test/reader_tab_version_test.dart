import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';

/// The version being read belongs to the **tab**, not to the app.
///
/// The bug this file guards: every open tab lives in the shell's `IndexedStack`,
/// so all their readers are mounted at once and all listened to
/// `AppPreferences.revision`. The reading version travelled through that shared
/// preference — so picking a version in tab 3 (and, since *any* preference save
/// bumps the revision, even changing the font size there) dragged tabs 1 and 2
/// onto it, and the choice made in a tab was lost as soon as another tab spoke.
///
/// Both versions used here are embedded, so nothing goes through `dart:io`:
/// `LibraryStore.installed()` reads shared_preferences alone and the two texts
/// come from the fake bundles.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    VersionRepository.clearCache();
  });

  /// The reading bar of the tab at [index] — every tab of the `IndexedStack`
  /// builds its own, so a bare `find.text('BYM')` would match several.
  ///
  /// `skipOffstage: false` throughout: `IndexedStack` keeps the tabs that are
  /// not on screen mounted but hidden, and the finders skip hidden widgets by
  /// default — the whole point here is to read a tab that is precisely *not*
  /// the one being looked at.
  Finder inBarOfTab(int index, String text) => find.descendant(
        of: find.byType(ReaderActionsBar, skipOffstage: false).at(index),
        matching: find.text(text, skipOffstage: false),
        skipOffstage: false,
      );

  /// The version pill of the tab on screen — the only bar that can be tapped,
  /// the hidden ones not being hit-testable.
  Finder activeVersionPill(String code) => find.descendant(
        of: find.byType(ReaderActionsBar),
        matching: find.text(code),
      );

  /// Two reading tabs on Genèse 1 and 2, the second one active.
  Future<TabManager> pumpTwoTabs(WidgetTester tester) async {
    final manager = TabManager();
    manager.openReading(1, 1);
    manager.openReading(1, 2);
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(initialManager: manager)),
    );
    await tester.pumpAndSettle();
    return manager;
  }

  /// Picks [name] in the « Version » sheet of the tab currently on screen.
  Future<void> pickVersionInActiveTab(
    WidgetTester tester, {
    required String activeCode,
    required String name,
  }) async {
    await tester.tap(activeVersionPill(activeCode));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(name), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    await tester.ensureVisible(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('a version picked in a tab leaves the other tabs alone',
      (tester) async {
    final manager = await pumpTwoTabs(tester);

    await pickVersionInActiveTab(tester,
        activeCode: 'BYM', name: 'Bible Segond 1910 + Strongs');

    expect(manager.tabs[1].versionCode, 'LSGS',
        reason: 'the active tab took the pick');
    expect(manager.tabs[0].versionCode, 'BYM',
        reason: 'the tab already open must not follow');
    expect(inBarOfTab(0, 'BYM'), findsOneWidget);
    expect(inBarOfTab(1, 'LSGS'), findsOneWidget);
  });

  testWidgets('a tab pick does not move the default version', (tester) async {
    // « Version de lecture par défaut » is what a NEW tab starts from. Writing
    // it from a tab is what bumped the revision every other tab listened to.
    await pumpTwoTabs(tester);

    await pickVersionInActiveTab(tester,
        activeCode: 'BYM', name: 'Bible Segond 1910 + Strongs');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('reading.versionCode'), isNot('LSGS'));
  });

  testWidgets('the version survives a round trip through another tab',
      (tester) async {
    final manager = await pumpTwoTabs(tester);
    await pickVersionInActiveTab(tester,
        activeCode: 'BYM', name: 'Bible Segond 1910 + Strongs');

    manager.activate(0);
    await tester.pumpAndSettle();
    manager.activate(1);
    await tester.pumpAndSettle();

    expect(manager.tabs[1].versionCode, 'LSGS');
    expect(inBarOfTab(1, 'LSGS'), findsOneWidget);
    expect(inBarOfTab(0, 'BYM'), findsOneWidget);
  });

  testWidgets('a display preference changed in one tab moves no version',
      (tester) async {
    // The sharpest form of the bug: the reader adopted the shared version code
    // on EVERY revision bump, and a font size is saved through the same
    // `AppPreferences.save()`.
    final manager = await pumpTwoTabs(tester);
    await pickVersionInActiveTab(tester,
        activeCode: 'BYM', name: 'Bible Segond 1910 + Strongs');

    final prefs = await AppPreferences.load();
    prefs.fontSize = ReadingTextSize.small.fontSize;
    await prefs.save();
    await tester.pumpAndSettle();

    expect(manager.tabs[0].versionCode, 'BYM');
    expect(inBarOfTab(0, 'BYM'), findsOneWidget);
    expect(inBarOfTab(1, 'LSGS'), findsOneWidget,
        reason: 'the active tab keeps its own version too');
  });

  testWidgets('changing the default version does not retrofit open tabs',
      (tester) async {
    // What the Réglages screen does. Its label reads « par défaut »: it seeds
    // the next tab, it does not re-translate the ones being read.
    final manager = await pumpTwoTabs(tester);

    final prefs = await AppPreferences.load();
    prefs.versionCode = 'LSGS';
    await prefs.save();
    await tester.pumpAndSettle();

    expect(manager.tabs[0].versionCode, 'BYM');
    expect(manager.tabs[1].versionCode, 'BYM');
    expect(inBarOfTab(0, 'BYM'), findsOneWidget);
    expect(inBarOfTab(1, 'BYM'), findsOneWidget);
  });

  testWidgets('a blank tab records its version on itself', (tester) async {
    // The ＋ tab has its own version slot; it used to write the shared
    // preference instead, which pulled every open tab along.
    final manager = TabManager();
    manager.openReading(1, 1);
    manager.openHome();
    await tester.pumpWidget(
      MaterialApp(home: ReaderScreen(initialManager: manager)),
    );
    await tester.pumpAndSettle();

    await pickVersionInActiveTab(tester,
        activeCode: 'BYM', name: 'Bible Segond 1910 + Strongs');

    expect(manager.tabs[1].versionCode, 'LSGS');
    expect(manager.tabs[0].versionCode, 'BYM',
        reason: 'the reading tab keeps what it was on');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('reading.versionCode'), isNot('LSGS'));
  });
}
