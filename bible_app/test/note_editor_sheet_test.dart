import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/data/app_database.dart';
import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/widgets/note_editor_sheet.dart';
/// SQLite FFI does REAL I/O, which never settles under the testWidgets
/// fake-async zone: every action that touches the database needs a slice of
/// genuine time (`runAsync`) before `pumpAndSettle` can mean anything.
Future<void> flushIo(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)));

/// Same seam for reads/writes whose VALUE the test needs back.
Future<T> io<T>(WidgetTester tester, Future<T> Function() action) async =>
    (await tester.runAsync(action)) as T;

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(factory: factory);
    return db.useInMemory();
  });

  tearDown(() => db.close());

  /// Pumps a host page and opens the editor the way the app does.
  Future<NoteEditorOutcome?> openEditor(
    WidgetTester tester, {
    UserNote? note,
    String reference = 'Jean 3:16',
    String verseText = 'Car Dieu a tant aimé le monde…',
  }) {
    final future = showNoteEditorSheet(
      context: tester.element(find.byType(Scaffold)),
      db: db,
      reference: reference,
      verseText: verseText,
      note: note,
      bookIndex: 43,
      chapter: 3,
      verse: 16,
    );
    return future;
  }

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(ValueKey(key)), text);
    await tester.pump();
  }

  testWidgets('a new note is written when the sheet closes', (tester) async {
    await pumpHost(tester);
    final done = openEditor(tester);
    await tester.pumpAndSettle();

    await type(tester, 'note-editor-body', 'kaphar = couvrir, expier');
    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await flushIo(tester);
    await tester.pumpAndSettle();

    expect(await done, NoteEditorOutcome.saved);
    final notes = await io(tester, () => db.notesForVerse(43, 3, 16));
    expect(notes, hasLength(1));
    expect(notes.single.text, 'kaphar = couvrir, expier');
    expect(notes.single.title, isEmpty);
  });

  testWidgets('an empty draft on a new note writes nothing', (tester) async {
    await pumpHost(tester);
    final done = openEditor(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await tester.pumpAndSettle();

    expect(await done, NoteEditorOutcome.untouched);
    expect(await io(tester, () => db.notesForVerse(43, 3, 16)), isEmpty);
  });

  testWidgets('the title round-trips with the body', (tester) async {
    await pumpHost(tester);
    final done = openEditor(tester);
    await tester.pumpAndSettle();

    await type(tester, 'note-editor-title', 'Agapè');
    await type(tester, 'note-editor-body', 'amour de don de soi');
    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await flushIo(tester);
    await tester.pumpAndSettle();

    expect(await done, NoteEditorOutcome.saved);
    final note = (await io(tester, () => db.notesForVerse(43, 3, 16))).single;
    expect(note.title, 'Agapè');
    expect(note.text, 'amour de don de soi');
  });

  testWidgets('closing over an existing note updates it in place', (
    tester,
  ) async {
    final id = await io(
      tester,
      () => db.upsertNote(
        UserNote(
          bookIndex: 43,
          chapter: 3,
          verse: 16,
          text: 'ancien texte',
          updatedAt: 1,
        ),
      ),
    );
    await pumpHost(tester);
    final existing =
        (await io(tester, () => db.notesForVerse(43, 3, 16))).single;
    final done = openEditor(tester, note: existing);
    await tester.pumpAndSettle();

    // The quoted verse and the stored body are on screen.
    expect(find.textContaining('Car Dieu a tant aimé'), findsOneWidget);
    expect(find.text('ancien texte'), findsOneWidget);

    await type(tester, 'note-editor-body', 'texte corrigé');
    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await flushIo(tester);
    await tester.pumpAndSettle();

    expect(await done, NoteEditorOutcome.saved);
    final notes = await io(tester, () => db.notesForVerse(43, 3, 16));
    expect(notes, hasLength(1));
    expect(notes.single.id, id);
    expect(notes.single.text, 'texte corrigé');
  });

  testWidgets('delete asks for confirmation before removing', (tester) async {
    await io(
      tester,
      () => db.upsertNote(
        UserNote(
          bookIndex: 43,
          chapter: 3,
          verse: 16,
          text: 'à supprimer',
          updatedAt: 1,
        ),
      ),
    );
    await pumpHost(tester);
    final done = openEditor(
      tester,
      note: (await io(tester, () => db.notesForVerse(43, 3, 16))).single,
    );
    await tester.pumpAndSettle();

    // Annuler keeps everything.
    await tester.tap(find.byKey(const ValueKey('note-editor-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-editor-delete')), findsOneWidget);

    // Then confirm.
    await tester.tap(find.byKey(const ValueKey('note-editor-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-delete-confirm')));
    await flushIo(tester);
    await tester.pumpAndSettle();

    expect(await done, NoteEditorOutcome.deleted);
    expect(await io(tester, () => db.notesForVerse(43, 3, 16)), isEmpty);
  });

  testWidgets('several notes per verse go through the picker first', (
    tester,
  ) async {
    await io(
      tester,
      () => db.upsertNote(
        UserNote(
          bookIndex: 43,
          chapter: 3,
          verse: 16,
          title: 'Première lecture',
          text: 'première',
          updatedAt: 1,
        ),
      ),
    );
    await io(
      tester,
      () => db.upsertNote(
        UserNote(
          bookIndex: 43,
          chapter: 3,
          verse: 16,
          title: 'Deuxième piste',
          text: 'deuxième',
          updatedAt: 2,
        ),
      ),
    );
    await pumpHost(tester);

    final picked = editVerseNotes(
      context: tester.element(find.byType(Scaffold)),
      db: db,
      bookIndex: 43,
      chapter: 3,
      verse: 16,
      reference: 'Note — Jean 3:16',
      verseText: 'Car Dieu…',
    );

    // The picker lists both notes… (its first read runs real I/O).
    await flushIo(tester);
    await tester.pumpAndSettle();
    expect(find.text('2 notes sur ce verset'), findsOneWidget);
    expect(find.text('Première lecture'), findsOneWidget);
    expect(find.text('Deuxième piste'), findsOneWidget);

    // …and « Nouvelle note » leads to an empty editor.
    await tester.tap(find.byKey(const ValueKey('note-picker-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('note-editor-body')), findsOneWidget);
    expect(find.text('première'), findsNothing);

    await type(tester, 'note-editor-body', 'troisième voie');
    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await flushIo(tester);
    await tester.pumpAndSettle();

    expect(await picked, NoteEditorOutcome.saved);
    expect((await io(tester, () => db.notesForVerse(43, 3, 16))).length, 3);
  });

  testWidgets('the editor fits above the keyboard', (tester) async {
    const keyboard = 260.0;
    // Insets live at the ROOT: the modal route reads them from the navigator's
    // MediaQuery, not from anything nested under `home`.
    await tester.pumpWidget(
      MediaQuery(
        data:
            const MediaQueryData(viewInsets: EdgeInsets.only(bottom: keyboard)),
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await tester.pump();
    final done = openEditor(tester);
    await tester.pumpAndSettle();

    // The sheet's bottom sits above the keyboard line: the body field the
    // reader is typing into stays on screen.
    final sheetBottom =
        tester.getBottomRight(find.byType(NoteEditorSheet)).dy;
    expect(sheetBottom, lessThanOrEqualTo(600 - keyboard + 1));

    await tester.tap(find.byKey(const ValueKey('note-editor-close')));
    await tester.pumpAndSettle();
    expect(await done, NoteEditorOutcome.untouched);
  });
}
