import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/ati_notes.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/widgets/ati_interlinear.dart';
import 'package:bible_app/widgets/ati_word_sheet.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_ati_notes_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// Un mot complet — les sept champs de la source, `g` et `a` rendant deux
/// lignes — et un mot nu, pour la voie sans lien.
const motComplet = AtiWord(
  strong: 'H7225',
  translit: 'berešit',
  hebrew: 'רֵאשִׁית',
  split: 'רֵאשִׁית רֵאשׁ',
  gloss: 'En un commencement',
  grammar: 'Nom',
  analysis: 'Nom commun · féminin singulier · état absolu',
  note: 'n12',
);

const motNu = AtiWord(
  translit: 'waw',
  hebrew: 'וְ',
  gloss: 'et',
  grammar: 'Conjonction',
);

/// Un mot du NTI — les six rangées du grec, dont deux lignes de texte et une
/// variante de glose. Matthieu 1:1, tel que le convertisseur le sort.
const motGrec = AtiWord(
  modern: 'γενέσεως',
  lemma: 'γένεσις',
  koine: 'γενεσεωσ',
  strong: 'G1078',
  gloss: 'de genèse',
  variant: 'de généalogie',
  grammar: 'N-GFS',
  analysis: 'Nature : Nom · Déclinaison : Génitif · Genre : féminin',
);

