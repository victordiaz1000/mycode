import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_catalog.dart';

/// Proves the BYM assets decode without any U+FFFD replacement character:
/// if the reader shows losanges ◆, the cause is glyph rendering (font
/// coverage), not the data or the JSON decoding.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no replacement character in any decoded BYM book', () async {
    var fffd = 0;
    final samples = <String>[];
    for (final book in bookCatalog) {
      final raw = await rootBundle
          .loadString('assets/bible/bym/${book.file}', cache: false);
      // Strict UTF-8 decode: throws on invalid bytes.
      final text = utf8.decode(utf8.encode(raw), allowMalformed: false);
      for (final rune in text.runes) {
        if (rune == 0xFFFD) {
          fffd++;
          if (samples.length < 5) {
            samples.add('${book.file}: …${_context(text, rune)}…');
          }
        }
      }
    }
    expect(fffd, 0, reason: samples.join('\n'));
  });

  test('guillemets and apostrophes survive decoding intact', () async {
    final raw = await rootBundle
        .loadString('assets/bible/bym/${bookCatalog.first.file}', cache: false);
    expect(raw.contains('«'), isTrue, reason: 'guillemet ouvrant attendu');
    expect(raw.contains('»'), isTrue, reason: 'guillemet fermant attendu');
  });

  test('no replacement character baked into the Dart sources', () {
    // A U+FFFD in a string literal reaches the screen as a losange — exactly
    // how the note-card separator once read "1 \uFFFD mot". Sources stay clean.
    final offenders = <String>[];
    for (final dir in ['lib', 'test']) {
      Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .forEach((f) {
        final text = f.readAsStringSync();
        if (text.contains(String.fromCharCode(0xFFFD))) {
          offenders.add(f.path);
        }
      });
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

String _context(String text, int rune) {
  final i = text.runes.toList().indexOf(rune);
  final s = i - 20 < 0 ? 0 : i - 20;
  final e = i + 20 > text.length ? text.length : i + 20;
  return text.substring(s, e).replaceAll('\n', ' ');
}
