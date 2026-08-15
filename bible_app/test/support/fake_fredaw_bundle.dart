import 'dart:convert';

import 'package:flutter/services.dart';

/// An [AssetBundle] that serves a tiny synthetic FreDAW dictionary.
///
/// Same reasoning as [FakeStrongLexiconBundle]: real `rootBundle` I/O never
/// completes inside the fake-async zone of `testWidgets`, and the real
/// `assets/lexicon/fredaw.json` is 12,7 Mo. Widget tests must point
/// [FreDawLexicon] at this before any search runs.
class FakeFreDawBundle extends AssetBundle {
  static const String _path = 'assets/lexicon/fredaw.json';

  final Map<String, dynamic> _entries;

  FakeFreDawBundle([Map<String, dynamic>? entries])
      : _entries = entries ??
            {
              'Verset': {
                'term': 'Verset',
                'definition': 'Portion d\'un chapitre de la Sainte Écriture.',
              },
              'ABBA': {
                'term': 'ABBA',
                'definition': 'Définition test FreDAW de ABBA.',
              },
            };

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != _path) throw ArgumentError('Asset inconnu : $key');
    return jsonEncode({'entries': _entries});
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}