import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Bibliothèque knows about one downloaded dictionary.
class InstalledDictionary {
  final String code;

  const InstalledDictionary({required this.code});

  static InstalledDictionary empty(String code) =>
      InstalledDictionary(code: code);
}

/// Files and registry of the dictionaries downloaded on the device.
///
/// A dictionary is **one** JSON file (`{entries: {...}}`) — nothing like the
/// 66 requests of a Bible version (décision 9), so the store is deliberately
/// smaller than [LibraryStore]: no per-book granularity, no resume. The file
/// lands under `<documents>/dictionaries/<code>.json` and the registry in
/// shared_preferences records which ones are present.
class DictionaryStore {
  static const String registryKey = 'dictionary.installed';
  static const String dictionariesDirectory = 'dictionaries';

  /// Bumped every time the registry changes — a dictionary landing, one being
  /// removed. **Static on purpose**, same reasoning as `LibraryStore.revision`:
  /// each screen builds its own [DictionaryStore], so an instance-level
  /// notifier would tell nobody.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bumpRevision() => revision.value++;

  static Directory? _root;

  /// Directory holding `dictionaries/`. Defaults to the app documents directory.
  static Future<Directory> root() async =>
      _root ??= await getApplicationDocumentsDirectory();

  /// Serves files from [dir] instead of the app directory. Tests must call this:
  /// `path_provider` answers over a platform channel, and inside the fake-async
  /// zone of `testWidgets` that reply never arrives, so the await hangs instead
  /// of failing.
  static void useRoot(Directory dir) => _root = dir;

  /// Restores the real app directory (call in `tearDown`).
  static void useAppDirectory() => _root = null;

  Future<Set<String>> _readRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(registryKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return {};
      return {
        for (final item in decoded)
          if (item is String && item.isNotEmpty) item,
      };
    } catch (_) {
      // A corrupt registry must not brick the Bibliothèque: the files are still
      // there and re-downloading is always allowed.
      return {};
    }
  }

  Future<void> _writeRegistry(Set<String> registry) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = registry.toList()..sort();
    if (payload.isEmpty) {
      await prefs.remove(registryKey);
      return;
    }
    await prefs.setString(registryKey, jsonEncode(payload));
  }

  /// Every dictionary code present on the device.
  Future<Set<String>> installed() => _readRegistry();

  Future<File> dictionaryFile(String code) async =>
      File(p.join((await root()).path, dictionariesDirectory, '$code.json'));

  /// Writes one downloaded dictionary and records it in the registry.
  ///
  /// The registry is written *after* the file, so an interrupt can leave a file
  /// unrecorded (harmless: it is fetched again) but never a recorded dictionary
  /// with no file, which would read as installed and fail at open time.
  Future<void> save(String code, Map<String, dynamic> json) async {
    final file = await dictionaryFile(code);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));

    final registry = await _readRegistry();
    registry.add(code);
    await _writeRegistry(registry);
    _bumpRevision();
  }

  /// Reads back a downloaded dictionary, or null when it is not on the device.
  Future<Map<String, dynamic>?> load(String code) async {
    try {
      final file = await dictionaryFile(code);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the file of [code] and drops it from the registry (🗑).
  Future<void> remove(String code) async {
    final registry = await _readRegistry();
    registry.remove(code);
    await _writeRegistry(registry);
    _bumpRevision();

    try {
      final file = await dictionaryFile(code);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Registry is already clean, so the dictionary reads as absent either way.
    }
  }

  /// Bytes held by [code] on the device — shown under each installed item.
  Future<int> sizeOnDisk(String code) async {
    try {
      final file = await dictionaryFile(code);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }
}