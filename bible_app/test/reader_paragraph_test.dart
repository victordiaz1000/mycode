import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';
import 'package:bible_app/widgets/note_aware_text.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_bible_bundle.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 2, verses: 80));
  });

  tearDown(LocalRepository.useRootBundle);

  Future<void> pumpReader(
    WidgetTester tester, {
    int? initialVerse,
    int chapter = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: chapter,
            initialVerse: initialVerse,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the ⋯ display sheet and picks [label] (« Texte continu » …).
  Future<void> pickDisplay(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    // Close the sheet so the reader body is reachable again.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('the default layout renders one tile per verse', (tester) async {
    await pumpReader(tester);

    expect(find.byType(VerseTile), findsWidgets);
    expect(find.text('Verset de test Ge. 1:1.'), findsOneWidget);
  });

  testWidgets('switching to « Texte continu » flows the chapter as blocks', (
    tester,
  ) async {
    await pumpReader(tester);

    await pickDisplay(tester, 'Texte continu');

    expect(find.byType(VerseTile), findsNothing);
    expect(find.byType(RichText), findsWidgets);

    // The choice is persisted for the next launches.
    final prefs = await AppPreferences.load();
    expect(prefs.layout, ReadingLayout.paragraph);
  });

  testWidgets('a persisted continuous layout survives a rebuild', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
    });
    await pumpReader(tester);

    expect(find.byType(VerseTile), findsNothing);
    expect(find.byType(RichText), findsWidgets);
  });

  testWidgets('tapping a verse of the flow opens the study sheet', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
    });
    // Chapter 2: no book header, so the block starts right under the bar.
    await pumpReader(tester, chapter: 2);

    // Tap ON the verse glyphs: a blind point can land on the inline note text,
    // which carries no recognizer by design (only reference spans answer), so
    // the position is computed from the rendered boxes of a note-free verse.
    final paragraph = tester.renderObject<RenderParagraph>(
      find.byType(RichText).last,
    );
    const needle = 'Verset de test Ge. 2:3.';
    final idx = paragraph.text.toPlainText().indexOf(needle);
    expect(idx, greaterThanOrEqualTo(0));
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: idx, extentOffset: idx + needle.length),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();

    expect(find.text('ACTIONS'), findsOneWidget);
  });

  testWidgets('long-pressing a verse enters multi-selection', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
    });
    await pumpReader(tester, chapter: 2);

    await tester.longPressAt(const Offset(140, 160));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
  });

  testWidgets('restoring a deep verse scrolls the block precisely', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
    });
    await pumpReader(tester, chapter: 1, initialVerse: 70);

    // Verse 70 sits ~2100 px into the flowing block (plus the book header):
    // restoring it must have driven the list far down.
    final offsets = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.widget.controller?.offset ?? 0.0);
    expect(offsets.any((o) => o > 800), isTrue);
  });

  testWidgets('size settings reach the continuous blocks', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
    });
    await pumpReader(tester, chapter: 2);

    double? blockFontSize() => tester
        .widget<RichText>(find.byType(RichText).last)
        .text
        .style
        ?.fontSize;

    final sizeBefore = blockFontSize();
    expect(sizeBefore, isNotNull);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The size row sits inside its card, below the fold of the scrollable
    // sheet on the test surface — bring it into view before tapping.
    await tester.scrollUntilVisible(
      find.byTooltip('Taille du texte énorme'),
      80,
      scrollable: find.descendant(
        of: find.byType(DisplaySettingsSheetLayout),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Taille du texte énorme'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(blockFontSize(), greaterThan(sizeBefore!));
  });

  /// Every literal string carried by the flowing block, concatenated — the
  /// easiest way to assert what the continuous layout actually prints.
  String blockText(WidgetTester tester) {
    final buffer = StringBuffer();
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      buffer.write(span.text ?? '');
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }

    walk(tester.widget<RichText>(find.byType(RichText).last).text);
    return buffer.toString();
  }

  /// « Texte + notes » is the whole switch in the continuous flow: the
  /// disposition is a tiles-only choice, so the notes weave into the sentence
  /// whichever one is stored.
  ///
  /// « sous le verset » is the DEFAULT, and it used to gate the flow's notes
  /// off entirely — while the sheet drew « Notes à la suite » as already
  /// selected (in this layout the « sous le verset » chip isn't offered at
  /// all). A reader turning notes on saw a highlighted chip and no notes, and
  /// had to tap the chip that already looked active.
  for (final stored in const ['below', 'inline']) {
    testWidgets('« Texte + notes » weaves notes into the flow ($stored)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'reading.layout': ReadingLayout.paragraph.name,
        'reading.notesMode': true,
        'reading.noteDisposition': stored,
      });
      await pumpReader(tester, chapter: 2);

      // Never cards in the flow — they would chop the printed-text feel.
      expect(find.byType(NoteCard), findsNothing);
      expect(blockText(tester), contains('(Note de test 2:1.'));
    });
  }

  /// The flow must not COERCE the preference either: a reader who goes back to
  /// « Versets séparés » gets the « sous le verset » cards they had chosen.
  testWidgets('the continuous flow leaves « sous le verset » intact', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
      'reading.notesMode': true,
      'reading.noteDisposition': 'below',
    });
    await pumpReader(tester, chapter: 2);
    expect(find.byType(NoteCard), findsNothing);

    final prefs = await AppPreferences.load();
    expect(
      prefs.disposition,
      NoteDisposition.below,
      reason: 'la disposition « sous le verset » doit survivre à un passage '
          'par le texte continu',
    );
  });

  testWidgets('texte seul keeps the continuous flow free of ✦ markers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
      'reading.notesMode': false,
    });
    await pumpReader(tester, chapter: 2);

    final text = blockText(tester);
    expect(text.contains('\u{2726}'), isFalse,
        reason: 'le ✦ ne doit plus apparaître dans le flux continu');
  });

  testWidgets('the header introduction shares the flow typography', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': ReadingLayout.paragraph.name,
      'reading.fontSize': 22.0,
    });
    await pumpReader(tester, chapter: 1);

    final intro = tester
        .widget<Text>(find.textContaining('Introduction de test'))
        .style!;
    // Target the flowing body BY CONTENT, and only after nudging the list:
    // with the size-derived leading the header grew enough that the single
    // block sits below the lazy build range (« .last » used to assume it was
    // always built).
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    final bodyRich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (rt) =>
              (rt.text as TextSpan).toPlainText().contains('Verset de test'),
        );
    final body = (bodyRich.text as TextSpan).style!;
    // One shared style object: the intro can never drift from the body.
    expect(intro.fontSize, body.fontSize);
    expect(intro.fontFamily, body.fontFamily);
    expect(intro.fontWeight, body.fontWeight);
    expect(intro.color, body.color);
    // Same leading too: the flow must breathe like the intro, or it reads
    // darker/bigger at the very same point size.
    expect(intro.height, body.height);
  });
}
