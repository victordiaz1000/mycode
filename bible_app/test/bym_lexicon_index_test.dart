import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/bym_lexicon_entry_screen.dart';
import 'package:bible_app/screens/bym_lexicon_index_screen.dart';

import 'support/fake_bible_bundle.dart';

/// The BYM lexicon index contract: it lists every distinct note anchor of the
/// 66 books (alphabetical, with a search field), and tapping an entry opens
/// its fiche — which carries the definition, the first reference, and an
/// « Ouvrir le verset » button wired to [BymLexiconIndexScreen.onOpenVerse].
void main() {
  setUp(() {
    LocalRepository.useBundle(FakeBibleBundle());
    LexiconIndex.instance.clearIndex();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LexiconIndex.instance.clearIndex();
  });

  Future<void> pumpIndex(WidgetTester tester,
      {void Function(int, int, int)? onOpenVerse}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BymLexiconIndexScreen(onOpenVerse: onOpenVerse),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every distinct note anchor, alphabetical', (tester) async {
    await pumpIndex(tester);

    // The fake bundle notes only the first verse of each chapter with the
    // anchor word « Verset » (2 chapters × 66 books = 132 occurrences).
    expect(find.text('Notes BYM Lexique'), findsOneWidget);
    expect(find.text('1 entrée'), findsOneWidget);
    expect(find.text('Verset'), findsOneWidget);
    expect(find.text('132 occurrences'), findsNothing); // count is on the fiche
  });

  testWidgets('the search field narrows the list', (tester) async {
    await pumpIndex(tester);

    await tester.enterText(find.byType(TextField), 'vers');
    await tester.pumpAndSettle();

    expect(find.text('Verset'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'xyz');
    await tester.pumpAndSettle();

    expect(find.text('Verset'), findsNothing);
    expect(find.text('Aucune entrée trouvée'), findsOneWidget);
  });

  testWidgets('tapping an entry opens its fiche with the reference',
      (tester) async {
    await pumpIndex(tester);

    await tester.tap(find.text('Verset'));
    await tester.pumpAndSettle();

    expect(find.byType(BymLexiconEntryScreen), findsOneWidget);
    expect(find.text('Notes BYM Lexique'), findsWidgets); // badge on the fiche
    expect(find.textContaining('Ge. 1:1'), findsOneWidget);
    expect(find.text('Note de test 1:1. Voir Es. 45:18.'), findsOneWidget);
  });

  testWidgets('the fiche button opens the verse through onOpenVerse',
      (tester) async {
    final opened = <List<int>>[];
    await pumpIndex(tester, onOpenVerse: (b, c, v) => opened.add([b, c, v]));

    await tester.tap(find.text('Verset'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ouvrir le verset'));
    await tester.pumpAndSettle();

    expect(opened, [
      [1, 1, 1],
    ]);
  });

  testWidgets('a reference inside the definition opens its own verse',
      (tester) async {
    final opened = <List<int>>[];
    await pumpIndex(tester, onOpenVerse: (b, c, v) => opened.add([b, c, v]));

    await tester.tap(find.text('Verset'));
    await tester.pumpAndSettle();

    // « Es. 45:18 » dans la définition est un lien, rendu comme les
    // références des notes de lecture, et mène à Ésaïe 45:18.
    final definition = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Es. 45:18'),
    );
    expect(definition, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(definition);
    final plain = paragraph.text.toPlainText();
    const needle = 'Es. 45:18';
    final idx = plain.indexOf(needle);
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: idx, extentOffset: idx + needle.length),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();

    expect(opened.single, [12, 45, 18]);
  });
}