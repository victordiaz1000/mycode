import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/settings_screen.dart';

/// The settings screen edits the persisted [AppPreferences] the reader reads:
/// a setting changed here must survive a reload, and controls that answer
/// nothing must not be shown.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// The display preferences moved here from the reader's ⋯ sheet, so the
  /// LECTURE card is now three times longer. A phone-sized surface only builds
  /// the first rows, and a `find` on anything below the fold returns 0 without
  /// anything being broken — so the surface is enlarged and the tests that
  /// genuinely scroll keep using [scrollTo].
  ///
  /// [pumpSettingsAt] ouvre la même chose à la largeur qu'on veut : un choix à
  /// plusieurs valeurs se juge à deux largeurs, le téléphone où les pastilles
  /// s'emballaient et la grande où elles s'étiraient.
  Future<void> pumpSettingsAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
  }

  Future<void> pumpSettings(WidgetTester tester) =>
      pumpSettingsAt(tester, 1200);

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

  /// The switch of the row titled [title], found through its own row rather
  /// than by type: `find.byType(Switch)` depends on how many switches the
  /// screen happens to draw, which is exactly what these tests should not pin.
  Finder switchInRow(String title) => find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(InkWell)),
        matching: find.byType(Switch),
      );

  testWidgets('notes switch reveals the disposition row', (tester) async {
    await pumpSettings(tester);

    // Disposition only matters when notes are on.
    expect(find.text('Disposition des notes'), findsNothing);

    await tester.tap(switchInRow('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Disposition des notes'), findsOneWidget);
    expect(find.text('Texte + notes'), findsOneWidget);

    // Persisted: a fresh screen still shows notes on.
    await tester.pumpWidget(const SizedBox());
    await pumpSettings(tester);
    expect(find.text('Disposition des notes'), findsOneWidget);
  });

  testWidgets('« sous le verset » is inert in the continuous layout', (
    tester,
  ) async {
    // The disposition is a tiles-only choice: the flow weaves the notes into the
    // sentence. « Sous » stays visible and inert — a disabled chip cannot be
    // tapped into overwriting a preference the reader wants back in the tiles.
    await pumpSettings(tester);
    await tester.tap(switchInRow('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('Disposition des notes'), findsOneWidget);

    // Tiles layout: both chips are live.
    Finder chipIn(String rowTitle, String label) => find.descendant(
          of: find.ancestor(
            of: find.text(rowTitle),
            matching: find.byType(InkWell),
          ),
          matching: find.text(label),
        );
    expect(find.byTooltip('Notes sous le verset'), findsOneWidget);
    expect(find.byTooltip('Indisponible en texte continu'), findsNothing);

    // Switch the layout to the continuous flow.
    await tester.tap(chipIn('Disposition du texte', 'Continu'));
    await tester.pumpAndSettle();
    expect(find.text('Texte continu'), findsOneWidget);

    expect(
      find.byTooltip('Indisponible en texte continu'),
      findsOneWidget,
      reason: 'l\'option doit rester visible mais inerte, et le dire',
    );
    expect(find.byTooltip('Notes sous le verset'), findsNothing);
    // The row explains itself rather than leaving a dead chip.
    expect(
      find.text('Le texte continu montre les notes à la suite'),
      findsOneWidget,
    );
  });

  testWidgets('a theme chosen elsewhere shows up here', (tester) async {
    // The home screen's palette button pushes the themes screen, which writes
    // `themeId` and resets the panel opacity. This screen lives in the shell's
    // IndexedStack, so its initState never replayed: without the listener it
    // kept announcing « Bois doré » long after the reader had chosen another.
    await pumpSettings(tester);
    expect(find.text('Bois doré'), findsOneWidget);

    // Exactly the gesture ThemesScreen performs.
    final prefs = await AppPreferences.load();
    prefs.themeId = 'azur';
    prefs.panelOpacity = .80;
    await prefs.save();
    await tester.pumpAndSettle();

    expect(
      find.text('Azur profond'),
      findsOneWidget,
      reason: 'le thème choisi ailleurs doit se lire ici',
    );
    expect(find.text('Bois doré'), findsNothing);
  });

  testWidgets('a display preference dialled in the reader shows up here', (
    tester,
  ) async {
    // Same staleness, wider than the theme: the reader's ⋯ sheet owns the size
    // and the panel opacity, and both have rows down here.
    await pumpSettings(tester);
    expect(find.text('80 %'), findsOneWidget);

    final prefs = await AppPreferences.load();
    prefs.panelOpacity = .55;
    await prefs.save();
    await tester.pumpAndSettle();

    expect(find.text('55 %'), findsOneWidget);
  });

  testWidgets('a size chip sets the default text size', (tester) async {
    await pumpSettings(tester);

    // « Géant » chip — the largest of the six sizes. Its tooltip comes from the
    // control shared with the reader's ⋯ sheet, hence the wording.
    await tester.tap(find.byTooltip('Taille du texte géant'));
    await tester.pump();

    final prefs = await AppPreferences.load();
    expect(prefs.fontSize, ReadingTextSize.giant.fontSize);
  });

  testWidgets('les choix du texte se lisent en une barre, jamais en pile', (
    tester,
  ) async {
    // 412 px, la largeur d'un téléphone : les six tailles arrivaient en 4 + 2
    // et chaque bouton de disposition s'étirait sur toute la carte pour se
    // retrouver empilé sous le suivant — trois écrans de réglages pour deux
    // valeurs.
    await pumpSettingsAt(tester, 412);

    final lignes = {
      for (final size in ReadingTextSize.values)
        tester.getCenter(find.byTooltip('Taille du texte ${size.label}')).dy,
    };
    expect(lignes.length, 1, reason: 'les six tailles sur une seule ligne');

    final separes = tester.getRect(find.text('Séparés'));
    final continu = tester.getRect(find.text('Continu'));
    expect(
      separes.center.dy,
      closeTo(continu.center.dy, 1),
      reason: 'côte à côte, pas empilés',
    );
    // Le pas entre les deux centres vaut la largeur d'un segment : à 412 px la
    // barre en a 142, jamais la carte entière.
    expect(
      continu.center.dx - separes.center.dx,
      inInclusiveRange(60, 200),
      reason: 'un segment n\'est ni un point ni la largeur de la rangée',
    );
  });

  testWidgets('sur un grand écran, la barre garde la taille d\'un contrôle', (
    tester,
  ) async {
    await pumpSettings(tester);

    final separes = tester.getRect(find.text('Séparés'));
    final continu = tester.getRect(find.text('Continu'));
    expect(
      separes.center.dy,
      closeTo(continu.center.dy, 1),
      reason: 'la largeur ne les remet pas l\'un sous l\'autre',
    );
    expect(
      continu.center.dx - separes.center.dx,
      inInclusiveRange(150, 250),
      reason: 'segments égaux et plafonnés : à 1 200 px la rangée mesure '
          '1 078 px et la barre reste celle d\'un contrôle, pas un curseur',
    );
  });

  testWidgets('a reading font choice is persisted', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Police de lecture'));
    await tester.pumpAndSettle();

    expect(find.text('Classique · Lora'), findsOneWidget);
    expect(find.text('Élégante'), findsOneWidget);
    expect(find.text('Plus Jakarta Sans'), findsWidgets);
    expect(find.text('Literata'), findsWidgets);
    // « Moderne » asked for the platform `sans-serif`, the one family the
    // bundle did not embed: it rendered differently on every device and was
    // dropped. A stored 'modern' migrates to Plus Jakarta Sans.
    expect(find.text('Moderne'), findsNothing);

    await tester.tap(find.text('Élégante'));
    await tester.pumpAndSettle();

    final prefs = await AppPreferences.load();
    expect(prefs.readingFont, ReadingFont.elegant);
  });
  testWidgets('the default-version sheet offers embedded versions only', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Bible de Yehoshoua Ha Mashiah'));
    await tester.pumpAndSettle();

    // Nothing downloaded: only the embedded BYM and LSGS are choosable.
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
    // A downloadable-but-absent version must not appear: it has no text to
    // default to.
    expect(find.text('Bible Darby'), findsNothing);
  });

  testWidgets('choosing LSGS in the sheet persists the default version', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Bible de Yehoshoua Ha Mashiah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bible Segond 1910 + Strongs'));
    await tester.pumpAndSettle();

    final prefs = await AppPreferences.load();
    expect(prefs.versionCode, VersionRepository.lsgsCode);
    expect(find.text('Bible Segond 1910 + Strongs'), findsOneWidget);
  });

  testWidgets('effacer l’historique asks for confirmation then clears', (
    tester,
  ) async {
    // A chapter recorded so the action has something to erase.
    final prefs = SharedPreferences.getInstance;
    (await prefs()).setString(
      'history.recent',
      '[{"book":1,"chapter":1,"at":1000}]',
    );

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

    expect(
      find.text('Choisis un thème de lecture : palette + fond.'),
      findsOneWidget,
    );
  });

  /// Une mise à jour appliquée doit se **dire**, et pas seulement se voir dans la
  /// ligne d'état : le lecteur vient de taper un bouton et il faut qu'il sache
  /// que c'est fait, et qu'il n'a rien à rouvrir.
  testWidgets('une mise à jour appliquée annonce que la lecture suit', (
    tester,
  ) async {
    BymUpdateChecker.available.value = const BymUpdateCheck(
      BymUpdateStatus.available,
      commit: 'cb535d4a3c9f1e2b7d8a4c5e6f708192a3b4c5d6',
      books: ['01-Genese.md', '28-Proverbes.md', '40-Matthieu.md'],
      notes: 'Pr. 6:16 qu\'Elohîm -> que YHWH',
    );
    addTearDown(BymUpdateChecker.clear);

    // L'installation réelle écrit des fichiers, et `path_provider` ne répond pas
    // dans la zone fake-async d'un `testWidgets` : c'est `apply` qu'on remplace,
    // pas le réseau. Ce test porte sur ce que l'écran dit, pas sur ce que le
    // service fait — `bym_update_service_test.dart` couvre l'autre moitié.
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(updateService: _AppliedUpdates())),
    );
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Mettre à jour (3 livres)'));

    await tester.tap(find.text('Mettre à jour (3 livres)'));
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('La lecture est déjà à jour'),
      findsOneWidget,
      reason: 'la ligne d\'état ne peut pas dire ça, le message si',
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

/// Service dont l'installation réussit sans toucher au disque ni au réseau.
class _AppliedUpdates extends BymUpdateService {
  @override
  Future<BymUpdateOutcome> apply(
    BymUpdateCheck plan, {
    void Function(BymUpdateProgress)? onProgress,
  }) async => BymUpdateOutcome(BymUpdateStatus.applied, plan.bookCount);
}
