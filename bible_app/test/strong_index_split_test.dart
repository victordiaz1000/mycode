import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/strong_occurrences.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';
import 'package:bible_app/screens/strong_index_screen.dart';

import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// Le split-view de l'index Strong (étape F) : à ≥ 840 px le tap d'une
/// entrée affiche sa fiche en volet de droite au lieu de pousser une route —
/// et sous ce seuil, la poussée reste.
void main() {
  setUp(() {
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongOccurrenceIndex.useAmbientRepository();
  });

  tearDown(() {
    StrongLexicon.useRootBundle();
    LsgsRepository.useRootBundle();
    StrongOccurrenceIndex.useAmbientRepository();
  });

  Future<void> pumpIndex(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StrongIndexScreen()));
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

  testWidgets('wide : le tap affiche la fiche en volet, sans pousser', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpIndex(tester);

    expect(find.textContaining('Choisissez une entrée'), findsOneWidget);
    expect(find.byType(StrongDetailScreen), findsNothing);

    await tester.tap(find.text('H0001'));
    await tester.pumpAndSettle();

    expect(find.byType(StrongDetailScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing,
        reason: 'le volet ne dépile pas l\u2019index');
    expectNoOverflow(tester, 'split strong');

    // Un second tap remplace la fiche, sans l'empiler.
    await tester.tap(find.text('H0430'));
    await tester.pumpAndSettle();
    expect(find.byType(StrongDetailScreen), findsOneWidget);
    expect(find.text('H0430'), findsWidgets);
    expectNoOverflow(tester, 'split strong remplacé');
  });

  testWidgets('phone : le tap pousse la fiche (garde-fou sous 840)', (
    tester,
  ) async {
    await pumpIndex(tester);

    await tester.tap(find.text('H0001'));
    await tester.pumpAndSettle();

    expect(find.byType(StrongDetailScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget,
        reason: 'la route garde son retour');
  });
}
