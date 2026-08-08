import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/reading_history.dart';
import 'package:bible_app/data/search_engine.dart';

import 'support/fake_bible_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    FulltextIndex.instance.clearIndex();
    LexiconIndex.instance.clearIndex();
    // No AppDatabase: it needs path_provider. The engine must degrade to the
    // sources it can reach, which is what a fresh install does too.
    engine = SearchEngine(history: ReadingHistory());
  });

  tearDown(LocalRepository.useRootBundle);

  group('SearchFilters', () {
    test('allows every book by default', () {
      const filters = SearchFilters();
      expect(filters.allows(1), isTrue);
      expect(filters.allows(66), isTrue);
      expect(filters.isNarrowed, isFalse);
      expect(filters.sectionLabel, 'Tout');
      expect(filters.bookLabel, 'Tout');
    });

    test('a section restricts to its range', () {
      // Section 0 is the Torah (books 1..5).
      const filters = SearchFilters(sectionIndex: 0);
      expect(filters.allows(1), isTrue);
      expect(filters.allows(5), isTrue);
      expect(filters.allows(6), isFalse);
      expect(filters.isNarrowed, isTrue);
      expect(filters.sectionLabel, 'Torah');
    });

    test('a book wins over its section', () {
      const filters = SearchFilters(sectionIndex: 0, bookIndex: 43);
      expect(filters.allows(43), isTrue);
      expect(filters.allows(1), isFalse);
    });

    test('copyWith clears a field only when asked', () {
      const filters = SearchFilters(sectionIndex: 2, bookIndex: 7);
      expect(filters.copyWith().sectionIndex, 2);
      expect(filters.copyWith(clearBook: true).bookIndex, isNull);
      expect(filters.copyWith(clearBook: true).sectionIndex, 2);
      expect(filters.copyWith(clearSection: true).sectionIndex, isNull);
    });
  });

  group('SearchCategory', () {
    test('Liens, Strong and Nave are declared unavailable', () {
      expect(SearchCategory.liens.available, isFalse);
      expect(SearchCategory.strong.available, isFalse);
      expect(SearchCategory.nave.available, isFalse);
      expect(SearchCategory.liens.unavailableReason, isNotEmpty);
      expect(SearchCategory.strong.unavailableReason, isNotEmpty);
      expect(SearchCategory.nave.unavailableReason, isNotEmpty);
    });

    test('searchable holds the four wired sources', () {
      expect(SearchCategory.searchable, {
        SearchCategory.passages,
        SearchCategory.notes,
        SearchCategory.etudes,
        SearchCategory.dictionnaire,
      });
    });
  });

  group('SearchEngine', () {
    test('a query under the minimum returns an empty outcome', () async {
      final outcome = await engine.search('a');
      expect(outcome.isEmpty, isTrue);
      expect(outcome.groups, isEmpty);
      expect(outcome.reference, isNull);
    });

    test('groups passage results and reports the uncapped total', () async {
      final outcome = await engine.search('verset');
      final passages = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.passages);

      expect(passages.hits.length, SearchEngine.pageSize);
      expect(passages.total, greaterThan(SearchEngine.pageSize));
      expect(passages.truncated, isTrue);
      expect(passages.hits.first.bookIndex, 1);
      expect(passages.hits.first.canOpen, isTrue);
    });

    test('expanding a category returns more than one page', () async {
      final outcome = await engine.search(
        'verset',
        expanded: {SearchCategory.passages},
      );
      final passages = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.passages);
      expect(passages.hits.length, greaterThan(SearchEngine.pageSize));
    });

    test('a reference query resolves to the verse itself', () async {
      final outcome = await engine.search('Jean 1:2');

      expect(outcome.reference, isNotNull);
      expect(outcome.reference!.bookIndex, 43);
      expect(outcome.reference!.chapter, 1);
      expect(outcome.reference!.verse, 2);
      expect(outcome.reference!.label, 'Jean 1:2');
      expect(outcome.reference!.text, contains('Jn. 1:2'));
    });

    test('a bare book name is not treated as a reference', () async {
      final outcome = await engine.search('Apocalypse');
      expect(outcome.reference, isNull);
    });

    test('a reference outside the filters is dropped', () async {
      final outcome = await engine.search(
        'Jean 1:2',
        // Torah only — Jean (43) is out of range.
        filters: const SearchFilters(sectionIndex: 0),
      );
      expect(outcome.reference, isNull);
    });

    test('a reference keeps the exact verse asked for', () async {
      // A chapter long enough that verse 16 is far from the top — the case
      // that used to open the chapter without ever reaching the verse.
      LocalRepository.useBundle(FakeBibleBundle(chapters: 4, verses: 20));
      final outcome =
          await SearchEngine(history: ReadingHistory()).search('Jean 3:16');

      expect(outcome.reference, isNotNull);
      expect(outcome.reference!.bookIndex, 43);
      expect(outcome.reference!.chapter, 3);
      expect(outcome.reference!.verse, 16);
      expect(outcome.reference!.text, contains('Jn. 3:16'));
    });

    test('a reference to a missing verse is dropped', () async {
      // The fake books stop at chapter 2, verse 3.
      final outcome = await engine.search('Jean 1:9');
      expect(outcome.reference, isNull);
    });

    test('the book filter restricts the passage rows', () async {
      final outcome = await engine.search(
        'verset',
        filters: const SearchFilters(bookIndex: 43),
      );
      final passages = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.passages);
      expect(passages.hits.every((h) => h.bookIndex == 43), isTrue);
    });

    test('selecting one category leaves the others out', () async {
      final outcome = await engine.search(
        'verset',
        categories: {SearchCategory.dictionnaire},
      );
      expect(
        outcome.groups.every((g) => g.category == SearchCategory.dictionnaire),
        isTrue,
      );
    });

    test('an unavailable category is never queried', () async {
      final outcome = await engine.search(
        'verset',
        categories: {SearchCategory.strong},
      );
      expect(outcome.groups, isEmpty);
    });

    test('études come from the reading history', () async {
      final history = ReadingHistory();
      await history.record(43, 1);
      final outcome = await SearchEngine(history: history).search('Jean');

      final etudes =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.etudes);
      expect(etudes.hits.first.title, 'Jean 1');
      expect(etudes.hits.first.bookIndex, 43);
      expect(etudes.hits.first.canOpen, isTrue);
    });

    test('groups keep the declaration order of their categories', () async {
      final history = ReadingHistory();
      await history.record(1, 1);
      final outcome = await SearchEngine(history: history).search('verset');

      final indices = [for (final g in outcome.groups) g.category.index];
      expect(indices, orderedEquals([...indices]..sort()));
    });
  });

  group('LexiconIndex', () {
    test('collapses note anchors by word and counts occurrences', () async {
      final entries = await LexiconIndex.instance.search('verset');

      expect(entries, isNotEmpty);
      expect(entries.first.word, 'Verset');
      // One note per chapter, 2 chapters × 66 books in the fake bundle.
      expect(entries.first.occurrences, 132);
      expect(LexiconIndex.instance.size, 1);
    });

    test('short queries return nothing', () async {
      expect(await LexiconIndex.instance.search('v'), isEmpty);
    });
  });
}
