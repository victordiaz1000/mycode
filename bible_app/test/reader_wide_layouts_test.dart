import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/parallel_reading_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';

/// Les deux mises en page larges de la lecture :
///
///  * §02 — la **lecture parallèle en volets**. Elle existait déjà, mais
///    uniquement en `push` plein écran : on quittait le chapitre pour
///    comparer, on perdait sa position et le panneau d'étude ouvert. À partir
///    du palier `expanded`, les deux versions tiennent côte à côte *dans* la
///    page, et le ⇄ de la barre devient une bascule. Sous le palier, la route
///    plein écran reste — deux colonnes y tomberaient sous 40 caractères.
///  * §03 — le **sommaire du livre**, troisième colonne au-delà de 1600 px.
///
/// Le viewport des tests fait 800x600 par défaut : assez large pour que la
/// barre porte son ⇄ (seuil 600) mais sous `expanded` (840), ce qui en fait
/// pile le garde-fou dont on a besoin.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3, verses: 4));
    LsgsRepository.useBundle(FakeLsgsBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpReader(WidgetTester tester, {Size? size}) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder parallelButton() =>
      find.byTooltip('Lecture parallèle — deux versions');

  testWidgets('≥ 840 : le ⇄ installe les volets dans la page', (tester) async {
    await pumpReader(tester, size: const Size(1024, 768));

    expect(find.byType(ParallelReadingScreen), findsNothing);

    await tester.tap(parallelButton());
    await tester.pumpAndSettle();

    final panes = find.byType(ParallelReadingScreen);
    expect(panes, findsOneWidget);
    expect(
      tester.widget<ParallelReadingScreen>(panes).embedded,
      isTrue,
      reason: 'les volets vivent dans la page, sans coque ni AppBar propre',
    );
    // La preuve qu'on n'a pas quitté le chapitre : aucune route empilée, donc
    // aucune flèche de retour, et la barre d'actions de la lecture est
    // toujours là au-dessus des volets.
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Fermer la lecture parallèle'), findsOneWidget);
  });

  testWidgets('≥ 840 : le même bouton referme les volets', (tester) async {
    await pumpReader(tester, size: const Size(1024, 768));

    await tester.tap(parallelButton());
    await tester.pumpAndSettle();
    expect(find.byType(ParallelReadingScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer la lecture parallèle'));
    await tester.pumpAndSettle();
    expect(find.byType(ParallelReadingScreen), findsNothing);
    expect(parallelButton(), findsOneWidget, reason: 'le ⇄ reprend son état');
  });

  testWidgets('sous 840 : le ⇄ pousse l’écran plein, comme avant', (
    tester,
  ) async {
    // 800x600 : le ⇄ est dans la barre, mais la largeur ne permet pas deux
    // colonnes lisibles.
    await pumpReader(tester);

    await tester.tap(parallelButton());
    await tester.pumpAndSettle();

    final pushed = find.byType(ParallelReadingScreen);
    expect(pushed, findsOneWidget);
    expect(
      tester.widget<ParallelReadingScreen>(pushed).embedded,
      isFalse,
      reason: 'en deçà du palier, la lecture parallèle reste un écran entier',
    );
  });

  testWidgets('≥ 1600 : le sommaire du livre prend la troisième colonne', (
    tester,
  ) async {
    await pumpReader(tester, size: const Size(1600, 900));

    expect(
      find.text(catalogEntry(1).barLabel.toUpperCase()),
      findsOneWidget,
      reason: 'l’en-tête du sommaire nomme le livre en cours',
    );
  });

  testWidgets('sous 1600 : pas de sommaire, la place manque', (tester) async {
    await pumpReader(tester, size: const Size(1280, 800));

    expect(find.text(catalogEntry(1).barLabel.toUpperCase()), findsNothing);
  });
}
