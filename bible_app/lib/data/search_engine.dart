import 'app_database.dart';
import '../models/chapter.dart';
import 'bible_sections.dart';
import 'book_catalog.dart';
import 'dictionary_catalog.dart';
import 'dictionary_reader.dart';
import 'dictionary_store.dart';
import 'fulltext_index.dart';
import 'lexicon_index.dart' as lexicon;
import 'local_repository.dart';
import 'reading_history.dart';
import 'reference_parser.dart';
import 'fredaw_lexicon.dart';
import 'strong_lexicon.dart';
import 'version_repository.dart';

/// The families a unified search looks into — the chip row of the maquette
/// (`rech/`).
///
/// Two of them have no data source in the app yet ([liens] and [nave]): they
/// are still listed so the screen matches the design, but they are shown
/// disabled. See [available].
enum SearchCategory {
  passages,
  notes,
  liens,
  etudes,
  strong,
  dictionnaire,
  nave;

  String get label => switch (this) {
        SearchCategory.passages => 'Passages',
        SearchCategory.notes => 'Notes',
        SearchCategory.liens => 'Liens',
        SearchCategory.etudes => 'Études',
        SearchCategory.strong => 'Strong',
        SearchCategory.dictionnaire => 'Dictionnaire',
        SearchCategory.nave => 'Nave',
      };

  /// False while the app ships no data for this family. Such a category is
  /// never searched and its chip cannot be selected.
  ///
  /// - [liens] : cross-references are not part of the BYM export yet.
  /// - [nave] : the topical index is not bundled.
  bool get available => switch (this) {
        SearchCategory.liens || SearchCategory.nave => false,
        _ => true,
      };

  /// One-line reason shown when a disabled chip is tapped.
  String get unavailableReason => switch (this) {
        SearchCategory.liens => 'Références croisées — bientôt disponible.',
        SearchCategory.nave => 'Index thématique Nave — bientôt disponible.',
        _ => '',
      };

  /// Every category the app can actually query.
  static Set<SearchCategory> get searchable =>
      {for (final c in SearchCategory.values) if (c.available) c};
}

/// How results are ordered inside a group — the « Ordre » menu.
enum SearchOrder {
  biblical,
  relevance;

  String get label => switch (this) {
        SearchOrder.biblical => 'Ordre biblique',
        SearchOrder.relevance => 'Pertinence',
      };
}

/// The state of the four menus under the search field: « Version », « Section »,
/// « Livre » and « Ordre ».
class SearchFilters {
  /// [VersionEntry.code] of the version searched. Only the embedded BYM text
  /// is indexed offline today, so this is 'BYM' unless a download lands.
  final String versionCode;

  /// Index into [bibleSections], or null for « Tout ».
  final int? sectionIndex;

  /// BYM book index (1..66), or null for « Tout ». Wins over [sectionIndex].
  final int? bookIndex;

  final SearchOrder order;

  const SearchFilters({
    this.versionCode = VersionRepository.embeddedCode,
    this.sectionIndex,
    this.bookIndex,
    this.order = SearchOrder.biblical,
  });

  /// Passing null to a field clears it — use [clearSection] / [clearBook] to
  /// go back to « Tout » explicitly.
  SearchFilters copyWith({
    String? versionCode,
    int? sectionIndex,
    int? bookIndex,
    SearchOrder? order,
    bool clearSection = false,
    bool clearBook = false,
  }) =>
      SearchFilters(
        versionCode: versionCode ?? this.versionCode,
        sectionIndex: clearSection ? null : (sectionIndex ?? this.sectionIndex),
        bookIndex: clearBook ? null : (bookIndex ?? this.bookIndex),
        order: order ?? this.order,
      );

  /// Whether [book] (1..66) passes the « Section » / « Livre » restriction.
  bool allows(int book) {
    if (bookIndex != null) return book == bookIndex;
    final section = sectionIndex;
    if (section == null) return true;
    return bibleSections[section].contains(book);
  }

  String get sectionLabel =>
      sectionIndex == null ? 'Tout' : bibleSections[sectionIndex!].name;

