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
import 'package:bible_app/widgets/strong_senses.dart';

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
      // occurrence, and the callback answers with the verse. The search
      // field above the list grew to its real height, so the second card
      // needs bringing into view first.
      await tester.ensureVisible(find.text('H7225'));
      await tester.pumpAndSettle();
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
      expect(find.text('Aucune occurrence dans la LSS embarquée.'),
          findsOneWidget);
      expect(find.textContaining('Voir plus'), findsNothing);
    });

    testWidgets('the definition card wears the shared premium surface',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      final definition = await StrongLexicon.instance.lookup('G2316');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      // La carte de « Définition complète » est l'unique conteneur ancêtre de
      // `StrongSenses` : c'est elle qui doit porter la surface partagée avec
      // l'étude du verset et la recherche — voile, liseré, deux ombres.
      final decor = tester
          .widgetList<Container>(
            find.ancestor(
              of: find.byType(StrongSenses),
              matching: find.byType(Container),
            ),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere(
            (box) => box.gradient != null,
            orElse: () => const BoxDecoration(),
          );
      expect(decor.gradient, isNotNull,
          reason: 'la carte de définition partage le voile des autres écrans');
      expect(decor.border, isNotNull,
          reason: 'et son liseré net');
      expect(decor.boxShadow, hasLength(2),
          reason: 'et ses deux ombres, ambiante puis de contact');
    });

    testWidgets('the fiche writes the Hebrew word as the study card does',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);
      StrongLexicon.useBundle(FakeStrongLexiconBundle({
        'H0001': {
          'strong': 'H0001',
          'language': 'hebrew',
          'lemma': 'אָב',
          'transliteration': "'ab",
          'partOfSpeech': 'Nom masculin',
          'pronunciation': '(awb)',
          'definition': 'Définition test de H0001 — père, chef de famille.',
        },
        'H7225': 'Définition test de H7225.',
      }));

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      // La fiche suit l'écriture de la carte d'étude du verset : la même
      // serif, le même graisse — un peu plus grand, pour lire chaque lettre.
      final mot = tester.widget<Text>(find.text('אָב'));
      expect(mot.style?.fontFamily, 'serif');
      expect(mot.style?.fontWeight, FontWeight.w700);
      expect(mot.style?.fontSize, 34);
      expect(mot.style?.letterSpacing, isNull);
      expect(
        tester
            .widgetList<Directionality>(
              find.ancestor(
                of: find.text('אָב'),
                matching: find.byType(Directionality),
              ),
            )
            .map((directionality) => directionality.textDirection),
        contains(TextDirection.rtl),
        reason: 'l’hébreu se lit de droite à gauche, comme dans la carte',
      );

      // L'alignement, lui, reste celui de l'en-tête : c'est de la mise en
      // page, pas de l'écriture.
      expect(mot.textAlign, TextAlign.center);
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

    testWidgets('the fiche shows Signification right after Origine',
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
          'etymology': 'Une racine primitive, le même que H7225.',
          'signification': 'Ab = père, chef de famille',
          'definition': 'Définition test de H0001 — père, chef de famille.',
        },
        'H7225': 'Définition test de H7225.',
      }));

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Origine'), findsOneWidget);
      expect(find.text('Signification'), findsOneWidget);
      expect(find.text('Ab = père, chef de famille'), findsOneWidget);

      final origine = tester.getTopLeft(find.text('Origine')).dy;
      final signification =
          tester.getTopLeft(find.text('Signification')).dy;
      expect(signification, greaterThan(origine),
          reason: 'la section « Signification » suit « Origine »');
    });

    testWidgets('no Signification section when the entry carries no gloss',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);

      // The default fake entry has an etymology but no signification.
      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Origine'), findsOneWidget);
      expect(find.text('Signification'), findsNothing);
    });

    testWidgets('the fiche indents the rungs of the source outline',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);
      StrongLexicon.useBundle(FakeStrongLexiconBundle({
        'H0001': {
          'strong': 'H0001',
          'language': 'hebrew',
          'lemma': 'אָב',
          'transliteration': "'ab",
          'definition': 'Définition test de H0001.',
          'senses': ['être, divinité'],
          'outline': [
            {'level': 0, 'kind': 'sense', 'text': 'un dieu, une divinité'},
            {'level': 0, 'kind': 'header', 'label': 'Qal', 'text': ''},
            {'level': 1, 'kind': 'number', 'text': '1a1) sens spirituel'},
          ],
        },
        'H7225': 'Définition test de H7225.',
      }));

      final definition = await StrongLexicon.instance.lookup('H0001');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(find.text('un dieu, une divinité', findRichText: true),
          findsOneWidget);
      expect(find.text('(Qal)', findRichText: true), findsOneWidget);
      expect(find.text('1a1) sens spirituel', findRichText: true),
          findsOneWidget);

      final sense =
          tester.getTopLeft(find.text('un dieu, une divinité', findRichText: true));
      final stem = tester.getTopLeft(find.text('(Qal)', findRichText: true));
      final rung =
          tester.getTopLeft(find.text('1a1) sens spirituel', findRichText: true));

      expect(stem.dx, sense.dx,
          reason: 'le stem est au même niveau que les sens de tête');
      expect(rung.dx, greaterThan(stem.dx),
          reason: '« 1a1) » s’indente d’un cran sous « (Qal) »');
      expect(rung.dy, greaterThan(stem.dy),
          reason: 'le rung est sous son stem, pas à côté');
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

    testWidgets('an entry present in the corpus shows its occurrences',
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

    testWidgets('a long lemma, transliteration and pronunciation never overflow',
        (tester) async {
      LsgsRepositoryDummy.install();
      addTearDown(LsgsRepositoryDummy.restore);
      StrongLexicon.useBundle(FakeStrongLexiconBundle({
        'H0859': {
          'strong': 'H0859',
          'language': 'hebrew',
          'lemma': 'Nebuwkadnetstsar',
          'transliteration':
              '’attah ou (raccourci) ’atta ou ’ath féminin (irrégulier) '
              'quelquefois ’attiy masculin pluriel ’attem féminin ’atten ou ’a',
          'pronunciation':
              "oat-taw') ou (oat-taw') ou (oat-taw') ou (oat-taw') ou (oat-taw'",
          'definition': 'Définition test de H0859.',
        },
      }));

      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final definition = await StrongLexicon.instance.lookup('H0859');
      await tester.pumpWidget(MaterialApp(
        home: StrongDetailScreen(strong: definition),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'a long lemma, transliteration and pronunciation must not '
              'overflow the header card');
      expect(find.textContaining('féminin'), findsOneWidget,
          reason: 'the transliteration is still rendered in full');
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