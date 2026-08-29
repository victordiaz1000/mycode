import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/parallel_reading_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_bible_bundle.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3, verses: 40));
  });

  tearDown(LocalRepository.useRootBundle);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ParallelReadingScreen(
          bookIndex: 1,
          chapter: 1,
          initialLeftCode: 'BYM',
          initialRightCode: 'BYM',
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('both panes render the same chapter', (tester) async {
    await pumpScreen(tester);

    // One version pill per pane.
    expect(find.text('BYM'), findsNWidgets(2));
    // The same verse exists on both sides.
    expect(
      find.widgetWithText(VerseTile, 'Verset de test Ge. 1:3.'),
      findsNWidgets(2),
    );
  });

  testWidgets('tapping a verse on the left scrolls the right pane', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const ValueKey('left_BYM_2')));
    await tester.pumpAndSettle();

    final offsets = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.widget.controller?.offset ?? 0.0)
        .toList();
    // Verse 2 of 40 sits ~1/39th down the right pane's range: small, but real.
    expect(offsets.any((o) => o > 5), isTrue);
  });

  testWidgets('the shared arrows step both panes to the next chapter', (
    tester,
  ) async {
    await pumpScreen(tester);

    final nextLabel = '${catalogEntry(1).barLabel} 2';
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();

    expect(find.text(nextLabel), findsOneWidget);
    expect(
      find.widgetWithText(VerseTile, 'Verset de test Ge. 2:3.'),
      findsNWidgets(2),
    );
  });

  testWidgets('the ⋯ display sheet opens the parallel reading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(bookIndex: 1, chapter: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    // The entry sits at the bottom of the sheet's scrollable — and the sheet
    // grew with the « Aération » section: scroll it into view instead of a
    // fixed drag that silently stopped short of it.
    await tester.scrollUntilVisible(
      find.text('Lecture parallèle — deux versions'),
      120,
      scrollable: find.descendant(
        of: find.byType(DisplaySettingsSheetLayout),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(find.text('Lecture parallèle — deux versions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lecture parallèle — deux versions'));
    // Fixed pumps: the pushed screen keeps an indeterminate spinner frame
    // alive long enough to starve pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ParallelReadingScreen), findsOneWidget);
  });
}
