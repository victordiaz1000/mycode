import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/ati_interlinear.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// Rendu interlinéaire de l'ATI dans la tuile du lecteur : un verset en
/// colonnes de mots, de droite à gauche, aligné sur cinq lignes communes —
/// numéro Strong et renvoi, translittération, hébreu vocalisé, glose,
/// étiquette grammaticale — et, dès que le verset n'a pas de mots (toutes les
/// autres versions, tout favori relu depuis son JSON), la ligne de gloses
/// jointes d'avant, intacte.
void main() {
  /// Genèse 1:1, tels que le convertisseur les sort : les trois premiers mots
  /// plus le marqueur d'accusatif `אֵת`, dont la glose n'est que `*`.
  const words = [
    AtiWord(
      strong: 'H7225',
      translit: 'bə·rê·šîṯ',
      hebrew: 'בְּרֵאשִׁ֖ית',
      gloss: 'En un commencement',
      grammar: 'Nom',
      note: 'n12',
    ),
    AtiWord(
      strong: 'H1254',
      translit: 'bā·rā',
      hebrew: 'בָּרָ֣א',
      gloss: 'créa',
      grammar: 'Verbe',
    ),
    AtiWord(
      strong: 'H430',
      translit: '’ĕ·lō·hîm',
      hebrew: 'אֱלֹהִ֑ים',
      gloss: 'Dieu',
      grammar: 'Nom',
    ),
    AtiWord(hebrew: 'אֵת', gloss: '*'),
  ];

  const text = 'En un commencement créa Dieu';

  Future<void> pumpTile(WidgetTester tester, Verse verse) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: VerseTile(
                verse: verse,
                showNotes: false,
                verseNumber: 1,
                theme: bibleThemes.first,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('le verset se lit en colonnes, de droite à gauche', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    expect(find.byType(AtiInterlinear), findsOneWidget);

    // Le mot initial tombe à droite du mot qui le suit : le flux suit le sens
    // du texte source, pas celui du français.
    final first = tester.getCenter(find.text('En un commencement')).dx;
    final second = tester.getCenter(find.text('créa')).dx;
    expect(
      first,
      greaterThan(second),
      reason: 'la première colonne du verset est la plus à droite',
    );

    // Les cinq niveaux empilés sont tous là, y compris le renvoi de glossaire.
    expect(find.text('בְּרֵאשִׁ֖ית'), findsOneWidget);
    expect(find.text('bə·rê·šîṯ'), findsOneWidget);
    expect(find.text('Nom'), findsNWidgets(2));
    expect(find.text('Verbe'), findsOneWidget);
    expect(find.text('n12'), findsOneWidget);
  });

  testWidgets('les cinq lignes s’alignent d’une colonne à l’autre', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    // La trame de la source : toutes les cellules portent les mêmes cinq
    // lignes à la même hauteur, donc l'hébreu du premier mot et l'hébreu du
    // quatrième partagent leur ordonnée. Le quatrième est `אֵת`, dont la glose
    // n'est qu'un `*` retiré du rendu — s'il ne réservait pas sa ligne, ce
    // serait le reste du verset qui remonterait.
    double top(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(top('בְּרֵאשִׁ֖ית'), closeTo(top('בָּרָ֣א'), .5));
    expect(top('בְּרֵאשִׁ֖ית'), closeTo(top('אֵת'), .5));
    expect(top('En un commencement'), closeTo(top('créa'), .5));
    expect(top('Nom'), closeTo(top('Verbe'), .5));

    // …et l'ordre des lignes, du haut de la colonne vers le bas.
    expect(top('7225'), lessThan(top('bə·rê·šîṯ')));
    expect(top('bə·rê·šîṯ'), lessThan(top('בְּרֵאשִׁ֖ית')));
    expect(top('בְּרֵאשִׁ֖ית'), lessThan(top('En un commencement')));
    expect(top('En un commencement'), lessThan(top('Nom')));
  });

  testWidgets('le numéro Strong part en haut, sans sa lettre', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    // La source n'imprime que le nombre (`216`, `1961`) : le `H` ne dit rien
    // au lecteur et coûte la largeur de la première colonne. Le champ brut,
    // lui, garde son préfixe — c'est la clé du lexique, pour le tap à venir.
    expect(find.text('7225'), findsOneWidget);
    expect(find.text('H7225'), findsNothing);
    expect(
      tester.getTopLeft(find.text('7225')).dy,
      lessThan(tester.getTopLeft(find.text('bə·rê·šîṯ')).dy),
      reason: 'le Strong ouvre la colonne',
    );
  });

  testWidgets('glose rouge, étiquette verte, Strong bleu', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    // Les trois couleurs de la source, dans la variante du thème de lecture
    // en cours — un crème sous « Nuit étoilée » n'aurait pas le même rouge.
    final theme = bibleThemes.first;
    expect(
      tester.widget<Text>(find.text('créa')).style?.color,
      theme.glossColor,
    );
    expect(
      tester.widget<Text>(find.text('Verbe')).style?.color,
      theme.grammarColor,
    );
    expect(
      tester.widget<Text>(find.text('7225')).style?.color,
      theme.strongColor,
    );
  });

  testWidgets('la gouttière du numéro part à droite avec l’interlinéaire', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    // La source imprime le numéro à droite du premier mot, là où le verset
    // commence. Une version sans mots garde sa gouttière à gauche, comme
    // depuis toujours.
    expect(
      tester.getCenter(find.text('1')).dx,
      greaterThan(tester.getCenter(find.byType(AtiInterlinear)).dx),
    );

    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text),
    );
    expect(find.byType(AtiInterlinear), findsNothing);
    expect(
      tester.getCenter(find.text('1')).dx,
      lessThan(tester.getCenter(find.text(text)).dx),
      reason: 'sans mots, rien ne bascule : le numéro reste à gauche',
    );
  });

  testWidgets('l’hébreu sort en Cardo et droite-à-gauche', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    final hebrew = tester.widget<Text>(find.text('בְּרֵאשִׁ֖ית'));
    expect(
      hebrew.style?.fontFamily,
      AtiInterlinear.cardoFamily,
      reason: 'seule famille embarquée qui couvre les points-voyelles',
    );
    expect(
      hebrew.textDirection,
      TextDirection.rtl,
      reason: 'sinon les ponctuations massorétiques se réordonnent',
    );

    // Les champs latins, eux, se relisent de gauche à droite : une glose
    // placée sous l'hébreu ne doit pas hériter du sens de lecture.
    final gloss = tester.widget<Text>(find.text('créa'));
    expect(gloss.textDirection, TextDirection.ltr);
  });

  testWidgets('un marqueur de glose ne s’affiche jamais', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
    );

    // `אֵת` n'a pas d'équivalent français : la source l'écrit `*`. Le mot
    // reste (hébreu présent) ; le marqueur, non — sinon l'interlinéaire
    // afficherait ce que la ligne jointe retire déjà.
    expect(find.text('אֵת'), findsOneWidget);
    expect(find.text('*'), findsNothing);
  });

  testWidgets('sans mots, le verset garde sa ligne de gloses', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text),
    );

    expect(find.byType(AtiInterlinear), findsNothing);
    expect(find.text(text), findsOneWidget);
    expect(find.text('בְּרֵאשִׁ֖ית'), findsNothing);
  });

  testWidgets('une liste de mots vide retombe aussi sur la ligne', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text, mots: []),
    );

    expect(find.byType(AtiInterlinear), findsNothing);
    expect(find.text(text), findsOneWidget);
  });
}
