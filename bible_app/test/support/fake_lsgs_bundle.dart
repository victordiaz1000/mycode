import 'dart:convert';

import 'package:flutter/services.dart';

/// An [AssetBundle] that serves a synthetic LSGS book.
///
/// Same reasoning as [FakeBibleBundle]: real `rootBundle` I/O never completes
/// inside the fake-async zone of `testWidgets`.
class FakeLsgsBundle extends AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    // The corpus scan reads all 66 books: every key beyond Genèse must serve an
    // empty book, or the index would register H7225 once per book number.
    final number = RegExp(r'_?(\d+)-').firstMatch(key)?.group(1);
    if (number != null && number != '01') {
      return jsonEncode({
        'book': 'Vide',
        'bym_index': int.parse(number),
        'abbreviation': '',
        'osis_id': '',
        'chapters': <Object>[],
      });
    }
    return jsonEncode({
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
  }

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