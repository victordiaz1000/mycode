import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_database.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/screens/favoris_screen.dart';

import 'support/fake_bible_bundle.dart';

/// AppDatabase in-memory pour les tests : les méthodes font de simples
/// microtâches (pas d'isolate FFI ni de path_provider), donc leurs futurs se
/// terminent dans la zone fake-async de `testWidgets`.
class _FakeDb extends AppDatabase {
  final Set<(int, int, int)> _favs = {};

  void seed(int book, int chapter, int verse) => _favs.add((book, chapter, verse));

  @override
  Future<List<UserFavorite>> allFavorites() async {
    final list = [
      for (final t in _favs)
        UserFavorite(bookIndex: t.$1, chapter: t.$2, verse: t.$3),
    ]..sort((a, b) {
        if (a.bookIndex != b.bookIndex) return a.bookIndex - b.bookIndex;
        if (a.chapter != b.chapter) return a.chapter - b.chapter;
        return a.verse - b.verse;
      });
    return list;
  }

  @override
  Future<void> setFavorite(int book, int chapter, int verse, bool value) async {
    if (value) {
      _favs.add((book, chapter, verse));
    } else {
      _favs.remove((book, chapter, verse));
    }
  }

  @override
  Future<bool> isFavorite(int book, int chapter, int verse) async =>
      _favs.contains((book, chapter, verse));
}

void main() {
  setUp(() {
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
  });

  Future<void> pumpFavoris(
    WidgetTester tester, {
    _FakeDb? db,
    void Function(int, int, int)? onOpenVerse,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: FavorisScreen(
        db: db ?? _FakeDb(),
        onOpenVerse: onOpenVerse ?? (book, chapter, verse) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lists every favorited verse with its reference and its text',
      (tester) async {
    final db = _FakeDb()
      ..seed(1, 1, 2)
      ..seed(43, 1, 1);
    await pumpFavoris(tester, db: db);

    expect(find.text('Genèse 1:2'), findsOneWidget);
    expect(find.text('Verset de test Ge. 1:2.'), findsOneWidget);
    expect(find.text('Jean 1:1'), findsOneWidget);
    expect(find.text('Verset de test Jn. 1:1.'), findsOneWidget);
    expect(find.text('2 favoris'), findsOneWidget);
  });

  testWidgets('the filter chips narrow the list by type', (tester) async {
    final db = _FakeDb()..seed(1, 1, 2);
    await pumpFavoris(tester, db: db);

    await tester.tap(find.text('Versets'));
    await tester.pumpAndSettle();
    expect(find.text('Genèse 1:2'), findsOneWidget,
        reason: 'verse favorites match the Versets filter');

    await tester.tap(find.text('Strong'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun favori ici'), findsOneWidget);
    expect(find.text('0 favori'), findsOneWidget);

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun favori ici'), findsOneWidget);

    await tester.tap(find.text('Tous'));
    await tester.pumpAndSettle();
    expect(find.text('Genèse 1:2'), findsOneWidget);
  });

  testWidgets('an empty database shows the empty state', (tester) async {
    await pumpFavoris(tester);

    expect(find.text('Aucun favori ici'), findsOneWidget);
    expect(find.text('0 favori'), findsOneWidget);
  });

  testWidgets('the heart removes the favorite from the list and the database',
      (tester) async {
    final db = _FakeDb()
      ..seed(1, 1, 2)
      ..seed(43, 1, 1);
    await pumpFavoris(tester, db: db);

    // Genèse 1:2 vient avant Jean 1:1 (ordre de lecture) : son cœur est le
    // premier de la liste.
    await tester.tap(find.byIcon(Icons.favorite_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Genèse 1:2'), findsNothing);
    expect(find.text('Jean 1:1'), findsOneWidget,
        reason: 'only the tapped favorite is removed');
    expect(await db.isFavorite(1, 1, 2), isFalse,
        reason: 'the removal reaches the database, not just the screen');
    expect(await db.isFavorite(43, 1, 1), isTrue);
    expect(find.text('1 favori'), findsOneWidget);
  });

  testWidgets('tapping a verse card asks the shell to open that verse',
      (tester) async {
    final db = _FakeDb()..seed(1, 1, 2);
    final opened = <(int, int, int)>[];
    await pumpFavoris(tester, db: db, onOpenVerse: (b, c, v) => opened.add((b, c, v)));

    await tester.tap(find.text('Genèse 1:2'));
    await tester.pumpAndSettle();

    expect(opened, [(1, 1, 2)],
        reason: 'the card navigates to the exact verse');
  });
}