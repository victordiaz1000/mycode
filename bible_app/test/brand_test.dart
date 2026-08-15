import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/main.dart';
import 'package:bible_app/screens/home_screen.dart';

void main() {
  testWidgets('the app launches straight onto the shell, no brand splash',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate((w) =>
          w is Image && w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/brand/splash.png'),
      findsNothing,
    );
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Bym classic', findRichText: true), findsOneWidget);
  });

  testWidgets('the home top bar shows the Bym classic title', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeScreen(
          manager: TabManager(),
          onSelectDestination: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Bym classic', findRichText: true), findsOneWidget);
  });
}