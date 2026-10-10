import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/models/lsgs.dart';
import 'package:bible_app/screens/etude_verset_screen.dart';

import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';
import 'support/memory_dictionary_store.dart';

void main() {
  setUp(() {
    // L'écran lit `EtudePreferences` (corpus du lexique) dès son ouverture.
    SharedPreferences.setMockInitialValues({});
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
  });
  tearDown(() {
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<LsgsToken> tokens = const [
      LsgsToken(text: 'Au ', strong: null),
      LsgsToken(text: 'commencement ', strong: 'H7225'),
      LsgsToken(text: 'ABBA ', strong: null),
      LsgsToken(text: 'Dieu.', strong: 'H0430'),
    ],
    MemoryDictionaryStore? dictionaryStore,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: EtudeVersetScreen(
        bookIndex: 1,
        chapter: 1,
        verseNumber: 1,
        tokens: tokens,
        dictionaryStore: dictionaryStore,
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('lexique mode shows the word-by-word verse and Strong cards',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Genèse 1:1'), findsOneWidget);
    expect(find.text('Lexique hébreu & grec'), findsOneWidget);

    // The verse is rendered word-by-word with tappable Strong words.
    expect(find.text('commencement'), findsWidgets);
    expect(find.text('Dieu.'), findsWidgets);

    // The first Strong card shows the definition of the selected word.
    expect(find.text('Définition - H7225'), findsOneWidget);
    expect(find.textContaining('Définition test de H7225'), findsWidgets);
  });

  testWidgets('the study sheet offers a choice of Strong corpus',
      (tester) async {
    await pumpScreen(tester);

    // Le corpus en vigueur tient dans l'AppBar, sous son code.
    expect(find.text('LSS'), findsOneWidget);
    expect(find.byTooltip('Corpus du lexique'), findsOneWidget);

    await tester.tap(find.byTooltip('Corpus du lexique'));
    await tester.pumpAndSettle();

    // Il n'y en a que deux : ceux que `tokensFor` sait lire. Proposer le
    // catalogue entier serait trompeur, une version sans ancre Strong
    // retombant en silence sur la LSGS.
    expect(find.text('Corpus du lexique'), findsOneWidget);
    expect(find.text('LSS — Segond Louis + Strong'), findsOneWidget);
    expect(find.text('LSGS — Segond 1910 + Strongs'), findsOneWidget);

    await tester.tap(find.text('LSGS — Segond 1910 + Strongs'));
    await tester.pumpAndSettle();

    expect(find.text('LSGS'), findsOneWidget);
    expect(find.text('LSS'), findsNothing);
  });

  testWidgets('tapping a Strong word shows its card', (tester) async {
    await pumpScreen(tester);

    // « Dieu. » is the second Strong word (index 1): tap it.
    await tester.tap(find.text('Dieu.').first);
    await tester.pumpAndSettle();

    expect(find.text('Définition - H0430'), findsOneWidget);
    expect(find.textContaining('Définition test de H0430'), findsWidgets);
  });

  testWidgets('a word the translation does not render shows its code',
      (tester) async {
    // La LSS numérote les particules que le français ne rend pas : le token
    // porte `text: ""`, il ne reste que le code. Il s'affichait alors dans une
    // pilule vide — invisible, mais cliquable. Le code prend sa place.
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'H4191': 'Définition test de H4191.',
      'H8799': 'Définition test de H8799.',
    }));
    addTearDown(StrongLexicon.useRootBundle);

    await pumpScreen(
      tester,
      tokens: const [
        LsgsToken(text: 'Béla ', strong: null),
        LsgsToken(text: 'mourut ', strong: 'H4191'),
        LsgsToken(text: '', strong: 'H8799'),
        LsgsToken(text: '; et Jobab', strong: null),
      ],
    );

    // Le code est à la place du mot : la pilule vide a disparu, le verset
    // porte bien le code à l'endroit où le mot manque.
    expect(find.text(''), findsNothing);
    expect(find.text('H8799'), findsWidgets);

    // Il ouvre sa carte, qui dit que ce mot n'a pas d'équivalent français.
    await tester.tap(find.text('H8799').first);
    await tester.pumpAndSettle();

    expect(find.text('Définition - H8799'), findsOneWidget);
    expect(
      find.textContaining('la traduction ne rend pas'),
      findsOneWidget,
    );
  });

  testWidgets('a code the lexicon does not hold is named, never blank',
      (tester) async {
    // Les codes hébreux de la numérotation étendue ont désormais une fiche —
    // reste la plage grecque (G5625+), que ni le lexique embarqué ni aucune
    // source trouvée ne couvrent : la carte doit le dire, avec le code.
    await pumpScreen(
      tester,
      tokens: const [LsgsToken(text: '', strong: 'G5719')],
    );

    expect(find.text('G5719'), findsWidgets);
    expect(find.text('Sans équivalent français - G5719'), findsOneWidget);
    expect(
      find.textContaining('numérotation étendue de Biblia'),
      findsOneWidget,
    );
  });

  testWidgets('the card lays the source outline out as an indented tree',
      (tester) async {
    // The card used to flatten every sense into its own « 1) », « 2) » line.
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'H7225': {
        'strong': 'H7225',
        'language': 'hebrew',
        'lemma': 'רֵאשִׁית',
        'definition': 'Définition test de H7225.',
        'senses': ['commencement'],
        'outline': [
          {'level': 0, 'kind': 'sense', 'text': 'commencement'},
          {'level': 0, 'kind': 'header', 'label': 'Qal', 'text': ''},
          {'level': 1, 'kind': 'number', 'text': '1a1) commencement du monde'},
        ],
      },
      'H0430': 'Définition test de H0430.',
    }));
    addTearDown(StrongLexicon.useRootBundle);

    await pumpScreen(tester);

    expect(find.text('Définition - H7225'), findsOneWidget);
    expect(find.text('(Qal)', findRichText: true), findsOneWidget);
    expect(find.text('1a1) commencement du monde', findRichText: true),
        findsOneWidget);
    // The source's own codes have taken the card's numbering over.
    expect(find.text('1) commencement', findRichText: true), findsNothing);

    final stem = tester.getTopLeft(find.text('(Qal)', findRichText: true));
    final rung = tester
        .getTopLeft(find.text('1a1) commencement du monde', findRichText: true));
    expect(rung.dx, greaterThan(stem.dx),
        reason: '« 1a1) » s’indente d’un cran sous « (Qal) »');
    expect(rung.dy, greaterThan(stem.dy),
        reason: 'le rung est sous son stem, pas à côté');
  });

  testWidgets('a word carrying two Strong codes shows a card for each',
      (tester) async {
    // Jean 18.35 : le même mot du corpus porte « G3588 G4674 ». Les deux
    // codes avaient pour adresse la chaîne entière — introuvable — et la
    // carte affichait « non disponible dans le lexique embarqué ».
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'G3588': {
        'strong': 'G3588',
        'language': 'greek',
        'lemma': 'ὁ, ἡ, τό',
        'definition': 'Définition test de G3588.',
      },
      'G4674': {
        'strong': 'G4674',
        'language': 'greek',
        'lemma': 'σός, σή, σόν',
        'definition': 'Définition test de G4674.',
      },
      'G1484': 'Définition test de G1484.',
    }));
    addTearDown(StrongLexicon.useRootBundle);

    await pumpScreen(
      tester,
      tokens: const [
        LsgsToken(text: 'τὰ ', strong: 'G3588 G4674'),
        LsgsToken(text: 'nation ', strong: 'G1484'),
      ],
    );

    expect(find.textContaining('non disponible'), findsNothing);
    expect(find.text('Définition - G3588'), findsOneWidget);
    expect(find.text('Définition - G4674'), findsOneWidget);
  });

  testWidgets('the card writes the Hebrew word in its own serif',
      (tester) async {
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'H7225': {
        'strong': 'H7225',
        'language': 'hebrew',
        'lemma': 'רֵאשִׁית',
        'definition': 'Définition test de H7225.',
      },
      'H0430': 'Définition test de H0430.',
    }));
    addTearDown(StrongLexicon.useRootBundle);

    await pumpScreen(tester);

    // La carte est la référence que la fiche suit : serif de la plateforme,
    // 26 pt, gras, sans espacement, mot hébreu lu de droite à gauche.
    final mot = tester.widget<Text>(find.text('רֵאשִׁית'));
    expect(mot.style?.fontFamily, 'serif');
    expect(mot.style?.fontWeight, FontWeight.w700);
    expect(mot.style?.fontSize, 26);
    expect(mot.style?.letterSpacing, isNull);
    expect(mot.textAlign, TextAlign.left);
    expect(_directionsOf(tester, find.text('רֵאשִׁית')),
        contains(TextDirection.rtl));

    // Le mot court sur toute la largeur de la carte, calé à gauche.
    final rect = tester.getRect(find.text('רֵאשִׁית'));
    final carte = tester.getRect(find.byKey(const Key('etude-card-0')));
    expect(rect.width, greaterThan(carte.width - 60),
        reason: 'le mot court sur toute la largeur de la carte');
    expect(rect.left, lessThan(carte.center.dx),
        reason: 'le mot reste calé à gauche, comme ses lignes');
  });

  testWidgets('dictionnaire mode links dictionary terms of the verse',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();

    // The subtitle switches, and the ABBA token of the verse is now a
    // dictionary card (the FreDAW fake knows ABBA).
    expect(find.text('Dictionnaire'), findsWidgets);
    expect(find.text('ABBA'), findsWidgets);
    expect(find.textContaining('Définition test FreDAW de ABBA'),
        findsOneWidget);

    // The full-article link is present on the dico card.
    expect(find.text('Ouvrir la fiche complète →'), findsOneWidget);
  });

  testWidgets('the study sheet offers a choice of dictionary', (tester) async {
    // Le Glossaire Martin a été téléchargé depuis la Bibliothèque : il doit
    // rejoindre le Westphal embarqué dans le sélecteur.
    final store = MemoryDictionaryStore({
      'GBM': {
        'entries': {'ABBA': 'Père, en araméen — définition Glossaire Martin.'},
      },
    });
    await pumpScreen(tester, dictionaryStore: store);

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();

    // Le dictionnaire en vigueur — le Westphal — tient dans l'AppBar, sous
    // son code, comme le corpus du lexique tient dans l'autre onglet.
    expect(find.text('FREDAW'), findsOneWidget);
    expect(find.byTooltip('Dictionnaire de l\'étude'), findsOneWidget);

    await tester.tap(find.byTooltip('Dictionnaire de l\'étude'));
    await tester.pumpAndSettle();

    // Deux sortes : l'embarqué, et ce que la Bibliothèque a téléchargé. Le
    // Strong français n'y est pas — indexé par numéro et non par mot, il ne
    // pourrait trouver aucun terme dans un verset : sa place est le Lexique.
    expect(find.text('Dictionnaire de l\'étude'), findsOneWidget);
    expect(find.text('Westphal 1932'), findsOneWidget);
    expect(find.text('Glossaire Martin 1744'), findsOneWidget);
    expect(find.text('Dictionnaire Strong français'), findsNothing);

    await tester.tap(find.text('Glossaire Martin 1744'));
    await tester.pumpAndSettle();

    // Le verset est reconstruit sur le dictionnaire choisi : c'est sa
    // définition qui sert la carte, plus celle de Westphal.
    expect(find.text('GBM'), findsOneWidget);
    expect(find.text('FREDAW'), findsNothing);
    expect(find.textContaining('définition Glossaire Martin'), findsOneWidget);
    expect(find.textContaining('Définition test FreDAW'), findsNothing);

    // Le choix est enregistré, comme le corpus du lexique : il tient d'une
    // ouverture de l'écran à l'autre.
    final prefs = await EtudePreferences.load();
    expect(prefs.dictionaryCode, 'GBM');
  });

  testWidgets('a downloaded dictionary opens its own full-article screen',
      (tester) async {
    final store = MemoryDictionaryStore({
      'GBM': {
        'entries': {'ABBA': 'Père, en araméen — définition Glossaire Martin.'},
      },
    });
    await pumpScreen(
      tester,
      dictionaryStore: store,
      tokens: const [LsgsToken(text: 'ABBA', strong: null)],
    );

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Dictionnaire de l\'étude'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Glossaire Martin 1744'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fiche complète du dictionnaire'));
    await tester.pumpAndSettle();

    // La fiche d'un téléchargement porte le nom de son dictionnaire — la
    // fiche Westphal, elle, ne nomme que FreDAW. C'est aussi la preuve que
    // la bonne famille d'écran a été ouverte.
    expect(find.text('Glossaire Martin 1744'), findsWidgets);
    expect(find.textContaining('définition Glossaire Martin'), findsWidgets);
  });

  testWidgets(
      'a dictionary deleted from the Bibliothèque falls back to Westphal',
      (tester) async {
    // L'utilisateur avait choisi le Glossaire Martin, puis la Bibliothèque a
    // retiré le fichier. Le choix reste enregistré — il revient seul quand
    // le fichier revient — mais l'écran s'ouvre sur ce qui a encore du texte.
    SharedPreferences.setMockInitialValues({'etude.dictionnaireCode': 'GBM'});
    await pumpScreen(tester, dictionaryStore: MemoryDictionaryStore());

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();

    expect(find.text('FREDAW'), findsOneWidget);
    expect(find.textContaining('Définition test FreDAW de ABBA'),
        findsOneWidget);
  });

  testWidgets('verse navigation loads the neighbouring verse tokens',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EtudeVersetScreen(
        bookIndex: 1,
        chapter: 1,
        verseNumber: 1,
        tokens: const [
          LsgsToken(text: 'Premier ', strong: 'H7225'),
        ],
        verseNumbers: const [1, 2],
        loadVerseTokens: (v) async => [
          if (v == 1) const LsgsToken(text: 'Premier ', strong: 'H7225'),
          if (v == 2) const LsgsToken(text: 'Second verset.'),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Verset précédent'), findsNothing);
    expect(find.text('Verset suivant'), findsOneWidget);

    await tester.tap(find.text('Verset suivant'));
    await tester.pumpAndSettle();

    // The reference updates and the second verse's (plain) text replaces it.
    expect(find.text('Genèse 1:2'), findsOneWidget);
    expect(find.textContaining('Second verset'), findsWidgets);
    expect(find.text('Verset précédent'), findsOneWidget);
  });

  testWidgets('a verse without Strong words keeps the lexicon cards empty',
      (tester) async {
    await pumpScreen(
      tester,
      tokens: const [
        LsgsToken(text: 'Texte sans code Strong.'),
      ],
    );

    expect(find.textContaining('aucun mot associé à un numéro Strong'),
        findsOneWidget);
  });

  /// Paysage : Android empile ses boutons de navigation sur un côté (la
  /// droite, ici 60 px logiques) et l'écran passe dessous.
  ///
  /// L'`AppBar` écoute déjà `MediaQuery.padding` — d'où la flèche et le⋮
  /// toujours visibles sur les captures — mais le corps, lui, n'est dans
  /// aucun `SafeArea` et file jusqu'au bord de l'écran. Chaque zone scrollable
  /// doit donc tenir entre les deux insets, à droite comme à gauche.
  testWidgets('en paysage, le corps reste dans la zone sûre', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(800, 360),
          devicePixelRatio: 1,
          padding: EdgeInsets.only(left: 44, right: 60, top: 24),
        ),
        child: MaterialApp(
          home: EtudeVersetScreen(
            bookIndex: 1,
            chapter: 1,
            verseNumber: 1,
            tokens: const [
              LsgsToken(text: 'commencement ', strong: 'H7225'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollables = find.byType(SingleChildScrollView);
    expect(scrollables, findsWidgets,
        reason: 'La zone scrollable du corps a disparu du widget tree.');

    for (var i = 0; i < scrollables.evaluate().length; i++) {
      final box = tester.renderObject<RenderBox>(scrollables.at(i));
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(rect.left, greaterThanOrEqualTo(44),
          reason: 'Zone scrollable $i commence à ${rect.left} : elle passe '
              'sous l\'encoche de gauche (44 px), comme sous les boutons '
              'Android à droite.');
      expect(rect.right, lessThanOrEqualTo(800 - 60),
          reason: 'Zone scrollable $i finit à ${rect.right} : elle passe '
              'sous les boutons Android (à partir de 740).');
    }
  });

  /// Une seule carte étirée sur toute la largeur n'est pas une mise en page :
  /// dès que l'écran s'ouvre — paysage de téléphone puis tablette — la bande
  /// doit tenir plusieurs cartes à la fois. L'échelle est celle des Thèmes,
  /// 600 / 900 / 1200 ; le portrait de téléphone garde, lui, la carte presque
  /// pleine largeur avec l'arête de la suivante qui invite au glissement.
  testWidgets('les cartes se multiplient quand la largeur grandit',
      (tester) async {
    const quatre = <LsgsToken>[
      LsgsToken(text: 'commencement ', strong: 'H7225'),
      LsgsToken(text: 'Dieu ', strong: 'H0430'),
      LsgsToken(text: 'fils ', strong: 'G2316'),
      LsgsToken(text: 'principe ', strong: 'G0001'),
    ];
    // largeur → cartes attendues, tenues en entier dans la largeur
    const attentes = <int, int>{412: 1, 800: 2, 1000: 3, 1300: 4};

    addTearDown(tester.view.reset);
    for (final cas in attentes.entries) {
      tester.view.physicalSize = Size(cas.key.toDouble(), 640);
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: EtudeVersetScreen(
            bookIndex: 1,
            chapter: 1,
            verseNumber: 1,
            tokens: quatre,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tenues = <int>[];
      for (var i = 0; i < quatre.length; i++) {
        final carte = find.byKey(Key('etude-card-$i'));
        if (carte.evaluate().isEmpty) break;
        final box = tester.renderObject<RenderBox>(carte);
        final rect = box.localToGlobal(Offset.zero) & box.size;
        if (rect.left >= 0 && rect.right <= cas.key) tenues.add(i);
      }
      expect(tenues, hasLength(cas.value),
          reason: 'À ${cas.key} px, ${tenues.length} carte(s) '
              '(${tenues.map((i) => 'n°$i').join(', ')}) tiennent en entier '
              'dans la largeur, ${cas.value} attendue(s) : la largeur '
              'grandit, les colonnes doivent suivre.');
    }
  });

  testWidgets('la barre du bas marque le mode en cours', (tester) async {
    await pumpScreen(tester);

    // La pastille d'un onglet : le seul état qui change est sa couleur, ses
    // mesures sont celles du Padding qu'elle a remplacé.
    BoxDecoration decor(String libelle) {
      // La pastille est sous l'infobulle (`find.byTooltip` rend le
      // `RawTooltip` interne, pas le `Tooltip` de la barre) : on descend.
      final pastille = find
          .descendant(
            of: find.byTooltip(libelle),
            matching: find.byType(AnimatedContainer),
          )
          .first;
      return tester
          .widget<AnimatedContainer>(pastille)
          .decoration! as BoxDecoration;
    }

    expect(decor('Lexique').color, isNotNull,
        reason: 'le mode ouvert est surligné dans la barre');
    expect(decor('Dictionnaire').color, isNull,
        reason: 'les autres modes restent en retrait');

    await tester.tap(find.text('Dictionnaire'));
    await tester.pumpAndSettle();

    expect(decor('Lexique').color, isNull);
    expect(decor('Dictionnaire').color, isNotNull,
        reason: 'le surlignage suit la bascule de mode');
  });
}

/// Sens de lecture imposés au mot par les `Directionality` de ses ancêtres :
/// le mot hébreu doit en porter au moins un en RTL.
List<TextDirection> _directionsOf(WidgetTester tester, Finder of) => tester
    .widgetList<Directionality>(
      find.ancestor(of: of, matching: find.byType(Directionality)),
    )
    .map((directionality) => directionality.textDirection)
    .toList();