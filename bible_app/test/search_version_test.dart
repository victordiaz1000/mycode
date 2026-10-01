import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/search_engine.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/search_screen.dart';

import 'reader_version_test.dart' show FakeStore;
import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';
import 'version_repository_test.dart' show getbibleBook;

/// Searching a version the reader downloaded — the other half of décision 6.
///
/// The whole file works over an in-memory [FakeStore]: a real [LibraryStore]
/// reads through `dart:io`, mute inside the fake-async zone of `testWidgets`,
/// and [FulltextIndex] is pointed at it with [FulltextIndex.useVersions].
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Points every index at [store], and drops whatever was indexed before.
  VersionRepository useStore(FakeStore store) {
    final versions = VersionRepository(store: store);
    VersionRepository.clearCache();
    FulltextIndex.useVersions(versions);
    return versions;
  }

  /// Darby with Genèse (1) and Lévitique (3) — a partial download, holes and
  /// all, which is the normal state of one in progress.
  FakeStore darbyPartial() => FakeStore({
        'DBY': {1: getbibleBook(1), 3: getbibleBook(3)},
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    LexiconIndex.instance.clearIndex();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    FulltextIndex.useAmbientVersions();
    VersionRepository.clearCache();
  });

  group('FulltextIndex over a downloaded version', () {
    test('indexes the books on the device, and reports how many', () async {
      useStore(darbyPartial());

      final index = FulltextIndex.of('DBY');
      final found = await index.search('téléchargé');

      expect(index.indexedBooks, 2, reason: 'Genèse and Lévitique only');
      expect(found.indexedBooks, 2, reason: 'carried on the results');
      expect(found.matches, isNotEmpty);
      expect(found.matches.map((m) => m.bookIndex).toSet(), {1, 3});
      expect(found.matches.first.text, contains('Texte téléchargé'));
    });

    test('a missing book is a hole, not an empty index', () async {
      useStore(darbyPartial());

      // Exode (2) sits between two downloaded books and must simply be absent
      // — indexing had to survive the gap rather than stop at it.
      final found = await FulltextIndex.of('DBY').search('téléchargé');
      expect(found.matches.any((m) => m.bookIndex == 2), isFalse);
      expect(found.total, greaterThan(0));
    });

    test('the BYM text is not reachable through the downloaded index',
        () async {
      useStore(darbyPartial());

      // The point of BookNotDownloaded: no embedded verse under a DBY label.
      final found = await FulltextIndex.of('DBY').search('Verset de test');
      expect(found.matches, isEmpty);
    });

    test('the embedded index still covers the whole Bible', () async {
      useStore(darbyPartial());

      final found = await FulltextIndex.instance.search('Verset de test');

      expect(FulltextIndex.instance.code, VersionRepository.embeddedCode);
      expect(found.indexedBooks, bookCatalog.length);
      expect(found.matches, isNotEmpty);
    });

    test('forget() stops a deleted version from answering from memory',
        () async {
      final store = darbyPartial();
      useStore(store);
      expect((await FulltextIndex.of('DBY').search('téléchargé')).matches,
          isNotEmpty);

      // Exactly what the Bibliothèque does on « Supprimer ». **Both** caches
      // have to go: dropping the index alone would let it rebuild itself from
      // the books [VersionRepository] still holds parsed, and the deleted
      // version would keep answering with no file left on the device.
      store.books.remove('DBY');
      VersionRepository.forget('DBY');
      FulltextIndex.forget('DBY');

      final after = await FulltextIndex.of('DBY').search('téléchargé');
      expect(after.matches, isEmpty);
      expect(after.indexedBooks, 0);
    });

    test('only two downloaded indexes stay in memory', () async {
      useStore(FakeStore({
        'DBY': {1: getbibleBook(1)},
        'LSG': {1: getbibleBook(1)},
        'MAR': {1: getbibleBook(1)},
      }));

      final darby = FulltextIndex.of('DBY');
      await darby.search('téléchargé');
      expect(darby.isBuilt, isTrue);

      FulltextIndex.of('LSG');
      FulltextIndex.of('MAR'); // third one: the oldest is dropped

      expect(identical(FulltextIndex.of('DBY'), darby), isFalse,
          reason: '~31 000 verses each — they cannot all stay resident');
      expect(FulltextIndex.of('DBY').isBuilt, isFalse);
    });

    test('the embedded index never counts against that cap', () async {
      useStore(FakeStore({
        'DBY': {1: getbibleBook(1)},
        'LSG': {1: getbibleBook(1)},
        'MAR': {1: getbibleBook(1)},
      }));

      final bym = FulltextIndex.instance;
      await bym.search('Verset de test');

      FulltextIndex.of('DBY');
      FulltextIndex.of('LSG');
      FulltextIndex.of('MAR');

      expect(identical(FulltextIndex.instance, bym), isTrue,
          reason: 'it is the default source of every search');
      expect(FulltextIndex.instance.isBuilt, isTrue);
    });
  });

  group('SearchEngine on a downloaded version', () {
    /// An engine over [store], reaching neither sqflite nor the real files.
    SearchEngine engineOver(FakeStore store) => SearchEngine(
          ambientDatabase: false,
          versions: useStore(store),
        );

    /// Passages only: the notes and études sources are another test's subject,
    /// and leaving them in would make the group list depend on them.
    Future<SearchOutcome> passages(
      SearchEngine engine,
      String query, {
      String code = 'DBY',
    }) =>
        engine.search(
          query,
          filters: SearchFilters(versionCode: code),
          categories: {SearchCategory.passages},
        );

    test('the hits carry the downloaded text and the version code', () async {
      final outcome = await passages(engineOver(darbyPartial()), 'téléchargé');

      final group = outcome.groups.single;
      expect(group.category, SearchCategory.passages);
      expect(group.hits.first.badge, 'DBY');
      expect(group.hits.first.subtitle, contains('Texte téléchargé'));
    });

    test('a partial version says what it covers', () async {
      final outcome = await passages(engineOver(darbyPartial()), 'téléchargé');

      // Without this line a short list reads as « ce mot n'est pas dans la
      // Bible » when it only means « pas dans les livres présents ».
      expect(outcome.coverageNote, contains('DBY'));
      expect(outcome.coverageNote, contains('2/${bookCatalog.length}'));
    });

    test('the BYM carries no coverage note', () async {
      final outcome =
          await passages(engineOver(darbyPartial()), 'Verset', code: 'BYM');

      expect(outcome.groups.single.hits, isNotEmpty);
      expect(outcome.coverageNote, isNull,
          reason: 'the embedded version is whole by construction');
    });

    test('a reference inside the download is served in that version',
        () async {
      final outcome = await passages(engineOver(darbyPartial()), 'Genèse 1:1');

      final reference = outcome.reference;
      expect(reference, isNotNull);
      expect(reference!.versionCode, 'DBY');
      expect(reference.text, 'Texte téléchargé 1:1.');
    });

    test('a reference outside it falls back to the BYM, and says so', () async {
      // Exode is not downloaded. Refusing the verse outright would hide a text
      // we can serve; serving it under a « DBY » badge would be a lie.
      final outcome = await passages(engineOver(darbyPartial()), 'Exode 1:1');

      final reference = outcome.reference;
      expect(reference, isNotNull);
      expect(reference!.versionCode, VersionRepository.embeddedCode);
      expect(reference.text, contains('Verset de test'));
    });
  });

  group('the « Version » menu of the search screen', () {
    /// The screen wired to [store], with an engine reading the same one.
    Widget app(FakeStore store) => MaterialApp(
          home: SearchScreen(
            onOpenReading: (_, _, {verse}) {},
            engine: SearchEngine(ambientDatabase: false, versions: useStore(store)),
            store: store,
          ),
        );

    /// Types [query] and lets the 300 ms debounce and the search complete.
    Future<void> type(WidgetTester tester, String query) async {
      await tester.enterText(find.byType(TextField), query);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    Future<void> openVersionMenu(WidgetTester tester) async {
      await tester.tap(find.text('Version'));
      await tester.pumpAndSettle();
    }

    /// Taps a version row of the open menu, bringing it into view first.
    Future<void> tapVersion(WidgetTester tester, String code) async {
      await tester.ensureVisible(find.text(code));
      await tester.pumpAndSettle();
      await tester.tap(find.text(code));
      await tester.pumpAndSettle();
    }

    testWidgets('it shows what the device holds of each version',
        (tester) async {
      await tester.pumpWidget(app(darbyPartial()));
      await tester.pumpAndSettle();
      await openVersionMenu(tester);

      expect(find.text('Bible Darby · 2/${bookCatalog.length} livres'),
          findsOneWidget);
    });

    testWidgets('a version with nothing downloaded is not offered',
        (tester) async {
      // It used to be listed, greyed, and answer « à télécharger depuis la
      // Bibliothèque » — a row that could not do anything, in a menu whose only
      // job is to choose. Ten of the twelve catalogue entries were like that.
      await tester.pumpWidget(app(darbyPartial()));
      await tester.pumpAndSettle();
      await openVersionMenu(tester);

      expect(find.text('Bible Segond 1910'), findsNothing);
      expect(find.text('LSG'), findsNothing);
      expect(find.textContaining('à télécharger depuis la Bibliothèque'),
          findsNothing);
      expect(find.text('BYM'), findsWidgets,
          reason: 'the embedded version is always searchable');
      expect(find.text('DBY'), findsOneWidget);
    });

    testWidgets('the menu ends on the way to the Bibliothèque', (tester) async {
      // What is left out has to stay reachable, or nothing on this screen says
      // the other translations exist at all.
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(
          onOpenReading: (_, _, {verse}) {},
          engine: SearchEngine(
              ambientDatabase: false, versions: useStore(FakeStore({}))),
          store: FakeStore({}),
          onOpenLibrary: () => opened++,
        ),
      ));
      await tester.pumpAndSettle();
      await openVersionMenu(tester);

      // 15 catalogue entries, BYM and LSGS the only searchable ones here, so 13
      // are left to fetch — the count moved when CHO and KJF became downloadable.
      expect(find.text('14 autres versions à télécharger'), findsOneWidget);
      await tester.tap(find.text('Bibliothèque'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('the footer does not change the version filter', (tester) async {
      // It is the last row of a radio menu: it must lead out, not select.
      await tester.pumpWidget(app(darbyPartial()));
      await tester.pumpAndSettle();
      await openVersionMenu(tester);
      await tapVersion(tester, 'DBY');
      expect(find.text('DBY'), findsOneWidget);

      await openVersionMenu(tester);
      await tester.tap(find.text('Bibliothèque'));
      await tester.pumpAndSettle();

      expect(find.text('DBY'), findsOneWidget,
          reason: 'the pick made just before must survive the footer tap');
    });

    testWidgets('picking a downloaded version swaps the text searched',
        (tester) async {
      await tester.pumpWidget(app(darbyPartial()));
      await tester.pumpAndSettle();

      // The word exists in the Darby files only, so the BYM finds nothing.
      await type(tester, 'téléchargé');
      expect(find.textContaining('Texte téléchargé'), findsNothing);

      await openVersionMenu(tester);
      await tapVersion(tester, 'DBY');

      expect(find.textContaining('Texte téléchargé'), findsWidgets);
      expect(find.textContaining('2/${bookCatalog.length} livres téléchargés'),
          findsOneWidget,
          reason: 'the coverage banner explains the short list');
    });

    testWidgets('a version deleted since the last search falls back to BYM',
        (tester) async {
      final store = darbyPartial();
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();
      await openVersionMenu(tester);
      await tapVersion(tester, 'DBY');
      expect(find.text('DBY'), findsOneWidget);

      // The Bibliothèque removed it while the screen sat in the IndexedStack.
      store.removeVersion('DBY');
      FulltextIndex.forget('DBY');
      await tester.pumpAndSettle();
      await type(tester, 'verset');

      expect(find.text('DBY'), findsNothing,
          reason: 'a filter pointing at nothing would search nothing');
      expect(find.textContaining('Verset de test'), findsWidgets);
    });

    testWidgets('a version downloaded since the tab opened becomes searchable',
        (tester) async {
      final store = FakeStore({});
      await tester.pumpWidget(app(store));
      await tester.pumpAndSettle();

      // The Bibliothèque finishes Darby while this tab sits in the IndexedStack.
      store.landBook('DBY', 1, getbibleBook(1));
      await tester.pumpAndSettle();

      await openVersionMenu(tester);
      expect(find.text('DBY'), findsOneWidget,
          reason: 'the menu must not show the registry as it was at initState');
      await tapVersion(tester, 'DBY');
      expect(find.text('DBY'), findsOneWidget);
    });
  });
}
