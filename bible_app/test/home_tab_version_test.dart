import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';

import 'support/fake_bible_bundle.dart';

/// The « Version » sheet of a tab that holds no chapter yet.
///
/// The bug this file guards: the two home pages built a [ReaderActionsBar]
/// without `installedVersions`, taking the `const {}` default. The sheet read
/// every downloaded translation as absent and answered « à télécharger depuis
/// la Bibliothèque » for versions already on the device — the reader was sent
/// to the Bibliothèque to fetch what it had.
///
/// Only `installed()` is exercised here, and it reads the registry from
/// shared_preferences alone — no `dart:io`, so it answers under `testWidgets`
/// where `loadBook` would hang.
void main() {
  /// A registry holding [books] of [code], as the Bibliothèque would leave it.
  void deviceHolds(String code, List<int> books) =>
      SharedPreferences.setMockInitialValues({
        'library.installed': '{"$code":$books}',
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(LocalRepository.useRootBundle);

  Finder inBar(String text) => find.descendant(
        of: find.byType(ReaderActionsBar),
        matching: find.text(text),
      );

  /// The no-tab home — the page the app opens on with nothing restored.
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> openVersionSheet(WidgetTester tester, String activeCode) async {
    await tester.tap(inBar(activeCode));
    await tester.pumpAndSettle();
  }

  /// Taps a row of the open sheet, scrolling it into view first.
  Future<void> tapVersionRow(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(find.text(name), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    // scrollUntilVisible stops as soon as the row exists, which can leave it
    // flush with the bottom edge where the tap would miss.
    await tester.ensureVisible(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('a downloaded version is selectable, not sent to the Bibliothèque',
      (tester) async {
    deviceHolds('DBY', [1, 2, 3]);
    await pumpHome(tester);

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    expect(find.textContaining('à télécharger depuis la Bibliothèque'),
        findsNothing,
        reason: 'the device holds it — the bar used to ignore the registry');
    expect(inBar('DBY'), findsOneWidget, reason: 'the pill follows the pick');
  });

  testWidgets('the sheet reports what the device holds', (tester) async {
    deviceHolds('DBY', [1, 2]);
    await pumpHome(tester);
    await openVersionSheet(tester, 'BYM');

    await tester.scrollUntilVisible(find.text('Bible Darby'), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    expect(find.text('Téléchargée en partie · 2/66 livres'), findsOneWidget);
  });

  testWidgets('the pick is recorded for the chapter opened next',
      (tester) async {
    // The pills read « version » then « livres » — picking the version first
    // has to mean something, or the choice is lost at the next tap.
    deviceHolds('DBY', [1]);
    await pumpHome(tester);

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('reading.versionCode'), 'DBY',
        reason: 'ChapterReader reads this key at initState');
  });

  testWidgets('a version with nothing on the device still says so',
      (tester) async {
    await pumpHome(tester);

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    expect(find.text('DBY — à télécharger depuis la Bibliothèque.'),
        findsOneWidget);
    expect(inBar('BYM'), findsOneWidget, reason: 'the pill does not move');
  });

  testWidgets('a version under copyright answers « bientôt disponible »',
      (tester) async {
    await pumpHome(tester);

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Segond 21');

    expect(find.text('S21 — bientôt disponible.'), findsOneWidget);
  });

  testWidgets('a download landing while the home tab sits idle is picked up',
      (tester) async {
    // Same IndexedStack trap as the reader and the search screen: the home page
    // is never rebuilt from scratch, so it has to listen to the registry.
    await pumpHome(tester);
    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');
    expect(find.text('DBY — à télécharger depuis la Bibliothèque.'),
        findsOneWidget);

    SharedPreferences.setMockInitialValues({'library.installed': '{"DBY":[1]}'});
    LibraryStore.revision.value++;
    await tester.pumpAndSettle();

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    expect(inBar('DBY'), findsOneWidget,
        reason: 'the registry moved while the tab was open');
  });

  testWidgets('deleting the recorded version drops the pill back to BYM',
      (tester) async {
    deviceHolds('DBY', [1]);
    await pumpHome(tester);
    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');
    expect(inBar('DBY'), findsOneWidget);

    // 🗑 in the Bibliothèque: the next chapter would fall back anyway, so the
    // pill must not keep naming a version with no files.
    SharedPreferences.setMockInitialValues({});
    LibraryStore.revision.value++;
    await tester.pumpAndSettle();

    expect(inBar('BYM'), findsOneWidget);
    expect(inBar('DBY'), findsNothing);
  });

  testWidgets('the last row of the sheet clears the Android navigation bar',
      (tester) async {
    // The sheet is sized as a fraction of the screen, gesture bar included: a
    // flat bottom padding drew KJV — the last catalogue entry — underneath it.
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    await openVersionSheet(tester, 'BYM');
    await tester.scrollUntilVisible(
        find.text('King James Version (anglais)'), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final navBarTop = screenHeight - 96 / tester.view.devicePixelRatio;
    expect(
        tester.getBottomLeft(find.text('King James Version (anglais)')).dy,
        lessThanOrEqualTo(navBarTop),
        reason: 'the row must be tappable, not behind the system bar');
  });
}
