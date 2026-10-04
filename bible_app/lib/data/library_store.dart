import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_catalog.dart';
import 'version_catalog.dart';

/// What the Bibliothèque knows about one downloaded version.
class InstalledVersion {
  final String code;

  /// BYM book indexes (1..66) whose file is on the device.
  final Set<int> books;

  const InstalledVersion({required this.code, required this.books});

  static InstalledVersion empty(String code) =>
      InstalledVersion(code: code, books: const {});

  int get bookCount => books.length;

  bool get isEmpty => books.isEmpty;

  /// Every book the version's canon holds landed.
  ///
  /// The canon comes from the catalogue, not from the 66: an `otOnly` version
  /// (SEF) holds 39 books, and without this it would read as partial forever —
  /// Matthieu, absent from its canon, could never land.
  bool get isComplete {
    final entry = versionByCode(code);
    for (var i = 1; i <= bookCatalog.length; i++) {
      if (entry != null && !entry.containsBook(i)) continue;
      if (!books.contains(i)) return false;
    }
    return true;
  }

  /// Started but interrupted — the case a resume exists for.
  bool get isPartial => books.isNotEmpty && !isComplete;

  /// 0.0 .. 1.0, for the progress bar — against the version's own canon, so a
  /// complete SEF install reads 39/39, not 39/66.
  double get progress {
    final entry = versionByCode(code);
    final total = entry?.bookCount ?? bookCatalog.length;
    if (total == 0 || bookCatalog.isEmpty) return 0;
    var landed = 0;
    for (final i in books) {
      if (entry == null || entry.containsBook(i)) landed++;
    }
    return (landed / total).clamp(0.0, 1.0);
  }

  bool has(int bookIndex) => books.contains(bookIndex);
}

/// Files and registry of the versions downloaded on the device (décision 6).
///
/// A book lands as one gzip-compressed JSON file under
/// `<documents>/versions/<code>/<bymIndex>.json.gz`, and the registry in
/// shared_preferences records which ones arrived. That is what makes an install
/// resumable: a download that dies at book 40 keeps its 39 files, and the next
/// attempt fetches only what is missing. With 66 requests per version, one
/// failing partway through is the normal case on a phone network, not the
/// exception.
///
/// Les installations antérieures à la compression portent le nom en clair
/// `<bymIndex>.json` ; [loadBook] lit les deux régimes, cf. [legacyBookFile].
class LibraryStore {
  static const String registryKey = 'library.installed';
  static const String versionsDirectory = 'versions';

  /// Bumped every time the registry changes — a book landing, a version being
  /// removed. **Static on purpose**: each screen builds its own [LibraryStore],
  /// so an instance-level notifier would tell nobody. Same reasoning as the
  /// static caches of `LocalRepository` / `VersionRepository`.
  ///
  /// Without it, a screen that read [installed] once keeps that answer forever.
  /// The reader lives inside the tab shell's `IndexedStack`, so `initState`
  /// never runs again: after a download it still believed the version was
  /// absent and sent the reader back to the Bibliothèque, which showed it as
  /// installed. Listen to this instead of reading the registry once.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bumpRevision() => revision.value++;

  static Directory? _root;

  /// Directory holding `versions/`. Defaults to the app documents directory.
  static Future<Directory> root() async =>
      _root ??= await getApplicationDocumentsDirectory();

  /// Serves files from [dir] instead of the app directory. Tests must call this:
  /// `path_provider` answers over a platform channel, and inside the fake-async
  /// zone of `testWidgets` that reply never arrives, so the await hangs instead
  /// of failing.
  static void useRoot(Directory dir) => _root = dir;

  /// Restores the real app directory (call in `tearDown`).
  static void useAppDirectory() => _root = null;

