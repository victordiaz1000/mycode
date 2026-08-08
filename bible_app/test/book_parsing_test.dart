import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = LocalRepository();

  test('Genèse parses book metadata and chapters', () async {
    final book = await repo.loadBook(1);
    expect(book.book, contains('Genèse'));
    expect(book.abbreviation, 'Ge.');
    expect(book.metadata.auteur, isNotEmpty);
    expect(book.chapters, isNotEmpty);
    final c1 = book.chapters.first;
    expect(c1.chapter, 1);
    expect(c1.verses, isNotEmpty);
  });

  test('First verse Genèse:1:1 has text and section', () async {
    final c1 = await repo.loadChapter(1, 1);
    final v1 = c1.verses.first;
    expect(v1.verse, '1:1');
    expect(v1.section, isNotNull);
    expect(v1.text, contains('Elohîm'));
    expect(v1.notes, isNotEmpty);
    expect(v1.textWithNotes, contains('['));
  });

  test('66 books exist in assets', () async {
    final counts = await Future.wait(
        [for (var i = 1; i <= 66; i++) repo.chapterCount(i)]);
    expect(counts.length, 66);
    for (final c in counts) {
      expect(c, greaterThan(0));
    }
  });

  test('loadBook caches (same instance)', () async {
    final a = await repo.loadBook(5);
    final b = await repo.loadBook(5);
    expect(identical(a, b), isTrue);
  });
}
