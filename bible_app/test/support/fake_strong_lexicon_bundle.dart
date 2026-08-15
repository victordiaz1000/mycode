import 'dart:convert';

import 'package:flutter/services.dart';

/// An [AssetBundle] that serves a tiny synthetic French Strong lexicon.
///
/// Same reasoning as [FakeBibleBundle]: real `rootBundle` I/O never completes
/// inside the fake-async zone of `testWidgets`.
class FakeStrongLexiconBundle extends AssetBundle {
  static const String _path = 'assets/lexicon/strong_fr.json';

  final Map<String, dynamic> _entries;

  FakeStrongLexiconBundle([
    Map<String, dynamic>? entries,
  ]) : _entries = entries ??
            {
              'H0001': {
                'strong': 'H0001',
                'language': 'hebrew',
                'lemma': '??',
                'transliteration': "'ab",
                'partOfSpeech': 'Nom masculin',
                'pronunciation': '(awb)',
                'etymology': 'Une racine primitive, le même que H7225.',
                'definition': 'Définition test de H0001 — père, chef de famille.',
              },
              'H7225': 'Définition test de H7225.',
              'H0430': 'Définition test de H0430.',
              'G2316': 'Définition test de G2316.',
              'G0001': 'Définition test de G0001.',
            };

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != _path) throw ArgumentError('Asset inconnu : $key');
    return jsonEncode(_entries);
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}