  String get bookLabel =>
      bookIndex == null ? 'Tout' : catalogEntry(bookIndex!).shortName;

  /// True when the search is narrowed to less than the whole bible.
  bool get isNarrowed => sectionIndex != null || bookIndex != null;
}

/// One row of the results list.
class SearchHit {
  final SearchCategory category;

  /// Bold first line ("Ge. 1:1", "Yod").
  final String title;

  /// Second line — the verse text, the note body, the definition.
  final String subtitle;

  /// The original word/lemma for Strong hits.
  final String? lemma;

  /// The transliterated form for Strong hits ("'ab" for H0001).
  final String? transliteration;

  /// Small pill next to the title (the version code, "Dictionnaire"…).
  final String? badge;

  /// The [DictionaryEntry.code] when this row comes from a downloaded
  /// dictionary (BAILLY, GBM…). Null on a Westphal row, which the app opens
  /// through [FreDawLexicon] instead of the generic [DictionaryReader].
  final String? dictionaryCode;

  /// The full BYM lexicon entry when this row comes from the embedded lexicon
  /// built over the BYM notes. Null on Westphal and downloaded rows: only the
  /// BYM fiche needs the occurrences count, which the scalars above don't
  /// carry.
  final lexicon.DictionaryEntry? bymLexiconEntry;

  /// Where tapping the row leads. Null on a row that cannot be opened.
  final int? bookIndex;
  final int? chapter;
  final int? verse;

  /// Epoch milliseconds, when the row carries a date (notes, études).
  final int? at;

  const SearchHit({
    required this.category,
    required this.title,
    required this.subtitle,
    this.lemma,
    this.transliteration,
    this.badge,
    this.dictionaryCode,
    this.bymLexiconEntry,
    this.bookIndex,
    this.chapter,
    this.verse,
    this.at,
  });

  bool get canOpen => category == SearchCategory.dictionnaire ||
      (bookIndex != null && chapter != null);
}
/// The rows found for one category, plus the total before capping.
class SearchGroup {
  final SearchCategory category;

  /// Rows to display, already capped at the requested page size.
  final List<SearchHit> hits;

  /// How many rows matched in total — the number shown in the header badge.
  final int total;

  const SearchGroup({
    required this.category,
    required this.hits,
    required this.total,
  });

  bool get isEmpty => hits.isEmpty;

  /// True when [total] exceeds what [hits] shows — the « Voir plus » chip.
  bool get truncated => total > hits.length;
}

/// A query that reads as a scripture reference ("Jean 3:16", "Psaume 23").
/// Rendered on its own, above the category groups, as in `rech/`.
class ReferenceHit {
  final int bookIndex;
  final int chapter;

  /// Null when the query only named a book and a chapter.
  final int? verse;

  /// End of the verse range when the query read as one (« Exode 4:5-10 »):
  /// the card prints the range and shows the first verse's text.
  final int? verseEnd;

  /// The verse text, or the chapter's opening verse when [verse] is null.
  final String text;

  /// Version code shown as a pill next to the reference.
  final String versionCode;

  const ReferenceHit({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    this.verseEnd,
    required this.text,
    required this.versionCode,
  });

  /// "Jean 3:16" — the full book name, as the maquette prints it.
  String get label {
    final name = catalogEntry(bookIndex).shortName;
    if (verse == null) return '$name $chapter';
    if (verseEnd != null) return '$name $chapter:$verse-$verseEnd';
    return '$name $chapter:$verse';
  }
}

/// Everything a single query produced.
class SearchOutcome {
  /// The query resolved as a reference, when it did.
  final ReferenceHit? reference;

  /// Non-empty groups only, in [SearchCategory] declaration order.
  final List<SearchGroup> groups;

  /// The query these results answer — guards against a stale async result
  /// overwriting a newer one.
  final String query;

  /// Why a downloaded version may be answering short: « DBY — 12/66 livres
  /// téléchargés ». Null for the BYM and for a complete download. Without it a
  /// partial version reads as « ce mot n'est pas dans la Bible » when it only
  /// means « pas dans les livres présents sur l'appareil ».
  final String? coverageNote;

