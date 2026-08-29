import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_store.dart';
import 'package:bible_app/screens/dictionary_browse_screen.dart';
import 'package:bible_app/widgets/loading_skeleton.dart';

/// An in-memory store: the browse screen only calls [load], so the disk never
/// has to be involved (path_provider never answers in fake-async).
class FakeDictionaryStore extends DictionaryStore {
  FakeDictionaryStore([Map<String, dynamic>? data]) : _data = data;

  final Map<String, dynamic>? _data;

  @override
  Future<Map<String, dynamic>?> load(String code) async => _data;
}

const bailly = DictionaryEntry(
  code: 'BAILLY',
  name: 'Bailly — Grec-français',
  rights: 'libre',
  description: 'Dictionnaire grec-français.',
  availability: DictionaryAvailability.downloadable,
);

Map<String, dynamic> sampleData() => {
      'entries': {
        'ABBA': {
          'term': 'ABBA',
          'definition': 'Père, en araméen.',
        },
        'AGAPÈ': {'term': 'AGAPÈ', 'definition': 'Amour inconditionnel.'},
        'ANGE': {'term': 'ANGE', 'definition': 'Messager céleste.'},
        'BÉNÉDICTION': {
          'term': 'BÉNÉDICTION',
          'definition': 'Action de bénir.',
        },
      },
    };

/// Flattens an [InlineSpan] tree into its leaf spans.
List<InlineSpan> _flatten(InlineSpan span, [List<InlineSpan>? out]) {
  final result = out ?? <InlineSpan>[];
  if (span is TextSpan && span.children != null) {
    for (final child in span.children!) {
      _flatten(child, result);
    }
  } else {
    result.add(span);
  }
  return result;
}

void main() {
  Future<void> pumpBrowse(
    WidgetTester tester, {
    DictionaryStore? store,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: DictionaryBrowseScreen(
        entry: bailly,
        store: store ?? FakeDictionaryStore(sampleData()),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('DictionaryBrowseScreen', () {
    testWidgets('lists the entries with a count', (tester) async {
      await pumpBrowse(tester);

      expect(find.text('Bailly — Grec-français'), findsOneWidget);
      expect(find.text('4 entrées'), findsOneWidget);
      expect(find.text('ABBA'), findsOneWidget);
      expect(find.text('BÉNÉDICTION'), findsOneWidget);
    });

    testWidgets('letter chips filter the list', (tester) async {
      await pumpBrowse(tester);

      await tester.tap(find.byKey(const Key('letter-chip-B')));
      await tester.pumpAndSettle();

      expect(find.text('1 entrée'), findsOneWidget);
      expect(find.text('BÉNÉDICTION'), findsOneWidget);
      expect(find.text('ABBA'), findsNothing);
    });

    testWidgets('search narrows by term and definition', (tester) async {
      await pumpBrowse(tester);

      await tester.enterText(find.byType(TextField), 'ange');
      await tester.pumpAndSettle();

      expect(find.text('ANGE'), findsOneWidget);
      expect(find.text('ABBA'), findsNothing);
    });

    testWidgets('a store without the file shows the loading skeleton, never a crash',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: DictionaryBrowseScreen(
          entry: bailly,
          store: FakeDictionaryStore(),
        ),
      ));
      await tester.pump();

      expect(find.byType(DictionaryBrowseLoadingSkeleton), findsOneWidget);
      expect(find.byType(TextField), findsNothing,
          reason: 'the whole screen waits, search included');
    });

    testWidgets('tapping an entry opens the rich fiche with badge and article',
        (tester) async {
      await pumpBrowse(tester);

      await tester.tap(find.text('ABBA'));
      await tester.pumpAndSettle();

      // The fiche reuses the generic dictionary article view: the dictionary
      // name as badge, its description as subtitle, and the article body.
      expect(find.text('Bailly — Grec-français'), findsWidgets);
      expect(find.text('Dictionnaire grec-français.'), findsOneWidget);
      expect(find.text('Père, en araméen.'), findsOneWidget);
    });

    testWidgets('a linked entry word opens its own fiche', (tester) async {
      final data = sampleData();
      (data['entries'] as Map)['VERBE'] = {
        'term': 'VERBE',
        'definition': 'Un mot qui contient AGAPÈ à l\'intérieur.',
      };
      await pumpBrowse(tester, store: FakeDictionaryStore(data));

      // The list is lazy: reach VERBE through the search field.
      await tester.enterText(find.byType(TextField), 'verbe');
      await tester.pumpAndSettle();

      await tester.tap(find.text('VERBE'));
      await tester.pumpAndSettle();

      // The cross-link pattern links AGAPÈ, which is itself an entry.
      final paragraph = tester
          .widget<Text>(find.text('Un mot qui contient AGAPÈ à l\'intérieur.'));
      final spans = _flatten(paragraph.textSpan! as TextSpan)
          .whereType<TextSpan>()
          .toList();
      final link = spans.firstWhere((span) => span.text == 'AGAPÈ');
      expect(link.recognizer, isNotNull,
          reason: 'the entry word is a tappable link');
    });
  });
}