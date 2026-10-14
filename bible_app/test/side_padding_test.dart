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

  /// La rangée vit bas dans la carte LECTURE : sans grande surface, le
  /// `find` sous le pli répond 0 sans que rien ne soit cassé.
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

  testWidgets('the default side padding is 14 px', (
    tester,
  ) async {
    final prefs = await AppPreferences.load();
    expect(prefs.sidePadding, 14.0);
  });

  testWidgets('the Settings row carries the margins slider', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Marges latérales'), findsOneWidget);
    expect(find.text('14 px'), findsOneWidget);

    // Limité au curseur des marges : la rangée de taille porte aussi un
    // curseur, et un finder libre répondrait le premier de l'arbre.
    final paddingSlider = find.descendant(
      of: find.byType(ReadingPaddingSlider),
      matching: find.byType(Slider),
    );
    await tester.scrollUntilVisible(paddingSlider, 80);
    await tester.pumpAndSettle();
    await tester.drag(paddingSlider, const Offset(600, 0));
    await tester.pumpAndSettle();

    final stored = (await SharedPreferences.getInstance()).getDouble(
      'reading.sidePadding',
    );
    expect(stored, 48.0);
    expect(find.text('48 px'), findsOneWidget);
  });

  testWidgets('the dialled padding is read back by the Settings screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reading.sidePadding': 8.0});
    await pumpSettings(tester);

    expect(find.text('8 px'), findsOneWidget);
  });

  testWidgets('the ⋯ sheet carries the same slider', (tester) async {
    await pumpReader(tester);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(find.text('MARGES LATÉRALES'), findsOneWidget);

    final sheetScrollable = find.descendant(
      of: find.byType(DisplaySettingsSheetLayout),
      matching: find.byType(Scrollable),
    );
    final paddingSlider = find.descendant(
      of: find.byType(DisplayPaddingSection),
      matching: find.byType(Slider),
    );
    await tester.scrollUntilVisible(
      paddingSlider,
      80,
      scrollable: sheetScrollable,
    );
    await tester.pumpAndSettle();
    await tester.drag(paddingSlider, const Offset(-200, 0));
    await tester.pumpAndSettle();

    final stored = (await SharedPreferences.getInstance()).getDouble(
      'reading.sidePadding',
    );
    expect(stored, lessThan(14.0));
  });

  testWidgets('the reader honours padding dialled in the Settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reading.sidePadding': 6.0});
    await pumpReader(tester);

    // La liste des versets est le seul endroit où le réglage se voit : une
    // préférence écrite ailleurs ne vaut rien si le lecteur l'ignore.
    final listView = tester.widgetList<ListView>(find.byType(ListView)).firstWhere(
      (v) {
        final p = v.padding;
        return p is EdgeInsets && p.left == 6.0 && p.right == 6.0;
      },
      orElse: () => throw TestFailure('aucune liste à 6 px de marges'),
    );
    final padding = listView.padding! as EdgeInsets;
    expect(padding.top, 16);
    expect(padding.bottom, 26);
  });
}