void main() {
  setUp(() {
    AtiNotes.useBundle(FakeNotesBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
  });

  tearDown(() {
    AtiNotes.useRootBundle();
    StrongLexicon.useRootBundle();
  });

  Future<void> pumpMot(
    WidgetTester tester, {
    AtiWord mot = motComplet,
    String reference = 'Ge. 1:1',
    Future<void> Function(String strong)? onStrongTap,
    Future<void> Function(String noteId)? onNoteTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => AtiInterlinear(
                words: [mot],
                rhythm: const ReadingRhythm(),
                theme: bibleThemes.first,
                onWordTap: (word) => showAtiWordSheet(
                  context,
                  reference: reference,
                  word: word,
                  onStrongTap: onStrongTap,
                  onNoteTap: onNoteTap,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapMot(WidgetTester tester) async {
    await tester.tap(find.text('En un commencement'));
    await tester.pumpAndSettle();
  }

  testWidgets('le tap sur la cellule ouvre la fiche de ses champs', (
    tester,
  ) async {
    await pumpMot(tester);
    await tapMot(tester);

    expect(find.text('Ge. 1:1'), findsOneWidget, reason: 'la référence nomme');
    expect(
      find.text('En un commencement'),
      findsWidgets,
      reason: 'la glose, en cellule et en fiche',
    );
    expect(find.text('Nom'), findsWidgets, reason: 'étiquette');
    expect(
      find.text('Nom commun · féminin singulier · état absolu'),
      findsOneWidget,
      reason: 'l’analyse, que la cellule ne peut pas tenir',
    );
    expect(
      find.text('רֵאשִׁית רֵאשׁ'),
      findsOneWidget,
      reason: 'le découpage, en hébreu',
    );
    expect(find.text('H7225'), findsOneWidget, reason: 'Strong, avec son H');
    expect(
      find.textContaining('Note 12 —'),
      findsOneWidget,
      reason: 'le renvoi résolu contre le glossaire',
    );
    expect(
      find.text('Champs portés par la source — aucun lien.'),
      findsNothing,
    );
  });

  testWidgets('la fiche ne promet pas un lien qu’elle ne peut pas tenir', (
    tester,
  ) async {
    await pumpMot(tester, mot: motNu);
    await tester.tap(find.text('et'));
    await tester.pumpAndSettle();

    expect(find.text('Ge. 1:1'), findsOneWidget);
    expect(find.text('Conjonction'), findsWidgets);
    expect(find.text('H7225'), findsNothing);
    expect(find.textContaining('Note 12'), findsNothing);
    expect(
      find.text('Champs portés par la source — aucun lien.'),
      findsOneWidget,
    );
  });

  testWidgets('un code écrit sans ses zéros reste cliquable', (tester) async {
    // L'ATI imprime « H430 » comme sa source, le lexique range « H0430 » :
    // la fiche ne se tait pas sur un code qu'elle connaît pourtant.
    String? opened;
    await pumpMot(
      tester,
      mot: const AtiWord(strong: 'H430', hebrew: 'וְ', gloss: 'et'),
      onStrongTap: (strong) async => opened = strong,
    );
    await tester.tap(find.text('et'));
    await tester.pumpAndSettle();

    expect(find.text('H430'), findsOneWidget);
    expect(
      find.byIcon(Icons.chevron_right_rounded),
      findsOneWidget,
      reason: 'le code existe au lexique, la flèche le dit',
    );

    await tester.ensureVisible(find.text('H430'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H430'));
    await tester.pumpAndSettle();

    expect(
      opened,
      'H430',
      reason: "on ouvre avec le code tel que la source l'écrit, le lexique "
          'le ramène à H0430',
    );
  });

  testWidgets('le Strong ouvre la fiche du lexique, la feuille se ferme', (
    tester,
  ) async {
    String? opened;
    await pumpMot(tester, onStrongTap: (strong) async => opened = strong);
    await tapMot(tester);

    await tester.ensureVisible(find.text('H7225'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H7225'));
    await tester.pumpAndSettle();

    expect(opened, 'H7225');
    expect(
      find.text('Ge. 1:1'),
      findsNothing,
      reason: 'la feuille est retombée avant la poussée',
    );
  });

  testWidgets('le renvoi ouvre la page de glossaire, la feuille se ferme', (
    tester,
  ) async {
    String? opened;
    await pumpMot(tester, onNoteTap: (noteId) async => opened = noteId);
    await tapMot(tester);

    final renvoi = find.textContaining('Note 12 —');
    await tester.ensureVisible(renvoi);
    await tester.pumpAndSettle();
    await tester.tap(renvoi);
    await tester.pumpAndSettle();

    expect(opened, 'n12');
    expect(find.text('Ge. 1:1'), findsNothing);
  });

  testWidgets('sans appelant, la fiche affiche le code sans le feindre '
      'cliquable', (tester) async {
    await pumpMot(tester);
    await tapMot(tester);

    await tester.ensureVisible(find.text('H7225'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H7225'));
    await tester.pumpAndSettle();

    // La feuille est restée ouverte : rien n'a bougé, le tap n'était pas un
    // lien.
    expect(find.text('Ge. 1:1'), findsOneWidget);
  });

  group('un mot grec (NTI)', () {
    testWidgets('la fiche nomme Lemme et Koinè, que la grille ne nomme pas', (
      tester,
    ) async {
      await pumpMot(tester, mot: motGrec, reference: 'Mt. 1:1');
      await tester.tap(find.text('γενέσεως'));
      await tester.pumpAndSettle();

      expect(find.text('Mt. 1:1'), findsOneWidget);
      // Les deux lignes de texte sont déjà en cellule : ce que la fiche
      // ajoute, c'est leur nom — la grille ne distingue « Lemme » de
      // « Koinè » que par ses étiquettes.
      expect(find.text('γένεσις'), findsWidgets);
      expect(find.text('γενεσεωσ'), findsWidgets);
      // Les deux fois : en cellule (la grille empile) et en fiche (la fiche
      // nomme).
      expect(find.text('Lemme'), findsWidgets);
      expect(find.text('Koinè'), findsWidgets);
      // Les lignes que la grille tient court : Strong, étiquette, analyse.
      expect(find.text('G1078'), findsOneWidget, reason: 'le G est gardé ici');
      expect(find.text('N-GFS'), findsWidgets);
      expect(
        find.text('Nature : Nom · Déclinaison : Génitif · Genre : féminin'),
        findsOneWidget,
        reason: 'l’analyse, que la cellule ne peut pas tenir',
      );
      expect(
        tester.widget<Text>(find.text('γενέσεως').last).textDirection,
        TextDirection.ltr,
        reason: 'le grec se lit de la gauche, fiche comprise',
      );
    });

    testWidgets('la variante est en italique, à la suite de la glose', (
      tester,
    ) async {
      await pumpMot(tester, mot: motGrec, reference: 'Mt. 1:1');
      await tester.tap(find.text('γενέσεως'));
      await tester.pumpAndSettle();

      // Deux cellules portent la même paire — celle de la grille et la ligne
      // « Glose » de la fiche — et toutes deux la portent pareil : l'italique
      // suit la variante partout, sans exception à retenir.
      final cells = tester.widgetList<RichText>(
        find.text('de genèse / de généalogie', findRichText: true),
      );
      expect(cells, hasLength(2));

      List<String> spans(RichText rich) {
        final found = <String>[];
        void walk(InlineSpan span) {
          if (span is TextSpan) {
            final text = span.text;
            if (text != null) {
              found.add(
                span.style?.fontStyle == FontStyle.italic ? '»$text' : text,
              );
            }
            for (final child in span.children ?? const <InlineSpan>[]) {
              walk(child);
            }
          }
        }

        walk(rich.text);
        return found;
      }

      for (final cell in cells) {
        expect(spans(cell), contains('» / de généalogie'));
        expect(spans(cell), contains('de genèse'));
      }
    });

    testWidgets('un mot sans Strong n’invente pas de lien', (tester) async {
      // Marc 16:8, un mot « non réf. » : la source ne le rattache à aucun
      // lexique, et aucun mot du corpus grec ne renvoie à son glossaire.
      await pumpMot(
        tester,
        mot: const AtiWord(
          modern: '[[[Πάντα',
          lemma: '-',
          koine: '-',
          gloss: '[[[Toutes',
        ),
        reference: 'Mr. 16:8',
      );
      await tester.tap(find.text('[[[Πάντα'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Note'), findsNothing);
      expect(
        find.text('Champs portés par la source — aucun lien.'),
        findsOneWidget,
      );
    });
  });
}
