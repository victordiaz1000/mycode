import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/premium_style.dart';
import 'package:bible_app/widgets/study_sheet.dart';

/// The contract of the study sheet: what it applies, and when.
///
/// Surlignage and favori are toggles, not actions — they must reach the reader
/// the moment they are tapped. They used to be reported through the pop value,
/// which meant a colour picked and then closed saved nothing, and the favourite
/// star saved nothing at all (no action ever carried it). These tests hold that
/// line: every expectation below is checked **before** the sheet closes.
///
/// The last three hold a different line — that the sheet stays **legible** on
/// the pale and warm palettes, where card and page are within a few percent of
/// each other and an edge made of blur alone reads as a smudge.
void main() {
  tearDown(() {
    AppPreferences.themeNotifier.value = AppPreferences.defaultThemeId;
  });

  /// The colour a hex string paints, as the sheet builds it.
  Color painted(String hex) =>
      Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));

  /// The dot of [hex] in the open sheet.
  Finder colorDot(String hex) => find.byWidgetPredicate(
    (w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == painted(hex),
  );

  final amber = highlightColors.first;
  final green = highlightColors[1];

  /// Rapport de contraste WCAG entre deux couleurs opaques — la mesure de « on
  /// voit le bord ou pas », indépendante de la teinte du thème.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
  }

  /// La palette telle que la feuille ouverte la voit, lue depuis un contexte de
  /// la feuille : pas de dérivation dupliquée ici, sinon un changement de
  /// [premiumPalette] passerait sous le radar des tests.
  PremiumPalette paletteOf(WidgetTester tester) =>
      premiumPalette(tester.element(find.byTooltip('Effacer le surlignage')));

  /// La décoration de la grande carte « Surligner » : seule surface de la
  /// feuille à porter à la fois le fond des cartes et un rayon de 16 (les tuiles
  /// d'action tiennent leur fond d'un `Material`, pas d'une décoration).
  BoxDecoration highlightCard(WidgetTester tester, Color surface) =>
      tester
              .widget<Container>(
                find.byWidgetPredicate((w) {
                  if (w is! Container) return false;
                  final d = w.decoration;
                  return d is BoxDecoration &&
                      d.color == surface &&
                      d.borderRadius == BorderRadius.circular(16);
                }),
              )
              .decoration!
          as BoxDecoration;

  /// Opens the sheet over a bare screen, recording everything it reports.
  /// Returns the log of highlight calls, of favourite calls, and a one-slot
  /// holder for the action the sheet finally popped with.
  ///
  /// [themeId] par défaut le premier du catalogue, celui sur lequel la feuille
  /// retombe en l'absence de portée : les attentes existantes rendent donc
  /// exactement sous le même thème qu'avant.
  Future<(List<String?>, List<bool>, List<StudyAction?>)> pumpSheet(
    WidgetTester tester, {
    String? currentHighlight,
    bool isFavorite = false,
    bool lexiqueEnabled = true,
    String lexiqueLabel = 'Lexique & Dictionnaire — verset mot à mot',
    String? themeId,
  }) async {
    final highlights = <String?>[];
    final favorites = <bool>[];
    final popped = <StudyAction?>[];

    final id = themeId ?? bibleThemes.first.id;
    AppPreferences.themeNotifier.value = id;
    await tester.pumpWidget(
      BibleThemeScope(
        // Clé portant le thème : un second `pumpWidget` d'un `MaterialApp` non
        // clé réutiliserait l'Element — donc le `Navigator` et la feuille déjà
        // ouverte — et le « ouvrir » suivant taperait dans la barrière modale.
        child: MaterialApp(
          key: ValueKey(id),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped.add(
                    await showStudySheet(
                      context,
                      reference: 'Ge. 1:1',
                      excerpt: 'Au commencement…',
                      isFavorite: isFavorite,
                      currentHighlight: currentHighlight,
                      lexiqueEnabled: lexiqueEnabled,
                      lexiqueLabel: lexiqueLabel,
                      onHighlight: (color) async => highlights.add(color),
                      onFavorite: (value) async => favorites.add(value),
                    ),
                  );
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return (highlights, favorites, popped);
  }

  testWidgets('a colour is applied as it is tapped, not on close', (
    tester,
  ) async {
    final (highlights, _, popped) = await pumpSheet(tester);

    await tester.tap(colorDot(amber));
    await tester.pumpAndSettle();

    expect(highlights, [amber], reason: 'the verse is painted right away');
    expect(popped, isEmpty, reason: 'and the sheet stays open');
  });

  testWidgets('closing with the ✕ keeps the colour and reports no action', (
    tester,
  ) async {
    final (highlights, _, popped) = await pumpSheet(tester);
    await tester.tap(colorDot(green));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(highlights, [green]);
    expect(popped, [null], reason: 'nothing to navigate to');
  });

  testWidgets('tapping the active colour again clears it', (tester) async {
    final (highlights, _, _) = await pumpSheet(tester, currentHighlight: amber);

    await tester.tap(colorDot(amber));
    await tester.pumpAndSettle();

    expect(highlights, [
      null,
    ], reason: 'null is the clear, not an empty string');
  });

  testWidgets('the eraser clears an existing highlight', (tester) async {
    final (highlights, _, _) = await pumpSheet(tester, currentHighlight: green);

    await tester.tap(find.byTooltip('Effacer le surlignage'));
    await tester.pumpAndSettle();

    expect(highlights, [null]);
  });

  testWidgets('the eraser is dead when there is nothing to erase', (
    tester,
  ) async {
    // It used to fire anyway, which stored '' over a verse that had no
    // highlight — the amber-phantom path.
    final (highlights, _, _) = await pumpSheet(tester);

    final eraser = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.format_color_reset),
    );
    expect(eraser.onPressed, isNull);
    expect(highlights, isEmpty);
  });

  testWidgets('the favourite is saved without pressing any action', (
    tester,
  ) async {
    final (_, favorites, popped) = await pumpSheet(tester);

    // The sheet now carries 16 colour dots, pushing the action chips below the
    // test screen edge — bring the chip into view before hitting it.
    await tester.ensureVisible(find.text('Favori'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favori'));
    await tester.pumpAndSettle();

    expect(favorites, [true], reason: 'the star used to be lost on close');
    expect(find.text('Favori ✓'), findsOneWidget);
    expect(popped, isEmpty, reason: 'a toggle does not close the sheet');
  });

  testWidgets('an already-favourite verse can be un-favourited', (
    tester,
  ) async {
    final (_, favorites, _) = await pumpSheet(tester, isFavorite: true);

    expect(find.text('Favori ✓'), findsOneWidget);
    await tester.ensureVisible(find.text('Favori ✓'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favori ✓'));
    await tester.pumpAndSettle();

    expect(favorites, [false]);
  });

  testWidgets('an action closes the sheet and names itself', (tester) async {
    final (_, _, popped) = await pumpSheet(tester);

    // The grid overflows the test screen — the chip has to be brought into
    // view before it can be hit.
    await tester.ensureVisible(find.text('Copier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    expect(popped, [StudyAction.copy]);
  });

  testWidgets(
    'the Lexique button is off when the version cannot offer Strong',
    (tester) async {
      await pumpSheet(
        tester,
        lexiqueEnabled: false,
        lexiqueLabel: 'Lexique & Dictionnaire — versions BYM/LSGS',
      );

      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(
          OutlinedButton,
          'Lexique & Dictionnaire — versions BYM/LSGS',
        ),
      );
      expect(button.onPressed, isNull);
    },
  );

  /// Désactivé ne suffit pas : il faut que ça **se voie**. Le bouton gardait son
  /// liseré doré, son fond doré et son libellé doré en gras — seule l'icône
  /// grisait — donc il avait exactement l'air d'un bouton actif qui ne répond
  /// pas. Trois causes, toutes vérifiées ici parce qu'aucune ne se corrige en
  /// touchant `onPressed` :
  ///
  /// * `styleFrom(side:)` passe par `allOrNull` — un seul liseré pour tous les
  ///   états, désactivé compris ;
  /// * la couleur explicite du libellé l'emporte sur le `foregroundColor` du
  ///   bouton, donc le texte ignorait l'état ;
  /// * `disabledBackgroundColor` laissé nul retombe sur le défaut du thème.
  testWidgets('désactivé, le bouton Lexique se voit désactivé', (tester) async {
    const label = 'Lexique & Dictionnaire — version BYM';
    await pumpSheet(tester, lexiqueEnabled: false, lexiqueLabel: label);
    final p = paletteOf(tester);

    final style = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
        .style!;
    const off = <WidgetState>{WidgetState.disabled};

    expect(
      style.side!.resolve(off)!.color,
      isNot(p.primary),
      reason: 'le liseré doré est le signal d’un bouton actif',
    );
    expect(
      style.foregroundColor!.resolve(off),
      p.textGrey,
      reason: 'l’icône doit grisonner avec le reste, pas selon Material',
    );
    expect(
      style.backgroundColor!.resolve(off),
      Colors.transparent,
      reason: 'pas de fond teinté d’accent sur une action indisponible',
    );

    final text = tester.widget<Text>(find.text(label));
    expect(
      text.style!.color,
      p.textGrey,
      reason: 'le libellé porte sa couleur en dur : c’est lui qui trahissait',
    );

    // Et la raison, écrite : gris seul, le lecteur voit que c'est fermé sans
    // savoir pourquoi ni comment l'ouvrir.
    expect(find.text('Disponible depuis le texte BYM.'), findsOneWidget);
  });

  testWidgets('actif, il garde l’accent doré et ne s’excuse pas', (
    tester,
  ) async {
    await pumpSheet(tester);
    final p = paletteOf(tester);

    final style = tester
        .widget<OutlinedButton>(
          find.widgetWithText(
            OutlinedButton,
            'Lexique & Dictionnaire — verset mot à mot',
          ),
        )
        .style!;

    expect(style.side!.resolve(const <WidgetState>{})!.color, p.primary);
    expect(
      tester
          .widget<Text>(find.text('Lexique & Dictionnaire — verset mot à mot'))
          .style!
          .color,
      p.primary,
    );
    expect(find.text('Disponible depuis le texte BYM.'), findsNothing);
  });

  testWidgets('the Lexique button carries a precise name when enabled', (
    tester,
  ) async {
    await pumpSheet(tester);

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        'Lexique & Dictionnaire — verset mot à mot',
      ),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'the name tells the reader it opens the Strong rendering',
    );
  });

  // ---- Lisibilité de la carte « Surligner » sur les palettes claires ----

  testWidgets('la carte Surligner est délimitée par un liseré, sur chaque thème', (
    tester,
  ) async {
    // La carte prend `p.surface` sur une feuille en [premiumBackground] : deux
    // lerps du même ton de fond (58 % et 72 % de blanc). Sur les thèmes clairs
    // et chauds l'écart tombe à quelques pourcents — 1,5 % sur Brume, 2 % sur
    // Oliveraie, 8 % sur Sinaï — et son seul contour était une ombre de 12 px à
    // 5 % : un bord fait de flou, la carte se lisait comme une tache. Le liseré
    // est donc exigé sur les douze palettes, pas seulement celles qui gênaient.
    for (final theme in bibleThemes) {
      await pumpSheet(tester, themeId: theme.id);
      final p = paletteOf(tester);
      final deco = highlightCard(tester, p.surface);

      expect(
        deco.border,
        isNotNull,
        reason: 'aucun bord sur « ${theme.name} »',
      );
      final edge = (deco.border! as Border).top.color;
      expect(
        contrast(Color.alphaBlend(edge, p.surface), p.surface),
        greaterThan(1.2),
        reason: 'liseré indistinct du fond de la carte sur « ${theme.name} »',
      );
    }
  });

  testWidgets('une pastille non choisie porte un liseré neutre, pas le sien', (
    tester,
  ) async {
    // Les seize couleurs de surlignage sont des pastels clairs et la bordure
    // valait sa propre couleur à 55 % : autant dire rien. Seize disques sans
    // contour posés sur une carte crème, et la rangée entière paraissait hors
    // de mise au point.
    await pumpSheet(tester, themeId: 'sinai');
    final deco =
        tester.widget<Container>(colorDot(green)).decoration! as BoxDecoration;
    final edge = (deco.border! as Border).top;

    expect(edge.color, isNot(painted(green)));
    expect(
      contrast(Color.alphaBlend(edge.color, painted(green)), painted(green)),
      greaterThan(1.2),
      reason: 'la pastille n’a pas de bord visible sur son propre fond',
    );
  });

  testWidgets(
    'la pastille choisie porte l’anneau d’accent et une coche lisible',
    (tester) async {
      await pumpSheet(tester, themeId: 'sinai', currentHighlight: amber);
      final p = paletteOf(tester);
      final deco =
          tester.widget<Container>(colorDot(amber)).decoration!
              as BoxDecoration;
      final edge = (deco.border! as Border).top;

      expect(edge.color, p.primary, reason: 'le choix se marque à l’accent');
      expect(
        edge.width,
        greaterThan(1.5),
        reason: 'et plus épais que les autres',
      );

      // La coche était en blanc à 70 % : invisible sur un jaune pâle, la pastille
      // choisie ne se distinguait plus que par son anneau.
      final check = tester.widget<Icon>(
        find.descendant(
          of: colorDot(amber),
          matching: find.byIcon(Icons.check_rounded),
        ),
      );
      expect(
        contrast(
          Color.alphaBlend(check.color!, painted(amber)),
          painted(amber),
        ),
        greaterThan(4.5),
        reason: 'coche illisible sur un pastel clair',
      );
    },
  );
}
