import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';

/// A pushed route that reports the active theme id it resolves.
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) =>
      Text(BibleThemeScope.of(context).id);
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
}
