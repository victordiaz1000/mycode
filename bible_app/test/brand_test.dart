import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/main.dart';
import 'package:bible_app/screens/home_screen.dart';
import 'package:bible_app/widgets/splash_screen.dart';

void main() {
  testWidgets('the splash shows the start-up image, then the shell takes over',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const BymApp(showSplash: true));

    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // The splash owns a real timer; pump past it instead of relying on
    // pumpAndSettle, which would wait past the transition.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    // The splash keeps its place in the tree but now renders the shell: the
    // brand image is gone (only the home logo image remains) and the
    // navigation bar took over.
    final remaining = find.byWidgetPredicate((w) =>
        w is Image && w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/brand/splash.png');
    expect(remaining, findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) =>
          w is Image && w.image is AssetImage &&
          (w.image as AssetImage).assetName == 'assets/brand/logo.png'),
      findsOneWidget,
    );
  });

  testWidgets('the home top bar shows the logo image', (tester) async {
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

    final logo = find.byWidgetPredicate((w) =>
        w is Image && w.image is AssetImage &&
        (w.image as AssetImage).assetName == 'assets/brand/logo.png');
    expect(logo, findsOneWidget);
  });
}