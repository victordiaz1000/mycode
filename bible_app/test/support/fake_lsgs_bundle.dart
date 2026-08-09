import 'dart:convert';

import 'package:flutter/services.dart';

/// An [AssetBundle] that serves a synthetic LSGS book.
///
/// Same reasoning as [FakeBibleBundle]: real `rootBundle` I/O never completes
/// inside the fake-async zone of `testWidgets`.
class FakeLsgsBundle extends AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      jsonEncode({
        'book': 'Genèse',
        'bym_index': 1,
        'chapters': [
          {
            'chapter': 1,
            'verses': [
              _verse(1),
              _verse(2),
            ],
          },
        ],
      });

  Map<String, dynamic> _verse(int number) => number == 1
      ? {
          'verse': 1,
          'tokens': [
            {'text': 'AA', 'strong': 'H7225'},
          ],
        }
      : {
          'verse': 2,
          'tokens': [
            {'text': 'Au commencement', 'strong': null},
          ],
        };

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}