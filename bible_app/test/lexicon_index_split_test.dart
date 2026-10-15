import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_store.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/lexicon_index.dart' hide DictionaryEntry;
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/screens/bym_lexicon_entry_screen.dart';
import 'package:bible_app/screens/bym_lexicon_index_screen.dart';
import 'package:bible_app/screens/dictionary_browse_screen.dart';
import 'package:bible_app/screens/dictionary_entry_screen.dart';
import 'package:bible_app/screens/fredaw_entry_screen.dart';
import 'package:bible_app/screens/fredaw_index_screen.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';

/// Le split-view des index lexique/dictionnaire (étape G) : à ≥ 840 px le
/// tap d'une entrée affiche sa fiche en volet de droite au lieu de pousser
/// une route — et sous ce seuil, la poussée reste.Un cas par index
/// (BYM, Westphal, dictionnaire téléchargé), plus le garde-fou phone.
void main() {
  setUp(() {
    LocalRepository.useBundle(FakeBibleBundle());
    LexiconIndex.instance.clearIndex();
    FreDawLexicon.useBundle(FakeFreDawBundle({
      'ABBA': {'term': 'ABBA', 'definition': 'Père, en araméen.'},
    }));
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LexiconIndex.instance.clearIndex();
    FreDawLexicon.useRootBundle();
  });

  Future<void> setWide(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Vide la file d'exceptions du binding : un débordement y arrive à chaque
  /// peinture fautive.
  void expectNoOverflow(WidgetTester tester, String where) {
    final overflows = <String>[];
    for (var i = 0; i < 20; i++) {
      final error = tester.takeException();
      if (error == null) break;
      overflows.add('$where :: ${error.toString().split('\n').first}');
    }
    expect(overflows, isEmpty, reason: 'débordements $where');
  }

  testWidgets('wide : l\u2019index BYM affiche la fiche en volet', (
    tester,
  ) async {
    await setWide(tester);
    await tester.pumpWidget(
      const MaterialApp(home: BymLexiconIndexScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Choisissez une entrée'), findsOneWidget);
    expect(find.byType(BymLexiconEntryScreen), findsNothing);

    await tester.tap(find.text('Verset'));
    await tester.pumpAndSettle();

    expect(find.byType(BymLexiconEntryScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing,
        reason: 'le volet ne dépile pas l\u2019index');
    expectNoOverflow(tester, 'split lexique BYM');
  });

  testWidgets('phone : l\u2019index BYM pousse la fiche (garde-fou)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: BymLexiconIndexScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verset'));
    await tester.pumpAndSettle();

    expect(find.byType(BymLexiconEntryScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('wide : l\u2019index Westphal affiche la fiche en volet', (
    tester,
  ) async {
    await setWide(tester);
    await tester.pumpWidget(const MaterialApp(home: FredawIndexScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ABBA'));
    await tester.pumpAndSettle();

    expect(find.byType(FredawEntryScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing,
        reason: 'le volet ne dépile pas l\u2019index');
    expectNoOverflow(tester, 'split Westphal');
  });

  testWidgets('wide : le dictionnaire téléchargé affiche la fiche en volet',
      (tester) async {
    await setWide(tester);
    await tester.pumpWidget(MaterialApp(
      home: DictionaryBrowseScreen(
        entry: const DictionaryEntry(
          code: 'BAILLY',
          name: 'Bailly — Grec-français',
          rights: 'libre',
          description: 'Dictionnaire grec-français.',
          availability: DictionaryAvailability.downloadable,
        ),
        store: _FakeDictionaryStore({
          'entries': {
            'ABBA': {'term': 'ABBA', 'definition': 'Père, en araméen.'},
          },
        }),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ABBA'));
    await tester.pumpAndSettle();

    expect(find.byType(DictionaryEntryScreen), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing,
        reason: 'le volet ne dépile pas l\u2019index');
    expectNoOverflow(tester, 'split dictionnaire');
  });
}

/// Un magasin en mémoire : l'écran ne fait que [load], le disque n'a jamais
/// à intervenir (même patron que le test de parcours).
class _FakeDictionaryStore extends DictionaryStore {
  _FakeDictionaryStore(this._data);

  final Map<String, dynamic>? _data;

  @override
  Future<Map<String, dynamic>?> load(String code) async => _data;
}
