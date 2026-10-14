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
/// grammaticale — sans colonne d'étiquettes en tête : les rangées se lisent
/// d'elles-mêmes, et, dès que le verset n'a pas de mots, la ligne de gloses
/// jointes d'avant, intacte.
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

    // Les rangées montrées sont là : la forme imprimée en gras, la glose.
    // Lemme, Koinè et analyse vivent dans la fiche, pas dans la grille.
    expect(find.text('Βίβλος'), findsOneWidget);
    expect(find.text('βίβλος'), findsNothing);
    expect(find.text('βιβλοσ'), findsNothing);
    expect(find.text('N-GFS'), findsNothing);
  });

  testWidgets('pas de colonne d’étiquettes en tête du verset', (
    tester,
  ) async {
    await pumpGreek(tester);

    // Les six rangées se lisent d'elles-mêmes : aucun nom de rangée ne
    // précède le premier mot.
    for (final nom in ['Moderne', 'Lemme', 'Koinè', 'Strong', 'Français', 'Analyse']) {
      expect(find.text(nom), findsNothing, reason: 'rangée « $nom »');
    }

    // …et le premier mot ouvre le verset, à gauche.
    expect(
      tester.getTopLeft(find.text('Βίβλος')).dx,
      lessThan(tester.getTopLeft(find.text('γενέσεως')).dx),
    );
  });

  testWidgets('la carte empile mot, pastille Strong puis glose', (
    tester,
  ) async {
    await pumpGreek(tester);

    double top(String t, {bool findRichText = false}) =>
        tester.getTopLeft(find.text(t, findRichText: findRichText).first).dy;

    // …et l'ordre des lignes, du haut de la carte vers le bas.
    expect(top('Βίβλος'), lessThan(top('976')));
    expect(top('976'), lessThan(top('Livre')));
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

  testWidgets('le numéro Strong part en pastille, sans sa lettre', (
    tester,
  ) async {
    await pumpGreek(tester);

    // Le `G` ne dit rien au lecteur — comme le `H` de l'ATI. Le champ brut
    // garde son préfixe, c'est la clé du lexique au tap.
    expect(find.text('976'), findsOneWidget);
    expect(find.text('G976'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Βίβλος')).dy,
      lessThan(tester.getTopLeft(find.text('976')).dy),
      reason: 'la pastille suit le mot et ouvre la glose',
    );
  });

  testWidgets('glose rouge, Strong bleu', (tester) async {
    await pumpGreek(tester);

    // Les deux couleurs de la source, dans la variante du thème en cours.
    final theme = bibleThemes.first;
    expect(
      tester.widget<Text>(find.text('Livre')).style?.color,
      theme.glossColor,
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
