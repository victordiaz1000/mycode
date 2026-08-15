import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/strong_occurrences.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';
import 'package:bible_app/screens/strong_index_screen.dart';
import 'package:bible_app/widgets/strong_code_text.dart';

import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
  });

  tearDown(() {
    StrongLexicon.useRootBundle();
  });

  Future<void> pumpIndex(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StrongIndexScreen()));
    await tester.pumpAndSettle();
  }

  group('Strong index', () {
    testWidgets('lists every entry with its code badge', (tester) async {
      await pumpIndex(tester);

      expect(find.text('Dictionnaire Strong'), findsOneWidget);
      expect(find.text('5 entrées'), findsOneWidget);
      expect(find.text('H0001'), findsOneWidget);
      expect(find.text('H7225'), findsOneWidget);
      expect(find.text('H0430'), findsOneWidget);
      expect(find.text('G2316'), findsOneWidget);
      expect(find.text('G0001'), findsOneWidget);
    });

    testWidgets('the Grec / Hébreu chips filter the list', (tester) async {
      await pumpIndex(tester);

      await tester.tap(find.text('Grec'));
      await tester.pumpAndSettle();

      expect(find.text('2 entrées'), findsOneWidget);
      expect(find.text('G2316'), findsOneWidget);
      expect(find.text('G0001'), findsOneWidget);
      expect(find.text('H0001'), findsNothing);

      await tester.tap(find.text('Hébreu'));
      await tester.pumpAndSettle();

      expect(find.text('3 entrées'), findsOneWidget);
      expect(find.text('H0001'), findsOneWidget);
      expect(find.text('H0430'), findsOneWidget);
      expect(find.text('G2316'), findsNothing);

      await tester.tap(find.text('Tous'));
      await tester.pumpAndSettle();
      expect(find.text('5 entrées'), findsOneWidget);
    });

    testWidgets('the search narrows by code, word or transliteration',
        (tester) async {
      await pumpIndex(tester);

      await tester.enterText(find.byType(TextField), '2316');
      await tester.pumpAndSettle();
      expect(find.text('1 entrée'), findsOneWidget);
      expect(find.text('G2316'), findsOneWidget);
      expect(find.text('H0001'), findsNothing);

      await tester.enterText(find.byType(TextField), "'ab");
      await tester.pumpAndSettle();
      expect(find.text('H0001'), findsOneWidget);
      expect(find.text('G2316'), findsNothing);
    });

    testWidgets('an unknown search shows the empty state', (tester) async {
      await pumpIndex(tester);

      await tester.enterText(find.byType(TextField), 'zzz-inconnu');
      await tester.pumpAndSettle();

      expect(find.text('Aucune entrée trouvée'), findsOneWidget);
    });

    testWidgets('tapping an entry opens the fiche', (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      await pumpIndex(tester);

      await tester.tap(find.text('H0001'));
      await tester.pumpAndSettle();

      expect(find.byType(StrongDetailScreen), findsOneWidget,
          reason: 'a pushed route shows the fiche');
      expect(find.text('H0001'), findsWidgets);
    });

    testWidgets('the onOpenVerse callback reaches the fiche occurrences',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final opened = <(int, int, int)>[];
      await tester.pumpWidget(MaterialApp(
        home: StrongIndexScreen(
          onOpenVerse: (b, c, v) => opened.add((b, c, v)),
        ),
      ));
      await tester.pumpAndSettle();

      // H7225 appears in the fake LSGS corpus: open its fiche, then its
      // occurrence, and the callback answers with the verse.
      await tester.tap(find.text('H7225'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Genèse 1:1'), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genèse 1:1'));
      await tester.pumpAndSettle();

      expect(opened, [(1, 1, 1)]);
    });
  });

  group('StrongCodeText', () {
    Future<void> pumpCode(WidgetTester tester,
        String text, List<String> tapped,
        {bool linkBareNumbers = false}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: StrongCodeText(
            text: text,
            linkBareNumbers: linkBareNumbers,
            onStrongTap: tapped.add,
          ),
        ),
      ));
    }

    Future<void> tapSpan(WidgetTester tester, String full, String code) async {
      await tester.pumpAndSettle();
      final p = tester.renderObject<RenderParagraph>(
          find.text(full, findRichText: true));
      final boxes = p.getBoxesForSelection(TextSelection(
        baseOffset: full.indexOf(code),
        extentOffset: full.indexOf(code) + code.length,
      ));
      expect(boxes, isNotEmpty);
      final box = boxes.first;
      await tester.tapAt(p.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();
    }

    testWidgets('reports the unpadded code when its span is tapped',
        (tester) async {
      final tapped = <String>[];
      const full = 'Correspondant à H1, à savoir H4236.';
      await pumpCode(tester, full, tapped);

      await tapSpan(tester, full, 'H1');
      expect(tapped, ['H1']);

      await tapSpan(tester, full, 'H4236');
      expect(tapped, ['H1', 'H4236']);
    });

    testWidgets('a bare Strong number is linked when the option is on',
        (tester) async {
      final tapped = <String>[];
      const full = 'Vient de 5975, à savoir H1.';
      await pumpCode(tester, full, tapped, linkBareNumbers: true);

      await tapSpan(tester, full, '5975');
      expect(tapped, ['5975'],
          reason: 'the bare number is reported unpadded, as written');

      await tapSpan(tester, full, 'H1');
      expect(tapped, ['5975', 'H1']);
    });

    testWidgets('bare numbers stay plain without the option',
        (tester) async {
      final tapped = <String>[];
      const full = 'Vient de 5975, à savoir H1.';
      await pumpCode(tester, full, tapped);

      await tapSpan(tester, full, '5975');
      expect(tapped, isEmpty,
          reason: 'only the lettered code is linked by default');
    });

    testWidgets('a verse reference does not link its numbers',
        (tester) async {
      final tapped = <String>[];
      const full = 'Cf. 1 Samuel 9.1.';
      await pumpCode(tester, full, tapped, linkBareNumbers: true);

      await tapSpan(tester, full, '9');
      expect(tapped, isEmpty,
          reason: 'the number follows a Bible book name, it is a verse');
    });

    testWidgets('the privative « 1 » is never linked', (tester) async {
      final tapped = <String>[];
      const full = 'Vient de 1 (négatif).';
      await pumpCode(tester, full, tapped, linkBareNumbers: true);

      await tapSpan(tester, full, '1');
      expect(tapped, isEmpty,
          reason: '« 1 » is the Greek privative alpha, not a Strong code');
    });
  });

  group('Strong fiche', () {
    testWidgets('Greek entry: badge, header number and definition',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('G2316');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Grec'), findsOneWidget);
      // Scalar fake entry: no partOfSpeech badge (falls back to the strong
      // number in the header), the definition comes from its scalar value.
      expect(find.text('G2316'), findsWidgets);
      expect(find.text('Définition test de G2316.'), findsWidgets);
    });

    testWidgets('Hebrew entry: badges, lemma, strong number and no occurrences',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Hébreu'), findsOneWidget);
      expect(find.text('H0001'), findsWidgets);
      expect(find.text("'ab"), findsOneWidget);
      expect(find.text('Occurrences du mot (0)'), findsOneWidget);
      expect(find.text('Aucune occurrence dans la LSGS embarquée.'),
          findsOneWidget);
      expect(find.textContaining('Voir plus'), findsNothing);
    });

    testWidgets('the fiche shows the Origine section when the entry carries it',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Nom masculin'), findsOneWidget);
      expect(find.text('Origine'), findsOneWidget);
      expect(
          find.text('Une racine primitive, le même que H7225.',
              findRichText: true),
          findsOneWidget,
          reason: 'the etymology is a rich text once it carries a Strong code');
      expect(find.text('H7225'), findsNothing,
          reason: 'the code is a span inside the etymology, not a Text widget');
    });

    testWidgets('a Strong code in the Origine opens its own fiche',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
          find.text('Une racine primitive, le même que H7225.',
              findRichText: true),
          120);
      await tester.pumpAndSettle();

      const code = 'H7225';
      const full = 'Une racine primitive, le même que H7225.';
      final paragraph = tester.renderObject<RenderParagraph>(
          find.text(full, findRichText: true));
      final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: full.indexOf(code),
        extentOffset: full.indexOf(code) + code.length,
      ));
      expect(boxes, isNotEmpty);
      final box = boxes.first;
      await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();

      expect(find.byType(StrongDetailScreen), findsOneWidget,
          reason: 'the pushed fiche covers the originating one');
      expect(find.text('Occurrences du mot (1)'), findsOneWidget,
          reason: 'H7225 appears in the fake LSGS corpus');
      expect(find.text('Définition test de H7225.'), findsWidgets,
          reason: 'the H7225 definition of the fake lexicon is shown');
    });

    testWidgets('a bare Strong number in the Origine opens the fiche too',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);
      StrongLexicon.useBundle(FakeStrongLexiconBundle({
        'H0001': {
          'strong': 'H0001',
          'language': 'hebrew',
          'lemma': '??',
          'transliteration': "'ab",
          'partOfSpeech': 'Nom masculin',
          'pronunciation': '(awb)',
          'etymology': 'Une racine primitive, le même que 7225.',
          'definition': 'Définition test de H0001 — père, chef de famille.',
        },
        'H7225': 'Définition test de H7225.',
      }));

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      const full = 'Une racine primitive, le même que 7225.';
      await tester.scrollUntilVisible(find.text(full, findRichText: true), 120);
      await tester.pumpAndSettle();

      const code = '7225';
      final paragraph = tester.renderObject<RenderParagraph>(
          find.text(full, findRichText: true));
      final boxes = paragraph.getBoxesForSelection(TextSelection(
        baseOffset: full.indexOf(code),
        extentOffset: full.indexOf(code) + code.length,
      ));
      expect(boxes, isNotEmpty);
      final box = boxes.first;
      await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();

      expect(find.byType(StrongDetailScreen), findsOneWidget,
          reason: 'the pushed fiche covers the originating one');
      expect(find.text('Définition test de H7225.'), findsWidgets,
          reason: 'the bare number resolved to the H7225 lexicon key');
    });

    testWidgets('Voir plus opens the books list, then the verses of a book',
        (tester) async {
      LsgsRepository.useBundle(_RichLsgsBundle());
      StrongOccurrenceIndex.useAmbientRepository();
      addTearDown(LsgsRepository.useRootBundle);
      addTearDown(StrongOccurrenceIndex.useAmbientRepository);

      final definition = await StrongLexicon.instance.lookup('H7225');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Occurrences du mot (8)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Voir plus (3 autres versets)'),
          120);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Voir plus (3 autres versets)'));
      await tester.pumpAndSettle();

      expect(find.text('Occurrences — H7225'), findsOneWidget);
      expect(find.text('8 versets répartis dans 2 livres'), findsOneWidget);
      expect(find.text('Genèse'), findsOneWidget);
      expect(find.text('Exode'), findsOneWidget);

      await tester.tap(find.text('Genèse'));
      await tester.pumpAndSettle();

      expect(find.text('Genèse 1:1'), findsOneWidget);
      expect(find.text('Genèse 2:2'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Genèse 3:2'), 120);
      await tester.pumpAndSettle();
      expect(find.text('Genèse 3:2'), findsOneWidget);
      expect(find.textContaining('Exode'), findsNothing,
          reason: 'the fiche and books list are covered by the pushed route');
    });

    testWidgets('an entry present in the LSGS shows its occurrences',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('H7225');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Occurrences du mot (1)'), findsOneWidget);
      expect(find.text('Genèse 1:1'), findsOneWidget);
      expect(find.text('AA'), findsOneWidget);
      expect(find.textContaining('Voir plus'), findsNothing,
          reason: 'one occurrence is fewer than the 5 limit');
    });

    testWidgets('the occurrence card shows the whole verse, word highlighted',
        (tester) async {
      LsgsRepository.useBundle(_MultiTokenLsgsBundle());
      StrongOccurrenceIndex.useAmbientRepository();
      addTearDown(LsgsRepository.useRootBundle);
      addTearDown(StrongOccurrenceIndex.useAmbientRepository);

      final definition = await StrongLexicon.instance.lookup('H7225');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Genèse 1:1'), findsOneWidget);
      expect(find.text('Au commencement'), findsOneWidget,
          reason: 'the first words of the verse are shown');
      expect(find.textContaining('créa les cieux.'), findsOneWidget,
          reason: 'the verse is complete, nothing truncated');

      final target = tester
          .widgetList<Text>(find.textContaining('AA'))
          .single;
      expect(target.style?.fontWeight, isNot(FontWeight.w700),
          reason: 'the occurrence word is not bolded');
      expect(target.style?.backgroundColor, isNotNull,
          reason: 'highlighted with a tint, not a link');
    });

    testWidgets('an occurrence opens the verse through the callback',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final opened = <(int, int, int)>[];
      final definition = await StrongLexicon.instance.lookup('H7225');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(
          strong: definition,
          onOpenVerse: (b, c, v) => opened.add((b, c, v)),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Genèse 1:1'), 120);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Genèse 1:1'));
      await tester.pumpAndSettle();

      expect(opened, [(1, 1, 1)]);
    });
  });
}

