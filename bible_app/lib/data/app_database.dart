import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/user_data.dart';

/// Local persistence for user data (highlights, notes, favorites, prefs).
///
/// Uses sqflite. The database factory is injectable so tests can use the FFI
/// implementation (`sqflite_common_ffi`).
class AppDatabase {
  // ignore: prefer_initializing_formals (private field, public named param)
  AppDatabase({DatabaseFactory? factory}) : _factory = factory;

  static AppDatabase? _singleton;
  static AppDatabase get instance => _singleton ??= AppDatabase();

  final DatabaseFactory? _factory;
  Database? _db;

  /// Incrémenté à chaque création / modification / suppression de note.
  /// L'Accueil écoute ce notifier pour rester live sans `setState` manuel.
  static final ValueNotifier<int> notesRevision = ValueNotifier<int>(0);

  DatabaseFactory get _effectiveFactory =>
      _factory ?? databaseFactory;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'bym.db');
    _db = await _effectiveFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
    return _db!;
  }

  /// Opens an in-memory database (used by tests via the FFI factory).
  Future<Database> openInMemory() async {
    final f = _factory ?? databaseFactory;
    return f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Makes this instance use an in-memory DB (tests), avoiding path_provider.
  Future<void> useInMemory() async {
    _db = await openInMemory();
  }

  /// Opens an existing file with the app's schema options — used by the
  /// migration tests to replay a v1 database through [_onUpgrade].
  Future<Database> testOpen(String path) async {
    final f = _factory ?? databaseFactory;
    return f.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Closes the underlying database, if any. The factory keys connections by
  /// path — including `inMemoryDatabasePath` — so tests MUST close between
  /// cases or every later « :memory: » open silently reuses the first one.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE highlights (
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        color TEXT NOT NULL,
        PRIMARY KEY (book, chapter, verse)
      )
    ''');
    await _createNotesTable(db);
    await db.execute('''
      CREATE TABLE favorites (
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        PRIMARY KEY (book, chapter, verse)
      )
    ''');
    await db.execute('''
      CREATE TABLE prefs (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  /// v2 — personal notes become first-class rows: autoincrement id (several
  /// notes per verse), optional title. The v1 table keyed notes by verse and
  /// is migrated row-per-row; nothing is dropped but the old shape.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE notes RENAME TO notes_v1');
      await _createNotesTable(db);
      await db.execute('''
        INSERT INTO notes (book, chapter, verse, title, text, updated_at, created_at)
        SELECT book, chapter, verse, '', text, updated_at, created_at FROM notes_v1
      ''');
      await db.execute('DROP TABLE notes_v1');
    }
  }

  Future<void> _createNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        text TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        created_at INTEGER
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_notes_verse ON notes(book, chapter, verse)',
    );
  }

  // ---- Highlights ----

  Future<void> setHighlight(int book, int chapter, int verse, String? colorId) async {
    final db = await database;
    if (colorId == null || colorId.isEmpty) {
      await db.delete('highlights',
          where: 'book=? AND chapter=? AND verse=?',
          whereArgs: [book, chapter, verse]);
      return;
    }
    await db.insert(
      'highlights',
      UserHighlight(
              bookIndex: book, chapter: chapter, verse: verse, colorId: colorId)
          .toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getHighlight(int book, int chapter, int verse) async {
    final db = await database;
    final rows = await db.query('highlights',
        columns: ['color'],
        where: 'book=? AND chapter=? AND verse=?',
        whereArgs: [book, chapter, verse]);
    return rows.isEmpty ? null : rows.first['color'] as String?;
  }

  Future<Map<int, String>> highlightsInChapter(int book, int chapter) async {
    final db = await database;
    final rows = await db.query('highlights',
        columns: ['verse', 'color'],
        where: 'book=? AND chapter=?',
        whereArgs: [book, chapter]);
    return {
      for (final r in rows) r['verse'] as int: r['color'] as String
    };
  }

  // ---- Notes ----

  /// Writes [note] and returns its row id. A note carrying an [UserNote.id]
  /// is updated in place; one without is inserted — so several notes can
  /// live on the same verse, each with its own identity.
  Future<int> upsertNote(UserNote note) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (note.id != null) {
      await db.update(
        'notes',
        {
          'title': note.title,
          'text': note.text,
          'updated_at': now,
        },
        where: 'id=?',
        whereArgs: [note.id],
      );
      notesRevision.value++;
      return note.id!;
    }
    final id = await db.insert(
      'notes',
      note
          .copyWith(updatedAt: now)
          .toMap(),
    );
    notesRevision.value++;
    return id;
  }

  /// Every note on the verse, most recently edited first.
  Future<List<UserNote>> notesForVerse(
    int book,
    int chapter,
    int verse,
  ) async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'book=? AND chapter=? AND verse=?',
      whereArgs: [book, chapter, verse],
      orderBy: 'updated_at DESC',
    );
    return [for (final r in rows) UserNote.fromMap(r)];
  }

  Future<void> deleteNoteById(int id) async {
    final db = await database;
    await db.delete('notes', where: 'id=?', whereArgs: [id]);
    notesRevision.value++;
  }

  // ---- Favorites ----

  Future<void> setFavorite(int book, int chapter, int verse, bool value) async {
    final db = await database;
    if (!value) {
      await db.delete('favorites',
          where: 'book=? AND chapter=? AND verse=?',
          whereArgs: [book, chapter, verse]);
      return;
    }
    await db.insert(
      'favorites',
      UserFavorite(bookIndex: book, chapter: chapter, verse: verse).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isFavorite(int book, int chapter, int verse) async {
    final db = await database;
    final rows = await db.query('favorites',
        where: 'book=? AND chapter=? AND verse=?',
        whereArgs: [book, chapter, verse]);
    return rows.isNotEmpty;
  }

  Future<Set<int>> favoritesInChapter(int book, int chapter) async {
    final db = await database;
    final rows = await db.query('favorites',
        columns: ['verse'],
        where: 'book=? AND chapter=?',
        whereArgs: [book, chapter]);
    return {for (final r in rows) r['verse'] as int};
  }

  /// Verse numbers (within the chapter) that carry a user note.
  Future<Set<int>> notesInChapter(int book, int chapter) async {
    final db = await database;
    final rows = await db.query('notes',
        columns: ['verse'],
        where: 'book=? AND chapter=? AND text != ?',
        whereArgs: [book, chapter, '']);
    return {for (final r in rows) r['verse'] as int};
  }

  /// User notes whose text contains [query], most recently edited first.
  ///
  /// Feeds the « Notes » category of the search screen. The match is a plain
  /// SQL `LIKE` (case-insensitive on ASCII, accent-sensitive); `%` and `_` in
  /// [query] are escaped so a note containing them can still be searched.
  Future<List<UserNote>> searchNotes(String query, {int limit = 30}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final db = await database;
    final pattern = trimmed
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final rows = await db.query(
      'notes',
      where: "text LIKE ? ESCAPE '\\' AND text != ''",
      whereArgs: ['%$pattern%'],
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return [for (final r in rows) UserNote.fromMap(r)];
  }

  /// Every note with text, most recent first. Feeds the home « Mes notes »
  /// section and the dedicated [NotesScreen].
  Future<List<UserNote>> allNotes() async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: "text != ''",
      orderBy: 'updated_at DESC',
    );
    return [for (final r in rows) UserNote.fromMap(r)];
  }

  /// Every favorited verse, in bible order. Feeds the « Passages » filter and
  /// the home screen's Favoris shortcut.
  Future<List<UserFavorite>> allFavorites() async {
    final db = await database;
    final rows = await db.query('favorites', orderBy: 'book, chapter, verse');
    return [
      for (final r in rows)
        UserFavorite(
          bookIndex: r['book'] as int,
          chapter: r['chapter'] as int,
          verse: r['verse'] as int,
        ),
    ];
  }

  // ---- Prefs ----

  Future<void> setPref(String key, String value) async {
    final db = await database;
    await db.insert(
      'prefs',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getPref(String key) async {
    final db = await database;
    final rows = await db.query('prefs',
        columns: ['value'], where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }
}
