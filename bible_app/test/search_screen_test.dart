import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/fulltext_index.dart';
import 'package:bible_app/data/lexicon_index.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/search_engine.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/screens/search_screen.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FulltextIndex.instance.clearIndex();
    LexiconIndex.instance.clearIndex();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
  });

  /// The screen under test, wired to an engine that never reaches sqflite:
  /// path_provider's channel never answers inside the fake-async zone, so an
  /// ambient [AppDatabase] would hang the search instead of failing fast.
  Widget app({void Function(int, int, {int? verse})? onOpen}) => MaterialApp(
        home: SearchScreen(
          onOpenReading: onOpen ?? (_, _, {verse}) {},
          engine: SearchEngine(ambientDatabase: false),
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

  testWidgets('« Voir plus » unfolds a truncated group', (tester) async {
    await tester.pumpWidget(app());
    // The fake bundle yields 2 chapters × 3 verses × 66 books, far beyond the
    // 5 rows a group shows by default.
    await type(tester, 'verset');

    expect(find.text('Voir plus'), findsWidgets);
    expect(find.text('Genèse 1:1'), findsOneWidget);
    expect(find.text('Exode 1:1'), findsNothing);

    // The chip sits at the end of the passages group, below the fold.
    await tester.scrollUntilVisible(find.text('Voir plus').first, 120,
        scrollable: resultList());
    await tester.pumpAndSettle();
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
}
