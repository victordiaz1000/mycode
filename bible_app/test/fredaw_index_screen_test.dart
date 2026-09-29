import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/screens/fredaw_entry_screen.dart';
import 'package:bible_app/screens/fredaw_index_screen.dart';

import 'support/fake_fredaw_bundle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FreDawLexicon.useBundle(FakeFreDawBundle({
      'VERSET': {
        'term': 'VERSET',
        'definition': 'Portion d\'un chapitre de la Sainte Écriture.',
      },
      'ABBA': {
        'term': 'ABBA',
        'definition': 'Définition test FreDAW de ABBA.',
      },
      'ÂGE': {
        'term': 'ÂGE',
        'definition': 'Définition commençant par une lettre accentuée.',
      },
    }));
  });

  tearDown(() {
    FreDawLexicon.useRootBundle();
  });

  Future<void> pumpIndex(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: FredawIndexScreen()));
    await tester.pumpAndSettle();
  }

  group('FreDAW index', () {
    testWidgets('lists every entry grouped by folded first letter',
        (tester) async {
      await pumpIndex(tester);

      expect(find.text('Westphal 1932'), findsOneWidget);
      // 3 entries, one of which starts with an accented « Â » — it must be
      // folded under « A » instead of forming its own letter group.
      expect(find.text('3 entrées'), findsOneWidget);
      expect(find.text('VERSET'), findsOneWidget);
      expect(find.text('ABBA'), findsOneWidget);
      expect(find.text('ÂGE'), findsOneWidget);
      expect(find.text('A'), findsNWidgets(2),
          reason: 'chip « Toutes » then group « A » are both labeled A');
      expect(find.text('V'), findsNWidgets(2),
          reason: 'chip « V » then group « V »');
    });

    testWidgets('the search field lights its border when it takes the focus',
        (tester) async {
      await pumpIndex(tester);

      // Le champ des index est le seul `AnimatedContainer` ancêtre du champ de
      // saisie : les puces sont des frères, pas des parents.
      BoxDecoration? decor() {
        final candidats = tester.widgetList<AnimatedContainer>(
          find.ancestor(
            of: find.byType(TextField),
            matching: find.byType(AnimatedContainer),
          ),
        );
        for (final champ in candidats) {
          final box = champ.decoration;
          if (box is BoxDecoration && box.gradient != null) return box;
        }
        return null;
      }

      final repos = decor();
      expect(repos, isNotNull,
          reason: 'le champ porte le voile de surface des index');
      expect(repos!.border!.top.color.a, lessThan(.3),
          reason: 'au repos, le liseré reste discret');

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final actif = decor();
      expect(actif!.border!.top.color.a, greaterThan(.5),
          reason: 'le focus éclaircit le liseré');
      expect(actif.boxShadow!.first.color.a, greaterThan(.1),
          reason: "et fait monter la lueur d'accent");
    });

    testWidgets('the letter chips filter the list', (tester) async {
      await pumpIndex(tester);

      await tester.tap(find.byKey(const Key('letter-chip-V')));
      await tester.pumpAndSettle();

      expect(find.text('1 entrée'), findsOneWidget);
      expect(find.text('VERSET'), findsOneWidget);
      expect(find.text('ABBA'), findsNothing);

      // Back to « Toutes » restores the full list.
      await tester.tap(find.text('Toutes'));
      await tester.pumpAndSettle();
      expect(find.text('3 entrées'), findsOneWidget);
    });

    testWidgets('the search field narrows the list by term or definition',
        (tester) async {
      await pumpIndex(tester);

      await tester.enterText(find.byType(TextField), 'abb');
      await tester.pumpAndSettle();

      expect(find.text('1 entrée'), findsOneWidget);
      expect(find.text('ABBA'), findsOneWidget);
      expect(find.text('VERSET'), findsNothing);

      // Search matches within definitions too.
      await tester.enterText(find.byType(TextField), 'écriture');
      await tester.pumpAndSettle();
      expect(find.text('VERSET'), findsOneWidget);
      expect(find.text('ABBA'), findsNothing);
    });

    testWidgets('an unknown search shows the empty state', (tester) async {
      await pumpIndex(tester);

      await tester.enterText(find.byType(TextField), 'zzz-inconnu');
      await tester.pumpAndSettle();

      expect(find.text('Aucune entrée trouvée'), findsOneWidget);
    });

    testWidgets('tapping an entry opens its article', (tester) async {
      await pumpIndex(tester);

      await tester.tap(find.text('ABBA'));
      await tester.pumpAndSettle();

      expect(find.byType(FredawEntryScreen), findsOneWidget,
          reason: 'a pushed route shows the fiche');
      expect(find.text('ABBA'), findsWidgets);
      expect(find.text('Westphal 1932'), findsOneWidget,
          reason: 'the badge in the fiche body, the AppBar title is gone');
      expect(find.text('Ouvrir onglet'), findsNothing,
          reason: 'the fiche no longer offers a reading-tab escape hatch');
    });
  });

  group('FreDAW fiche', () {
    testWidgets('shows a badge, term and source mention', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(
            term: 'ABBA',
            definition: 'Définition test FreDAW de ABBA.',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Westphal 1932'), findsOneWidget,
          reason: 'the badge in the fiche body, the AppBar title is gone');
      expect(find.text('ABBA'), findsOneWidget);
      expect(find.text('Dictionnaire encyclopédique de la Bible'),
          findsOneWidget);
      expect(find.textContaining('Auguste Westphal, 1932'), findsOneWidget);
      // Single paragraph: nothing to expand.
      expect(find.textContaining('Lire la suite'), findsNothing);
    });

    testWidgets('a multi-paragraph article is truncated then expandable',
        (tester) async {
      const definition = 'p1\n\np2\n\np3\n\np4';
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(term: 'ABBA', definition: definition),
        ),
      ));
      await tester.pumpAndSettle();

      // Only the first two paragraphs are shown by default.
      expect(find.text('p1'), findsOneWidget);
      expect(find.text('p2'), findsOneWidget);
      expect(find.text('p3'), findsNothing);
      expect(find.text('Lire la suite (2 paragraphes)'), findsOneWidget);

      await tester.tap(find.text('Lire la suite (2 paragraphes)'));
      await tester.pumpAndSettle();
      expect(find.text('p4'), findsOneWidget);
      expect(find.text('Réduire'), findsOneWidget);

      await tester.tap(find.text('Réduire'));
      await tester.pumpAndSettle();
      expect(find.text('p3'), findsNothing);
      expect(find.text('Lire la suite (2 paragraphes)'), findsOneWidget);
    });

    testWidgets('entry words in the article render as links',
        (tester) async {
      const definition = 'Verset porte le mot ABBA dans le texte.';
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(term: 'VERSET', definition: definition),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.widget<Text>(find.text(definition));
      final spans = _flatten(paragraph.textSpan! as TextSpan);
      final abba = spans.firstWhere((span) => span.text == 'ABBA');
      expect(abba.recognizer, isA<TapGestureRecognizer>(),
          reason: 'the entry word is a tappable link');
      expect(abba.style?.decoration, TextDecoration.underline,
          reason: 'the link is underlined');
      expect(abba.style?.color, isNotNull,
          reason: 'the link carries the accent colour');
    });

    testWidgets('tapping a linked word opens its own fiche', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(term: 'VERSET', definition: 'Voir ABBA pour plus.'),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Voir ABBA pour plus.', findRichText: true));
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 5, extentOffset: 9),
      );
      expect(boxes, isNotEmpty);
      await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
      await tester.pumpAndSettle();

      expect(find.byType(FredawEntryScreen), findsOneWidget,
          reason: 'the pushed fiche covers the originating one');
      expect(find.text('ABBA'), findsOneWidget,
          reason: 'the new fiche header shows the linked term');
      expect(find.text('Définition test FreDAW de ABBA.'), findsOneWidget,
          reason: 'the linked entry article is shown');
    });

    testWidgets('a Bible reference in the article stays plain text',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(
            term: 'VERSET',
            definition: 'Voir Jn 1:42 pour la suite.',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.widget<Text>(find.text('Voir Jn 1:42 pour la suite.'));
      final spans = _flatten(paragraph.textSpan! as TextSpan);
      expect(spans.where((s) => s.recognizer != null), isEmpty,
          reason: 'the reference is not clickable');
    });

    testWidgets('references stay plain when no reader callback is wired',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: FredawEntryScreen(
          entry: FreDawEntry(term: 'VERSET', definition: 'Voir Jn 1:42.'),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.widget<Text>(find.text('Voir Jn 1:42.'));
      final spans = _flatten(paragraph.textSpan! as TextSpan);
      expect(spans.where((s) => s.recognizer != null), isEmpty,
          reason: 'no callback, no link');
    });

    testWidgets('a dictionary word next to a reference stays tappable',
        (tester) async {
      FreDawLexicon.useBundle(FakeFreDawBundle({
        'VERSET': {
          'term': 'VERSET',
          'definition': 'Portion de la Sainte Écriture.',
        },
        'JEAN': {
          'term': 'JEAN',
          'definition': 'Un des quatre évangiles.',
        },
      }));
      addTearDown(FreDawLexicon.useRootBundle);

      await tester.pumpWidget(MaterialApp(
        home: FredawEntryScreen(
          entry: const FreDawEntry(
            term: 'VERSET',
            definition: 'Voir Jean 3:16 en entier.',
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.widget<Text>(find.text('Voir Jean 3:16 en entier.'));
      final spans = _flatten(paragraph.textSpan! as TextSpan);
      final jean = spans.singleWhere((s) => s.text == 'Jean');
      expect(jean.recognizer, isNotNull,
          reason: 'the dictionary word « Jean » stays a link');
      expect(spans.any((s) => s.text == 'Jean 3:16'), isFalse,
          reason: 'the reference itself is not a single linked span');
    });
  });
}

List<TextSpan> _flatten(TextSpan span) => [
      span,
      for (final child in span.children ?? const <InlineSpan>[])
        ..._flatten(child as TextSpan),
    ];