import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/premium_style.dart';

/// A pushed route that reports the active theme id it resolves.
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) =>
      Text(BibleThemeScope.of(context).id);
}

/// Rapporte la palette dérivée, pas le thème : c'est elle que l'interface lit.
class _PaletteProbe extends StatelessWidget {
  const _PaletteProbe();

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Text('${p.primary.toARGB32()}/${p.surface.toARGB32()}');
  }
}

void main() {
  testWidgets('the theme scope reaches routes pushed on the Navigator',
      (tester) async {
    AppPreferences.themeNotifier.value = 'azur';
    addTearDown(
      () => AppPreferences.themeNotifier.value = bibleThemes.first.id,
    );

    // Mirrors the app's builder: the scope wraps the Navigator, so every route
    // — `home` and anything pushed later — inherits it. It used to sit on
    // `home` only, leaving pushed routes to fall back to bibleThemes.first.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BibleThemeScope(child: child!),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _ThemeProbe()),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(
      find.text('azur'),
      findsOneWidget,
      reason: 'the pushed route inherits the scope, not the fallback theme',
    );
  });

  testWidgets('la palette suit un changement de thème, cache compris', (
    tester,
  ) async {
    // `premiumPalette` garde la dernière palette calculée pour ne pas refaire
    // une douzaine de `Color.lerp` à chacun de ses appels — une quinzaine par
    // build d'écran. Le cache tient sur l'identité du thème ; ce test est son
    // garde-fou : une entrée qui ne s'invaliderait pas figerait les couleurs
    // de toute l'interface au premier thème rencontré.
    addTearDown(
      () => AppPreferences.themeNotifier.value = bibleThemes.first.id,
    );

    Future<String> paletteUnder(String themeId) async {
      AppPreferences.themeNotifier.value = themeId;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => BibleThemeScope(child: child!),
          home: const _PaletteProbe(),
        ),
      );
      await tester.pumpAndSettle();
      return (tester.widget<Text>(find.byType(Text)).data)!;
    }

    // « Nuit étoilée » contre « Oliveraie » : accents et surfaces opposés, et
    // l'un est un thème sombre — une palette figée se verrait immédiatement.
    final nuit = await paletteUnder('nuit');
    final oliveraie = await paletteUnder('oliveraie');

    expect(
      oliveraie,
      isNot(nuit),
      reason: 'la palette doit être recalculée quand le thème change',
    );

    // Et le retour au premier thème redonne exactement sa palette : le cache
    // sert la bonne entrée, il ne décale pas d'un cran.
    expect(await paletteUnder('nuit'), nuit);
  });
}
