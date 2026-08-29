import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';

import 'support/fake_bible_bundle.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    AppPreferences.revision.value = 0;
  });

  Future<void> pumpReader(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the default panel opacity reproduces the historical rendering', (
    tester,
  ) async {
    final prefs = await AppPreferences.load();
    expect(prefs.panelOpacity, .80);
  });

  testWidgets('the ⋯ sheet carries the opacity slider, live then persisted', (
    tester,
  ) async {
    await pumpReader(tester);

    // Open the display sheet.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('OPACITÉ DU PANNEAU'), findsOneWidget);
    expect(find.text('80 %'), findsOneWidget);

    // The slider sits inside its card: bring it into view through the
    // sheet's own scrollable (the reader behind holds another one).
    final sheetScrollable = find.descendant(
      of: find.byType(DisplaySettingsSheetLayout),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byType(Slider),
      80,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    // Drag the thumb left: the label follows live, the reader behind rebuilds.
    await tester.drag(find.byType(Slider), const Offset(-120, 0));
    await tester.pumpAndSettle();
    final live = (await AppPreferences.load()).panelOpacity;
    expect(live, lessThan(.80), reason: 'the dial moved the value down');

    // Release persisted it: the stored double matches the dialled value.
    final stored = (await SharedPreferences.getInstance()).getDouble(
      'reading.panelOpacity',
    );
    expect(stored, live);
  });

  testWidgets('the dialled opacity survives a fresh reader', (tester) async {
    SharedPreferences.setMockInitialValues({
      'reading.panelOpacity': .55,
    });
    LocalRepository.useBundle(FakeBibleBundle());
    await pumpReader(tester);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('55 %'), findsOneWidget);
  });
}
