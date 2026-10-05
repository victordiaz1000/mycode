import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Le `notes.json` **embarqué**, lu sur disque.
///
/// Dans `testWidgets`, le `rootBundle` réel ne complète jamais — zone
/// fake-async — et un extrait synthétique ne prouverait rien sur les 37 pages
/// qui partent vraiment en bundle. Lire le fichier du package, donc : mêmes
/// octets, aucune panne à deviner.
class FakeNotesBundle extends AssetBundle {
  static const String assetPath = 'assets/ati/notes.json';

  /// Jeton d'échec : [loadString] lève, comme le ferait un bundle auquel le
  /// fichier manque.
  static const String missing = ':absent:';

  final String _key;

  FakeNotesBundle([this._key = assetPath]);

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != assetPath) throw ArgumentError('Asset inconnu : $key');
    if (_key == missing) throw ArgumentError('Asset absent : $key');
    return File(assetPath).readAsStringSync();
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
