import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:bible_app/data/app_database.dart';

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

  test('note save/get/update/delete persisted', () async {
    await db.saveNote(1, 6, 14, 'couvriras = kaphar : expiatoire');
    final note = await db.getNote(1, 6, 14);
    expect(note, isNotNull);
    expect(note!.text, contains('kaphar'));

    final inChapter = await db.notesInChapter(1, 6);
    expect(inChapter, contains(14));

    await db.deleteNote(1, 6, 14);
    expect(await db.getNote(1, 6, 14), isNull);
  });

  test('favorite toggle', () async {
    await db.setFavorite(1, 1, 27, true);
    expect(await db.isFavorite(1, 1, 27), isTrue);
    final favorites = await db.favoritesInChapter(1, 1);
    expect(favorites, contains(27));
    await db.setFavorite(1, 1, 27, false);
    expect(await db.isFavorite(1, 1, 27), isFalse);
  });

  test('prefs get/set', () async {
    await db.setPref('reading.disposition', 'inline');
    expect(await db.getPref('reading.disposition'), 'inline');
  });
}