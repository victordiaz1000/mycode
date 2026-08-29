import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';

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

  /// Opens the ⋯ sheet (unless it is already open — a second tap would hit
  /// the modal barrier and dismiss it) and scrolls [target] into view: the
  /// colour section sits at the bottom of the scrollable sheet, off-screen
  /// in the test surface.
  Future<void> openSheet(WidgetTester tester, Finder target) async {
    if (find.byType(DisplaySettingsSheetLayout).evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(
      target,
      80,
      scrollable: find.descendant(
        of: find.byType(DisplaySettingsSheetLayout),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('without an override the verses wear the theme colour', (
    tester,
  ) async {
    await pumpReader(tester);
    // Défaut de la lecture : Bois doré (« forest »).
    expect(verseColor(tester), themeById('forest').textColor);
  });

  testWidgets('the ⋯ sheet offers the swatches and applies one live', (
    tester,
  ) async {
    await pumpReader(tester);

    await openSheet(tester, find.text('COULEUR DU TEXTE'));
    expect(find.text('COULEUR DU TEXTE'), findsOneWidget);
    expect(find.byTooltip('Suivre le thème'), findsOneWidget);

    await openSheet(tester, find.byTooltip('Bleu nuit'));
    await tester.tap(find.byTooltip('Bleu nuit'));
    await tester.pumpAndSettle();

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

    await openSheet(tester, find.byTooltip('Suivre le thème'));
    await tester.tap(find.byTooltip('Suivre le thème'));
    await tester.pumpAndSettle();

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
