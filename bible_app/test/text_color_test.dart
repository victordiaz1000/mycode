import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/screens/settings_screen.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

/// The rendered colour of the fake chapter's first verse.
Color? verseColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('Verset de test Ge. 1:1.')).style?.color;

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
      // Le scope porte le thème actif (défaut : Bois doré) ; sans lui le
      // lecteur retomberait sur bibleThemes.first, un secours de catalogue.
      const BibleThemeScope(
        child: MaterialApp(
          home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The swatches moved to the Settings screen with the rest of the display
  /// preferences. Each test therefore changes the colour there and **re-opens the
  /// reader**: the reader listens to `AppPreferences.revision`, and a setting
  /// written on another surface is worth nothing if the reader ignores it. That
  /// propagation is the thing worth pinning now.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const BibleThemeScope(child: MaterialApp(home: SettingsScreen())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapSwatch(WidgetTester tester, String tooltip) async {
    await pumpSettings(tester);
    await tester.scrollUntilVisible(find.byTooltip(tooltip), 80);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  testWidgets('without an override the verses wear the theme colour', (
    tester,
  ) async {
    await pumpReader(tester);
    // Défaut de la lecture : Bois doré (« forest »).
    expect(verseColor(tester), themeById('forest').textColor);
  });

  testWidgets('the Settings row offers the swatches and applies one live', (
    tester,
  ) async {
    await pumpSettings(tester);
    expect(find.text('Couleur du texte'), findsOneWidget);
    expect(find.byTooltip('Suivre le thème'), findsOneWidget);

    await tapSwatch(tester, 'Bleu nuit');
    await pumpReader(tester);

    expect(verseColor(tester), const Color(0xFF1E2A44));
    final stored = (await SharedPreferences.getInstance()).getString(
      'reading.textColor',
    );
    expect(stored, const Color(0xFF1E2A44).toARGB32().toString());
  });

  testWidgets('back to « Suivre le thème » clears the override', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.textColor': const Color(0xFF1E2A44).toARGB32().toString(),
    });
    LocalRepository.useBundle(FakeBibleBundle());
    await pumpReader(tester);
    expect(verseColor(tester), const Color(0xFF1E2A44));

    await tapSwatch(tester, 'Suivre le thème');
    await pumpReader(tester);

    expect(verseColor(tester), themeById('forest').textColor);
    expect(
      (await SharedPreferences.getInstance()).getString('reading.textColor'),
      isNull,
    );
  });

  test('withTextColor recomputes the derived colours and the light/dark flip',
      () {
    final base = themeById('vitrail');
    expect(base.usesLightText, isFalse);

    final light = base.withTextColor(const Color(0xFFEDF3FC));
    expect(light.textColor, const Color(0xFFEDF3FC));
    expect(
      light.usesLightText,
      isTrue,
      reason: 'a light text colour must flip the panels dark',
    );
    expect(light.noteColor, isNot(base.noteColor));
    // Everything else is carried over untouched.
    expect(light.accentColor, base.accentColor);
    expect(light.backgroundAsset, base.backgroundAsset);
    expect(light.id, base.id);
  });
}
