import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3));
  });

  tearDown(LocalRepository.useRootBundle);

  Future<void> pumpReader(
    WidgetTester tester,
    List<String> opened,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 2,
            onOpenChapter: (b, c) => opened.add('$b:$c'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipe(
    WidgetTester tester,
    Offset delta,
  ) async {
    // Start on a verse body, away from the action bar. The drag is played in
    // small steps like a real finger: a single instant jump would be resolved
    // by the gesture arena without ever dispatching the update events the
    // reader accumulates.
    final start = tester.getCenter(find.text('Verset de test Ge. 2:1.'));
    final gesture = await tester.startGesture(start);
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(delta / 12);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('swiping left opens the next chapter', (tester) async {
    final opened = <String>[];
    await pumpReader(tester, opened);

    await swipe(tester, const Offset(-180, 0));

    expect(opened, ['1:3']);
  });

  testWidgets('swiping right opens the previous chapter', (tester) async {
    final opened = <String>[];
    await pumpReader(tester, opened);

    await swipe(tester, const Offset(180, 0));

    expect(opened, ['1:1']);
  });

  testWidgets('a short slow drag does not turn the page', (tester) async {
    final opened = <String>[];
    await pumpReader(tester, opened);

    await swipe(tester, const Offset(-56, 0));

    expect(opened, isEmpty);
  });

  testWidgets('swiping is inert while verses are being selected', (
    tester,
  ) async {
    final opened = <String>[];
    await pumpReader(tester, opened);

    // Enter multi-selection with a long press.
    await tester.longPress(find.text('Verset de test Ge. 2:1.'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);

    await swipe(tester, const Offset(-200, 0));

    expect(opened, isEmpty);
  });
}
