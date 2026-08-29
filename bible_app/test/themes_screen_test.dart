import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/custom_background.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/screens/themes_screen.dart';

/// The two scene-like fonds (frieze, world map) cover the screen; every other
/// fond is a small seamless texture that must repeat as tiles.
const Set<String> _coverThemes = {'vitrail', 'parchemin'};

/// The only dark palettes: their light text is what flips the whole app to
/// dark surfaces (`usesLightText`), so it must stay in sync with the catalog.
const Set<String> _lightTextThemes = {'azur', 'nuit'};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    AppPreferences.themeNotifier.value = bibleThemes.first.id;
    CustomBackgroundStore.restore(null);
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ThemesScreen()));
    await tester.pumpAndSettle();
  }

  int columnsOf(WidgetTester tester) {
    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    return delegate.crossAxisCount;
  }

  testWidgets('uses two columns on a phone, without overflow', (tester) async {
    await pump(tester, const Size(360, 800));
    expect(columnsOf(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow phones keep two columns and fit the cards',
      (tester) async {
    await pump(tester, const Size(320, 640));
    expect(columnsOf(tester), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablets widen the grid, without overflow', (tester) async {
    await pump(tester, const Size(900, 800));
    expect(columnsOf(tester), greaterThan(2));
    expect(tester.takeException(), isNull);
  });

  test('every theme points at an existing fond and declares the right fit', () {
    expect(bibleThemes.map((t) => t.id), containsAll(_coverThemes));
    for (final theme in bibleThemes) {
      expect(
        File(theme.backgroundAsset).existsSync(),
        isTrue,
        reason: '${theme.id}: missing asset ${theme.backgroundAsset}',
      );
      expect(
        theme.backgroundFit,
        _coverThemes.contains(theme.id) ? BackgroundFit.cover : BackgroundFit.tile,
        reason: '${theme.id} (${theme.backgroundAsset})',
      );
      expect(
        theme.usesLightText,
        _lightTextThemes.contains(theme.id),
        reason: '${theme.id} must ${_lightTextThemes.contains(theme.id) ? "keep" : "drop"} light text',
      );
    }
  });

  testWidgets('cards preview the real background the way the reader paints it',
      (tester) async {
    await pump(tester, const Size(360, 800));

    DecorationImage? imageOf(String asset) {
      for (final box in tester.widgetList<DecoratedBox>(
        find.byWidgetPredicate(
          (w) => w is DecoratedBox && (w.decoration as BoxDecoration).image != null,
        ),
      )) {
        final image = (box.decoration as BoxDecoration).image!;
        if ((image.image as AssetImage).assetName == asset) return image;
      }
      return null;
    }

    // Azur profond is the first displayed card: its fond is a texture, so the
    // preview must tile it at natural size — the old cover stretched it blurry.
    final azur = imageOf('assets/themes/bleu.png');
    expect(azur, isNotNull);
    expect(azur!.repeat, ImageRepeat.repeat);
    expect(azur.fit, isNull);

    // The mini-reading panel sits on the preview: body sample + verse number.
    expect(find.text('Aa'), findsWidgets);
    expect(find.text('12'), findsWidgets);

    // Papier clair carries the world-map scene: cover, never repeated.
    // The GridView is itself a Scrollable (shrinkWrap, never-scrollable), so
    // the drag targets the outer ListView explicitly.
    await tester.dragUntilVisible(
      find.text('Papier clair'),
      find.byType(ListView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final map = imageOf('assets/themes/bg.png');
    expect(map, isNotNull);
    expect(map!.fit, BoxFit.cover);
    expect(map.repeat, ImageRepeat.noRepeat);
  });

  testWidgets('tapping a card saves the theme and says so', (tester) async {
    await pump(tester, const Size(360, 800));

    await tester.tap(find.text('Azur profond'));
    await tester.pumpAndSettle();

    expect(AppPreferences.themeNotifier.value, 'azur');
    expect(find.text('Thème enregistré'), findsOneWidget);
  });

  testWidgets('choosing a NEW theme resets the panel opacity to the default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.panelOpacity': 0.5,
      'reading.themeId': 'vitrail',
    });
    await pump(tester, const Size(360, 800));

    await tester.tap(find.text('Azur profond'));
    await tester.pumpAndSettle();

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('reading.themeId'), 'azur');
    expect(
      sp.getDouble('reading.panelOpacity'),
      .80,
      reason: 'a new background must not inherit the previous dial',
    );
  });

  testWidgets('re-tapping the CURRENT theme keeps the dialled opacity', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reading.panelOpacity': 0.5,
      'reading.themeId': 'azur',
    });
    await pump(tester, const Size(360, 800));

    await tester.tap(find.text('Azur profond'));
    await tester.pumpAndSettle();

    expect(
      (await SharedPreferences.getInstance()).getDouble('reading.panelOpacity'),
      0.5,
    );
  });

  /// Scrolls the outer ListView until [finder] is on screen — the 12 theme
  /// cards push the custom section below the fold, and a lazy list never
  /// builds what is off-screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.dragUntilVisible(finder, find.byType(ListView),
        const Offset(0, -300));
    await tester.pumpAndSettle();
  }

  testWidgets('without a photo the custom section offers picking one', (
    tester,
  ) async {
    await pump(tester, const Size(360, 800));
    await scrollTo(tester, find.text('Choisir une photo'));

    expect(find.text('FOND PERSONNALISÉ'), findsOneWidget);
    expect(find.text('Choisir une photo'), findsOneWidget);
    // Nothing to select or delete yet.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('an installed photo theme shows its card and deletes cleanly', (
    tester,
  ) async {
    // A real file so the delete can actually remove it, persisted through
    // the same JSON path a restart would read. SYNC disk access only:
    // awaited file I/O never completes inside the fake-async zone.
    final temp = Directory.systemTemp.createTempSync('custom_theme_ui');
    addTearDown(() => temp.deleteSync(recursive: true));
    // A valid 1×1 PNG — the preview's FileImage must decode, not error.
    final photo = File('${temp.path}/custom_background.img');
    photo.writeAsBytesSync(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ'
      'AAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    ));
    final theme = BibleTheme(
      id: customThemeId,
      name: 'Ma photo',
      customFile: photo.path,
      backgroundTone: const Color(0xFF202020),
      textColor: const Color(0xFFEEEEEE),
      titleColor: const Color(0xFFF0C75C),
      verseNumColor: const Color(0xFFA8B4C8),
      accentColor: const Color(0xFFD9B44A),
      highlightRef: const Color(0xFFE6BE55),
    );
    SharedPreferences.setMockInitialValues({
      'reading.customTheme': jsonEncode(
        CustomBackgroundStore.themeToJson(theme),
      ),
      // Reading on the default theme: the photo card offers applying it.
      'reading.themeId': bibleThemes.first.id,
    });

    await pump(tester, const Size(360, 800));
    await scrollTo(tester, find.text('Ma photo'));

    expect(find.text('FOND PERSONNALISÉ'), findsOneWidget);
    expect(find.text('Ma photo'), findsOneWidget);
    expect(find.text('Toucher pour appliquer'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Selecting the photo theme persists the 'custom' id.
    await tester.tap(find.text('Toucher pour appliquer'));
    await tester.pumpAndSettle();
    expect(
      (await SharedPreferences.getInstance()).getString('reading.themeId'),
      customThemeId,
    );

    // Deleting asks first, then clears the slot, the JSON and the file —
    // and the selection falls back to the default theme.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('reading.customTheme'), isNull);
    expect(sp.getString('reading.themeId'), bibleThemes.first.id);
    expect(photo.existsSync(), isFalse);
    expect(CustomBackgroundStore.current, isNull);
    await scrollTo(tester, find.text('Choisir une photo'));
    expect(find.text('Choisir une photo'), findsOneWidget);
  });
}
