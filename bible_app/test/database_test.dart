import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/data/app_database.dart';
import 'package:bible_app/models/user_data.dart';

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late AppDatabase db;
  setUp(() {
    db = AppDatabase(factory: factory);
    return db.useInMemory();
  });

  test('highlight set/get/clear', () async {
    await db.setHighlight(1, 1, 26, '#fff3b0');
    expect(await db.getHighlight(1, 1, 26), '#fff3b0');
    final chapterHighlights = await db.highlightsInChapter(1, 1);
    expect(chapterHighlights[26], '#fff3b0');

    await db.setHighlight(1, 1, 26, null);
    expect(await db.getHighlight(1, 1, 26), isNull);
  });

  test('note upsert / multiple per verse / delete by id', () async {
    final id = await db.upsertNote(
      UserNote(
        bookIndex: 1,
        chapter: 6,
        verse: 14,
        title: 'Kaphar',
        text: 'couvriras = kaphar : expiatoire',
        updatedAt: 1,
      ),
    );
    var notes = await db.notesForVerse(1, 6, 14);
    expect(notes, hasLength(1));
    expect(notes.single.text, contains('kaphar'));
    expect(notes.single.title, 'Kaphar');

    // Updating keeps ONE row (identity lives on the id, not the verse).
    await db.upsertNote(notes.single.copyWith(text: 'texte corrigé'));
    notes = await db.notesForVerse(1, 6, 14);
    expect(notes, hasLength(1));
    expect(notes.single.text, 'texte corrigé');

    // A second note on the same verse coexists with the first.
    final id2 = await db.upsertNote(
      UserNote(
        bookIndex: 1,
        chapter: 6,
        verse: 14,
        text: 'seconde lecture',
        updatedAt: 2,
      ),
    );
    expect(id2, isNot(id));
    notes = await db.notesForVerse(1, 6, 14);
    expect(notes, hasLength(2));

    final inChapter = await db.notesInChapter(1, 6);
    expect(inChapter, {14});

    await db.deleteNoteById(id2);
    notes = await db.notesForVerse(1, 6, 14);
    expect(notes, hasLength(1));
    expect(notes.single.id, id);

    await db.deleteNoteById(id);
    expect(await db.notesForVerse(1, 6, 14), isEmpty);
  });

  test('v1 rows survive the v2 migration (title empty, text kept)', () async {
    // Simulate a v1 database: open at version 1 with the old schema.
    final f = databaseFactoryFfi;
    final dir = await f.getDatabasesPath();
    final path = p.join(dir, 'migration-test-${DateTime.now().microsecondsSinceEpoch}.db');
    final old = await f.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE notes (
            book INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            created_at INTEGER,
            PRIMARY KEY (book, chapter, verse)
          )
        ''');
      }),
    );
    await old.insert('notes', {
      'book': 23,
      'chapter': 53,
      'verse': 5,
      'text': 'blessé pour nos péchés',
      'updated_at': 42,
      'created_at': 40,
    });
    await old.close();

    // Reopen through the app class: the upgrade path runs to v2.
    final migrated = AppDatabase(factory: f);
    final dbHandle = await migrated.testOpen(path);
    final rows =
        await dbHandle.query('notes', where: 'book=?', whereArgs: [23]);
    expect(rows, hasLength(1));
    expect(rows.single['text'], 'blessé pour nos péchés');
    expect(rows.single['title'], '');
    expect(rows.single['id'], isNotNull);
    await dbHandle.close();
    // Leave no trace in the temp databases dir.
    await File(path).delete();
  });

  test('favorite toggle', () async {
    await db.setFavorite(1, 1, 27, true);
    expect(await db.isFavorite(1, 1, 27), isTrue);
    final favorites = await db.favoritesInChapter(1, 1);
    expect(favorites, contains(27));
    await db.setFavorite(1, 1, 27, false);
    expect(await db.isFavorite(1, 1, 27), isFalse);
  });

  test('every write bumps the revision the live screens listen to', () async {
    // Ces deux notifiers sont les seules sources de rafraîchissement hors
    // rebuild : un écran ne se recharge pas tout seul quand ailleurs on écrit.
    // On pose ici le contrat sur la vraie base ; les tests d'écran ne prouvent
    // que l'écoute.
    final favBefore = AppDatabase.favoritesRevision.value;
    await db.setFavorite(1, 1, 27, true);
    expect(AppDatabase.favoritesRevision.value, favBefore + 1,
        reason: 'un favori ajouté depuis la lecture réveille Favoris');
    await db.setFavorite(1, 1, 27, false);
    expect(AppDatabase.favoritesRevision.value, favBefore + 2,
        reason: 'le retrait notifie aussi : le cœur retire depuis l’écran');

    final noteBefore = AppDatabase.notesRevision.value;
    final id = await db.upsertNote(
      UserNote(
        bookIndex: 1,
        chapter: 6,
        verse: 14,
        text: 'première version',
        updatedAt: 1,
      ),
    );
    expect(AppDatabase.notesRevision.value, noteBefore + 1,
        reason: 'une note créée depuis la lecture réveille Mes notes');

    await db.upsertNote(
      (await db.notesForVerse(1, 6, 14)).single.copyWith(text: 'corrigé'),
    );
    expect(AppDatabase.notesRevision.value, noteBefore + 2);

    await db.deleteNoteById(id);
    expect(AppDatabase.notesRevision.value, noteBefore + 3,
        reason: 'une note supprimée vide la liste sans lancement');
  });

  test('prefs get/set', () async {
    await db.setPref('reading.disposition', 'inline');
    expect(await db.getPref('reading.disposition'), 'inline');
  });
}