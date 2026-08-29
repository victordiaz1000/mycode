import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/ecran_comparer.dart';
import 'package:bible_app/screens/home_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'reader_version_test.dart' show FakeStore;
import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'version_repository_test.dart' show getbibleBook;

/// The « Comparer » screen (maquette `interfaces/ecran_comparer.dart`): the
/// current verse shown across every version present on the device — BYM and
/// LSGS embedded, then the downloaded translations that hold the book — each as
/// a card that a chip can show or hide.
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

  Future<void> pumpComparer(
    WidgetTester tester, {
    LibraryStore? store,
    int bookIndex = 1,
    int chapter = 1,
    int verse = 1,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: ComparerScreen(
        bookIndex: bookIndex,
        chapter: chapter,
        verseNumber: verse,
        store: store ?? FakeStore({}),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the verse across the embedded BYM and LSGS translations',
      (tester) async {
    await pumpComparer(tester);

    expect(find.text('Genèse 1:1'), findsOneWidget,
        reason: 'the header names the compared reference');
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget,
        reason: 'the BYM text is there');
    expect(find.text('AA H7225'), findsOneWidget,
        reason: 'the LSGS text is there (Strong codes included)');
    expect(find.text('Bible de Yehoshoua Ha Mashiah'), findsOneWidget);
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
    expect(find.text('2 versions affichées'), findsOneWidget);
  });

  testWidgets('includes a downloaded version that holds the book',
      (tester) async {
    await pumpComparer(tester, store: FakeStore({'DBY': {1: getbibleBook(1)}}));

    expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
        reason: 'the downloaded Darby text joins the comparison');
    expect(find.text('Bible Darby'), findsOneWidget);
    expect(find.text('3 versions affichées'), findsOneWidget);
  });

  testWidgets('skips a downloaded version missing the book', (tester) async {
    // DBY holds Exode (2); the compared verse is in Genèse (1).
    await pumpComparer(tester, store: FakeStore({'DBY': {2: getbibleBook(2)}}));

    expect(find.text('Texte téléchargé 1:1.'), findsNothing);
    expect(find.text('Bible Darby'), findsNothing,
        reason: 'no text, no card — a version without the book has nothing '
            'to compare');
    expect(find.text('2 versions affichées'), findsOneWidget);
  });

  testWidgets('a chip toggles its translation card on and off', (tester) async {
    await pumpComparer(tester, store: FakeStore({'DBY': {1: getbibleBook(1)}}));
    expect(find.text('Texte téléchargé 1:1.'), findsOneWidget);

    // The chip is the first « DBY » in the tree (the card badge comes later).
    await tester.tap(find.text('DBY').first);
    await tester.pumpAndSettle();
    expect(find.text('Texte téléchargé 1:1.'), findsNothing,
        reason: 'the card hides with its chip');
    expect(find.text('2 versions affichées'), findsOneWidget);

    await tester.tap(find.text('DBY').first);
    await tester.pumpAndSettle();
    expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
        reason: 'tapping again brings the card back');
    expect(find.text('3 versions affichées'), findsOneWidget);
  });

  testWidgets('turning every version off explains itself', (tester) async {
    await pumpComparer(tester);

    await tester.tap(find.text('BYM').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('LSGS').first);
    await tester.pumpAndSettle();

    expect(find.text('Sélectionnez au moins une version à comparer.'),
        findsOneWidget);
    expect(find.text('0 version affichée'), findsOneWidget);
  });

  testWidgets('the Comparer action of the study sheet opens this screen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          store: FakeStore({}),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The book header (metadata + introduction) is tall: the first verse sits
    // below the fold on the small default surface, scroll it into view.
    await tester.dragUntilVisible(
      find.text('Verset de test Ge. 1:1.'),
      find.descendant(
        of: find.byType(ChapterReader),
        matching: find.byType(ListView),
      ),
      const Offset(0, -200),
    );
    await tester.ensureVisible(find.text('Verset de test Ge. 1:1.'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verset de test Ge. 1:1.'));
    await tester.pumpAndSettle();

    // The sheet grew: 16 colour dots push the action chips below the test
    // screen edge, and scrollUntilVisible stops as soon as the Wrap builds the
    // chip even when it is off-screen — ensureVisible does the final scroll.
    await tester.ensureVisible(find.text('Comparer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Comparer'));
    await tester.pumpAndSettle();

    expect(find.byType(ComparerScreen), findsOneWidget,
        reason: 'the action is wired, not a « bientôt disponible » snackbar');
    expect(find.text('Genèse 1:1'), findsOneWidget,
        reason: 'the compared verse is the one that was being read');
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('the home Comparer shortcut opens the screen on the last read',
      (tester) async {
    // L'historique ne garde que le chapitre, pas le verset : la puce compare
    // depuis le début du chapitre repris (Jean 1 — chapitre 1 pour que le faux
    // livre de test, limité à 2 chapitres, le contienne).
    SharedPreferences.setMockInitialValues({
      'history.recent': jsonEncode([
        {'book': 43, 'chapter': 1, 'at': 1700000000000},
      ]),
    });

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        manager: TabManager(),
        onSelectDestination: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Comparer'));
    await tester.pumpAndSettle();

    expect(find.byType(ComparerScreen), findsOneWidget);
    expect(find.text('Jean 1:1'), findsOneWidget,
        reason: 'the compare opens on the resumed chapter, verse 1');
    expect(find.text('Verset de test Jn. 1:1.'), findsOneWidget);
  });
}
