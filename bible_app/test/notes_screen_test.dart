import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_database.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/screens/notes_screen.dart';

import 'support/fake_bible_bundle.dart';

/// Base factice : aucune base SQLite n'est ouverte et toutes les méthodes sont
/// des microtâches, qui se terminent dans la zone fake-async de `testWidgets`.
///
/// [upsertNote] reproduit le contrat de `AppDatabase.upsertNote` — **écrire
/// incrémente `notesRevision`** —, contrat que `database_test.dart` vérifie
/// sur la vraie base. Ici, seule l'écoute de l'écran est en jeu.
class _FakeDb extends AppDatabase {
  final List<UserNote> notes = [];

  @override
  Future<List<UserNote>> allNotes() async => List.unmodifiable(notes);

  @override
  Future<int> upsertNote(UserNote note) async {
    notes.add(note);
    AppDatabase.notesRevision.value++;
    return note.id ?? notes.length;
  }
}

void main() {
  setUp(() {
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
  });

  Future<void> pumpNotes(WidgetTester tester, _FakeDb db) async {
    await tester.pumpWidget(MaterialApp(home: NotesScreen(db: db)));
    await tester.pumpAndSettle();
  }

  testWidgets('an empty database shows the empty state', (tester) async {
    await pumpNotes(tester, _FakeDb());

    expect(find.text('0 note'), findsOneWidget);
    expect(find.text('Aucune note pour l’instant'), findsOneWidget);
  });

  testWidgets('a note written while the screen is open appears by itself',
      (tester) async {
    final db = _FakeDb();
    await pumpNotes(tester, db);
    expect(find.text('Aucune note pour l’instant'), findsOneWidget);

    // Une note écrite pendant que « Mes notes » est ouvert : l'écran ne se
    // reconstruit pas, seul `notesRevision` peut le recharger — c'est le
    // contrat que `home_screen._openNotes` annonce.
    await db.upsertNote(
      UserNote(
        id: 1,
        bookIndex: 1,
        chapter: 1,
        verse: 2,
        title: 'Première note',
        text: 'Note écrite depuis la lecture.',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 note'), findsOneWidget,
        reason: 'sans notesRevision, la carte attendrait un nouveau lancement');
    expect(find.text('Genèse 1:2'), findsOneWidget);
    expect(find.text('Première note'), findsOneWidget);
    expect(find.text('« Verset de test Ge. 1:2. »'), findsOneWidget);
  });
}