  const SearchOutcome({
    required this.query,
    this.reference,
    this.groups = const [],
    this.coverageNote,
  });

  bool get isEmpty => reference == null && groups.isEmpty;

  /// Total rows across every group (the reference excluded).
  int get count => groups.fold(0, (sum, g) => sum + g.total);
}
/// Runs one query against every enabled source and merges the results.
///
/// Sources, one per available [SearchCategory]:
/// - [SearchCategory.passages] → [FulltextIndex] over the 66 embedded books;
/// - [SearchCategory.notes] → the `notes` table of [AppDatabase];
/// - [SearchCategory.etudes] → [ReadingHistory] (the chapters already studied);
/// - [SearchCategory.strong] → [StrongLexicon] (the French Strong definitions);
/// - [SearchCategory.dictionnaire] → [FreDawLexicon] (Westphal 1932, embedded)
///   plus every downloaded dictionary on the device ([DictionaryStore]).
///
/// Each source is queried concurrently and failures are swallowed per source,
/// so a missing database (widget tests, first launch) still lets the passages
/// and dictionary results through.
class SearchEngine {
  SearchEngine({
    FulltextIndex? fulltext,
    FreDawLexicon? freDaw,
    StrongLexicon? strong,
    AppDatabase? database,
    bool ambientDatabase = true,
    DictionaryStore? dictionaries,
    ReadingHistory? history,
    LocalRepository? repository,
    VersionRepository? versions,
  })  : _freDawLexicon = freDaw ?? FreDawLexicon.instance,
        _strongLexicon = strong ?? StrongLexicon.instance,
        // ignore: prefer_initializing_formals (named params cannot be private)
        _fulltext = fulltext,
        // ignore: prefer_initializing_formals (named params cannot be private)
        _database = database,
        // ignore: prefer_initializing_formals (named params cannot be private)
        _ambientDatabase = ambientDatabase,
        _dictionaries = dictionaries ?? DictionaryStore(),
        _history = history ?? ReadingHistory(),
        _repository = repository ?? LocalRepository(),
        _versions = versions ?? VersionRepository();

  /// An index to use in place of the registry, for the version it covers.
  final FulltextIndex? _fulltext;
  final StrongLexicon _strongLexicon;
  final AppDatabase? _database;
  final bool _ambientDatabase;
  final ReadingHistory _history;
  final LocalRepository _repository;
  final VersionRepository _versions;

  /// Downloaded dictionaries to search beside Westphal — a real store in
  /// production, an injected one in tests (path_provider never answers inside
  /// the fake-async zone of `testWidgets`, so a real store would hang `load`).
  final DictionaryStore _dictionaries;

  final FreDawLexicon _freDawLexicon;

  /// Parsed readers of the downloaded dictionaries, keyed by code. See
  /// [_downloadedEntries] for why they are cached.
  final Map<String, DictionaryReader> _readerCache = {};

  /// The [DictionaryStore.revision] the cache was built against.
  int _dictionaryRevision = DictionaryStore.revision.value;

  /// The index covering [code] — the injected one when it matches, else the
  /// shared per-version registry.
  FulltextIndex _indexFor(String code) {
    final injected = _fulltext;
    if (injected != null && injected.code == code) return injected;
    return FulltextIndex.of(code);
  }

  /// Rows kept per group before the « Voir plus » chip appears.
  static const int pageSize = 5;

  /// Hard cap per source, so a two-letter query cannot build a huge list.
  static const int sourceLimit = 60;

  /// Shortest query that triggers a search.
  static const int minQueryLength = 2;

  /// The database to query notes from, or null when there is none to reach.
  ///
  /// `AppDatabase.instance` opens through path_provider, whose platform channel
  /// never answers inside the fake-async zone of `testWidgets`: the future
  /// would hang rather than throw, so widget tests pass `ambientDatabase:
  /// false` to skip the source outright.
  AppDatabase? get _db {
    if (_database != null) return _database;
    if (!_ambientDatabase) return null;
    try {
      return AppDatabase.instance;
    } catch (_) {
      return null;
    }
  }

