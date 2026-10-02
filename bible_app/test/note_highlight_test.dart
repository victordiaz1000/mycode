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

  testWidgets('a noted verse renders its text with its notes listed',
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

  testWidgets('the noted word loses its paint, its index keeps the colour', (
    WidgetTester tester,
  ) async {
    const verse = Verse(
      verse: '1:2',
      text: 'La Terre devint tohu et bohu.',
      textWithNotes: '',
      notes: [
        VerseNote(word: 'devint', position: 9, note: 'Note de test.'),
      ],
    );
    for (final disposition in NoteDisposition.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NoteAwareVerseText(verse: verse, disposition: disposition),
        ),
      ));

      final spans = _renderedSpans(tester);
      final word = spans.firstWhere((s) => s.text == 'devint');
      expect(word.style?.color, isNull,
          reason: '$disposition : le mot noté perd sa couleur');
      expect(word.style?.decoration, isNull,
          reason: '$disposition : le mot noté perd son soulignage');
      expect(word.style?.backgroundColor, isNull,
          reason: '$disposition : le mot noté perd son surlignage');
      expect(word.style?.fontWeight, FontWeight.bold,
          reason: '$disposition : la graisse seule reste, sans peinture');

      if (disposition == NoteDisposition.below) {
        final index = spans.firstWhere((s) => s.text == '1');
        expect(index.style?.color, isNotNull,
            reason: "« sous le verset » : l'exposant garde la couleur");
      }
    }
  });

  testWidgets('a « \\ » pair in a note becomes a real line break',
      (WidgetTester tester) async {
    const verse = Verse(
      verse: '1:3',
      text: 'Elohim dit.',
      textWithNotes: '',
      notes: [
        VerseNote(word: 'dit', position: 7, note: 'Ligne une\\\\Ligne deux.'),
      ],
    );

    Future<List<String>> pumpAndRead(NoteDisposition disposition) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NoteAwareVerseText(verse: verse, disposition: disposition),
        ),
      ));
      return [
        for (final w in tester.widgetList<RichText>(find.byType(RichText)))
          w.text.toPlainText(),
      ];
    }

    for (final disposition in NoteDisposition.values) {
      final texts = await pumpAndRead(disposition);
      expect(texts.any((t) => t.contains('Ligne une\nLigne deux.')), isTrue,
          reason: '$disposition doit rendre la note sur deux lignes');
      expect(texts.any((t) => t.contains('\\')), isFalse,
          reason: '$disposition ne doit plus porter le marqueur');
    }
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

/// Tous les [TextSpan] rendus à l'écran, enfants inclus.
List<TextSpan> _renderedSpans(WidgetTester tester) {
  final spans = <TextSpan>[];
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    spans.add(span);
    span.children?.forEach(walk);
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return spans;
}