import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/ati_notes.dart';
import 'package:bible_app/screens/ati_note_screen.dart';

import 'support/fake_ati_notes_bundle.dart';

/// La page de glossaire, sur les 37 pages réelles du bundle — servies par
/// fichier, puisque `rootBundle` ne complète pas dans `testWidgets`.
void main() {
  setUp(AtiNotes.useRootBundle);
  tearDown(AtiNotes.useRootBundle);

  Future<void> pumpNote(
    WidgetTester tester,
    String id, {
    Future<void> Function(String strong)? onStrongTap,
    Future<void> Function(String osis)? onVerseTap,
  }) async {
    AtiNotes.useBundle(FakeNotesBundle());
    await tester.pumpWidget(
      MaterialApp(
        home: AtiNoteScreen(
          noteId: id,
          onStrongTap: onStrongTap,
          onVerseTap: onVerseTap,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Tout le texte affiché, `Text` comme `Text.rich` — les fragments de la
  /// page sont des RichText, les trouver un par un ne dirait rien d'eux.
  String shown(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rich) => rich.text.toPlainText())
      .join('\n');

  /// Un tap sur un lien de page longue : d'abord l'amener à l'écran, sinon le
  /// geste part dans le vide au-dessus ou en dessous.
  Future<void> tapLink(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('la note 12 s’ouvre : intitulé, corps et mention de source', (
    tester,
  ) async {
    await pumpNote(tester, 'n12');

    expect(find.text('Note 12'), findsOneWidget, reason: 'titre de l’AppBar');
    final text = shown(tester);
    expect(text, contains('Mot rare, hapax'));
    expect(text, contains('difficile à comprendre'));
    expect(text, contains('© Biblia Universalis'));
    expect(
      text,
      contains('Biblia Hebraica Stuttgartensia'),
      reason: 'la mention de la source ferme la page',
    );
  });

  testWidgets('la page « Difficulté 12 » rend sa table de références', (
    tester,
  ) async {
    await pumpNote(tester, 'd12');

    final text = shown(tester);
    expect(text, contains('La conjonction ou particule démonstrative'));
    expect(
      find.text('Juges 1.28'),
      findsOneWidget,
      reason: 'le lien de verset est un fragment à part, donc son Text',
    );
    expect(text, contains('quand Israël fut fort'));
  });

  testWidgets('un renvoi de glossaire pousse la page appelée', (tester) async {
    await pumpNote(tester, 'd10');

    await tapLink(tester, find.text('► difficulté n° 7'));

    expect(
      find.text('Difficulté 7'),
      findsOneWidget,
      reason: 'l’AppBar de la page poussée',
    );
    expect(shown(tester), contains('Difficulté 7'));
    // Et le retour en arrière remonte à la page d’origine.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Difficulté 10'), findsOneWidget);
  });

  testWidgets('un code Strong appelle le lexique, sans préfixe à deviner', (
    tester,
  ) async {
    String? opened;
    await pumpNote(
      tester,
      'd2',
      onStrongTap: (strong) async => opened = strong,
    );

    await tapLink(tester, find.text('►InCs'));

    expect(opened, 'H8812');
  });

  testWidgets('un verset de la table appelle le lecteur en code OSIS', (
    tester,
  ) async {
    String? opened;
    await pumpNote(tester, 'd12', onVerseTap: (osis) async => opened = osis);

    await tapLink(tester, find.text('Juges 1.28'));

    expect(opened, 'JDG1.28');
  });

  testWidgets('une référence sans appelant se lit, elle ne se presse pas', (
    tester,
  ) async {
    String? opened;
    // Sans `onVerseTap`, le lien de verset n'est plus qu'une référence.
    await pumpNote(tester, 'd12');
    await tapLink(tester, find.text('Juges 1.28'));

    expect(opened, isNull);
  });

  testWidgets('un identifiant hors glossaire dit la page manquante', (
    tester,
  ) async {
    await pumpNote(tester, 'zzz');

    expect(
      find.textContaining('n’existe pas dans le glossaire'),
      findsOneWidget,
    );
  });

  testWidgets('la liste des abréviations tient sur ses colonnes', (
    tester,
  ) async {
    await pumpNote(tester, 'abr');

    final text = shown(tester);
    expect(text, contains('Biblia Hebraica Stuttgartensia'));
    expect(text, contains('infinitif'));
    expect(text, contains('masculin'));
  });
}
