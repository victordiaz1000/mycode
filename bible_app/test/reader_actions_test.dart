import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/screens/settings_screen.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/premium_style.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_bible_bundle.dart';

/// Finds [text] inside the action bar itself (the same label often also exists
/// in the sheet or in the chapter body behind it).
Finder inBar(String text) => find.descendant(
  of: find.byType(ReaderActionsBar),
  matching: find.text(text),
);

/// Finds a number tile of a sheet grid (chapters or verses); the same digits
/// also exist as verse numbers in the reader behind the sheet.
Finder gridTile(String number) =>
    find.descendant(of: find.byType(Wrap), matching: find.text(number));

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
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The display preferences (notes, aération, colour, opacity…) live in the
  /// Settings screen since they left the reader's ⋯ sheet. Its LECTURE card is
  /// long, so the surface is enlarged: a `find` below the fold of a phone-sized
  /// viewport returns 0 without anything being broken.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            key: ValueKey('$book:$chapter'),
            bookIndex: book,
            chapter: chapter,
            onOpenChapter: (b, c) => opened.add('$b:$c'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the bar shows the reference pill, the version and the chevron', (
    tester,
  ) async {
    await pumpReader(tester);

    expect(find.byType(ReaderActionsBar), findsOneWidget);
    // « Bereshit 1 » : on the BYM the pill carries the book's own name,
    // which is also how the reader knows which text is on screen.
    expect(inBar('Bereshit 1'), findsOneWidget);
    expect(inBar('BYM'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_double_arrow_down), findsOneWidget);
  });

  testWidgets('a long book name is shortened in the pill and never overflows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 49,
            chapter: 1,
            onOpenChapter: (b, c) => opened.add('$b:$c'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: '1 Corinthiens must not overflow the action bar',
    );
    expect(
      inBar('1 Kor. 1'),
      findsOneWidget,
      reason: 'the bar uses the compact name for long books',
    );

    // The pill has ONE width, and the Hebrew names are not the French ones
    // shortened: `Divrei Hayamim 1` is the widest of them, so the BYM — the
    // version the app opens on — is the one that must not overflow.
    const pires = [(38, '1 Hay. d. 1'), (30, 'Shir Hash. 1'), (66, 'Apokalupsis 1')];
    for (final (bymIndex, expected) in pires) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChapterReader(bookIndex: bymIndex, chapter: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'livre $bymIndex en BYM ne doit pas déborder la barre',
      );
      expect(inBar(expected), findsOneWidget, reason: 'livre $bymIndex');
    }

    // And the same bar in French, on a downloaded translation.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderActionsBar(
            bookIndex: 49,
            chapter: 1,
            versionCode: 'DBY',
            onOpenChapter: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inBar('1 Cor. 1'), findsOneWidget,
        reason: 'une traduction se lit en français');
  });

  testWidgets(
    'the reference pill opens the Livres sheet and unfolds chapters',
    (tester) async {
      await pumpReader(tester);

      await tester.tap(inBar('Bereshit 1'));
      await tester.pumpAndSettle();

      expect(find.text('Livres'), findsOneWidget);
      // Sections are kept (only the first ones fit on screen); les livres
      // portent leur nom BYM complet, scopé à la feuille car l'en-tête du
      // lecteur, derrière, affiche le même nom.
      Finder inSheet(Finder f) => find.descendant(
            of: find.byType(BottomSheet),
            matching: f,
          );
      expect(find.text('Torah'), findsOneWidget);
      expect(inSheet(find.text('Bereshit (Genèse)')), findsOneWidget);
      // La grille dépliée de la Genèse pousse les rangées suivantes hors du
      // premier extent : viser la voisine directe plutôt que Deutéronome.
      expect(inSheet(find.text('Shemot (Exode)')), findsOneWidget);

      // The current book starts unfolded: its chapters are already listed
      // (FakeBibleBundle generates 2 chapters per book).
      expect(gridTile('1'), findsOneWidget);
      expect(gridTile('2'), findsOneWidget);

      // Fold it back: the chapter grid disappears.
      await tester.tap(inSheet(find.text('Bereshit (Genèse)')));
      await tester.pumpAndSettle();
      expect(gridTile('2'), findsNothing);
    },
  );

  testWidgets('picking a chapter in the Livres sheet reports it and closes', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            onOpenChapter: (book, chapter) => opened.add('$book:$chapter'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(inBar('Bereshit 1'));
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
    // 14 catalogue entries, BYM and LSGS being the only readable ones here.
    expect(find.text('13 autres versions à télécharger'), findsOneWidget);
  });

  testWidgets('a listed version no longer carries an audio glyph', (
    tester,
  ) async {
    // Audio was removed from the app (décision 2026-08) : the maquette prints a
    // 🔊 next to versions with an audio reading, but nothing plays audio today,
    // so the sheet must not advertise what it cannot deliver.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderActionsBar(
            installedVersions: const {
              'LSG': InstalledVersion(code: 'LSG', books: {1}),
            },
            onOpenChapter: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();

    expect(find.text('Bible Segond 1910'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
  });

  testWidgets('a version without files is absent, whatever its licence', (
    tester,
  ) async {
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
    expect(
      find.text('DBY — à télécharger depuis la Bibliothèque.'),
      findsNothing,
    );
  });

  testWidgets('the chevron opens the verse grid and jumps to the pick', (
    tester,
  ) async {
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

  testWidgets('a far verse is reached even though its tile was never built', (
    tester,
  ) async {
    // 60 verses: verse 55 sits well past the lazy list's cache extent, so its
    // tile does not exist when the jump is asked for.
    LocalRepository.useBundle(FakeBibleBundle(verses: 60));
    final target = ValueNotifier<VerseTarget?>(null);
    addTearDown(target.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(bookIndex: 1, chapter: 1, jumpToVerse: target),
        ),
      ),
    );
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

  testWidgets('a restored verse is scrolled to on open, without the flash', (
    tester,
  ) async {
    // 60 verses so verse 55 is past the cache extent on first load: the
    // restore has to drive the lazy list, exactly like a jump.
    LocalRepository.useBundle(FakeBibleBundle(verses: 60));
    final verses = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            initialVerse: 55,
            onVerseChanged: verses.add,
          ),
        ),
      ),
    );
    // The restore waits a frame, loads the chapter, then converges: pump
    // explicitly like the jump test above.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();

    final tile = find.text('Verset de test Ge. 1:55.');
    expect(tile, findsOneWidget);
    final viewport = tester.getRect(find.byType(ChapterReader));
    final rect = tester.getRect(tile);
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // The restored position is reported once to the owning tab.
    expect(verses, contains(55));
  });

  testWidgets('scrolling the reader reports the current verse', (tester) async {
    final verses = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            onVerseChanged: verses.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Drag far enough that the reader settles beyond verse 1: the debounced
    // reporter then estimates the verse at the top of the viewport.
    await tester.drag(find.byType(ChapterVerseList), const Offset(0, -800));
    // The reporter debounces 400 ms and reads the position asynchronously.
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();

    expect(verses, isNotEmpty);
    // FakeBibleBundle makes 3 verses; drifting the whole list must land on the
    // last one at the top.
    expect(verses.last, greaterThan(1));
  });

  testWidgets('the ⋯ sheet turns the notes on and the reader follows', (
    tester,
  ) async {
    await pumpReader(tester);
    expect(find.textContaining('Note de test', findRichText: true), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // The checkmark offsets the label's centre; the tap still lands on the chip.
    await tester.tap(find.text('Texte + notes'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Both dispositions appear, the reader reconstructs the annotated verse from
    // text + notes (NoteAwareVerseText), so the note body now shows. It lives in
    // a RichText span, hence findRichText.
    expect(find.text('Notes à la suite'), findsOneWidget);
    expect(find.text('Notes sous le verset'), findsOneWidget);
    expect(
      find.textContaining('Note de test', findRichText: true),
      findsWidgets,
    );
  });

  testWidgets('the continuous flow offers only « à la suite »', (tester) async {
    // The disposition is a tiles-only choice: the flow weaves the notes into
    // the sentence, so offering « sous le verset » there would be a control that
    // changes nothing. The reader also ignores the stored disposition there
    // rather than rewriting it — see `_effectiveShowNotes`.
    await pumpReader(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texte + notes'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Notes à la suite'), findsOneWidget);
    expect(find.text('Notes sous le verset'), findsOneWidget);

    await tester.tap(find.text('Texte continu'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Notes à la suite'), findsOneWidget);
    expect(
      find.text('Notes sous le verset'),
      findsNothing,
      reason: 'in the flow the notes are woven in, the option does not apply',
    );

    // And the stored disposition survives the round trip to the tiles layout.
    await tester.tap(find.text('Versets séparés'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Notes sous le verset'), findsOneWidget);
  });

  testWidgets('the ⋯ sheet follows the canonical section order', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    // The sheet is a SingleChildScrollView: every section is laid out, even
    // the ones below the fold, so their vertical order is directly readable.
    // DisplaySectionLabel uppercases its text; plain Text rows do not.
    double y(String label) => tester.getTopLeft(find.text(label)).dy;
    // What one reaches for while reading — the layout, the size, the notes and
    // the panel behind the verses — then the way out to the rest (police,
    // graisse, aération, couleur, thème, données).
    final sections = [
      'Mode immersion',
      'DISPOSITION DU TEXTE',
      'TAILLE DU TEXTE',
      'NOTES',
      'OPACITÉ DU PANNEAU',
      'Tous les réglages',
      'Lecture parallèle — deux versions',
    ];
    for (var i = 0; i < sections.length - 1; i++) {
      expect(
        y(sections[i]),
        lessThan(y(sections[i + 1])),
        reason: '"${sections[i]}" must sit above "${sections[i + 1]}"',
      );
    }
  });

  testWidgets('no-tab home shows the Livres pill with the chevron disabled', (
    tester,
  ) async {
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

  testWidgets('at Genèse 1 the back arrow is disabled and forward steps on', (
    tester,
  ) async {
    final opened = <String>[];
    await pumpReaderReporting(tester, 1, 1, opened);

    expect(
      arrow(tester, Icons.chevron_left).onPressed,
      isNull,
      reason: 'Bereshit 1 is the very beginning',
    );
    expect(arrow(tester, Icons.chevron_right).onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(opened, ['1:2']);
  });

  testWidgets('the arrows cross book boundaries in both directions', (
    tester,
  ) async {
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

  testWidgets('the forward arrow is disabled at the end of Apocalypse', (
    tester,
  ) async {
    await pumpReaderReporting(tester, 66, 2, []);

    expect(arrow(tester, Icons.chevron_right).onPressed, isNull);
    expect(arrow(tester, Icons.chevron_left).onPressed, isNotNull);
  });

  testWidgets('the reading font is applied and updates live', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reading.fontFamily': ReadingFont.classic.name,
    });
    await pumpReader(tester);

    Text verse() => tester.widget<Text>(find.text('Verset de test Ge. 1:1.'));
    expect(verse().style?.fontFamily, 'Lora');

    final prefs = await AppPreferences.load();
    prefs.readingFont = ReadingFont.jakarta;
    await prefs.save();
    await tester.pumpAndSettle();

    expect(verse().style?.fontFamily, 'Plus Jakarta Sans');
  });

  testWidgets('a font choice stored as « Moderne » migrates', (tester) async {
    // 'modern' asked for the platform `sans-serif`, the one family the bundle
    // did not embed — it rendered differently on every device, so the option
    // was dropped. A reader who had picked it must land on the embedded sans
    // serif, NOT on the reader's Literata fallback, which is a serif.
    SharedPreferences.setMockInitialValues({'reading.fontFamily': 'modern'});
    await pumpReader(tester);

    expect(
      tester
          .widget<Text>(find.text('Verset de test Ge. 1:1.'))
          .style
          ?.fontFamily,
      'Plus Jakarta Sans',
    );
  });
  // ---- Reading text size --------------------------------------------------

  testWidgets('the ⋯ menu changes the verse text size and remembers it', (
    tester,
  ) async {
    await pumpReader(tester);

    // Default is « très grand » (22) — ReadingTextSize.extraLarge.
    expect(verseFontSize(tester), 22);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The ladder is a row of « A » chips, labelled for screen readers.
    expect(find.text('TAILLE DU TEXTE'), findsOneWidget);
    // The full ladder is offered, « petit » through « géant ».
    expect(find.byTooltip('Taille du texte petit'), findsOneWidget);
    expect(find.byTooltip('Taille du texte moyen'), findsOneWidget);
    expect(find.byTooltip('Taille du texte grand'), findsOneWidget);
    expect(find.byTooltip('Taille du texte très grand'), findsOneWidget);
    expect(find.byTooltip('Taille du texte énorme'), findsOneWidget);
    expect(find.byTooltip('Taille du texte géant'), findsOneWidget);
    // The sheet scrolls if needed, but « géant » must stay reachable without
    // hunting: it fits inside the viewport of a standard test surface.
    final screen =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    await tester.ensureVisible(find.byTooltip('Taille du texte géant'));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomLeft(find.byTooltip('Taille du texte géant')).dy,
      lessThan(screen),
    );

    await tester.tap(find.byTooltip('Taille du texte géant'));
    await tester.pumpAndSettle();
    expect(verseFontSize(tester), 30);

    // Remounting reads the size back from shared_preferences.
    await pumpReader(tester);
    expect(verseFontSize(tester), 30);
  });
  testWidgets('the ⋯ sheet has a labelled close button', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('display-sheet-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('display-sheet-close')));
    await tester.pumpAndSettle();

    // Back to the reader, sheet gone.
    expect(find.text('TAILLE DU TEXTE'), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('the Settings screen changes the aération and the reader follows', (
    tester,
  ) async {
    double? verseHeight(WidgetTester tester) =>
        tester.widget<Text>(find.text('Verset de test Ge. 1:1.')).style?.height;

    await pumpReader(tester);
    final before = verseHeight(tester)!;

    // The aération row moved to the Settings screen. « Normal » appears twice
    // there (Graisse + Aération), so the tap is scoped to the row.
    Future<void> choisir(String label) async {
      await pumpSettings(tester);
      final range = find.descendant(
        of: find.ancestor(
          of: find.text('Aération du texte'),
          matching: find.byType(InkWell),
        ),
        matching: find.text(label),
      );
      await tester.tap(range);
      await tester.pumpAndSettle();
    }

    await choisir('Aéré');
    await pumpReader(tester);
    expect(verseHeight(tester), greaterThan(before));

    // And « serré » tightens below the default leading again.
    await choisir('Serré');
    await pumpReader(tester);
    expect(verseHeight(tester), lessThan(before));
  });

  testWidgets('reading sheets inherit the selected theme surface', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reading.themeId': 'forest'});
    AppPreferences.themeNotifier.value = 'forest';
    addTearDown(() => AppPreferences.themeNotifier.value = 'vitrail');

    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final expected = premiumPalette(
      tester.element(find.byType(ReaderActionsBar)),
    ).surface;
    await tester.tap(inBar('Bereshit 1'));
    await tester.pumpAndSettle();
    final bookTiles = tester.widgetList<Material>(
      find.descendant(of: find.byType(Wrap), matching: find.byType(Material)),
    );
    expect(bookTiles.any((tile) => tile.color == expected), isTrue);
    expect(bookTiles.any((tile) => tile.color == Colors.white), isFalse);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(inBar('BYM'));
    await tester.pumpAndSettle();
    final versionTiles = tester.widgetList<Material>(
      find.descendant(
        of: find.byKey(const Key('versionSheetList')),
        matching: find.byType(Material),
      ),
    );
    expect(versionTiles.any((tile) => tile.color == expected), isTrue);
    expect(versionTiles.any((tile) => tile.color == Colors.white), isFalse);
  });
}
