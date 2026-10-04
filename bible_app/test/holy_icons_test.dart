import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/widgets/holy_icons.dart';

/// Les cinq icônes de la barre d'onglets.
///
/// Deux choses sont à garantir : le dessin suit la taille qu'on lui donne,
/// et — le point qui fait l'or — que l'[IconTheme] posé par [NavigationBar]
/// et [NavigationRail] arrive bien jusqu'au peintre. C'est lui qui colore
/// l'onglet choisi : l'icône, elle, ne connaît pas son état.
void main() {
  const gold = Color(0xFFC9A227);
  const muted = Color(0xFF8B8B8B);

  List<HolyIconPainter> painters(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is HolyIconPainter,
        ),
      )
      .map((w) => w.painter! as HolyIconPainter)
      .toList();

  Future<void> pumpBar(WidgetTester tester, {required int selected}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              iconTheme: WidgetStateProperty.resolveWith(
                (states) => IconThemeData(
                  color: states.contains(WidgetState.selected) ? gold : muted,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (_) {},
              destinations: [
                for (final glyph in HolyGlyph.values)
                  NavigationDestination(icon: HolyIcon(glyph), label: glyph.name),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('les cinq motifs se peignent, en taille 24 par défaut',
      (tester) async {
    await pumpBar(tester, selected: 0);

    expect(HolyGlyph.values, hasLength(5));
    final found = painters(tester);
    expect(found, hasLength(5), reason: 'un peintre par onglet');
    expect(found.map((p) => p.glyph).toSet(), HolyGlyph.values.toSet());
    expect(tester.getSize(find.byType(HolyIcon).first).width, 24);
  });

  testWidgets('l\'onglet choisi est peint en or, les autres en gris',
      (tester) async {
    await pumpBar(tester, selected: 2);

    final found = painters(tester);
    expect(
      found.map((p) => p.color),
      [muted, muted, gold, muted, muted],
      reason: 'la couleur vient du thème, l’icône ne la choisit pas',
    );
  });

  testWidgets('la taille suit l\'IconTheme du contexte', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: IconTheme(
          data: IconThemeData(size: 32),
          child: Center(child: HolyIcon(HolyGlyph.etoile)),
        ),
      ),
    );

    expect(tester.getSize(find.byType(HolyIcon)).width, 32);
  });

  testWidgets('le rail de tablette distingue l\'onglet choisi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: 1,
                onDestinationSelected: (_) {},
                destinations: [
                  for (final glyph in HolyGlyph.values)
                    NavigationRailDestination(
                      icon: HolyIcon(glyph),
                      label: Text(glyph.name),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final found = painters(tester);
    expect(found, hasLength(5));
    expect(
      found.map((p) => p.color).toSet().length,
      2,
      reason: 'deux teintes au moins : sélection et repos',
    );
    expect(found[1].color, isNot(found[0].color));
  });
}
