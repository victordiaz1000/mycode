import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/main.dart';

void main() {
  testWidgets('Home shell renders navigation destinations', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const BymApp());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Recherche'), findsOneWidget);
    expect(find.text('Bibliothèque'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });

  testWidgets('Home shell uses a navigation rail on tablets', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const BymApp());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('the active destination is restored after a cold restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'shell.destination': 2,
    });
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();

    // The Recherche destination (index 2) is selected, not the Accueil.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);

    // An out-of-range value falls back to the Accueil instead of crashing.
    SharedPreferences.setMockInitialValues({
      'shell.destination': 42,
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0);
  });
}
