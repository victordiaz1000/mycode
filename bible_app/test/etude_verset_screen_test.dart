import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/models/lsgs.dart';
import 'package:bible_app/screens/etude_verset_screen.dart';

import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

void main() {
  setUp(() {
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
  });
  tearDown(() {
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<LsgsToken> tokens = const [
      LsgsToken(text: 'Au ', strong: null),
      LsgsToken(text: 'commencement ', strong: 'H7225'),
      LsgsToken(text: 'ABBA ', strong: null),
      LsgsToken(text: 'Dieu.', strong: 'H0430'),
    ],
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EtudeVersetScreen(
        bookIndex: 1,
        chapter: 1,
        verseNumber: 1,
        tokens: tokens,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lexique mode shows the word-by-word verse and Strong cards',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Genèse 1:1'), findsOneWidget);
    expect(find.text('Lexique hébreu & grec'), findsOneWidget);

    // The verse is rendered word-by-word with tappable Strong words.
    expect(find.text('commencement'), findsWidgets);
    expect(find.text('Dieu.'), findsWidgets);

    // The first Strong card shows the definition of the selected word.
    expect(find.text('Définition - H7225'), findsOneWidget);
    expect(find.textContaining('Définition test de H7225'), findsWidgets);
  });

  testWidgets('tapping a Strong word shows its card', (tester) async {
    await pumpScreen(tester);

    // « Dieu. » is the second Strong word (index 1): tap it.
    await tester.tap(find.text('Dieu.').first);
    await tester.pumpAndSettle();

    expect(find.text('Définition - H0430'), findsOneWidget);
    expect(find.textContaining('Définition test de H0430'), findsWidgets);
  });

  testWidgets('dictionnaire mode links dictionary terms of the verse',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();

    // The subtitle switches, and the ABBA token of the verse is now a
    // dictionary card (the FreDAW fake knows ABBA).
    expect(find.text('Dictionnaire'), findsWidgets);
    expect(find.text('ABBA'), findsWidgets);
    expect(find.textContaining('Définition test FreDAW de ABBA'),
        findsOneWidget);

    // The full-article link is present on the dico card.
    expect(find.text('Ouvrir la fiche complète →'), findsOneWidget);
  });

  testWidgets('verse navigation loads the neighbouring verse tokens',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EtudeVersetScreen(
        bookIndex: 1,
        chapter: 1,
        verseNumber: 1,
        tokens: const [
          LsgsToken(text: 'Premier ', strong: 'H7225'),
        ],
        verseNumbers: const [1, 2],
        loadVerseTokens: (v) async => [
          if (v == 1) const LsgsToken(text: 'Premier ', strong: 'H7225'),
          if (v == 2) const LsgsToken(text: 'Second verset.'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Verset précédent'), findsNothing);
    expect(find.text('Verset suivant'), findsOneWidget);

    await tester.tap(find.text('Verset suivant'));
    await tester.pumpAndSettle();

    // The reference updates and the second verse's (plain) text replaces it.
    expect(find.text('Genèse 1:2'), findsOneWidget);
    expect(find.textContaining('Second verset'), findsWidgets);
    expect(find.text('Verset précédent'), findsOneWidget);
  });

  testWidgets('a verse without Strong words keeps the lexicon cards empty',
      (tester) async {
    await pumpScreen(
      tester,
      tokens: const [
        LsgsToken(text: 'Texte sans code Strong.'),
      ],
    );

    expect(find.textContaining('aucun mot associé à un numéro Strong'),
        findsOneWidget);
  });
}