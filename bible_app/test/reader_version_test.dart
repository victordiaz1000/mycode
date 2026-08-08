import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';

import 'support/fake_bible_bundle.dart';
import 'version_repository_test.dart' show getbibleBook;

/// The downloaded books, in memory.
///
/// A real [LibraryStore] reads through `dart:io`, which never completes inside
/// the fake-async zone of `testWidgets` — the reader would wait forever on its
/// first `pumpAndSettle`. Only [installed] and [loadBook] are used on the
/// reading path, so those two are all that need answering.
class FakeStore extends LibraryStore {
  FakeStore(this.books);

  /// `code` → BYM index → getbible payload.
  final Map<String, Map<int, Map<String, dynamic>>> books;

  @override
  Future<Map<String, InstalledVersion>> installed() async => {
        for (final entry in books.entries)
          entry.key:
              InstalledVersion(code: entry.key, books: entry.value.keys.toSet()),
      };

  @override
  Future<Map<String, dynamic>?> loadBook(String code, int bookIndex) async =>
      books[code]?[bookIndex];

  /// Simulates the Bibliothèque finishing a book while a screen is alive.
  ///
  /// Mirrors what the real `saveBook` does — write, then bump the revision —
  /// without touching `dart:io`, which never answers under `testWidgets`.
  void landBook(String code, int bookIndex, Map<String, dynamic> payload) {
    books.putIfAbsent(code, () => {})[bookIndex] = payload;
    LibraryStore.revision.value++;
  }

  /// Simulates 🗑 in the Bibliothèque.
  void removeVersion(String code) {
    books.remove(code);
    VersionRepository.forget(code);
    LibraryStore.revision.value++;
  }
}

