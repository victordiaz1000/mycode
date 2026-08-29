import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/reference_parser.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/note_aware_text.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';

/// The note-link contract: a Bible reference embedded in a note (« Voir
/// Es. 45:18. ») is tappable, in both note dispositions, and reports the
/// parsed [BibleReference] through the reader — which the shell turns into a
/// jump to the referenced passage.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
  });

  /// The RichText carrying the note text (its only rendering, inline or card).
  Finder noteRichText() => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Es. 45:18'));

  /// Taps inside the recognised reference span, not the centre of the whole
  /// RichText (which fills the reading line).
  ///
  /// The reader renders notes inside a lazy ListView, so the note card can sit
  /// below the viewport: bring it into view first or the tap lands off-screen.
  Future<void> tapReference(WidgetTester tester, String needle) async {
    // The reader renders notes inside a lazy ListView, so the note card can sit
    // below the viewport: bring it into view first or the tap lands off-screen.
    // The book header (metadata + introduction) is tall, so on the small default
    // surface even verse 1's card is beyond the cache extent: drag the list.
    await tester.dragUntilVisible(
      noteRichText(),
      find.descendant(
        of: find.byType(ChapterReader),
        matching: find.byType(ListView),
      ),
      const Offset(0, -200),
    );
    await tester.ensureVisible(noteRichText());
    await tester.pumpAndSettle();
    final paragraph =
        tester.renderObject<RenderParagraph>(noteRichText());
    final plain = paragraph.text.toPlainText();
    final idx = plain.indexOf(needle);
    expect(idx, greaterThanOrEqualTo(0),
        reason: 'the reference "$needle" should be rendered');
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: idx, extentOffset: idx + needle.length),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();
  }

  const noteText = 'Note de test 1:1. Voir Es. 45:18.';
  const verse = Verse(
    verse: '1:1',
    text: 'Verset de test Ge. 1:1.',
    textWithNotes: '',
    notes: [VerseNote(word: 'Verset', position: 0, note: noteText)],
  );

  testWidgets('a note reference is tappable with notes inline',
      (tester) async {
    BibleReference? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteAwareVerseText(
          verse: verse,
          disposition: NoteDisposition.inline,
          onReferenceTap: (ref) => tapped = ref,
        ),
      ),
    ));

    await tapReference(tester, 'Es. 45:18');
    expect(tapped, const BibleReference(bookIndex: 12, chapter: 45, verse: 18),
        reason: '« Es. 45:18 » is Ésaïe 45:18 (BYM index 12)');
  });

  testWidgets('a note reference is tappable with notes below',
      (tester) async {
    BibleReference? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteAwareVerseText(
          verse: verse,
          disposition: NoteDisposition.below,
          onReferenceTap: (ref) => tapped = ref,
        ),
      ),
    ));

    await tapReference(tester, 'Es. 45:18');
    expect(tapped, const BibleReference(bookIndex: 12, chapter: 45, verse: 18));
  });

  testWidgets('without a callback the reference stays plain text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NoteAwareVerseText(
          verse: verse,
          disposition: NoteDisposition.below,
        ),
      ),
    ));

    // Tapping does nothing (no recognizer): the test passes if no exception is
    // thrown, and the note is still rendered as one text.
    await tester.tapAt(tester.getCenter(noteRichText()));
    await tester.pump();
    expect(noteRichText(), findsOneWidget);
  });

  testWidgets('ChapterReader reports a tapped note reference',
      (tester) async {
    // The reader only renders notes once « Texte + notes » is on.
    SharedPreferences.setMockInitialValues({'reading.notesMode': true});
    BibleReference? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          onReferenceTap: (ref) => tapped = ref,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tapReference(tester, 'Es. 45:18');
    expect(tapped, const BibleReference(bookIndex: 12, chapter: 45, verse: 18),
        reason: 'the note of verse 1 carries « Voir Es. 45:18. »');
  });

  testWidgets('ReaderScreen forwards a note reference to onOpenVerse',
      (tester) async {
    // A reading tab already open, notes on.
    SharedPreferences.setMockInitialValues({'reading.notesMode': true});
    final manager = TabManager();
    manager.openReading(1, 1);

    (int, int, int)? opened;
    await tester.pumpWidget(MaterialApp(
      home: ReaderScreen(
        initialManager: manager,
        onOpenVerse: (b, c, v) => opened = (b, c, v),
      ),
    ));
    await tester.pumpAndSettle();

    await tapReference(tester, 'Es. 45:18');
    expect(opened, (12, 45, 18),
        reason: 'the shell opens the referenced passage, verse kept');
  });
}