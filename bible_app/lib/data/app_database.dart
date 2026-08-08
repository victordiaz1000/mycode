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

  DatabaseFactory get _effectiveFactory =>
      _factory ?? databaseFactory;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'bym.db');
    _db = await _effectiveFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
    return _db!;
  }

  /// Opens an in-memory database (used by tests via the FFI factory).
  Future<Database> openInMemory() async {
    final f = _factory ?? databaseFactory;
    return f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _onCreate),
    );
  }

  /// Makes this instance use an in-memory DB (tests), avoiding path_provider.
  Future<void> useInMemory() async {
    _db = await openInMemory();
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

  Future<void> saveNote(int book, int chapter, int verse, String text) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await getNote(book, chapter, verse);
    await db.insert(
      'notes',
      UserNote(
        bookIndex: book,
        chapter: chapter,
        verse: verse,
        text: text,
        updatedAt: now,
        createdAt: existing?.createdAt ?? now,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserNote?> getNote(int book, int chapter, int verse) async {
    final db = await database;
    final rows = await db.query('notes',
        where: 'book=? AND chapter=? AND verse=?',
        whereArgs: [book, chapter, verse]);
    return rows.isEmpty ? null : UserNote.fromMap(rows.first);
  }

  Future<void> deleteNote(int book, int chapter, int verse) async {
    final db = await database;
    await db.delete('notes',
        where: 'book=? AND chapter=? AND verse=?',
        whereArgs: [book, chapter, verse]);
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
