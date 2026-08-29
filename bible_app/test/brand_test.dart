import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/main.dart';
import 'package:bible_app/screens/home_screen.dart';

void main() {
  testWidgets('the app launches straight onto the shell, no brand splash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/brand/splash.png',
      ),
      findsNothing,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Bym classic', findRichText: true), findsOneWidget);
  });

  testWidgets('the home top bar shows the Bym classic title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(manager: TabManager(), onSelectDestination: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bym classic', findRichText: true), findsOneWidget);
  });

  testWidgets('quick actions carry Notes, never Audio, and speak as buttons', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(manager: TabManager(), onSelectDestination: (_) {}),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Reprendre'), findsOneWidget);
    expect(find.text('Favoris'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Comparer'), findsOneWidget);
    expect(find.text('Audio'), findsNothing);

    // Icon-only header buttons announce their action to screen readers.
    expect(find.bySemanticsLabel('Thèmes'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^Onglets ouverts')), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('the « Jean 3.16 » pill hands the query to the search', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    String? asked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeScreen(
            manager: TabManager(),
            onSelectDestination: (_) {},
            onSearchQuery: (query) => asked = query,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Jean 3.16'));
    await tester.pump();

    expect(asked, 'Jean 3:16',
        reason: 'la puce lance la recherche, elle ne se contente pas d’ouvrir '
            'l’onglet Recherche');
  });
}
