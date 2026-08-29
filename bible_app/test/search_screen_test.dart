import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_store.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/search_engine.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/strong_occurrences.dart';
import 'package:bible_app/screens/search_screen.dart';
import 'package:bible_app/screens/bym_lexicon_entry_screen.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// An in-memory [DictionaryStore] for the search screen: opening a downloaded
/// dictionary hit reads the file back through [load], which must not touch the
/// disk (path_provider never answers inside the fake-async zone).
class FakeDictionaryStore extends DictionaryStore {
  FakeDictionaryStore(Map<String, Map<String, dynamic>> data) : _data = data;

  final Map<String, Map<String, dynamic>> _data;

  @override
  Future<Set<String>> installed() async => _data.keys.toSet();

  @override
  Future<Map<String, dynamic>?> load(String code) async => _data[code];
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    FulltextIndex.instance.clearIndex();
    LexiconIndex.instance.clearIndex();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
  });

  /// The screen under test, wired to an engine that never reaches sqflite:
  /// path_provider's channel never answers inside the fake-async zone, so an
  /// ambient [AppDatabase] would hang the search instead of failing fast.
  Widget app({
    void Function(int, int, {int? verse})? onOpen,
    DictionaryStore? dictionaryStore,
  }) =>
      MaterialApp(
        home: SearchScreen(
          onOpenReading: onOpen ?? (_, _, {verse}) {},
          engine: SearchEngine(
            ambientDatabase: false,
            dictionaries: dictionaryStore,
          ),
          dictionaryStore: dictionaryStore,
        ),
      );

  /// Types [query] and lets the 300 ms debounce and the search complete.
  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  // Finders cache their result, so these are rebuilt per call: a finder shared
  // across tests would hand back elements from the previous widget tree.

  /// The chip row scrolls horizontally and builds lazily, so the last chips
  /// ("Dictionnaire", "Nave") do not exist until they are scrolled into view.
  Finder chipRow() => find.descendant(
        of: find.byKey(categoryRowKey),
        matching: find.byType(Scrollable),
      );

  /// The results list, whose rows also build lazily.
  Finder resultList() => find.descendant(
        of: find.byKey(resultListKey),
        matching: find.byType(Scrollable),
      );

  /// A chip label, scoped to the chip row: "Dictionnaire" is also a group
  /// header once results are in, and an ambiguous finder cannot be tapped.
  Finder chipLabel(String label) =>
      find.descendant(of: chipRow(), matching: find.text(label));

  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(chipLabel(label), 80,
        scrollable: chipRow());
    // scrollUntilVisible ends on ensureVisible, whose scroll only lands once a
    // frame is pumped — without this the tap aims at the pre-scroll offset.
    await tester.pumpAndSettle();
    await tester.tap(chipLabel(label));
  }

  testWidgets('the empty state offers the suggestion groups', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Rechercher'), findsOneWidget);
    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
    expect(find.text('Chercher une référence'), findsOneWidget);
    expect(find.text('Jean 3:16'), findsOneWidget);
  });

  testWidgets('the seven categories of the maquette are listed',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    for (final category in SearchCategory.values) {
      await tester.scrollUntilVisible(chipLabel(category.label), 80,
          scrollable: chipRow());
      expect(chipLabel(category.label), findsOneWidget,
          reason: 'missing chip ${category.label}');
    }
  });

  testWidgets('the four filter menus are shown with their defaults',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Version'), findsOneWidget);
    expect(find.text('BYM'), findsOneWidget);
    expect(find.text('Section'), findsOneWidget);
    expect(find.text('Livre'), findsOneWidget);
    expect(find.text('Ordre'), findsOneWidget);
    expect(find.text('Ordre biblique'), findsOneWidget);
    // Section and Livre both read « Tout ».
    expect(find.text('Tout'), findsNWidgets(2));
  });

  testWidgets('typing shows grouped passage results after the debounce',
      (tester) async {
    await tester.pumpWidget(app());

    await tester.enterText(find.byType(TextField), 'verset');
    // Before the debounce elapses nothing is grouped yet.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ge. 1:1'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Passages'), findsWidgets);
    expect(find.text('Genèse 1:1'), findsOneWidget);
    expect(find.textContaining('Verset de test'), findsWidgets);
  });

  testWidgets('tapping a result opens its chapter and verse', (tester) async {
    final opened = <({int book, int chapter, int? verse})>[];
    await tester.pumpWidget(app(
      onOpen: (book, chapter, {verse}) =>
          opened.add((book: book, chapter: chapter, verse: verse)),
    ));

    await type(tester, 'verset');
    await tester.tap(find.text('Genèse 1:1'));
    await tester.pumpAndSettle();

    expect(opened, isNotEmpty);
    expect(opened.first.book, 1);
    expect(opened.first.chapter, 1);
    expect(opened.first.verse, 1);
  });

  testWidgets('a reference query gets its own « Référence biblique » section',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'Jean 1:2');

    expect(find.text('Référence biblique'), findsOneWidget);
    expect(find.text('Jean 1:2'), findsWidgets);
  });

  testWidgets('a request handed in before construction runs on its own',
      (tester) async {
    // Le shell écrit la requête puis crée la page : l'écran doit la consommer
    // au premier build, sans aucune frappe, puis remettre le notificateur à
    // null (une relance identique devra re-tirer).
    final request = ValueNotifier<String?>('Jean 1:2');
    addTearDown(request.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        onOpenReading: (_, _, {verse}) {},
        engine: SearchEngine(ambientDatabase: false),
        request: request,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Référence biblique'), findsOneWidget);
    expect(find.text('Jean 1:2'), findsWidgets);
    expect(request.value, isNull, reason: 'la requête a été consommée');
  });

  testWidgets('an external request reaches an already-mounted screen',
      (tester) async {
    final request = ValueNotifier<String?>(null);
    addTearDown(request.dispose);
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        onOpenReading: (_, _, {verse}) {},
        engine: SearchEngine(ambientDatabase: false),
        request: request,
      ),
    ));
    await tester.pumpAndSettle();

    request.value = 'Jean 1:2';
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Référence biblique'), findsOneWidget);
    expect(request.value, isNull);
  });

  testWidgets('an unavailable category explains itself instead of filtering',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');

    await tapChip(tester, 'Nave');
    await tester.pump();

    expect(find.textContaining('Index thématique Nave'), findsOneWidget);
    // Passages are still listed: the disabled chip did not filter anything.
    expect(find.text('Genèse 1:1'), findsOneWidget);
  });

  testWidgets('the Strong category lists the French definitions',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'H0430');

    await tapChip(tester, 'Strong');
    await tester.pumpAndSettle();

    expect(find.text('Strong'), findsWidgets);
    expect(find.text('H0430'), findsWidgets);
    expect(find.textContaining('Définition test de H0430'), findsWidgets);
  });

  testWidgets('Strong hits show a transliteration label when available',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'H0001');

    await tapChip(tester, 'Strong');
    await tester.pumpAndSettle();

    expect(find.text('translitéré'), findsOneWidget);
    expect(find.text("'ab"), findsOneWidget);
  });

  testWidgets('a long transliteration never overflows the result card',
      (tester) async {
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'H0001': {
        'strong': 'H0001',
        'language': 'hebrew',
        'lemma': 'ab',
        'transliteration':
            '’attah ou (raccourci) ’atta ou ’ath féminin (irrégulier) '
            'quelquefois ’attiy masculin pluriel ’attem féminin ’atten ou ’a',
        'definition': 'Définition test de H0001.',
      },
    }));

    await tester.pumpWidget(app());
    await type(tester, 'H0001');

    await tapChip(tester, 'Strong');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a long transliteration must not overflow the result card');
    expect(find.text('translitéré'), findsOneWidget);
    expect(find.textContaining('quelquefois'), findsOneWidget,
        reason: 'the transliteration is still rendered, ellipsized if needed');
  });

  testWidgets('tapping a Strong hit opens the fiche with its occurrences',
      (tester) async {
    // The fiche reads the LSGS corpus for its occurrences section.
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongOccurrenceIndex.useAmbientRepository();
    addTearDown(LsgsRepository.useRootBundle);
    addTearDown(StrongOccurrenceIndex.useAmbientRepository);

    await tester.pumpWidget(app());
    await type(tester, 'H7225');

    await tapChip(tester, 'Strong');
    await tester.pumpAndSettle();

    await tester.tap(find.text('H7225').last);
    await tester.pumpAndSettle();

    // The fiche: header number, definition and the occurrence in Genèse.
    expect(find.text('Occurrences du mot (1)'), findsOneWidget);
    expect(find.text('Genèse 1:1'), findsOneWidget);
  });

  testWidgets('an occurrence verse clears the whole chain of fiches',
      (tester) async {
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongOccurrenceIndex.useAmbientRepository();
    addTearDown(LsgsRepository.useRootBundle);
    addTearDown(StrongOccurrenceIndex.useAmbientRepository);

    final opened = <(int, int, int)>[];
    await tester.pumpWidget(
        app(onOpen: (b, c, {verse}) => opened.add((b, c, verse!))));
    await type(tester, 'H0001');
    await tapChip(tester, 'Strong');
    await tester.pumpAndSettle();
    await tester.tap(find.text('H0001').last);
    await tester.pumpAndSettle();

    // The etymology of the fake H0001 links a code: pushing its fiche leaves
    // two StrongDetailScreen routes on the stack.
    const full = 'Une racine primitive, le même que H7225.';
    const code = 'H7225';
    await tester.scrollUntilVisible(find.text(full, findRichText: true), 120);
    await tester.pumpAndSettle();
    final paragraph = tester.renderObject<RenderParagraph>(
        find.text(full, findRichText: true));
    final boxes = paragraph.getBoxesForSelection(TextSelection(
      baseOffset: full.indexOf(code),
      extentOffset: full.indexOf(code) + code.length,
    ));
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
    await tester.pumpAndSettle();

    expect(find.text('Occurrences du mot (1)'), findsOneWidget,
        reason: 'the pushed H7225 fiche shows its occurrence');

    await tester.scrollUntilVisible(find.text('Genèse 1:1'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genèse 1:1'));
    await tester.pumpAndSettle();

    expect(opened, [(1, 1, 1)],
        reason: 'the verse is handed to the reading callback');
    expect(find.byType(StrongDetailScreen), findsNothing,
        reason: 'the whole chain of pushed fiches is dismissed before reading');
  });

  testWidgets('unavailable categories cannot narrow the results',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');
    expect(find.text('Genèse 1:1'), findsOneWidget);

    await tapChip(tester, 'Nave');
    await tester.pumpAndSettle();

    // The chip was ignored: the query was not rerun with a Nave-only filter.
    expect(find.text('Genèse 1:1'), findsOneWidget);
  });

  testWidgets('selecting a category narrows the results to it', (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');
    expect(find.text('Genèse 1:1'), findsOneWidget);

    // « Dictionnaire » alone: the fake bundle notes are anchored on "Verset",
    // so the word matches there too, but no passage row may remain.
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    expect(find.text('Genèse 1:1'), findsNothing);
    expect(find.text('Verset'), findsWidgets);
  });

  testWidgets('tapping a dictionary result opens its detail page',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    // The fake dictionary entries in the notes service contain 'Verset'.
    await tester.tap(find.text('Verset').first);
    await tester.pumpAndSettle();

    // The FreDAW fiche: term in the article header, Westphal stamp, and the
    // article section of the dictionary entry screen.
    expect(find.text('Verset'), findsWidgets);
    expect(find.text('Westphal 1932'), findsWidgets);
    expect(find.text('Dictionnaire encyclopédique de la Bible'),
        findsOneWidget);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('the dictionary fiche is pushed from the search results',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verset').first);
    await tester.pumpAndSettle();

    // The fiche opens without the « Ouvrir onglet » escape hatch: dictionary
    // entries are read as a fiche, not as a reading tab.
    expect(find.text('Ouvrir onglet'), findsNothing);
    expect(find.text('Westphal 1932'), findsWidgets);
  });

  testWidgets('tapping a downloaded dictionary result opens its fiche',
      (tester) async {
    final store = FakeDictionaryStore({
      'GBM': {
        'entries': {
          'RACHAT': {'term': 'RACHAT', 'definition': 'Action de racheter.'},
        },
      },
    });
    await tester.pumpWidget(app(dictionaryStore: store));

    await type(tester, 'rachat');
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    // The GBM row carries its dictionary badge.
    expect(find.text('RACHAT'), findsOneWidget);
    expect(find.text(dictionaryByCode('GBM')!.name), findsOneWidget);

    await tester.tap(find.text('RACHAT').first);
    await tester.pumpAndSettle();

    // The generic fiche: the dictionary name as badge and the article body.
    expect(find.text(dictionaryByCode('GBM')!.name), findsWidgets);
    expect(find.text('Action de racheter.'), findsOneWidget);
  });

  testWidgets('a Westphal result still opens the embedded FreDAW fiche',
      (tester) async {
    // No downloaded dictionary on the device: the Dictionnaire category answers
    // from the embedded Westphal alone, which must keep opening its own fiche.
    final store = FakeDictionaryStore({});
    await tester.pumpWidget(app(dictionaryStore: store));

    await type(tester, 'verset');
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verset').first);
    await tester.pumpAndSettle();

    expect(find.text('Westphal 1932'), findsWidgets);
  });

  testWidgets('tapping a BYM lexicon result opens its own fiche',
      (tester) async {
    final opened = <(int, int, int)>[];
    await tester.pumpWidget(app(
      onOpen: (book, chapter, {verse}) => opened.add((book, chapter, verse!)),
    ));
    await type(tester, 'verset');
    await tapChip(tester, 'Dictionnaire');
    await tester.pumpAndSettle();

    // The BYM row carries its own badge, distinct from Westphal's.
    expect(find.text('Notes BYM Lexique'), findsOneWidget);

    await tester.tap(find.text('Notes BYM Lexique'));
    await tester.pumpAndSettle();

    // The embedded BYM fiche: word, reference with occurrences, and the
    // « Ouvrir le verset » button wired to the reading tab.
    expect(find.byType(BymLexiconEntryScreen), findsOneWidget);
    expect(find.text('Verset'), findsWidgets);
    expect(find.textContaining('132 occurrences'), findsOneWidget);

    await tester.tap(find.text('Ouvrir le verset'));
    await tester.pumpAndSettle();
    expect(opened, [(1, 1, 1)]);
  });

  testWidgets('« Voir plus » unfolds a truncated group', (tester) async {
    await tester.pumpWidget(app());
    // The fake bundle yields 2 chapters × 3 verses × 66 books, far beyond the
    // 5 rows a group shows by default.
    await type(tester, 'verset');

    expect(find.text('Genèse 1:1'), findsOneWidget);
    expect(find.text('Exode 1:1'), findsNothing);

    // The chip sits at the end of the passages group, below the fold.
    await tester.scrollUntilVisible(find.text('Voir plus'), 120,
        scrollable: resultList());
    await tester.pumpAndSettle();
    expect(find.text('Voir plus'), findsWidgets);
    await tester.tap(find.text('Voir plus').first);
    await tester.pumpAndSettle();

    // Genèse fills 6 rows (2 chapters × 3 verses), so Exode starts below the
    // fold once the group is unfolded.
    await tester.scrollUntilVisible(find.text('Exode 1:1').first, 120,
        scrollable: resultList());
    await tester.pumpAndSettle();
    expect(find.text('Exode 1:1'), findsWidgets);
  });

  testWidgets('clearing the field returns to the empty state', (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'verset');
    expect(find.text('Que cherchez-vous ?'), findsNothing);

    await tester.tap(find.byTooltip('Effacer'));
    await tester.pumpAndSettle();

    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
  });

  testWidgets('tapping a suggestion runs that query', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jean 3:16'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // The fake books only have 2 chapters, so Jean 3:16 resolves to nothing —
    // what matters is that the query ran and left the empty state.
    expect(find.text('Que cherchez-vous ?'), findsNothing);
    expect(find.textContaining('Jean 3:16'), findsWidgets);
  });

  testWidgets('a query under the minimum asks for more letters, not silence',
      (tester) async {
    await tester.pumpWidget(app());
    await type(tester, 'a');

    expect(find.textContaining('Saisissez au moins'), findsOneWidget);
    expect(find.textContaining('Aucun résultat'), findsNothing);
  });

  testWidgets('clearing mid-search does not resurrect stale results',
      (tester) async {
    final gate = Completer<void>();
    late final GatedEngine engine;
    engine = GatedEngine(gate);

    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(
        onOpenReading: (_, _, {verse}) {},
        engine: engine,
        dictionaryStore: FakeDictionaryStore(const {}),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'verset');
    // Past the debounce: the search is now in flight, held by the gate.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Que cherchez-vous ?'), findsNothing);

    await tester.tap(find.byTooltip('Effacer'));
    await tester.pumpAndSettle();
    expect(find.text('Que cherchez-vous ?'), findsOneWidget);

    // The in-flight search lands NOW — it must stay ignored.
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Que cherchez-vous ?'), findsOneWidget);
    expect(find.textContaining('Ge. 1:1'), findsNothing);
  });
}

/// An engine whose answer only lands once [Completer] resolves — the slow
/// source racing the field being cleared.
class GatedEngine extends SearchEngine {
  GatedEngine(this._gate) : super(ambientDatabase: false);

  final Completer<void> _gate;

  @override
  Future<SearchOutcome> search(
    String query, {
    SearchFilters filters = const SearchFilters(),
    Set<SearchCategory>? categories,
    Set<SearchCategory> expanded = const {},
  }) =>
      _gate.future.then(
        (_) => SearchOutcome(
          query: query,
          groups: [
            SearchGroup(
              category: SearchCategory.passages,
              total: 1,
              hits: [
                const SearchHit(
                  category: SearchCategory.passages,
                  title: 'Ge. 1:1',
                  subtitle: 'Verset de test Ge. 1:1.',
                  bookIndex: 1,
                  chapter: 1,
                  verse: 1,
                ),
              ],
            ),
          ],
        ),
      );
}
