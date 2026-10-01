import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// Rendu SEF dans la tuile du lecteur : la ligne grecque au-dessus du
/// français, le pied de page de la source dessous. Les deux sont muets dès
/// que le verset ne les porte pas — ce qui est le cas de toutes les autres
/// versions, où le champ reste à null.
void main() {
  const grec = 'Ἐν ἀρχῇ ἐποίησεν ὁ θεὸς τὸν οὐρανὸν καὶ τὴν γῆν.';
  const text = 'Au commencement Dieu créa le ciel et la terre.';
  const note = '• Au commencement : en arkhèi…';

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

  testWidgets('la ligne grecque passe au-dessus du français, la note dessous',
      (tester) async {
    await pumpTile(
      tester,
      const Verse(
        verse: '1:1',
        text: text,
        textWithNotes: text,
        grec: grec,
        note: note,
      ),
    );

    final greekY = tester.getCenter(find.text(grec)).dy;
    final textY = tester.getCenter(find.text(text)).dy;
    final noteY = tester.getCenter(find.text(note)).dy;

    expect(greekY, lessThan(textY),
        reason: 'le grec se lit avant le français, comme dans la source');
    expect(noteY, greaterThan(textY),
        reason: 'la note de bas de page ferme le verset');
  });

  testWidgets('un verset sans grec ne dessine ni grec ni note',
      (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:2', text: text, textWithNotes: text),
    );

    expect(find.text(grec), findsNothing);
    expect(find.text(note), findsNothing);
    expect(find.text(text), findsOneWidget);
  });
}
