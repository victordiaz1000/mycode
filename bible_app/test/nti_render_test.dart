import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/ati_interlinear.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// Rendu interlinéaire du NTI dans la tuile du lecteur : un verset grec en
/// colonnes de mots, **de gauche à droite**, aligné sur six lignes communes —
/// forme imprimée, lemme, Koinè, numéro Strong, glose et sa variante, étiquette
/// grammaticale — précédées de la colonne d'étiquettes que la source imprime
/// elle-même, et, dès que le verset n'a pas de mots, la ligne de gloses jointes
/// d'avant, intacte.
void main() {
  /// Matthieu 1:1, tels que le convertisseur les sort — le deuxième mot est
  /// celui qui porte une variante de glose, le troisième une forme construite.
  const words = [
    AtiWord(
      modern: 'Βίβλος',
      lemma: 'βίβλος',
      koine: 'βιβλοσ',
      strong: 'G976',
      gloss: 'Livre',
      grammar: 'N-NFS',
      analysis: 'Nature : Nom · Déclinaison : Nominatif',
    ),
    AtiWord(
      modern: 'γενέσεως',
      lemma: 'γένεσις',
      koine: 'γενεσεωσ',
      strong: 'G1078',
      gloss: 'de genèse',
      variant: 'de généalogie',
      grammar: 'N-GFS',
    ),
    AtiWord(
      modern: '˚Ἰησοῦ',
      lemma: 'Ἰησοῦς',
      koine: '=ιυ',
      strong: 'G2424',
      gloss: 'de Jésus',
      grammar: 'N-GMS',
    ),
  ];

  /// La ligne jointe que porterait `joinAtiGlosses` : les deux propositions
  /// côte à côte, séparées d'un blanc — l'italique est un affichage, la
  /// ligne jointe n'a pas de style.
  const text = 'Livre de genèse de généalogie de Jésus';

  /// Genèse 1:1 en deux mots — le contrepoint hébreu, pour que la grille grecque
  /// ne change rien à celle de l'ATI.
  const hebrewWords = [
    AtiWord(
      strong: 'H7225',
      translit: 'bə·rê·šîṯ',
      hebrew: 'בְּרֵאשִׁ֖ית',
      gloss: 'En un commencement',
      grammar: 'Nom',
    ),
    AtiWord(
      strong: 'H1254',
      translit: 'bā·rā',
      hebrew: 'בָּרָ֣א',
      gloss: 'créa',
      grammar: 'Verbe',
    ),
  ];

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

  Future<void> pumpGreek(WidgetTester tester) => pumpTile(
    tester,
    const Verse(verse: '1:1', text: text, textWithNotes: text, mots: words),
  );

  testWidgets('le verset se lit en colonnes, de gauche à droite', (
    tester,
  ) async {
    await pumpGreek(tester);

    expect(find.byType(AtiInterlinear), findsOneWidget);

    // Le mot initial tombe à gauche du mot qui le suit : le grec se lit dans
    // ce sens, et l'hébreu seul part de la droite.
    final first = tester.getCenter(find.text('Livre')).dx;
    final second = tester
        .getCenter(find.text('de genèse / de généalogie', findRichText: true))
        .dx;
    expect(
      first,
      lessThan(second),
      reason: 'la première colonne du verset est la plus à gauche',
    );

    // Les six rangées sont toutes là, y compris les trois lignes de texte.
    expect(find.text('Βίβλος'), findsOneWidget);
    expect(find.text('βίβλος'), findsOneWidget);
    expect(find.text('βιβλοσ'), findsOneWidget);
    expect(find.text('N-GFS'), findsOneWidget);
  });

  testWidgets('la colonne d’étiquettes nomme les six rangées, à gauche', (
    tester,
  ) async {
    await pumpGreek(tester);

    // Les six noms, dans l'ordre que la source imprime.
    for (final nom in ['Moderne', 'Lemme', 'Koinè', 'Strong', 'Français', 'Analyse']) {
      expect(find.text(nom), findsOneWidget, reason: 'rangée « $nom »');
    }

    // …et chacun posé au milieu de la ligne qu'il nomme : c'est la hauteur
    // commune qui les aligne sur le mot, sinon « Lemme » et « Koinè » se
    // liraient sur la même ordonnée. Le libellé est plus petit que le texte
    // qu'il nomme — au centre, jamais au dessus.
    double cy(String t) => tester.getCenter(find.text(t).first).dy;
    expect(cy('Moderne'), closeTo(cy('Βίβλος'), 1));
    expect(cy('Lemme'), closeTo(cy('βίβλος'), 1));
    expect(cy('Koinè'), closeTo(cy('βιβλοσ'), 1));
    expect(cy('Français'), closeTo(cy('Livre'), 1));
    expect(cy('Analyse'), closeTo(cy('N-NFS'), 1));

    // Les étiquettes ouvrent le verset : à gauche du premier mot.
    expect(
      tester.getCenter(find.text('Moderne')).dx,
      lessThan(tester.getCenter(find.text('Βίβλος')).dx),
    );
  });

  testWidgets('les six lignes s’alignent d’une colonne à l’autre', (
    tester,
  ) async {
    await pumpGreek(tester);

    double top(String t, {bool findRichText = false}) =>
        tester.getTopLeft(find.text(t, findRichText: findRichText).first).dy;

    // La trame de l'ATI, inchangée : une cellule ne peut pas être plus haute
    // que sa voisine.
    expect(top('Βίβλος'), closeTo(top('γενέσεως'), .5));
    expect(top('Βίβλος'), closeTo(top('˚Ἰησοῦ'), .5));
    expect(
      top('de genèse / de généalogie', findRichText: true),
      closeTo(top('de Jésus'), .5),
    );

    // …et l'ordre des lignes, du haut de la colonne vers le bas.
    expect(top('Βίβλος'), lessThan(top('βίβλος')));
    expect(top('βίβλος'), lessThan(top('βιβλοσ')));
    expect(top('βιβλοσ'), lessThan(top('976')));
    expect(top('976'), lessThan(top('Livre')));
    expect(top('Livre'), lessThan(top('N-NFS')));
  });

  testWidgets('la variante de glose est en italique à la suite de la glose', (
    tester,
  ) async {
    await pumpGreek(tester);

    // Une seule cellule porte les deux propositions : le « / » de la source ne
    // sert qu'à les séparer, l'italique dit laquelle est la variante. Le
    // finder tombe sur le `RichText` que le `Text.rich` construit — c'est lui
    // qui porte les `TextSpan`, enveloppe comprise.
    final rich = tester.widget<RichText>(
      find.text('de genèse / de généalogie', findRichText: true),
    );

    List<TextSpan> sous(InlineSpan span) => [
      if (span is TextSpan) ...[
        if (span.text != null) span,
        for (final child in span.children ?? const <InlineSpan>[]) ...sous(child),
      ],
    ];

    final spans = sous(rich.text);
    expect(spans.map((s) => s.text), ['de genèse', ' / de généalogie']);
    expect(
      spans.first.style?.fontStyle,
      isNot(FontStyle.italic),
      reason: 'la glose principale est droite',
    );
    expect(
      spans.last.style?.fontStyle,
      FontStyle.italic,
      reason: 'la variante, seule, est en italique',
    );
  });

  testWidgets('le numéro Strong part en haut, sans sa lettre', (tester) async {
    await pumpGreek(tester);

    // Le `G` ne dit rien au lecteur — comme le `H` de l'ATI. Le champ brut
    // garde son préfixe, c'est la clé du lexique au tap.
    expect(find.text('976'), findsOneWidget);
    expect(find.text('G976'), findsNothing);
    expect(
      tester.getTopLeft(find.text('βιβλοσ')).dy,
      lessThan(tester.getTopLeft(find.text('976')).dy),
      reason: 'le Strong suit la Koinè et ouvre la glose',
    );
  });

  testWidgets('glose rouge, étiquette verte, Strong bleu', (tester) async {
    await pumpGreek(tester);

    // Les trois couleurs de la source, dans la variante du thème en cours.
    final theme = bibleThemes.first;
    expect(
      tester.widget<Text>(find.text('Livre')).style?.color,
      theme.glossColor,
    );
    expect(
      tester.widget<Text>(find.text('N-NFS')).style?.color,
      theme.grammarColor,
    );
    expect(
      tester.widget<Text>(find.text('976')).style?.color,
      theme.strongColor,
    );
  });

  testWidgets('le grec sort en Cardo et gauche-à-droite', (tester) async {
    await pumpGreek(tester);

    final grec = tester.widget<Text>(find.text('Βίβλος'));
    expect(
      grec.style?.fontFamily,
      AtiInterlinear.cardoFamily,
      reason: 'seule famille embarquée qui couvre le grec polytonique',
    );
    expect(
      grec.textDirection,
      TextDirection.ltr,
      reason: 'le grec n\'a pas à être isolé dans un flux de droite',
    );
    // Le `˚` du marqueur de forme construite reste, et le mot part de la
    // gauche — c'est un mot, pas un bloc à réordonner.
    final construit = tester.widget<Text>(find.text('˚Ἰησοῦ'));
    expect(construit.textDirection, TextDirection.ltr);
    expect(find.text('Ἰησοῦ'), findsNothing);
  });

  testWidgets('la gouttière du numéro reste à gauche', (tester) async {
    await pumpGreek(tester);

    // Le grec part de la gauche, le numéro garde donc sa place d'ordinaire —
    // à l'inverse de l'ATI, dont la gouttière part à droite avec le mot.
    expect(
      tester.getCenter(find.text('1')).dx,
      lessThan(tester.getCenter(find.byType(AtiInterlinear)).dx),
    );
  });

  testWidgets('l’hébreu de l’ATI n’a rien perdu de son sens', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(
        verse: '1:1',
        text: 'En un commencement créa',
        textWithNotes: 'En un commencement créa',
        mots: hebrewWords,
      ),
    );

    expect(find.byType(AtiInterlinear), findsOneWidget);
    // La première colonne hébraïque tombe à droite, la gouttière avec elle.
    expect(
      tester.getCenter(find.text('En un commencement')).dx,
      greaterThan(tester.getCenter(find.text('créa')).dx),
    );
    expect(
      tester.getCenter(find.text('1')).dx,
      greaterThan(tester.getCenter(find.byType(AtiInterlinear)).dx),
    );
    // Et la grille grecque ne s'est pas invitée : pas d'étiquettes, aucune
    // ligne de plus.
    expect(find.text('Moderne'), findsNothing);
    expect(find.text('Koinè'), findsNothing);
    expect(find.text('7225'), findsOneWidget);
  });

  testWidgets('sans mots, le verset garde sa ligne de gloses', (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:1', text: text, textWithNotes: text),
    );

    expect(find.byType(AtiInterlinear), findsNothing);
    expect(find.text(text), findsOneWidget);
    expect(find.text('Βίβλος'), findsNothing);
  });
}
