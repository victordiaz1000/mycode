import 'dart:convert';

import 'package:flutter/services.dart';

/// An [AssetBundle] that serves a synthetic LSGS — or LSS — book.
///
/// Same reasoning as [FakeBibleBundle]: real `rootBundle` I/O never completes
/// inside the fake-async zone of `testWidgets`.
///
/// The two embedded corpora are told apart by their particles: the LSS numbers
/// the waw consecutive of Genèse 1:1 (H8804), a token the LSGS does not carry
/// — that density is the whole point of the LSS. Only a key under `bible/lss/`
/// gets it, so a test can prove which corpus a screen is reading by its text
/// alone.
class FakeLsgsBundle extends AssetBundle {
  static const String _lssPath = 'bible/lss/';

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
            _verse(1, particle: key.contains(_lssPath)),
            _verse(2),
          ],
        },
      ],
    });
  }

  Map<String, dynamic> _verse(int number, {bool particle = false}) => number == 1
      ? {
          'verse': 1,
          'tokens': [
            {'text': 'AA', 'strong': 'H7225'},
            if (particle)
              // Un jeton sans texte : le mot n'existe pas en français, il n'en
              // reste que le code. En lecture il prend la place du mot.
              {'text': '', 'strong': 'H8804'},
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