void main() {
  /// Darby with Genèse only — the normal state of a partial download, and what
  /// makes the missing-book panel reachable (Exode is registered nowhere).
  FakeStore darbyGenesisOnly() => FakeStore({
        'DBY': {1: getbibleBook(1)},
      });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    required LibraryStore store,
    int bookIndex = 1,
    int chapter = 1,
    VoidCallback? onOpenLibrary,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: bookIndex,
          chapter: chapter,
          store: store,
          onOpenLibrary: onOpenLibrary,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Opens the « Version » sheet from the reading bar.
  Future<void> openVersionSheet(WidgetTester tester, String activeCode) async {
    await tester.tap(find.descendant(
        of: find.byType(ReaderActionsBar), matching: find.text(activeCode)));
    await tester.pumpAndSettle();
  }

  /// Taps a version row in the open sheet, scrolling it into view first.
  Future<void> tapVersionRow(WidgetTester tester, String name) async {
    await tester.scrollUntilVisible(find.text(name), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('the bar announces BYM, and the BYM text is on screen',
      (tester) async {
    await pumpReader(tester, store: FakeStore({}));

    expect(
      find.descendant(
          of: find.byType(ReaderActionsBar), matching: find.text('BYM')),
      findsOneWidget,
    );
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('picking a downloaded version swaps the text and the pill',
      (tester) async {
    await pumpReader(tester, store: darbyGenesisOnly());

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
        reason: 'the verses now come from the downloaded files');
    expect(find.text('Verset de test Ge. 1:1.'), findsNothing);
    expect(
      find.descendant(
          of: find.byType(ReaderActionsBar), matching: find.text('DBY')),
      findsOneWidget,
    );
  });

  testWidgets('the choice is written to the preferences', (tester) async {
    await pumpReader(tester, store: darbyGenesisOnly());
    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    final prefs = await AppPreferencesProbe.versionCode();
    expect(prefs, 'DBY');
  });

  testWidgets('a version saved but since deleted falls back to BYM',
      (tester) async {
    // The Bibliothèque removed DBY between two runs: the stored choice points
    // at nothing, and the reader must not open on an error panel.
    SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});

    await pumpReader(tester, store: FakeStore({}));

    expect(
      find.descendant(
          of: find.byType(ReaderActionsBar), matching: find.text('BYM')),
      findsOneWidget,
    );
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('a book missing from the version says so instead of faking it',
      (tester) async {
    // DBY holds Genèse only; the reader opens on Exode (2).
    SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});

    await pumpReader(tester, store: darbyGenesisOnly(), bookIndex: 2);

    expect(find.textContaining('n\'est pas téléchargé en DBY'), findsOneWidget);
    expect(find.text('Lire en BYM'), findsOneWidget);
    // The point of the panel: no BYM text under the DBY label.
    expect(find.text('Verset de test Ex. 1:1.'), findsNothing);
  });

  testWidgets('« Lire en BYM » brings the embedded text back', (tester) async {
    SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
    await pumpReader(tester, store: darbyGenesisOnly(), bookIndex: 2);

    await tester.tap(find.text('Lire en BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Verset de test Ex. 1:1.'), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(ReaderActionsBar), matching: find.text('BYM')),
      findsOneWidget,
    );
    expect(find.text('Lire en BYM'), findsNothing);
  });

  testWidgets('a version with nothing downloaded cannot be picked',
      (tester) async {
    await pumpReader(tester, store: FakeStore({}));

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    expect(find.text('DBY — à télécharger depuis la Bibliothèque.'),
        findsOneWidget);
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget,
        reason: 'the reading stays on BYM');
  });

  testWidgets('the « à télécharger » snackbar leads to the Bibliothèque',
      (tester) async {
    var opened = 0;
    await pumpReader(tester,
        store: FakeStore({}), onOpenLibrary: () => opened++);

    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'Bible Darby');

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('the missing-book panel offers the Bibliothèque', (tester) async {
    SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
    var opened = 0;
    await pumpReader(tester,
        store: darbyGenesisOnly(), bookIndex: 2, onOpenLibrary: () => opened++);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('without a shell the panel only names the Bibliothèque',
      (tester) async {
    // Standalone ChapterScreen / tests: no destination to switch to, so the
    // button is absent rather than dead.
    SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
    await pumpReader(tester, store: darbyGenesisOnly(), bookIndex: 2);

    expect(find.text('Lire en BYM'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Bibliothèque'), findsNothing);
  });

  testWidgets('the sheet shows what the device holds of each version',
      (tester) async {
    await pumpReader(tester, store: darbyGenesisOnly());
    await openVersionSheet(tester, 'BYM');

    await tester.scrollUntilVisible(find.text('Bible Darby'), 200,
        scrollable: find.descendant(
            of: find.byKey(const Key('versionSheetList')),
            matching: find.byType(Scrollable)));
    expect(find.text('Téléchargée en partie · 1/66 livres'), findsOneWidget);
  });

  group('a download landing while the reader is open', () {
    testWidgets('makes the version selectable without leaving the reader',
        (tester) async {
      // The bug this guards: the reader lives in the tab shell's IndexedStack,
      // so `initState` never runs again. It kept the library map read at
      // startup, answered « à télécharger » for a version the Bibliothèque had
      // just installed, and the user bounced between the two screens forever.
      final store = FakeStore({});
      await pumpReader(tester, store: store);

      await openVersionSheet(tester, 'BYM');
      await tapVersionRow(tester, 'Bible Darby');
      expect(find.text('DBY — à télécharger depuis la Bibliothèque.'),
          findsOneWidget,
          reason: 'nothing downloaded yet');

      store.landBook('DBY', 1, getbibleBook(1));
      await tester.pumpAndSettle();

      await openVersionSheet(tester, 'BYM');
      await tapVersionRow(tester, 'Bible Darby');

      expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
          reason: 'the reader saw the download without being rebuilt');
      expect(
        find.descendant(
            of: find.byType(ReaderActionsBar), matching: find.text('DBY')),
        findsOneWidget,
      );
    });

    testWidgets('replaces the missing-book panel with the text', (tester) async {
      // Reading Exode in DBY, which holds Genèse only; the download reaches
      // Exode while the panel is on screen.
      SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
      final store = darbyGenesisOnly();
      await pumpReader(tester, store: store, bookIndex: 2);
      expect(find.textContaining('n\'est pas téléchargé en DBY'), findsOneWidget);

      store.landBook('DBY', 2, getbibleBook(2));
      await tester.pumpAndSettle();

      expect(find.textContaining('n\'est pas téléchargé en DBY'), findsNothing);
      expect(find.text('Texte téléchargé 1:1.'), findsOneWidget);
    });

    testWidgets('deleting the version being read falls back to BYM',
        (tester) async {
      SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
      final store = darbyGenesisOnly();
      await pumpReader(tester, store: store);
      expect(find.text('Texte téléchargé 1:1.'), findsOneWidget);

      store.removeVersion('DBY');
      await tester.pumpAndSettle();

      expect(
        find.descendant(
            of: find.byType(ReaderActionsBar), matching: find.text('BYM')),
        findsOneWidget,
        reason: 'the files are gone — the next read would have thrown',
      );
      expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
    });
  });

  group('the book header', () {
    testWidgets('opens chapter 1 of a BYM book', (tester) async {
      await pumpReader(tester, store: FakeStore({}));

      expect(find.text('Signification'), findsOneWidget);
      expect(find.textContaining('Traduction BYM'), findsOneWidget);
    });

    testWidgets('is hidden on a downloaded version, which has no metadata',
        (tester) async {
      // getbible serves text and nothing else, so `bookFromGetbible` fills the
      // metadata with empty strings. Rendering the card anyway put a title over
      // four blank cells, under a « Traduction BYM » line that was a lie.
      SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
      await pumpReader(tester, store: darbyGenesisOnly());

      expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
          reason: 'the chapter itself still reads');
      expect(find.text('Signification'), findsNothing);
      expect(find.textContaining('Traduction BYM'), findsNothing);
    });

    testWidgets('comes back when the reading returns to BYM', (tester) async {
      SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
      await pumpReader(tester, store: darbyGenesisOnly());
      expect(find.text('Signification'), findsNothing);

      await openVersionSheet(tester, 'DBY');
      await tapVersionRow(tester, 'Bible de Yehoshoua Ha Mashiah');

      expect(find.text('Signification'), findsOneWidget);
      expect(find.textContaining('Traduction BYM'), findsOneWidget);
    });
  });
}

/// Reads back the persisted version, without exposing `AppPreferences` fields
/// the test does not care about.
class AppPreferencesProbe {
  static Future<String?> versionCode() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('reading.versionCode');
  }
}
