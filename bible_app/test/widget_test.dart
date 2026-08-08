import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/main.dart';

void main() {
  testWidgets('Home shell renders navigation destinations',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BymApp());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Accueil'), findsOneWidget);
    expect(find.text('Lecture'), findsOneWidget);
    expect(find.text('Recherche'), findsOneWidget);
    expect(find.text('Bibliothèque'), findsOneWidget);
    expect(find.text('Réglages'), findsOneWidget);
  });
}
