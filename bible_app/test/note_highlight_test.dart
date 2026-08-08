import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/note_aware_text.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all note.position point exactly to note.word in text (Genèse)', () async {
    final repo = LocalRepository();
    final book = await repo.loadBook(1);
    for (final chapter in book.chapters) {
      for (final verse in chapter.verses) {
        expect(verse.text, isNotEmpty,
            reason: '${verse.verse} should have text');
        for (final n in verse.notes) {
          final inBounds = n.position >= 0 &&
              n.position + n.word.length <= verse.text.length;
          final extracted = inBounds
              ? verse.text.substring(n.position, n.position + n.word.length)
              : '';
          expect(ok(inBounds, extracted, n.word), isTrue,
              reason: '${verse.verse}: note "${n.word}" pos=${n.position}');
        }
      }
    }
  });

  testWidgets('a noted verse renders its text highlighted + notes listed',
      (WidgetTester tester) async {
    const verse = Verse(
      verse: '1:2',
      text: 'La Terre devint tohu et bohu.',
      textWithNotes: '',
      notes: [
        VerseNote(word: 'devint', position: 9, note: 'Voir Es. 45:18.'),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: NoteAwareVerseText(
              verse: verse, disposition: NoteDisposition.inline)),
    ));
    expect(find.textContaining('La Terre'), findsOneWidget);
    expect(find.textContaining('Voir Es. 45:18.'), findsOneWidget);
  });

  testWidgets('verse without notes shows plain text and no footnotes',
      (WidgetTester tester) async {
    const verse = Verse(
      verse: '1:6',
      text: 'Texte simple sans note.',
      textWithNotes: '',
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: NoteAwareVerseText(
              verse: verse, disposition: NoteDisposition.below)),
    ));
    expect(find.text('Texte simple sans note.'), findsOneWidget);
    expect(find.textContaining('1.'), findsNothing);
  });
}

bool ok(bool inBounds, String extracted, String word) =>
    inBounds && extracted == word;