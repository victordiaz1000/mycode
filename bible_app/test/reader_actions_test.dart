import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';

import 'support/fake_bible_bundle.dart';

/// Finds [text] inside the action bar itself (the same label often also exists
/// in the sheet or in the chapter body behind it).
Finder inBar(String text) => find.descendant(
      of: find.byType(ReaderActionsBar),
      matching: find.text(text),
    );

/// Finds a number tile of a sheet grid (chapters or verses); the same digits
/// also exist as verse numbers in the reader behind the sheet.
Finder gridTile(String number) => find.descendant(
      of: find.byType(Wrap),
      matching: find.text(number),
    );

/// The chapter-stepping arrow carrying [icon]; read its `onPressed` to tell
/// enabled from greyed.
IconButton arrow(WidgetTester tester, IconData icon) =>
    tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

/// Rendered point size of the first verse of the fake Genèse 1.
double? verseFontSize(WidgetTester tester) =>
    tester.widget<Text>(find.text('Verset de test Ge. 1:1.')).style?.fontSize;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(LocalRepository.useRootBundle);

  Future<void> pumpReader(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ChapterReader(bookIndex: 1, chapter: 1),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// A reader on [book]/[chapter] that records every navigation as `book:ch`
  /// instead of touching a tab manager.
  Future<void> pumpReaderReporting(
    WidgetTester tester,
    int book,
    int chapter,
    List<String> opened,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          key: ValueKey('$book:$chapter'),
          bookIndex: book,
          chapter: chapter,
          onOpenChapter: (b, c) => opened.add('$b:$c'),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the bar shows the reference pill, the version and the chevron',
      (tester) async {
    await pumpReader(tester);

    expect(find.byType(ReaderActionsBar), findsOneWidget);
    // « Genèse 1 » : short French name of book 1 + chapter.
    expect(inBar('Genèse 1'), findsOneWidget);
    expect(inBar('BYM'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);
  });

  testWidgets('the reference pill opens the Livres sheet and unfolds chapters',
      (tester) async {
    await pumpReader(tester);

    await tester.tap(inBar('Genèse 1'));
    await tester.pumpAndSettle();

    expect(find.text('Livres'), findsOneWidget);
    // Sections are kept (only the first ones fit on screen), books use their
    // short French name.
    expect(find.text('Torah'), findsOneWidget);
    expect(find.text('Genèse'), findsOneWidget);
    expect(find.text('Deutéronome'), findsOneWidget);

    // The current book starts unfolded: its chapters are already listed
    // (FakeBibleBundle generates 2 chapters per book).
    expect(gridTile('1'), findsOneWidget);
    expect(gridTile('2'), findsOneWidget);

    // Fold it back: the chapter grid disappears.
    await tester.tap(find.text('Genèse'));
    await tester.pumpAndSettle();
    expect(gridTile('2'), findsNothing);
  });

  testWidgets('picking a chapter in the Livres sheet reports it and closes',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          onOpenChapter: (book, chapter) => opened.add('$book:$chapter'),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(inBar('Genèse 1'));
    await tester.pumpAndSettle();
    await tester.tap(gridTile('2'));
    await tester.pumpAndSettle();

    expect(opened, ['1:2']);
    expect(find.text('Livres'), findsNothing);
  });

  testWidgets('the version pill lists only what can be read', (tester) async {
    await pumpReader(tester);

    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('Version intégrée'), findsOneWidget);
    expect(find.text('Bible de Yehoshoua Ha Mashiah'), findsOneWidget);

    // Nothing is downloaded here, so the downloadable half of the catalogue is
    // not offered: it used to sit below, greyed, a dozen rows answering « à
    // télécharger ». LSGS, like BYM, is embedded — it is offered.
    expect(find.text('Bible Segond 1910'), findsNothing);
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
    expect(find.text('Bible Darby'), findsNothing);
    expect(find.text('Autres versions'), findsNothing);
  });

  testWidgets('the sheet ends on the way to the Bibliothèque', (tester) async {
    // What is left out has to stay reachable, or the reader has no way of
    // knowing there are other translations at all.
    await pumpReader(tester);

    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Bibliothèque'), findsOneWidget);
    // 12 catalogue entries, BYM and LSGS being the only readable ones here.
    expect(find.text('10 autres versions à télécharger'), findsOneWidget);
  });

  testWidgets('a listed version no longer carries an audio glyph', (tester) async {
    // Audio was removed from the app (décision 2026-08) : the maquette prints a
    // 🔊 next to versions with an audio reading, but nothing plays audio today,
    // so the sheet must not advertise what it cannot deliver.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderActionsBar(
          installedVersions: const {
            'LSG': InstalledVersion(code: 'LSG', books: {1}),
          },
          onOpenChapter: (_, _) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Bible Segond 1910'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('a version without files is absent, whatever its licence',
      (tester) async {
    // LSG has no free source (décision 9) and DBY is only downloadable: both
    // used to be listed and answer a snackbar. Neither can be read, so the
    // sheet does not carry them — the Bibliothèque does.
    await pumpReader(tester);

    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Bible Segond 1910'), findsNothing);
    expect(find.text('Bible Darby'), findsNothing);
    // Only BYM and the footer are tappable, so nothing can raise these.
    expect(find.text('LSG — bientôt disponible.'), findsNothing);
    expect(find.text('DBY — à télécharger depuis la Bibliothèque.'),
        findsNothing);
  });

  testWidgets('the chevron opens the verse grid and jumps to the pick',
      (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
    await tester.pumpAndSettle();

    expect(find.text('Aller au verset'), findsOneWidget);
    // FakeBibleBundle generates 3 verses per chapter: 1, 2, 3.
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('3'));
    await tester.pumpAndSettle();
    expect(find.text('Aller au verset'), findsNothing);

    // Let the 900 ms flash timer finish so no timer is left pending.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a far verse is reached even though its tile was never built',
      (tester) async {
    // 60 verses: verse 55 sits well past the lazy list's cache extent, so its
    // tile does not exist when the jump is asked for.
    LocalRepository.useBundle(FakeBibleBundle(verses: 60));
    final target = ValueNotifier<VerseTarget?>(null);
    addTearDown(target.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(bookIndex: 1, chapter: 1, jumpToVerse: target),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Verset de test Ge. 1:55.'), findsNothing);

    target.value = const VerseTarget(bookIndex: 1, chapter: 1, verse: 55);
    // The jump waits a frame, then loads the chapter, then converges over a
    // few frames. pumpAndSettle alone stops as soon as no frame is pending,
    // which happens between those awaits, so pump explicitly.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();

    final tile = find.text('Verset de test Ge. 1:55.');
    expect(tile, findsOneWidget);
    // Built is not enough — it must be inside the viewport, not in the cache
    // extent above or below it.
    final viewport = tester.getRect(find.byType(ChapterReader));
    final rect = tester.getRect(tile);
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('the ⋯ menu carries the text display options', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('Texte seul'), findsOneWidget);
    expect(find.text('Texte + notes'), findsOneWidget);
    expect(find.text('Notes à la suite'), findsOneWidget);
    expect(find.text('Notes sous le verset'), findsOneWidget);

    // The checkmark offsets the label's centre; the tap still lands on the menu
    // item, so silence the known spurious hit-test warning.
    await tester.tap(find.text('Texte + notes'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // Notes are on: the reader reconstructs the annotated verse from text +
    // notes (NoteAwareVerseText), so the note body now shows. It lives in a
    // RichText span, hence findRichText.
    expect(
      find.textContaining('Note de test', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('no-tab home shows the Livres pill with the chevron disabled',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReaderScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(ReaderActionsBar), findsOneWidget);
    expect(inBar('Livres'), findsOneWidget);
    expect(inBar('BYM'), findsOneWidget);

    // No chapter to jump inside: tapping the chevron opens nothing.
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
    await tester.pumpAndSettle();
    expect(find.text('Aller au verset'), findsNothing);

    // Nowhere to step to either.
    expect(arrow(tester, Icons.chevron_left).onPressed, isNull);
    expect(arrow(tester, Icons.chevron_right).onPressed, isNull);
  });

  // ---- Previous / next chapter ------------------------------------------

  testWidgets('at Genèse 1 the back arrow is disabled and forward steps on',
      (tester) async {
    final opened = <String>[];
    await pumpReaderReporting(tester, 1, 1, opened);

    expect(arrow(tester, Icons.chevron_left).onPressed, isNull,
        reason: 'Genèse 1 is the very beginning');
    expect(arrow(tester, Icons.chevron_right).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(opened, ['1:2']);
  });

  testWidgets('the arrows cross book boundaries in both directions',
      (tester) async {
    // FakeBibleBundle gives every book 2 chapters, so Genèse 2 is the last one.
    final forward = <String>[];
    await pumpReaderReporting(tester, 1, 2, forward);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(forward, ['2:1'], reason: 'Genèse 2 → Exode 1');

    final backward = <String>[];
    await pumpReaderReporting(tester, 2, 1, backward);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(backward, ['1:2'], reason: 'Exode 1 → last chapter of Genèse');
  });

  testWidgets('the forward arrow is disabled at the end of Apocalypse',
      (tester) async {
    await pumpReaderReporting(tester, 66, 2, []);

    expect(arrow(tester, Icons.chevron_right).onPressed, isNull);
    expect(arrow(tester, Icons.chevron_left).onPressed, isNotNull);
  });

  // ---- Reading text size --------------------------------------------------

  testWidgets('the ⋯ menu changes the verse text size and remembers it',
      (tester) async {
    await pumpReader(tester);

    // Default is « moyen » — the Material bodyLarge size the reader used
    // before the control existed.
    expect(verseFontSize(tester), 16);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The ladder is a row of « A » chips, labelled for screen readers.
    expect(find.text('Taille du texte'), findsOneWidget);
    expect(find.byTooltip('Texte petit'), findsOneWidget);
    expect(find.byTooltip('Texte moyen'), findsOneWidget);
    expect(find.byTooltip('Texte très grand'), findsOneWidget);
    // The two large-print steps for failing eyesight.
    expect(find.byTooltip('Texte énorme'), findsOneWidget);
    expect(find.byTooltip('Texte géant'), findsOneWidget);
    // The whole ladder must fit without scrolling: the readers who need
    // « géant » are the least likely to go hunting for it.
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      tester.getBottomLeft(find.byTooltip('Texte géant')).dy,
      lessThan(screen),
    );

    await tester.tap(find.byTooltip('Texte grand'));
    await tester.pumpAndSettle();
    expect(verseFontSize(tester), 19);

    // Remounting reads the size back from shared_preferences.
    await pumpReader(tester);
    expect(verseFontSize(tester), 19);
  });
}
