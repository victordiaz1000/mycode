import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/bible_sections.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/screens/historique_screen.dart';
import 'package:bible_app/screens/home_screen.dart';

/// Seeds the reading history as the reader would leave it in
/// shared_preferences (the « history.recent » JSON list, newest first).
void seedHistory(List<({int book, int chapter})> entries) {
  SharedPreferences.setMockInitialValues({
    'history.recent': jsonEncode([
      for (var i = 0; i < entries.length; i++)
        {
          'book': entries[i].book,
          'chapter': entries[i].chapter,
          'at': DateTime.now()
              .subtract(Duration(minutes: (i + 1) * 5))
              .millisecondsSinceEpoch,
        },
    ]),
  });
}

/// The « Tout voir » history screen (Accueil → Études récentes).
///
/// Shows every read chapter, filterable by section (chips) and by book name
/// (search, accent-insensitive). A tap reopens the chapter in the reader.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpHistorique(
    WidgetTester tester, {
    void Function(int, int)? onOpenReading,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: HistoriqueScreen(
        onOpenReading: onOpenReading ?? (b, c) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every entry with its book, chapter and a date',
      (tester) async {
    seedHistory([
      (book: 43, chapter: 3),
      (book: 1, chapter: 1),
      (book: 27, chapter: 23), // Tehilim (Psaumes)
    ]);
    await pumpHistorique(tester);

    expect(find.text('Jean 3'), findsOneWidget);
    expect(find.text('Bereshit (Genèse) 1'), findsOneWidget);
    expect(find.text('Tehilim (Psaumes) 23'), findsOneWidget);
    expect(find.text('3 études'), findsOneWidget);
    expect(find.textContaining('Lecture · '), findsNWidgets(3),
        reason: 'each card carries its relative date');
  });

  testWidgets('an empty history shows the hint, not a list', (tester) async {
    await pumpHistorique(tester);

    expect(find.text('Aucune étude pour le moment'), findsOneWidget);
    expect(find.text('0 étude'), findsOneWidget);
  });

  testWidgets('the section chips narrow the list', (tester) async {
    seedHistory([
      (book: 43, chapter: 3), // Évangiles
      (book: 1, chapter: 1), // Torah
      (book: 27, chapter: 23), // Ketouvim
      (book: 44, chapter: 2), // Testament
    ]);
    await pumpHistorique(tester);

    await tester.tap(find.text('Évangiles'));
    await tester.pumpAndSettle();

    expect(find.text('Jean 3'), findsOneWidget);
    expect(find.text('Bereshit (Genèse) 1'), findsNothing);
    expect(find.text('Tehilim (Psaumes) 23'), findsNothing);
    expect(find.text('Actes 2'), findsNothing);
    expect(find.text('1 étude'), findsOneWidget);
  });

  testWidgets('the search filters by book name, accent-insensitive',
      (tester) async {
    seedHistory([
      (book: 43, chapter: 3), // Jean
      (book: 1, chapter: 1), // Bereshit (Genèse)
      (book: 27, chapter: 23), // Tehilim (Psaumes)
    ]);
    await pumpHistorique(tester);

    await tester.enterText(find.byType(TextField), 'psaumes');
    await tester.pumpAndSettle();

    expect(find.text('Tehilim (Psaumes) 23'), findsOneWidget);
    expect(find.text('Jean 3'), findsNothing);
    expect(find.text('Bereshit (Genèse) 1'), findsNothing);
    expect(find.text('1 étude'), findsOneWidget);
  });

  testWidgets('search and section combine', (tester) async {
    seedHistory([
      (book: 43, chapter: 3), // Jean, Évangiles
      (book: 40, chapter: 5), // Matthieu, Évangiles
      (book: 1, chapter: 1), // Genèse, Torah
    ]);
    await pumpHistorique(tester);

    await tester.tap(find.text('Évangiles'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'jean');
    await tester.pumpAndSettle();

    expect(find.text('Jean 3'), findsOneWidget);
    expect(find.text('Matthieu 5'), findsNothing);
    expect(find.text('Bereshit (Genèse) 1'), findsNothing);
  });

  testWidgets('a filter with no match shows the empty state', (tester) async {
    seedHistory([
      (book: 43, chapter: 3),
    ]);
    await pumpHistorique(tester);

    await tester.enterText(find.byType(TextField), 'apocalypse');
    await tester.pumpAndSettle();

    expect(find.text('Aucun résultat'), findsOneWidget);
    expect(find.text('0 étude'), findsOneWidget);
  });

  testWidgets('tapping a card opens the chapter', (tester) async {
    seedHistory([
      (book: 43, chapter: 3),
    ]);
    final opened = <(int, int)>[];
    await pumpHistorique(tester, onOpenReading: (b, c) => opened.add((b, c)));

    await tester.tap(find.text('Jean 3'));
    await tester.pumpAndSettle();

    expect(opened, [(43, 3)]);
  });

  // ---- Intégration Accueil ----

  /// The home page's studies section sits below the fold on the default test
  /// surface : give the list room so the recent cards are actually built.
  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        manager: TabManager(),
        onSelectDestination: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('Études récentes shows at most 5 positions after the resume',
      (tester) async {
    // 7 lectures : la première alimente la carte « Reprendre la lecture »,
    // il en reste 6 pour la liste — qui doit en retenir 5.
    seedHistory([
      (book: 1, chapter: 1),
      (book: 2, chapter: 1),
      (book: 3, chapter: 1),
      (book: 4, chapter: 1),
      (book: 5, chapter: 1),
      (book: 6, chapter: 1),
      (book: 7, chapter: 1),
    ]);
    await pumpHome(tester);

    expect(find.text('Shemot (Exode) 1'), findsOneWidget);
    expect(find.text('Vayiqra (Lévitique) 1'), findsOneWidget);
    expect(find.text('Bemidbar (Nombres) 1'), findsOneWidget);
    expect(find.text('Devarim (Deutéronome) 1'), findsOneWidget);
    expect(find.text('Yehoshoua (Josué) 1'), findsOneWidget,
        reason: 'la 5ᵉ carte (2ᵉ→6ᵉ positions) est affichée');
    expect(find.text('Shoftim (Juges) 1'), findsNothing,
        reason: 'la 7ᵉ lecture est réservée au « Tout voir »');
  });

  testWidgets('« Tout voir » opens the full, filterable history',
      (tester) async {
    seedHistory([
      (book: 1, chapter: 1),
      (book: 2, chapter: 1),
      (book: 3, chapter: 1),
      (book: 4, chapter: 1),
      (book: 5, chapter: 1),
      (book: 6, chapter: 1),
      (book: 7, chapter: 1),
    ]);
    await pumpHome(tester);

    await tester.tap(find.text('Tout voir'));
    await tester.pumpAndSettle();

    expect(find.byType(HistoriqueScreen), findsOneWidget);
    expect(find.text('Shoftim (Juges) 1'), findsOneWidget,
        reason: 'l\'historique complet liste aussi la 7ᵉ lecture');
    expect(find.text('7 études'), findsOneWidget);
    // Le filtre de l'historique est bien là.
    expect(find.text(bibleSections[0].name), findsOneWidget);
  });

  testWidgets('« Tout voir » reopens the chapter through the reader',
      (tester) async {
    seedHistory([
      (book: 43, chapter: 3),
    ]);
    final opened = <(int, int)>[];
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        manager: TabManager(),
        onSelectDestination: (_) {},
        onOpenReading: (b, c, {verse}) => opened.add((b, c)),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tout voir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jean 3'));
    await tester.pumpAndSettle();

    expect(opened, [(43, 3)]);
  });
}