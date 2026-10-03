// La règle visuelle du squelette : sous le `ShaderMask` en `srcATop`, seul
// l'alpha du contenu survit — deux aplats opaques (carte et barre) recevaient
// donc la *même* teinte et toute la structure fusionnait dans une masse grise.
// Ces tests tiennent cet écart pour acquis.
import 'package:bible_app/widgets/loading_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Color? _fillOf(Widget widget) {
  if (widget is! Container) return null;
  final decoration = widget.decoration;
  return decoration is BoxDecoration ? decoration.color : null;
}

void main() {
  testWidgets('cartes translucides, barres opaques : la structure se lit', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ListLoadingSkeleton(itemCount: 3)),
    ));

    final fills = tester
        .widgetList<Container>(find.byType(Container))
        .map(_fillOf)
        .whereType<Color>()
        .toList();

    expect(fills, contains(kSkeletonCardFill),
        reason: 'le panneau du squelette doit être translucide : deux aplats '
            'opaques fusionnent sous le masque et effacent les barres');
    expect(fills, contains(Colors.white),
        reason: 'les barres restent opaques — c’est cet écart alpha qui '
            'dessine la hiérarchie');
    expect(kSkeletonCardFill.a, greaterThan(0),
        reason: 'un fond totalement transparent n’est plus un panneau');
    expect(kSkeletonCardFill.a, lessThan(1),
        reason: 'un fond opaque redevient la même masse que les barres');
  });

  testWidgets('le balayage traverse un cycle sans casser le squelette', (
    tester,
  ) async {
    // Liste, pas [HomeLoadingSkeleton] : celle-ci porte 659 px de hauteurs
    // figées et n'existe que dans un défilement (cf. `_InterfaceSkeleton`).
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ListLoadingSkeleton()),
    ));

    // 1900 ms par demi-cycle : un aller-retour complet, à l'aveugle.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 475));
    }

    expect(tester.takeException(), isNull,
        reason: 'un aller-retour adouci ne doit rien faire sauter');
    expect(find.byType(ListLoadingSkeleton), findsOneWidget);
  });

  testWidgets('animations réduites : le squelette s’affiche, le moteur non', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ListLoadingSkeleton(itemCount: 2),
        ),
      ),
    ));

    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull,
        reason: 'le contrôleur doit se figer sans jamais démarrer de ticker');
    expect(find.byType(SkeletonBox), findsWidgets,
        reason: 'le contenu reste affiché, simplement immobile');
  });
}
