import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/chapter.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// Rendu SEF dans la tuile du lecteur : la ligne grecque au-dessus du
/// français, la seconde traduction (la Bible d'Alexandrie) dessous — les
/// deux muets dès que le verset ne les porte pas, ce qui est le cas de
/// toutes les autres versions. Les pieds de page de la source ne sont pas
/// montrés : ils restent dans les fichiers.
///
/// Couleurs : le français en bleu, l'Alexandrie en vert, le grec dans la
/// couleur du corps — le dédoublement de la source (Biblia), dont c'est le
/// premier usage : deux françaises sous un même grec ne se lisent pas.
void main() {
  const grec = 'Ἐν ἀρχῇ ἐποίησεν ὁ θεὸς τὸν οὐρανὸν καὶ τὴν γῆν.';
  const text = 'Au commencement Dieu créa le ciel et la terre.';
  const alexandrie = 'Au commencement, Dieu fit le ciel et la terre.';
  final theme = bibleThemes.first;

  Future<void> pumpTile(WidgetTester tester, Verse verse) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: VerseTile(
                verse: verse,
                showNotes: false,
                verseNumber: 1,
                theme: bibleThemes.first,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
      'la ligne grecque passe au-dessus du français, l’Alexandrie dessous',
      (tester) async {
    await pumpTile(
      tester,
      const Verse(
        verse: '1:1',
        text: text,
        textWithNotes: text,
        grec: grec,
        alexandrie: alexandrie,
      ),
    );

    final greekY = tester.getCenter(find.text(grec)).dy;
    final textY = tester.getCenter(find.text(text)).dy;
    final alexY = tester.getCenter(find.text(alexandrie)).dy;

    expect(greekY, lessThan(textY),
        reason: 'le grec se lit avant le français, comme dans la source');
    expect(alexY, greaterThan(textY),
        reason: 'la seconde traduction ferme le verset sous la première');
  });

  testWidgets('un verset seul français ne dessine ni grec ni Alexandrie',
      (tester) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:2', text: text, textWithNotes: text),
    );

    expect(find.text(grec), findsNothing);
    expect(find.text(alexandrie), findsNothing);
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('chaque ligne porte sa couleur : bleu, vert, corps pour le grec',
      (tester) async {
    await pumpTile(
      tester,
      const Verse(
        verse: '1:1',
        text: text,
        textWithNotes: text,
        grec: grec,
        alexandrie: alexandrie,
      ),
    );

    expect(
      tester.widget<Text>(find.text(text)).style?.color,
      theme.sefMainTranslationColor,
      reason: 'le français principal prend le bleu de la source',
    );
    expect(
      tester.widget<Text>(find.text(alexandrie)).style?.color,
      theme.sefSecondTranslationColor,
      reason: 'la seconde traduction ferme le verset en vert',
    );
    final greekColor = tester.widget<Text>(find.text(grec)).style?.color;
    expect(
      greekColor,
      allOf(
        isNot(theme.sefMainTranslationColor),
        isNot(theme.sefSecondTranslationColor),
      ),
      reason: 'le grec est la ligne neutre : aucune couleur de traduction',
    );
  });

  testWidgets('un verset qui n\'est pas de la SEF garde la couleur du corps', (
    tester,
  ) async {
    await pumpTile(
      tester,
      const Verse(verse: '1:3', text: text, textWithNotes: text),
    );

    expect(
      tester.widget<Text>(find.text(text)).style?.color,
      isNot(theme.sefMainTranslationColor),
      reason: 'rien à distinguer : le français reste dans le corps',
    );
  });

  testWidgets('le texte continu rejoue le même dédoublement', (tester) async {
    const verset = Verse(
      verse: '1:1',
      text: text,
      textWithNotes: text,
      grec: grec,
      alexandrie: alexandrie,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: Scaffold(
            body: ChapterVerseList(
              chapter: const Chapter(chapter: 1, verses: [verset]),
              showNotes: false,
              layout: ReadingLayout.paragraph,
              theme: theme,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Le flux est un seul `RichText` : les lignes y sont des spans, pas des
    // `Text` — la couleur se lit au span, pas au widget.
    TextStyle? styleOf(InlineSpan span, String wanted) {
      if (span is! TextSpan) return null;
      if (span.text == wanted) return span.style;
      for (final child in span.children ?? const <InlineSpan>[]) {
        final found = styleOf(child, wanted);
        if (found != null) return found;
      }
      return null;
    }

    TextStyle? styleFor(String wanted) {
      for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
        final found = styleOf(rich.text, wanted);
        if (found != null) return found;
      }
      return null;
    }

    expect(
      styleFor(text)?.color,
      theme.sefMainTranslationColor,
      reason: 'le français principal prend le bleu de la source',
    );
    expect(
      styleFor(alexandrie)?.color,
      theme.sefSecondTranslationColor,
      reason: 'la seconde traduction ferme le verset en vert',
    );
    expect(
      styleFor(grec)?.color,
      allOf(
        isNot(theme.sefMainTranslationColor),
        isNot(theme.sefSecondTranslationColor),
      ),
      reason: 'le grec est la ligne neutre : aucune couleur de traduction',
    );
  });
}
