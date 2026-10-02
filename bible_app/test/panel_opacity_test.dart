import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/settings_screen.dart';
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

  /// The display preferences left the reader's ⋯ sheet for the Settings screen,
  /// and the opacity row sits far down a long LECTURE card: a phone-sized
  /// surface does not build it, and a `find` below the fold returns 0 without
  /// anything being broken.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

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

  /// The opacity dial is reachable from two surfaces — the reader's ⋯ sheet and
  /// the Settings row — through the same control. Both are exercised, because
  /// a dial that works in one and not the other is exactly the kind of drift
  /// this file's counterpart guards against.
  testWidgets('the ⋯ sheet carries the opacity slider, live then persisted', (
    tester,
  ) async {
    await pumpReader(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('OPACITÉ DU PANNEAU'), findsOneWidget);
    expect(find.text('80 %'), findsOneWidget);

    // The slider sits inside its card: bring it into view through the sheet's
    // own scrollable (the reader behind holds another one). Scoped to the
    // opacity card — the size slider shares the sheet and would answer first.
    final sheetScrollable = find.descendant(
      of: find.byType(DisplaySettingsSheetLayout),
      matching: find.byType(Scrollable),
    );
    final opacitySlider = find.descendant(
      of: find.byType(DisplayOpacitySection),
      matching: find.byType(Slider),
    );
    await tester.scrollUntilVisible(
      opacitySlider,
      80,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();

    // Drag the thumb left: the label follows live, the reader behind rebuilds.
    await tester.drag(opacitySlider, const Offset(-120, 0));
    await tester.pumpAndSettle();
    final live = (await AppPreferences.load()).panelOpacity;
    expect(live, lessThan(.80), reason: 'the dial moved the value down');

    // The label must follow **during** the drag, and this assertion is the whole
    // point of the test. It used not to: `_setPanelOpacity` only called the
    // reader's `setState`, and the sheet sits in its own subtree behind its own
    // route, so nothing rebuilt it — the panel faded behind the sheet while the
    // thumb's label sat on « 80 % » until some other control happened to call
    // `setSheet` and snapped it. Checking the stored value alone passed happily
    // through that bug: the model was right, the screen was not.
    expect(
      find.text('80 %'),
      findsNothing,
      reason: 'l\'étiquette doit suivre le pouce, pas rester sur la valeur '
          'd\'avant le glissement',
    );
    expect(
      find.text('${(live * 100).round()} %'),
      findsOneWidget,
      reason: 'l\'étiquette doit afficher la valeur effectivement choisie',
    );

    // Release persisted it: the stored double matches the dialled value — on
    // release only, because writing every tick would hammer the preferences a
    // dozen times per gesture.
    final stored = (await SharedPreferences.getInstance()).getDouble(
      'reading.panelOpacity',
    );
    expect(stored, live);
  });

  testWidgets('the Settings row carries the same slider', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Opacité du panneau'), findsOneWidget);
    expect(find.text('80 %'), findsOneWidget);

    // Scoped to the opacity dial: the size row now carries a slider too, and
    // an unscoped finder would answer with whichever the tree lists first.
    final opacitySlider = find.descendant(
      of: find.byType(ReadingOpacitySlider),
      matching: find.byType(Slider),
    );
    await tester.scrollUntilVisible(opacitySlider, 80);
    await tester.pumpAndSettle();
    await tester.drag(opacitySlider, const Offset(-120, 0));
    await tester.pumpAndSettle();

    final stored = (await SharedPreferences.getInstance()).getDouble(
      'reading.panelOpacity',
    );
    expect(stored, lessThan(.80));
  });

  testWidgets('the dialled opacity is read back by the Settings screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.panelOpacity': .55,
    });
    await pumpSettings(tester);

    expect(find.text('55 %'), findsOneWidget);
  });

  testWidgets('the reader honours an opacity dialled in the Settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.panelOpacity': .30,
    });
    LocalRepository.useBundle(FakeBibleBundle());
    await pumpReader(tester);

    // The panel behind the verses is the only place the dial shows: a preference
    // written elsewhere is worthless if the reader ignores it.
    final alphas = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null)
        .map((d) => d.color!.a)
        .toList();
    expect(
      alphas.any((a) => a < .6),
      isTrue,
      reason: 'un panneau plus opaque que 0,6 trahirait une valeur ignorée',
    );
  });
}
