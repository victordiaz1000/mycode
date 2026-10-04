import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/widgets/holy_icons.dart';

/// Le rendu des cinq icônes, tel qu'il doit paraître sur la barre.
///
/// Un golden et non un détail de tracé : ce qui est jugé ici est l'image —
/// lisibilité à 24 px, équilibre du trait, tenue de l'étoile dans la lentille.
/// Se régénère par `flutter test --update-goldens test/holy_icons_golden_test.dart`.
void main() {
  // Fond et teintes de l'application : fond crème, or sélectionné, gris repos.
  const background = Color(0xFFFAF7F0);
  const gold = Color(0xFFB08535);
  const muted = Color(0xFF8B8B8B);

  testWidgets('les cinq icônes, gris en haut et or en bas', (tester) async {
    // Cadre serré : l'image juge le dessin, pas un fond vide de 800×600.
    tester.view.physicalSize = const Size(700, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: background,
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final glyph in HolyGlyph.values)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconTheme(
                          data: IconThemeData(color: muted, size: 24),
                          child: HolyIcon(glyph),
                        ),
                        SizedBox(height: 22),
                        IconTheme(
                          data: IconThemeData(color: gold, size: 44),
                          child: HolyIcon(glyph),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/holy_icons.png'),
    );
  });
}
