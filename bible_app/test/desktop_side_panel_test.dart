import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// Les panneaux latéraux du desktop (étapes C/C2) : à ≥ 1040 px de large, le
/// tap d'un code Strong et le tap d'un verset épinglent leur contenu à droite
/// au lieu d'ouvrir une modale — et sous ce seuil, les modales restent.
///
/// Le seuil était 1200 : une fenêtre ouverte sur la moitié d'un écran 13
/// pouces (~1100 px) retombait en bottom-sheet alors qu'elle a la place du
/// panneau. Le viewport des tests fait 800x600 par défaut (régime phone, et
/// toujours sous 1040) : chaque test desktop pose son 1280x800 lui-même, comme
/// `responsive_overflow_test`.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 2, verses: 3));
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> setDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpReader(
    WidgetTester tester, {
    String? versionCode,
    int chapter = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: chapter,
            initialVersionCode: versionCode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Vide la file d'exceptions du binding : un débordement y arrive à chaque
  /// peinture fautive.
  void expectNoOverflow(WidgetTester tester, String where) {
    final overflows = <String>[];
    for (var i = 0; i < 20; i++) {
      final error = tester.takeException();
      if (error == null) break;
      overflows.add('$where :: ${error.toString().split('\n').first}');
    }
    expect(overflows, isEmpty, reason: 'débordements $where');
  }

  Finder strongVerseText() => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == 'AA H7225',
  );

  Future<void> tapStrongCode(WidgetTester tester) async {
    const full = 'AA H7225';
    const code = 'H7225';
    final paragraph = tester.renderObject<RenderParagraph>(strongVerseText());
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: full.indexOf(code),
        extentOffset: full.indexOf(code) + code.length,
      ),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();
  }

  testWidgets('desktop : le tap Strong épingle le panneau, pas de modale', (
    tester,
  ) async {
    await setDesktop(tester);
    await pumpReader(tester, versionCode: VersionRepository.lsgsCode);

    await tapStrongCode(tester);

    // Le panneau montre l'entrée en un regard, sans route ni feuille.
    expect(find.text('Définition test de H7225.'), findsOneWidget);
    expect(find.byType(StrongDetailScreen), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Voir la fiche complète'), findsNothing,
        reason: 'la feuille d\'extrait ne s\'ouvre plus sur desktop');
    expectNoOverflow(tester, 'panneau Strong');

    // « Fiche complète » pousse l'écran, comme le bouton de l'extrait.
    await tester.tap(find.text('Fiche complète'));
    await tester.pumpAndSettle();
    expect(find.byType(StrongDetailScreen), findsOneWidget);
  });

  testWidgets('desktop : le panneau Strong se ferme et suit les taps', (
    tester,
  ) async {
    await setDesktop(tester);
    await pumpReader(tester, versionCode: VersionRepository.lsgsCode);

    await tapStrongCode(tester);
    expect(find.text('Définition test de H7225.'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer le panneau'));
    await tester.pumpAndSettle();
    expect(find.text('Définition test de H7225.'), findsNothing);
    expectNoOverflow(tester, 'panneau Strong fermé');
  });

  testWidgets('desktop : le tap verset épingle l\u2019étude, pas de modale', (
    tester,
  ) async {
    await setDesktop(tester);
    // Chapitre 2 : pas d'en-tête de livre, le verset 2 est sans note.
    await pumpReader(tester, chapter: 2);

    await tester.tap(find.text('Verset de test Ge. 2:2.'));
    await tester.pumpAndSettle();

    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing,
        reason: 'la feuille d\'étude ne s\'ouvre plus sur desktop');
    expectNoOverflow(tester, 'panneau étude');

    // Un autre verset tapé remplace le panneau, sans l'empiler.
    await tester.tap(find.text('Verset de test Ge. 2:3.'));
    await tester.pumpAndSettle();
    expect(find.text('ACTIONS'), findsOneWidget);
    expect(find.text('Ge. 2:3'), findsOneWidget);
    expectNoOverflow(tester, 'panneau étude remplacé');

    // La ✕ du panneau le congédie.
    expect(find.byIcon(Icons.close), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('ACTIONS'), findsNothing);
  });

  testWidgets('sous le palier desktop : les modales restent (garde-fou)', (
    tester,
  ) async {
    await pumpReader(tester, versionCode: VersionRepository.lsgsCode);

    await tapStrongCode(tester);

    // Régime phone : l'extrait modal, pas le panneau docké.
    expect(find.text('Voir la fiche complète'), findsOneWidget);
    expect(find.text('Fiche complète'), findsNothing);
  });
}
