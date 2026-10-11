import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/share_text.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/settings_screen.dart';
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
    // `scrollUntilVisible` stops as soon as the row *exists*, which can leave
    // it flush with the bottom edge where the tap lands outside the surface —
    // one more catalogue row above it (the LSS) is enough to move it there.
    await tester.ensureVisible(find.text(name));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('a downloaded version names itself in what is copied and shared',
      (tester) async {
    // A Darby verse pasted into a note with no mention of Darby is a claim the
    // BYM did not make. Both surfaces must say whose words these are — and
    // neither string may be written by hand at its call site, or they drift
    // (they had: the sheet's copy named no version, the selection bar's did).
    final previous = shareText;
    var shared = '';
    shareText = (message, {origin}) async => shared = message;
    addTearDown(() => shareText = previous);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          copied =
              (message.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpReader(tester, store: darbyGenesisOnly());
    await openVersionSheet(tester, 'BYM');
    await tapVersionRow(tester, 'DBY');

    // Share from the selection bar: the badge rides the attribution line.
    // Done *before* the copy, whose confirmation snackbar would sit on top of
    // the verse and swallow the long press.
    await tester.longPress(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Partager les versets'), findsOneWidget,
        reason: 'la sélection doit être ouverte');
    await tester.tap(find.byTooltip('Partager les versets'));
    await tester.pumpAndSettle();
    expect(shared.trim(), endsWith('— Genèse 1:1 (DBY)'),
        reason: 'le partage nomme la version téléchargée');

    // Copy from the study sheet: the badge sits after the reference.
    await tester.tap(find.byTooltip('Terminer la sélection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Copier'),
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();
    expect(copied, '$appName\nGenèse 1:1 (DBY) Texte téléchargé 1:1.',
        reason: 'la copie nomme la version téléchargée, après le nom de l\'app');
    expect(shared.split('\n').first, appName,
        reason: 'le partage aussi s\'ouvre sur le nom de l\'app');
  });

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

  testWidgets('a version with nothing downloaded is not offered',
      (tester) async {
    await pumpReader(tester, store: FakeStore({}));

    await openVersionSheet(tester, 'BYM');

    // It used to be listed and answer « à télécharger depuis la Bibliothèque »
    // — a row that could not do anything, in a sheet meant for picking.
    expect(find.text('Bible Darby'), findsNothing);
    expect(find.text('Bible de Yehoshoua Ha Mashiah'), findsOneWidget,
        reason: 'the embedded version is always there');
    expect(find.text('15 autres versions à télécharger'), findsOneWidget);
  });

  testWidgets('the footer leads to the Bibliothèque', (tester) async {
    var opened = 0;
    await pumpReader(tester,
        store: FakeStore({}), onOpenLibrary: () => opened++);

    await openVersionSheet(tester, 'BYM');
    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('Version'), findsNothing, reason: 'the sheet closes too');
  });

  testWidgets('without a shell the footer only names the Bibliothèque',
      (tester) async {
    // Standalone use (tests, ChapterScreen on its own): no destination to
    // switch to, so the row states the fact instead of pretending to be a
    // button.
    await pumpReader(tester, store: FakeStore({}));

    await openVersionSheet(tester, 'BYM');
    expect(find.text('Bibliothèque'), findsOneWidget);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(find.text('Version'), findsOneWidget,
        reason: 'the row is inert — closing on nothing would lose the sheet');
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
      // startup, and a version the Bibliothèque had just installed stayed out
      // of the sheet — the user bounced between the two screens forever.
      final store = FakeStore({});
      await pumpReader(tester, store: store);

      await openVersionSheet(tester, 'BYM');
      expect(find.text('Bible Darby'), findsNothing,
          reason: 'nothing downloaded yet');
      // The sheet has no ✕: tap the barrier above it, as a swipe down would.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

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

  group('the notes setting', () {
    /// The notes rows moved to the Settings screen with the rest of the display
    /// preferences. Its LECTURE card is long, so the surface is enlarged: a
    /// `find` below the fold of a phone-sized viewport returns 0 without
    /// anything being broken.
    Future<void> openSettings(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('a downloaded version says the notes are BYM-only', (
      tester,
    ) async {
      // `bookFromGetbible` copies the bare text into `textWithNotes` and leaves
      // `notes` empty, so « Texte + notes » toggled between two identical
      // renderings and the two dispositions governed nothing. The switch stays
      // usable — the preference is global — but the row says it changes nothing
      // here, which beats a control with no visible effect.
      SharedPreferences.setMockInitialValues({'reading.versionCode': 'DBY'});
      await pumpReader(tester, store: darbyGenesisOnly());
      await openSettings(tester);

      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Texte seul — notes du texte BYM'), findsOneWidget);
      // No disposition row while the notes are off: it would govern nothing.
      expect(find.text('Disposition des notes'), findsNothing);

      // The size ladder still applies — it is not about notes.
      expect(find.text('Taille du texte'), findsOneWidget);
    });

    testWidgets('the embedded text keeps the plain wording', (tester) async {
      await openSettings(tester);
      expect(find.text('Texte seul'), findsOneWidget);
      expect(find.textContaining('notes du texte BYM'), findsNothing);
    });

    testWidgets('a stored « notes on » does not follow onto a download',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'reading.versionCode': 'DBY',
        'reading.notesMode': true,
      });
      await pumpReader(tester, store: darbyGenesisOnly());

      // Notes off ⇒ a plain Text; the annotated path builds a RichText, which
      // `find.text` skips unless asked for it.
      expect(find.text('Texte téléchargé 1:1.'), findsOneWidget,
          reason: 'the verse reads as text, not through the note renderer');
    });

    testWidgets('the choice is found again on the return to BYM',
        (tester) async {
      // The guard is a display rule, not a write: forcing `reading.notesMode`
      // to false would have cost the reader its setting on a single detour
      // through a downloaded version.
      SharedPreferences.setMockInitialValues({
        'reading.versionCode': 'DBY',
        'reading.notesMode': true,
      });
      await pumpReader(tester, store: darbyGenesisOnly());
      expect(
          find.textContaining('Note de test', findRichText: true), findsNothing);

      await openVersionSheet(tester, 'DBY');
      await tapVersionRow(tester, 'Bible de Yehoshoua Ha Mashiah');

      expect(find.textContaining('Note de test', findRichText: true),
          findsWidgets,
          reason: 'the preference was never overwritten');
      await openSettings(tester);
      expect(find.text('Texte + notes'), findsOneWidget);
      expect(find.text('Disposition des notes'), findsOneWidget);
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
