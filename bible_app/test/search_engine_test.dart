import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_store.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/reading_history.dart';
import 'package:bible_app/data/search_engine.dart';
import 'package:bible_app/data/strong_lexicon.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// An in-memory [DictionaryStore]: the engine only calls [installed] and
/// [load], so the disk never has to be involved.
class FakeDictionaryStore extends DictionaryStore {
  FakeDictionaryStore(Map<String, Map<String, dynamic>> data) : _data = data;

  final Map<String, Map<String, dynamic>> _data;

  @override
  Future<Set<String>> installed() async => _data.keys.toSet();

  @override
  Future<Map<String, dynamic>?> load(String code) async => _data[code];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SearchEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    FulltextIndex.instance.clearIndex();
    LexiconIndex.instance.clearIndex();
    // No AppDatabase: it needs path_provider. The engine must degrade to the
    // sources it can reach, which is what a fresh install does too.
    engine = SearchEngine(history: ReadingHistory());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
  });

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
    test('Liens and Nave are declared unavailable', () {
      expect(SearchCategory.liens.available, isFalse);
      expect(SearchCategory.nave.available, isFalse);
      expect(SearchCategory.strong.available, isTrue);
      expect(SearchCategory.liens.unavailableReason, isNotEmpty);
      expect(SearchCategory.nave.unavailableReason, isNotEmpty);
    });

    test('searchable holds the five wired sources', () {
      expect(SearchCategory.searchable, {
        SearchCategory.passages,
        SearchCategory.notes,
        SearchCategory.etudes,
        SearchCategory.strong,
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
      // La BYM sert ce verset : l'étiquette porte son nom de livre, pas le
      // français de la maquette.
      expect(outcome.reference!.label, 'Yohanan 1:2');
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

    test('a reference range resolves to its first verse and keeps the span',
        () async {
      // The fake books stop at chapter 2 by default — widen for Exode 4.
      LocalRepository.useBundle(FakeBibleBundle(chapters: 4, verses: 12));
      final outcome =
          await SearchEngine(history: ReadingHistory()).search('Exode 4:5-10');

      expect(outcome.reference, isNotNull);
      expect(outcome.reference!.bookIndex, 2);
      expect(outcome.reference!.chapter, 4);
      expect(outcome.reference!.verse, 5);
      expect(outcome.reference!.verseEnd, 10);
      expect(outcome.reference!.label, 'Shemot 4:5-10');
      expect(outcome.reference!.text, contains('Ex. 4:5'));
    });

    test('a bare dashed tail reads as chapters, not as a verse', () async {
      // « Matthieu 1-2 » : sans deux-points, le second nombre est un
      // chapitre — la carte ouvre le chapitre au lieu d'échouer.
      final outcome = await engine.search('Matthieu 1-2');
      expect(outcome.reference, isNotNull);
      expect(outcome.reference!.chapter, 1);
      expect(outcome.reference!.verse, isNull);
      expect(outcome.reference!.verseEnd, isNull);
      expect(outcome.reference!.label, 'Mattithyah 1');
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

    test('Strong category can match a definition word', () async {
      final outcome = await engine.search(
        'père',
        categories: {SearchCategory.strong},
      );
      final strong = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.strong);
      expect(strong.hits, isNotEmpty);
      expect(strong.hits.any((hit) => hit.title == 'H0001'), isTrue);
      expect(strong.hits.first.subtitle.toLowerCase(), contains('père'));
    });

    test('Strong hits carry the transliteration when the lexicon has one',
        () async {
      final outcome = await engine.search(
        'père',
        categories: {SearchCategory.strong},
      );
      final strong = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.strong);
      final h0001 = strong.hits.firstWhere((hit) => hit.title == 'H0001');
      expect(h0001.transliteration, "'ab");
    });

    test('an unavailable category is never queried', () async {
      final outcome = await engine.search(
        'verset',
        categories: {SearchCategory.nave},
      );
      expect(outcome.groups, isEmpty);
    });

    test('downloaded dictionaries are searched beside the Westphal', () async {
      final store = FakeDictionaryStore({
        'GBM': {
          'entries': {
            'ABBA': {
              'term': 'ABBA',
              'definition': 'Père, en hébreu.',
            },
          },
        },
      });
      final outcome = await SearchEngine(
        history: ReadingHistory(),
        dictionaries: store,
      ).search('abba', categories: {SearchCategory.dictionnaire});

      final group =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.dictionnaire);
      expect(group.hits, isNotEmpty);
      final gbm = group.hits.firstWhere((h) => h.dictionaryCode == 'GBM');
      expect(gbm.title, 'ABBA');
      expect(gbm.badge, dictionaryByCode('GBM')!.name);
      expect(gbm.subtitle, contains('hébreu'));
    });

    test('a crowded Westphal cannot push the glossary behind « Voir plus »',
        () async {
      // Le vrai Westphal répond à un mot courant par des dizaines
      // d'articles : à page plate, le dictionnaire téléchargé ne serait
      // jamais visible avant « Voir plus ».
      FreDawLexicon.useBundle(FakeFreDawBundle({
        for (var i = 0; i < 8; i++)
          'VERSET$i': {
            'term': 'Verset $i',
            'definition': 'Définition $i du Westphal.',
          },
      }));
      final store = FakeDictionaryStore({
        'GBM': {
          'entries': {
            'VERSET': {'term': 'Verset', 'definition': 'Portion de chapitre.'},
          },
        },
      });

      final outcome = await SearchEngine(
        history: ReadingHistory(),
        dictionaries: store,
      ).search('verset', categories: {SearchCategory.dictionnaire});

      final group = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.dictionnaire);

      // Le Westphal remplit la page tout seul…
      expect(group.total, greaterThan(SearchEngine.pageSize));
      expect(group.hits.length, SearchEngine.pageSize);
      // …et la première page contient pourtant une ligne du glossaire.
      expect(
        group.hits.any((h) => h.dictionaryCode == 'GBM'),
        isTrue,
        reason: 'le dictionnaire téléchargé doit rester sur l\'écran, pas derrière « Voir plus »',
      );
    });

    // Le lexique « Notes BYM Lexique » est débranché de la recherche : la
    // famille Dictionnaire ne répond plus qu'avec Westphal et les
    // dictionnaires téléchargés.
    test('the BYM lexicon no longer answers in the dictionary family',
        () async {
      final outcome = await SearchEngine(
        history: ReadingHistory(),
        dictionaries: FakeDictionaryStore({}),
      ).search('verset', categories: {SearchCategory.dictionnaire});

      final group = outcome.groups
          .firstWhere((g) => g.category == SearchCategory.dictionnaire);

      expect(group.hits.any((h) => h.badge == 'Notes BYM Lexique'), isFalse);

      // The Westphal row still answers on its own badge.
      final westphal =
          group.hits.firstWhere((h) => h.badge == 'Westphal 1932');
      expect(westphal.title, 'Verset');
    });

    test('a dictionary with no matching entry contributes nothing', () async {
      final store = FakeDictionaryStore({
        'GBM': {
          'entries': {'ABBA': {'term': 'ABBA', 'definition': 'Père.'}},
        },
      });
      final outcome = await SearchEngine(
        history: ReadingHistory(),
        dictionaries: store,
      ).search('verset', categories: {SearchCategory.dictionnaire});

      final group =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.dictionnaire);
      expect(group.hits.every((h) => h.dictionaryCode == null), isTrue,
          reason: 'only the embedded Westphal matched');
    });

    test('a dictionary absent from the catalogue is skipped', () async {
      final store = FakeDictionaryStore({
        'INCONNU': {
          'entries': {
            'Verset': {'term': 'Verset', 'definition': 'Une portion.'},
          },
        },
      });
      final outcome = await SearchEngine(
        history: ReadingHistory(),
        dictionaries: store,
      ).search('verset', categories: {SearchCategory.dictionnaire});

      final group =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.dictionnaire);
      expect(group.hits.every((h) => h.dictionaryCode == null), isTrue,
          reason: 'an unknown code has no name to badge the row with');
    });

    test('a removed dictionary is dropped from the next search', () async {
      final store = FakeDictionaryStore({
        'GBM': {
          'entries': {
            'Verset': {'term': 'Verset', 'definition': 'Père.'},
          },
        },
      });
      final engine = SearchEngine(history: ReadingHistory(), dictionaries: store);

      final first = await engine.search(
        'verset',
        categories: {SearchCategory.dictionnaire},
      );
      expect(
        first.groups
            .firstWhere((g) => g.category == SearchCategory.dictionnaire)
            .hits
            .any((h) => h.dictionaryCode == 'GBM'),
        isTrue,
      );

      // The registry changes: the dictionary is gone. The cached reader must
      // not survive — the next search must answer without it.
      final revisionBefore = DictionaryStore.revision.value;
      store._data.clear();
      DictionaryStore.revision.value = revisionBefore + 1;

      final second = await engine.search(
        'verset',
        categories: {SearchCategory.dictionnaire},
      );
      final group =
          second.groups.firstWhere((g) => g.category == SearchCategory.dictionnaire);
      expect(group.hits.every((h) => h.dictionaryCode == null), isTrue,
          reason: 'a deleted dictionary must not keep answering from the cache');
    });

    test('études come from the reading history', () async {
      final history = ReadingHistory();
      await history.record(43, 1);
      final outcome = await SearchEngine(history: history).search('Jean');

      final etudes =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.etudes);
      // L'historique n'a pas de version : il parle le registre de la feuille
      // Livres, tête BYM puis français.
      expect(etudes.hits.first.title, 'Yohanan (Jean) 1');
      expect(etudes.hits.first.bookIndex, 43);
      expect(etudes.hits.first.canOpen, isTrue);
    });

    test('études answer to the BYM name of their book as well', () async {
      final history = ReadingHistory();
      await history.record(43, 1);

      // Le lecteur cherche sous le nom BYM — l'historique doit répondre, et
      // avec le titre bilingue déjà vérifié plus haut.
      final outcome = await SearchEngine(history: history).search('Yohanan');
      final etudes =
          outcome.groups.firstWhere((g) => g.category == SearchCategory.etudes);
      expect(etudes.hits.first.bookIndex, 43);

      // Et sous le nom que le catalogue ne porte que dans `bymName`.
      final matthieu = ReadingHistory();
      await matthieu.record(40, 2);
      final bym = await SearchEngine(history: matthieu).search('Mattithyah');
      expect(
        bym.groups
            .firstWhere((g) => g.category == SearchCategory.etudes)
            .hits
            .first
            .title,
        'Mattithyah (Matthieu) 2',
      );
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
