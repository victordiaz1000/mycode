import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/screens/bym_lexicon_entry_screen.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';

/// The fiche display menu: the ⋮ action of every fiche (dictionary, Strong,
/// Notes BYM Lexique) drives its OWN size / alignment / typeface setting —
/// the `fiche.*` keys, separate from the reader's — and the change lands
/// live, behind the open sheet.
void main() {
  const definition = 'Définition de test sans référence.';

  DictionaryEntry entry() => const DictionaryEntry(
        word: 'Verset',
        definition: definition,
        bookIndex: 1,
        chapter: 1,
        verseNumber: 1,
        occurrences: 3,
      );

  Future<void> pumpFiche(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: BymLexiconEntryScreen(entry: entry(), onOpenVerse: (_, _, _) {}),
    ));
    await tester.pumpAndSettle();
  }

  Text definitionText(WidgetTester tester) =>
      tester.widget<Text>(find.text(definition));

  testWidgets('the fiche starts on the stored fiche preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'fiche.fontSize': 19.0,
      'fiche.textAlign': 'center',
      'fiche.fontFamily': 'classic', // enum name of « Classique · Lora »
    });
    await pumpFiche(tester);

    final style = definitionText(tester).style!;
    expect(style.fontSize, 19.0);
    expect(style.fontFamily, 'Lora');
    expect(definitionText(tester).textAlign, TextAlign.center);
  });

  testWidgets('the ⋮ menu changes size, alignment and font live',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpFiche(tester);

    await tester.tap(find.byTooltip('Affichage'));
    await tester.pumpAndSettle();

    // Taille à 30 : le curseur compte en pourcentage des 16 pt par défaut
    // des fiches — 187,5 %.
    tester
        .widget<Slider>(
          find.descendant(
            of: find.byType(DisplaySizeSection),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(187.5);
    await tester.pump();

    // Alignement à droite.
    await tester.tap(find.byTooltip('Aligner droite'));
    await tester.pump();

    // Police EB Garamond.
    await tester.tap(find.text('EB Garamond'));
    await tester.pump();

    // The fiche behind the sheet has already picked the changes up.
    final style = definitionText(tester).style!;
    expect(style.fontSize, 30.0);
    expect(style.fontFamily, 'EB Garamond');
    expect(definitionText(tester).textAlign, TextAlign.right);

    // Persisted under the FICHE keys — the reader's settings stay theirs.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('fiche.fontSize'), 30.0);
    expect(prefs.getString('fiche.fontFamily'), 'garamond');
    expect(prefs.getString('fiche.textAlign'), 'right');
    expect(prefs.getDouble('reading.fontSize'), isNull);
  });

  testWidgets('the fiche display does not follow a change made to the reading',
      (tester) async {
    SharedPreferences.setMockInitialValues({'reading.fontSize': 30.0});
    await pumpFiche(tester);

    expect(definitionText(tester).style!.fontSize, 16.0,
        reason: 'the fiche default (moyen), not the reader size');
  });

  testWidgets('the etude group is separate from the fiche group',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    FicheTextStyle? seen;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          actions: const [FicheDisplayMenuButton(group: DisplayGroup.etude)],
        ),
        body: FicheTextScope(
          group: DisplayGroup.etude,
          builder: (context, style) {
            seen = style;
            return const SizedBox.shrink();
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Change the ETUDE settings through its own button.
    await tester.tap(find.byTooltip('Affichage'));
    await tester.pumpAndSettle();
    // 30 = 187,5 % des 16 pt par défaut de la portée étude.
    tester
        .widget<Slider>(
          find.descendant(
            of: find.byType(DisplaySizeSection),
            matching: find.byType(Slider),
          ),
        )
        .onChanged!(187.5);
    await tester.pumpAndSettle();

    expect(seen!.fontSize, 30.0,
        reason: 'the etude scope follows its own revision');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('etude.fontSize'), 30.0);
    expect(prefs.getDouble('fiche.fontSize'), isNull);
    expect(prefs.getDouble('reading.fontSize'), isNull);
  });
}
