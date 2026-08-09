import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/widgets/study_sheet.dart';

/// The contract of the study sheet: what it applies, and when.
///
/// Surlignage and favori are toggles, not actions — they must reach the reader
/// the moment they are tapped. They used to be reported through the pop value,
/// which meant a colour picked and then closed saved nothing, and the favourite
/// star saved nothing at all (no action ever carried it). These tests hold that
/// line: every expectation below is checked **before** the sheet closes.
void main() {
  /// The colour a hex string paints, as the sheet builds it.
  Color painted(String hex) =>
      Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));

  /// The dot of [hex] in the open sheet.
  Finder colorDot(String hex) => find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).color == painted(hex));

  final amber = highlightColors.first;
  final green = highlightColors[1];

  /// Opens the sheet over a bare screen, recording everything it reports.
  /// Returns the log of highlight calls, of favourite calls, and a one-slot
  /// holder for the action the sheet finally popped with.
  Future<(List<String?>, List<bool>, List<StudyAction?>)> pumpSheet(
    WidgetTester tester, {
    String? currentHighlight,
    bool isFavorite = false,
    bool lexiqueEnabled = true,
    String lexiqueLabel = 'Lexique Strong — verset mot à mot',
  }) async {
    final highlights = <String?>[];
    final favorites = <bool>[];
    final popped = <StudyAction?>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              popped.add(await showStudySheet(
                context,
                reference: 'Ge. 1:1',
                excerpt: 'Au commencement…',
                isFavorite: isFavorite,
                currentHighlight: currentHighlight,
                lexiqueEnabled: lexiqueEnabled,
                lexiqueLabel: lexiqueLabel,
                onHighlight: (color) async => highlights.add(color),
                onFavorite: (value) async => favorites.add(value),
              ));
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return (highlights, favorites, popped);
  }

  testWidgets('a colour is applied as it is tapped, not on close',
      (tester) async {
    final (highlights, _, popped) = await pumpSheet(tester);

    await tester.tap(colorDot(amber));
    await tester.pumpAndSettle();

    expect(highlights, [amber], reason: 'the verse is painted right away');
    expect(popped, isEmpty, reason: 'and the sheet stays open');
  });

  testWidgets('closing with the ✕ keeps the colour and reports no action',
      (tester) async {
    final (highlights, _, popped) = await pumpSheet(tester);
    await tester.tap(colorDot(green));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(highlights, [green]);
    expect(popped, [null], reason: 'nothing to navigate to');
  });

  testWidgets('tapping the active colour again clears it', (tester) async {
    final (highlights, _, _) = await pumpSheet(tester, currentHighlight: amber);

    await tester.tap(colorDot(amber));
    await tester.pumpAndSettle();

    expect(highlights, [null], reason: 'null is the clear, not an empty string');
  });

  testWidgets('the eraser clears an existing highlight', (tester) async {
    final (highlights, _, _) = await pumpSheet(tester, currentHighlight: green);

    await tester.tap(find.byTooltip('Effacer le surlignage'));
    await tester.pumpAndSettle();

    expect(highlights, [null]);
  });

  testWidgets('the eraser is dead when there is nothing to erase',
      (tester) async {
    // It used to fire anyway, which stored '' over a verse that had no
    // highlight — the amber-phantom path.
    final (highlights, _, _) = await pumpSheet(tester);

    final eraser = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.format_color_reset));
    expect(eraser.onPressed, isNull);
    expect(highlights, isEmpty);
  });

  testWidgets('the favourite is saved without pressing any action',
      (tester) async {
    final (_, favorites, popped) = await pumpSheet(tester);

    await tester.tap(find.text('Favori'));
    await tester.pumpAndSettle();

    expect(favorites, [true], reason: 'the star used to be lost on close');
    expect(find.text('Favori ✓'), findsOneWidget);
    expect(popped, isEmpty, reason: 'a toggle does not close the sheet');
  });

  testWidgets('an already-favourite verse can be un-favourited', (tester) async {
    final (_, favorites, _) = await pumpSheet(tester, isFavorite: true);

    expect(find.text('Favori ✓'), findsOneWidget);
    await tester.tap(find.text('Favori ✓'));
    await tester.pumpAndSettle();

    expect(favorites, [false]);
  });

  testWidgets('an action closes the sheet and names itself', (tester) async {
    final (_, _, popped) = await pumpSheet(tester);

    // The grid overflows the test screen — the chip has to be brought into
    // view before it can be hit.
    await tester.ensureVisible(find.text('Copier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(popped, [StudyAction.copy]);
  });

  testWidgets('the Lexique button is off when the version cannot offer Strong',
    (tester) async {
  await pumpSheet(
      tester,
      lexiqueEnabled: false,
      lexiqueLabel: 'Lexique Strong — versions BYM/LSGS');

  final button = tester.widget<OutlinedButton>(find.widgetWithText(
      OutlinedButton, 'Lexique Strong — versions BYM/LSGS'));
  expect(button.onPressed, isNull);
});

testWidgets('the Lexique button carries a precise name when enabled',
    (tester) async {
  await pumpSheet(tester);

  final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Lexique Strong — verset mot à mot'));
  expect(button.onPressed, isNotNull,
      reason: 'the name tells the reader it opens the Strong rendering');
});
}
