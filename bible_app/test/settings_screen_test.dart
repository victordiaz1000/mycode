import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/settings_screen.dart';

/// The settings screen edits the persisted [AppPreferences] the reader reads:
/// a setting changed here must survive a reload, and controls that answer
/// nothing must not be shown.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  /// Brings a (possibly below-the-fold) row into view — the ListView only
  /// builds what the viewport can see.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 120);
    await tester.pumpAndSettle();
  }

  testWidgets('renders the four sections', (tester) async {
    await pumpSettings(tester);

    expect(find.text('LECTURE'), findsOneWidget);
    expect(find.text('APPARENCE'), findsOneWidget);
    // The default version is the embedded BYM.
    expect(find.text('Bible de Yehoshoua Ha Mashiah'), findsOneWidget);

    await scrollTo(tester, find.text('DONNÉES'));
    await scrollTo(tester, find.text('À PROPOS'));
  });

  testWidgets('notes switch reveals the disposition row', (tester) async {
    await pumpSettings(tester);

    // Disposition only matters when notes are on.
    expect(find.text('Disposition des notes'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('Disposition des notes'), findsOneWidget);
    expect(find.text('Texte + notes'), findsOneWidget);

    // Persisted: a fresh screen still shows notes on.
    await tester.pumpWidget(const SizedBox());
    await pumpSettings(tester);
    expect(find.text('Disposition des notes'), findsOneWidget);
  });

  testWidgets('a size chip sets the default text size', (tester) async {
    await pumpSettings(tester);

    // « Géant » chip — the largest of the six sizes.
    await tester.tap(find.byTooltip('Texte géant'));
    await tester.pump();

    final prefs = await AppPreferences.load();
    expect(prefs.fontSize, ReadingTextSize.giant.fontSize);
  });

  testWidgets('the default-version sheet offers embedded versions only',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Bible de Yehoshoua Ha Mashiah'));
    await tester.pumpAndSettle();

    // Nothing downloaded: only the embedded BYM and LSGS are choosable.
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
    // A downloadable-but-absent version must not appear: it has no text to
    // default to.
    expect(find.text('Bible Darby'), findsNothing);
  });

  testWidgets('choosing LSGS in the sheet persists the default version',
      (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Bible de Yehoshoua Ha Mashiah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bible Segond 1910 + Strongs'));
    await tester.pumpAndSettle();

    final prefs = await AppPreferences.load();
    expect(prefs.versionCode, VersionRepository.lsgsCode);
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
  });

  testWidgets('effacer l’historique asks for confirmation then clears',
      (tester) async {
    // A chapter recorded so the action has something to erase.
    final prefs = SharedPreferences.getInstance;
    (await prefs()).setString('history.recent',
        '[{"book":1,"chapter":1,"at":1000}]');

    await pumpSettings(tester);
    await scrollTo(tester, find.text('Effacer l’historique'));

    // Cancel keeps the history.
    await tester.tap(find.text('Effacer l’historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect((await prefs()).getString('history.recent'), isNotNull);

    // Confirm clears it.
    await tester.tap(find.text('Effacer l’historique'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Effacer'));
    await tester.pumpAndSettle();
    expect((await prefs()).getString('history.recent'), isNull);
  });

  testWidgets('vider le cache reports its result', (tester) async {
    await pumpSettings(tester);
    await scrollTo(tester, find.text('Vider le cache'));

    await tester.tap(find.text('Vider le cache'));
    await tester.pump();

    expect(find.textContaining('Cache vidé'), findsOneWidget);
  });

  testWidgets('thème row opens the themes screen', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Thème de lecture'));
    await tester.pumpAndSettle();

    expect(find.text('Choisis un thème de lecture : palette + fond.'),
        findsOneWidget);
  });
}