  /// Searches [query] across [categories] (defaults to every available one).
  ///
  /// [expanded] lists the categories the user unfolded with « Voir plus »;
  /// those return up to [sourceLimit] rows instead of [pageSize].
  Future<SearchOutcome> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    Set<SearchCategory>? categories,
    Set<SearchCategory> expanded = const {},
  }) async {
    final trimmed = query.trim();
    if (normalizeForSearch(trimmed).length < minQueryLength) {
      return SearchOutcome(query: trimmed);
    }

    final wanted = (categories ?? SearchCategory.searchable)
        .where((c) => c.available)
        .toSet();

    final results = await Future.wait([
      _resolveReference(trimmed, filters),
      if (wanted.contains(SearchCategory.passages))
        _passages(trimmed, filters, expanded.contains(SearchCategory.passages))
      else
        Future.value(null),
      if (wanted.contains(SearchCategory.notes))
        _notes(trimmed, filters, expanded.contains(SearchCategory.notes))
      else
        Future.value(null),
      if (wanted.contains(SearchCategory.etudes))
        _etudes(trimmed, filters, expanded.contains(SearchCategory.etudes))
      else
        Future.value(null),
      if (wanted.contains(SearchCategory.dictionnaire))
        _dictionnaire(
            trimmed, expanded.contains(SearchCategory.dictionnaire))
      else
        Future.value(null),
      if (wanted.contains(SearchCategory.strong))
        _strong(trimmed, expanded.contains(SearchCategory.strong))
      else
        Future.value(null),
    ]);

    final groups = <SearchGroup>[
      for (final r in results.skip(1))
        if (r is SearchGroup && !r.isEmpty) r,
    ]..sort((a, b) => a.category.index - b.category.index);

    return SearchOutcome(
      query: trimmed,
      reference: results.first as ReferenceHit?,
      groups: groups,
      coverageNote: _coverageNote(filters.versionCode),
    );
  }

  /// « DBY — 27/66 livres téléchargés », or null when the version covers the
  /// whole Bible. Read after the search so the index is built; an unbuilt index
  /// (passages not among the searched categories) reports nothing rather than
  /// a misleading 0/66.
  String? _coverageNote(String code) {
    if (code == VersionRepository.embeddedCode) return null;
    final index = _indexFor(code);
    if (!index.isBuilt) return null;
    final books = index.indexedBooks;
    if (books >= bookCatalog.length) return null;
    return '$code — $books/${bookCatalog.length} livres téléchargés, '
        'la recherche ne couvre qu\'eux.';
  }

  // ---- Sources ----

  /// "Jean 3:16", "Psaume 23", "1 S 3.4" → the verse itself, above the groups.
  ///
  /// A bare book name ("psaumes") does not qualify: it would push a reference
  /// card in front of every word search that happens to look like a book.
  Future<ReferenceHit?> _resolveReference(
    String query,
    SearchFilters filters,
  ) async {
    final parsed = parseReference(query);
    if (parsed == null || parsed.chapter == null) return null;
    if (!filters.allows(parsed.bookIndex)) return null;

    try {
      // Read in the version being searched. A book absent from a partial
      // download falls back to the BYM — but the card then carries the **BYM**
      // badge, so the reader sees which text they are being shown. Refusing
      // outright would hide a verse we can perfectly well serve.
      var used = filters.versionCode;
      Chapter chapter;
      try {
        chapter = await _versions.loadChapter(
            used, parsed.bookIndex, parsed.chapter!);
      } on BookNotDownloaded {
        used = VersionRepository.embeddedCode;
        chapter =
            await _repository.loadChapter(parsed.bookIndex, parsed.chapter!);
      }
      if (chapter.verses.isEmpty) return null;

      final target = parsed.verse;
      final verse = target == null
          ? chapter.verses.first
          : chapter.verses.where((v) => v.number == target).firstOrNull;
      if (verse == null) return null;

      return ReferenceHit(
        bookIndex: parsed.bookIndex,
        chapter: parsed.chapter!,
        verse: target,
        verseEnd: parsed.verseEnd,
        text: verse.text,
        versionCode: used,
      );
    } catch (_) {
      return null;
    }
  }

  Future<SearchGroup?> _passages(
    String query,
    SearchFilters filters,
    bool expanded,
  ) async {
    try {
      final found = await _indexFor(filters.versionCode).search(
        query,
        limit: sourceLimit,
        bookFilter: filters.allows,
        biblicalOrder: filters.order == SearchOrder.biblical,
      );
      if (found.isEmpty) return null;
      final shown = expanded ? found.matches : found.matches.take(pageSize);
      return SearchGroup(
        category: SearchCategory.passages,
        total: found.total,
        hits: [
          for (final m in shown)
            SearchHit(
              category: SearchCategory.passages,
              title: '${catalogEntry(m.bookIndex).shortName} '
                  '${m.chapter}:${m.verseNumber}',
              subtitle: m.text,
              badge: filters.versionCode,
              bookIndex: m.bookIndex,
              chapter: m.chapter,
              verse: m.verseNumber,
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  Future<SearchGroup?> _notes(
    String query,
    SearchFilters filters,
    bool expanded,
  ) async {
    final db = _db;
    if (db == null) return null;
    try {
      final notes = await db.searchNotes(query, limit: sourceLimit);
      final kept = notes.where((n) => filters.allows(n.bookIndex)).toList();
      if (kept.isEmpty) return null;
      if (filters.order == SearchOrder.biblical) {
        kept.sort((a, b) => a.bookIndex != b.bookIndex
            ? a.bookIndex - b.bookIndex
            : a.chapter != b.chapter
                ? a.chapter - b.chapter
                : a.verse - b.verse);
      }
      final shown = expanded ? kept : kept.take(pageSize);
      return SearchGroup(
        category: SearchCategory.notes,
        total: kept.length,
        hits: [
          for (final n in shown)
            SearchHit(
              category: SearchCategory.notes,
              title: '${catalogEntry(n.bookIndex).shortName} '
                  '${n.chapter}:${n.verse}',
              subtitle: n.text,
              badge: 'Ma note',
              bookIndex: n.bookIndex,
              chapter: n.chapter,
              verse: n.verse,
              at: n.updatedAt,
            ),
        ],
      );
    } catch (_) {
      // No database yet (fresh install, widget tests) — skip the category.
      return null;
    }
  }

  /// Chapters already opened whose book name matches the query — the closest
  /// thing to the maquette's « Études » until authored studies exist.
  Future<SearchGroup?> _etudes(
    String query,
    SearchFilters filters,
    bool expanded,
  ) async {
    try {
      final entries = await _history.load();
      final q = normalizeForSearch(query);
      final kept = [
        for (final e in entries)
          if (filters.allows(e.bookIndex) &&
              (normalizeForSearch(e.bookName).contains(q) ||
                  normalizeForSearch(e.label).contains(q)))
            e,
      ];
      if (kept.isEmpty) return null;
      if (filters.order == SearchOrder.biblical) {
        kept.sort((a, b) => a.bookIndex != b.bookIndex
            ? a.bookIndex - b.bookIndex
            : a.chapter - b.chapter);
      }
      final shown = expanded ? kept : kept.take(pageSize);
      return SearchGroup(
        category: SearchCategory.etudes,
        total: kept.length,
        hits: [
          for (final e in shown)
            SearchHit(
              category: SearchCategory.etudes,
              title: '${e.bookName} ${e.chapter}',
              subtitle: 'Chapitre déjà étudié',
              badge: 'Étude',
              bookIndex: e.bookIndex,
              chapter: e.chapter,
              at: e.at,
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }

  /// Westphal 1932 (embedded) plus every downloaded dictionary on the device —
  /// the Dictionnaire family of the maquette. Each source contributes its own
  /// badge, so a "père" query shows Westphal and Bailly side by side.
  Future<SearchGroup?> _dictionnaire(String query, bool expanded) async {
    try {
      final hits = <SearchHit>[];

      final freDawEntries =
          await _freDawLexicon.search(query, limit: sourceLimit);
      hits.addAll([
        for (final e in freDawEntries)
          SearchHit(
            category: SearchCategory.dictionnaire,
            title: e.term,
            subtitle: e.definition,
            badge: 'Westphal 1932',
          ),
      ]);

      // The embedded BYM lexicon, built over the anchored notes of the 66
      // books. Its own badge distinguishes it from Westphal and the
      // downloaded dictionaries in the same family.
      final bymLexiconEntries =
          await lexicon.LexiconIndex.instance.search(query, limit: sourceLimit);
      hits.addAll([
        for (final e in bymLexiconEntries)
          SearchHit(
            category: SearchCategory.dictionnaire,
            title: e.word,
            subtitle: e.definition,
            badge: 'Notes BYM Lexique',
            bymLexiconEntry: e,
          ),
      ]);

      final downloaded = await _downloadedEntries(query);
      hits.addAll(downloaded);

      if (hits.isEmpty) return null;

      final shown = expanded ? hits : hits.take(pageSize);
      return SearchGroup(
        category: SearchCategory.dictionnaire,
        total: hits.length,
        hits: shown.toList(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Every downloaded dictionary on the device, searched. Each row carries its
  /// [SearchHit.dictionaryCode] so the screen can open the right fiche.
  ///
  /// Parsed readers are cached per code: a downloaded dictionary is one file
  /// of thousands of entries (Bailly: 50 493), and a search is debounced but
  /// re-fired on every keystroke. The cache drops when the registry changes
  /// ([DictionaryStore.revision]), so a freshly downloaded or deleted
  /// dictionary is picked up on the next search without a stale reader.
  Future<List<SearchHit>> _downloadedEntries(String query) async {
    final store = _dictionaries;
    Set<String> installed;
    try {
      installed = await store.installed();
    } catch (_) {
      return const []; // no registry → nothing downloaded to search
    }

    final revision = DictionaryStore.revision.value;
    if (revision != _dictionaryRevision) {
      _dictionaryRevision = revision;
      _readerCache.clear();
    }

    final hits = <SearchHit>[];
    for (final code in installed) {
      final entry = dictionaryByCode(code);
      if (entry == null) continue;
      try {
        var reader = _readerCache[code];
        if (reader == null) {
          reader = await _loadReader(store, code);
          if (reader != null) _readerCache[code] = reader;
        }
        if (reader == null || reader.size == 0) continue;
        hits.addAll([
          for (final article in reader.search(query, limit: sourceLimit))
            SearchHit(
              category: SearchCategory.dictionnaire,
              title: article.term,
              subtitle: article.definition,
              badge: entry.name,
              dictionaryCode: code,
            ),
        ]);
      } catch (_) {
        continue; // a corrupted file skips its dictionary, not the search
      }
    }
    return hits;
  }

  /// Reads one dictionary file into a reader, or null when it is absent or
  /// unreadable — the file can vanish between [installed] and [load] (deleted
  /// from the Bibliothèque mid-search).
  Future<DictionaryReader?> _loadReader(
    DictionaryStore store,
    String code,
  ) async {
    final payload = await store.load(code);
    if (payload == null) return null;
    return DictionaryReader.fromJson(payload);
  }

  /// The French Strong dictionary: a code query ("H0430") answers the
  /// definition itself; a word query finds every definition that mentions it.
  ///
  /// Strong rows carry no book/chapter — the definition is the destination, so
  /// the search screen shows them as a dictionary rather than a passage.
  Future<SearchGroup?> _strong(String query, bool expanded) async {
    try {
      final entries = await _strongLexicon.search(query, limit: sourceLimit);
      if (entries.isEmpty) return null;
      final shown = expanded ? entries : entries.take(pageSize);
      return SearchGroup(
        category: SearchCategory.strong,
        total: entries.length,
        hits: [
          for (final e in shown)
            SearchHit(
              category: SearchCategory.strong,
              title: e.strong,
              subtitle: e.definition,
              lemma: e.lemma,
              transliteration: e.transliteration,
              badge: 'Strong',
            ),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}