/// Installs the fake LSGS corpus into both the occurrence index and
/// `LsgsRepository`, the two read paths of the fiche.
class LsgsRepositoryDummy {
  static void install() {
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongOccurrenceIndex.useAmbientRepository();
  }

  static void restore() {
    LsgsRepository.useRootBundle();
    StrongOccurrenceIndex.useAmbientRepository();
  }
}

/// A richer fake LSGS corpus: H7225 appears in 8 verses across 2 books
/// (Genèse 1-3, Exode 1), enough to exercise the « Voir plus » navigation.
class _RichLsgsBundle extends AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final number = RegExp(r'_?(\d+)-').firstMatch(key)?.group(1);
    if (number == null || (number != '01' && number != '02')) {
      return jsonEncode({
        'book': 'Vide',
        'bym_index': int.parse(number ?? '0'),
        'abbreviation': '',
        'osis_id': '',
        'chapters': <Object>[],
      });
    }
    final isExode = number == '02';
    final chapters = isExode
        ? [
            {
              'chapter': 1,
              'verses': [_verse(1), _verse(2)],
            },
          ]
        : [
            {
              'chapter': 1,
              'verses': [_verse(1), _verse(2)],
            },
            {
              'chapter': 2,
              'verses': [_verse(1), _verse(2)],
            },
            {
              'chapter': 3,
              'verses': [_verse(1), _verse(2)],
            },
          ];
    return jsonEncode({
      'book': isExode ? 'Exode' : 'Genèse',
      'bym_index': int.parse(number),
      'chapters': chapters,
    });
  }

  Map<String, dynamic> _verse(int number) => {
        'verse': number,
        'tokens': [
          {'text': 'Texte $number', 'strong': 'H7225'},
        ],
      };

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// A fake LSGS corpus where the H7225 verse carries several tokens, to check
/// that the occurrence card renders the whole verse and only the word bearing
/// the code is highlighted.
class _MultiTokenLsgsBundle extends AssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final number = RegExp(r'_?(\d+)-').firstMatch(key)?.group(1);
    if (number != null && number != '01') {
      return jsonEncode({
        'book': 'Vide',
        'bym_index': int.parse(number),
        'abbreviation': '',
        'osis_id': '',
        'chapters': <Object>[],
      });
    }
    return jsonEncode({
      'book': 'Genèse',
      'bym_index': 1,
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {
              'verse': 1,
              'tokens': [
                {'text': 'Au commencement', 'strong': null},
                {'text': 'AA', 'strong': 'H7225'},
                {'text': 'créa les cieux.', 'strong': null},
              ],
            },
          ],
        },
      ],
    });
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}