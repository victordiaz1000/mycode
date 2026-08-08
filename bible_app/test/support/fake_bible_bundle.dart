import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:bible_app/data/book_catalog.dart';

/// An [AssetBundle] that serves synthetic BYM books.
///
/// Widget tests must not read the real `assets/bible/bym/` files: `rootBundle`
/// does real I/O, which never completes inside the fake-async zone of
/// `testWidgets`, so every `pumpAndSettle` waits forever. Install it with
/// `LocalRepository.useBundle(FakeBibleBundle())` and restore the real one with
/// `LocalRepository.useRootBundle()` in `tearDown`.
///
/// Any of the 66 catalog files resolves; the book keeps its real name and
/// abbreviation so navigation assertions stay meaningful.
class FakeBibleBundle extends AssetBundle {
  FakeBibleBundle({this.chapters = 2, this.verses = 3});

  /// Chapters generated per book.
  final int chapters;

  /// Verses generated per chapter.
  final int verses;

  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      jsonEncode(bookJson(bookNumberOf(key)));

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  /// BYM number (1..66) behind an `assets/bible/bym/<file>.json` key.
  int bookNumberOf(String key) {
    final file = key.split('/').last;
    final index = bookCatalog.indexWhere((b) => b.file == file);
    if (index < 0) {
      throw StateError('FakeBibleBundle: unknown asset "$key"');
    }
    return index + 1;
  }

  Map<String, dynamic> bookJson(int bookNumber) {
    final entry = bookCatalog[bookNumber - 1];
    return {
      'book': entry.name,
      'abbreviation': entry.abbreviation,
      'metadata': {
        'signification': 'Signification ${entry.abbreviation}',
        'auteur': 'Auteur de test',
        'theme': 'Thème de test',
        'date': 'Date de test',
      },
      'introduction': 'Introduction de test pour ${entry.name}.',
      'chapters': [
        for (var c = 1; c <= chapters; c++)
          {
            'chapter': c,
            'verses': [
              for (var v = 1; v <= verses; v++) _verseJson(entry, c, v),
            ],
          },
      ],
    };
  }

  Map<String, dynamic> _verseJson(BookEntry entry, int c, int v) {
    final text = 'Verset de test ${entry.abbreviation} $c:$v.';
    return {
      'verse': '$c:$v',
      if (v == 1) 'section': 'Section $c',
      'text': text,
      'textWithNotes': v == 1 ? 'Verset [annoté] de test $c:$v.' : text,
      'notes': [
        if (v == 1)
          {'word': 'Verset', 'position': 0, 'note': 'Note de test $c:$v.'},
      ],
    };
  }
}
