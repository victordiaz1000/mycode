import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';
import 'package:bible_app/widgets/tab_strip.dart';

import 'support/fake_bible_bundle.dart';

/// The gold counter inside the strip (an exact "N", never a tab title).
Finder tabCounter(String n) =>
    find.descendant(of: find.byType(TabStrip), matching: find.text(n));

/// Opens [book] chapter [chapter] through the reference pill of the reading
/// action bar. The bar's books sheet (an accordion) replaced the old
/// full-screen sections listing on the home / no-tab pages. [pill] is the label
/// the pill currently carries: « Livres » with no chapter open, the reference
/// (`Genèse 1`) inside a reading tab.
Future<void> openChapterViaLivres(
  WidgetTester tester,
  String book,
  String chapter, {
  String pill = 'Livres',
}) async {
  await tester.tap(find.text(pill));
  await tester.pumpAndSettle();
  // Unfold the book, then pick the chapter tile from its grid.
  await tester.tap(find.text(book));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(Wrap), matching: find.text(chapter)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Real assets would stall every pumpAndSettle (rootBundle I/O cannot
    // complete inside the fake-async zone of testWidgets).
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(LocalRepository.useRootBundle);

  testWidgets('ReaderScreen shows the new-tab home when empty',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    await tester.pumpAndSettle();

    // The empty state has no AppBar at all: the reading action bar is the only
    // navigation surface (the ＋ button lives in the strip, once tabs exist).
    expect(find.byType(AppBar), findsNothing);
    // Navigation now goes through the reading action bar (« Livres » pill), not
    // the old full-screen sections listing.
    expect(find.byType(ReaderActionsBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReaderActionsBar),
        matching: find.text('Livres'),
      ),
      findsOneWidget,
    );
    expect(find.byType(TabStrip), findsNothing);
  });

  testWidgets('injected manager: pre-opened tab is shown with strip',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(initialManager: m)));
    await tester.pumpAndSettle();

    expect(find.byType(TabStrip), findsOneWidget);
    expect(find.text('Ge. 1'), findsOneWidget);
    expect(tabCounter('1'), findsOneWidget);
    expect(find.byType(ChapterReader), findsOneWidget);
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('Reading a chapter opens it in a tab', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    await tester.pumpAndSettle();

    await openChapterViaLivres(tester, 'Genèse', '1');

    expect(find.byType(TabStrip), findsOneWidget);
    expect(find.text('Ge. 1'), findsOneWidget);
    expect(tabCounter('1'), findsOneWidget);
    // The books sheet was popped, the chapter is rendered in the tab.
    expect(find.byType(ChapterReader), findsOneWidget);
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('a second chapter opens a second tab, reopening focuses',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(initialManager: m)));
    await tester.pumpAndSettle();

    // ＋ → home tab, then navigate to Genèse chapter 2 via « Livres ». The
    // fresh « Nouvel onglet » is *filled* by the pick, it does not stay behind.
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await openChapterViaLivres(tester, 'Genèse', '2');

    expect(m.tabs.map((t) => t.title), ['Ge. 1', 'Ge. 2']);
    expect(m.activeIndex, 1);
    expect(tabCounter('2'), findsOneWidget);

    // Re-opening Ge. 1 focuses the existing tab instead of adding one.
    m.openReading(1, 1);
    await tester.pumpAndSettle();

    expect(m.count, 2);
    expect(m.activeIndex, 0);
    expect(tabCounter('2'), findsOneWidget);
  });

  testWidgets('the Livres pill navigates the active tab in place',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(initialManager: m)));
    await tester.pumpAndSettle();

    final id = m.active!.id;
    // Inside a reading tab the pill carries the current reference.
    await openChapterViaLivres(tester, 'Exode', '2', pill: 'Genèse 1');

    expect(m.count, 1, reason: 'the pill moves the tab, it does not add one');
    expect(m.active!.title, 'Ex. 2');
    expect(m.active!.id, id);
    expect(find.text('Verset de test Ex. 2:1.'), findsOneWidget);
    expect(tabCounter('1'), findsOneWidget);
  });

  testWidgets('the chapter arrows navigate the active tab in place',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: ReaderScreen(initialManager: m)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(m.count, 1);
    expect(m.active!.title, 'Ge. 2');
    expect(find.text('Verset de test Ge. 2:1.'), findsOneWidget);
  });
}
