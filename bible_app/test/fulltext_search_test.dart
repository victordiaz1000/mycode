import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/reference_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final index = FulltextIndex.instance;

  setUp(index.clearIndex);

  test('indexes all 66 BYM books and finds Genèse 1:1', () async {
    final found = await index.search('commencement');

    expect(index.isBuilt, isTrue);
    expect(index.size, greaterThan(30_000));
    expect(found.matches, isNotEmpty);
    expect(found.total, greaterThanOrEqualTo(found.matches.length));

    final first = found.matches.firstWhere(
      (m) => m.bookIndex == 1 && m.chapter == 1 && m.verseNumber == 1,
      orElse: () => throw StateError('Gen 1:1 not found'),
    );
    expect(first.text, startsWith('Au commencement'));
  });

  test('search is accent-insensitive (evangile finds Évangile)', () async {
    final found = await index.search('evangile');
    expect(found.matches, isNotEmpty);
    for (final m in found.matches.take(20)) {
      expect(normalizeForSearch(m.text), contains('evangile'));
    }
  });

  test('whole-phrase at verse start ranks before loose matches', () async {
    final found = await index.search('Au commencement');
    expect(found.matches, isNotEmpty);
    expect(found.matches.first.score, 0);
    expect(found.matches.first.bookIndex, 1);
    expect(found.matches.first.chapter, 1);
    expect(found.matches.first.verseNumber, 1);
  });

  test('short and empty queries return nothing', () async {
    expect((await index.search('')).matches, isEmpty);
    expect((await index.search('a')).matches, isEmpty);
  });

  test('results are capped at the default limit', () async {
    final found = await index.search('elohim');
    expect(found.matches.length, lessThanOrEqualTo(60));
    // The cap hides matches but `total` still counts them all.
    expect(found.total, greaterThanOrEqualTo(found.matches.length));
  });

  test('bookFilter restricts the scan to the accepted books', () async {
    final found = await index.search(
      'commencement',
      bookFilter: (book) => book == 1,
    );
    expect(found.matches, isNotEmpty);
    expect(found.matches.every((m) => m.bookIndex == 1), isTrue);
  });

  test('biblicalOrder sorts by position instead of score', () async {
    final found = await index.search('lumiere', biblicalOrder: true);
    expect(found.matches.length, greaterThan(1));
    for (var i = 1; i < found.matches.length; i++) {
      final previous = found.matches[i - 1];
      final current = found.matches[i];
      final ordered = previous.bookIndex < current.bookIndex ||
          (previous.bookIndex == current.bookIndex &&
              (previous.chapter < current.chapter ||
                  (previous.chapter == current.chapter &&
                      previous.verseNumber < current.verseNumber)));
      expect(ordered, isTrue,
          reason: 'out of order at $i: '
              '${previous.bookIndex}/${previous.chapter}/'
              '${previous.verseNumber} then ${current.bookIndex}/'
              '${current.chapter}/${current.verseNumber}');
    }
  });

  test('a second search reuses the built index', () async {
    await index.search('commencement');
    expect(index.isBuilt, isTrue);
    index.clearIndex();
    expect(index.isBuilt, isFalse);
  });
}