  Future<Map<String, Set<int>>> _readRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(registryKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          entry.key: {
            for (final n in (entry.value as List<dynamic>? ?? const []))
              if (n is num) n.toInt(),
          },
      };
    } catch (_) {
      // A corrupt registry must not brick the Bibliothèque: the files are still
      // there and re-downloading is always allowed.
      return {};
    }
  }

  Future<void> _writeRegistry(Map<String, Set<int>> registry) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      for (final entry in registry.entries)
        if (entry.value.isNotEmpty) entry.key: (entry.value.toList()..sort()),
    };
    if (payload.isEmpty) {
      await prefs.remove(registryKey);
      return;
    }
    await prefs.setString(registryKey, jsonEncode(payload));
  }
  /// Every version with at least one book on the device, by code.
  Future<Map<String, InstalledVersion>> installed() async {
    final registry = await _readRegistry();
    return {
      for (final entry in registry.entries)
        entry.key: InstalledVersion(code: entry.key, books: entry.value),
    };
  }

  /// What is on the device for [code] — never null, empty when nothing landed.
  Future<InstalledVersion> versionState(String code) async {
    final registry = await _readRegistry();
    final books = registry[code];
    return books == null || books.isEmpty
        ? InstalledVersion.empty(code)
        : InstalledVersion(code: code, books: books);
  }

  /// BYM book indexes still to fetch for [code], in reading order — scoped to
  /// the version's canon: books the version does not hold (New Testament in an
  /// `otOnly` SEF) are not « missing », they do not exist.
  Future<List<int>> missingBooks(String code) async {
    final entry = versionByCode(code);
    final state = await versionState(code);
    return [
      for (var i = 1; i <= bookCatalog.length; i++)
        if ((entry == null || entry.containsBook(i)) && !state.has(i)) i,
    ];
  }

  Future<Directory> versionDirectory(String code) async =>
      Directory(p.join((await root()).path, versionsDirectory, code));

  /// Where [saveBook] writes: gzip, `$bookIndex.json.gz`.
  ///
  /// Le JSON d'une version est très compressible — du texte, des clés répétées
  /// à chaque verset. L'ATI le rend décisif : 35 Mo en clair, 7 Mo en gzip, et
  /// c'est le second chiffre qu'on peut demander à un téléphone. Les autres
  /// versions y gagnent aussi, sans rien changer d'autre que ce nom de fichier.
  Future<File> bookFile(String code, int bookIndex) async =>
      File(p.join((await versionDirectory(code)).path, '$bookIndex.json.gz'));

  /// L'ancien nom, en clair — lu, jamais écrit.
  ///
  /// Les versions déjà installées sur l'appareil portent ce nom. Les relire
  /// plutôt que les réécrire évite une migration : rien à exécuter au premier
  /// lancement, rien qui puisse échouer à moitié. Une version ne passe en gzip
  /// qu'à sa réinstallation.
  Future<File> legacyBookFile(String code, int bookIndex) async =>
      File(p.join((await versionDirectory(code)).path, '$bookIndex.json'));

  /// Writes one downloaded book and records it in the registry.
  ///
  /// The registry is written *after* the file, so an interrupt can leave a file
  /// unrecorded (harmless: it is fetched again) but never a recorded book with
  /// no file, which would read as installed and fail at open time.
  Future<void> saveBook(
    String code,
    int bookIndex,
    Map<String, dynamic> json,
  ) async {
    final file = await bookFile(code, bookIndex);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(gzip.encode(utf8.encode(jsonEncode(json))));

    // Un livre réinstallé laisserait sinon son ancienne copie en clair derrière
    // lui : deux fichiers pour un livre, et `sizeOnDisk` annoncerait le double.
    final legacy = await legacyBookFile(code, bookIndex);
    if (await legacy.exists()) await legacy.delete();

    final registry = await _readRegistry();
    registry.putIfAbsent(code, () => <int>{}).add(bookIndex);
    await _writeRegistry(registry);
    _bumpRevision();
  }

  /// Reads back a downloaded book, or null when it is not on the device.
  ///
  /// Les deux régimes, gzip d'abord : une installation d'avant la compression
  /// continue de se lire telle quelle.
  Future<Map<String, dynamic>?> loadBook(String code, int bookIndex) async {
    try {
      final file = await bookFile(code, bookIndex);
      if (await file.exists()) {
        final texte = utf8.decode(gzip.decode(await file.readAsBytes()));
        return jsonDecode(texte) as Map<String, dynamic>;
      }
      final legacy = await legacyBookFile(code, bookIndex);
      if (!await legacy.exists()) return null;
      return jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Deletes every file of [code] and drops it from the registry (🗑).
  Future<void> remove(String code) async {
    final registry = await _readRegistry();
    registry.remove(code);
    await _writeRegistry(registry);
    _bumpRevision();

    try {
      final dir = await versionDirectory(code);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Registry is already clean, so the version reads as absent either way.
    }
  }

  /// Bytes held by [code] on the device — shown under each installed item.
  Future<int> sizeOnDisk(String code) async {
    try {
      final dir = await versionDirectory(code);
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}
