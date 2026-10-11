import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Files and registry of the works downloaded on the device.
///
/// Un ouvrage est **un** fichier JSON — comme un dictionnaire, rien à voir avec
/// les 66 requêtes d'une version biblique : pas de granularité par chapitre,
/// pas de reprise. Le fichier atterrit dans `<documents>/works/<code>.json` et
/// le registre de shared_preferences retient lesquels sont présents.
class WorkStore {
  static const String registryKey = 'work.installed';
  static const String worksDirectory = 'works';

  /// Bumped every time the registry changes — un ouvrage qui arrive, un qui
  /// s'en va. **Static on purpose**, même raison que `DictionaryStore.revision`
  /// et `LibraryStore.revision` : chaque écran construit son propre
  /// [WorkStore], donc un notifieur d'instance ne préviendrait personne.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bumpRevision() => revision.value++;

  static Directory? _root;

  /// Directory holding `works/`. Defaults to the app documents directory.
  static Future<Directory> root() async =>
      _root ??= await getApplicationDocumentsDirectory();

  /// Serves files from [dir] instead of the app directory. Tests must call
  /// this : `path_provider` répond par un canal de plateforme, et dans la zone
  /// fake-async de `testWidgets` cette réponse n'arrive jamais — l'await
  /// resterait pendu au lieu d'échouer.
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

  /// Every work code present on the device.
  Future<Set<String>> installed() => _readRegistry();

  Future<File> workFile(String code) async =>
      File(p.join((await root()).path, worksDirectory, '$code.json'));

  /// Writes one downloaded work and records it in the registry.
  ///
  /// The registry is written *after* the file, so an interrupt can leave a file
  /// unrecorded (harmless: it is fetched again) but never a recorded work with
  /// no file, which would read as installed and open empty.
  Future<void> save(String code, Map<String, dynamic> json) async {
    final file = await workFile(code);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(json));

    final registry = await _readRegistry();
    registry.add(code);
    await _writeRegistry(registry);
    _bumpRevision();
  }

  /// Reads back a downloaded work, or null when it is not on the device.
  Future<Map<String, dynamic>?> load(String code) async {
    try {
      final file = await workFile(code);
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
      final file = await workFile(code);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Registry is already clean, so the work reads as absent either way.
    }
  }

  /// Bytes held by [code] on the device — shown under each installed item.
  Future<int> sizeOnDisk(String code) async {
    try {
      final file = await workFile(code);
      if (!await file.exists()) return 0;
      return await file.length();
    } catch (_) {
      return 0;
    }
  }
}
