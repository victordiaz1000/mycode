import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/chapter.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// L'interlinéaire de l'ATI, tel qu'il doit paraître dans le lecteur :
/// Genèse 1:1-2 en colonnes de mots, de droite à gauche, aligné en lignes
/// — et non la ligne de gloses aplatie, que la tuile ne pose plus pour
/// cette version.
///
/// **Le chemin est celui du lecteur** : `ChapterVerseList`, pas un
/// `VerseTile` posé nu. C'est la liste qui pose le thème de lecture — la
/// police de lecture (Crimson Pro par défaut), le corps, la gouttière — et le
/// panneau arrondi sur lequel les versets se lisent. Un `VerseTile` isolé
/// hérite du `MaterialApp` nu, c'est-à-dire de Roboto : la suite ne charge pas
/// cette famille et `flutter test` dessine alors chaque glyphe en carré plein,
/// d'où un PNG qui ne jugeait rien du tout.
///
/// Un golden et non un détail de tracé : ce qui est jugé ici est l'image —
/// le sens de lecture, l'alignement des cinq lignes d'une colonne à l'autre,
/// les filets, les couleurs de la source (glose rouge, étiquette verte, Strong
/// bleu), le retour à la ligne sur un écran de téléphone.
///
/// Se régénère par
/// `flutter test --update-goldens test/ati_interlinear_golden_test.dart`.

/// Genèse 1:1, copiée depuis `ATI/json/1.json` (comme dans
/// `ati_format_test.dart`) : les tables `cg` / `ca` sont résolues d'avance,
/// le modèle ne voit que des libellés.
const motsVerset1 = [
  AtiWord(
    strong: 'H7225',
    translit: 'bə·rê·šîṯ',
    hebrew: 'בְּרֵאשִׁ֖ית',
    gloss: 'En un commencement',
    grammar: 'Nom',
    analysis: 'Nom commun· féminin singulier· état absolu— Préposition',
    note: 'n12',
  ),
  AtiWord(
    strong: 'H1254',
    translit: 'bā·rā',
    hebrew: 'בָּרָ֣א',
    gloss: 'créa',
    grammar: 'Verbe',
    analysis: 'Verbe qal parfait (qatal)· 3ᵉ masculin singulier',
  ),
  AtiWord(
    strong: 'H430',
    translit: '’ĕ·lō·hîm;',
    hebrew: 'אֱלֹהִ֑ים',
    gloss: 'Dieu',
    grammar: 'Nom',
    analysis: 'Nom commun· masculin pluriel· état absolu',
  ),
  AtiWord(
    strong: 'H853',
    translit: '’êṯ',
    hebrew: 'אֵ֥ת',
    gloss: '*',
    grammar: 'Accusatif',
    analysis: 'Particule marqueur d’objet direct',
    note: 'r2',
  ),
  AtiWord(
    strong: 'H8064',
    translit: 'haš·šā·ma·yim',
    hebrew: 'הַשָּׁמַ֖יִם',
    gloss: 'les cieux',
    grammar: 'Nom',
    analysis:
        'Nom commun· masculin pluriel· état absolu— '
        'Particule article défini',
  ),
  AtiWord(
    strong: 'H853',
    translit: 'wə·’êṯ',
    hebrew: 'וְאֵ֥ת',
    gloss: 'et -',
    grammar: 'Accusatif',
    analysis: 'Particule marqueur d’objet direct— Conjonction',
  ),
  AtiWord(
    strong: 'H776',
    translit: 'hā·’ā·reṣ.',
    hebrew: 'הָאָֽרֶץ׃',
    gloss: 'la terre.',
    grammar: 'Nom',
    analysis:
        'Nom commun· féminin et masculin singulier· état absolu— '
        'Particule article défini',
  ),
];

const motsVerset2 = [
  AtiWord(
    strong: 'H776',
    translit: 'wə·hā·’ā·reṣ,',
    hebrew: 'וְהָאָ֗רֶץ',
    gloss: 'Et la terre',
    grammar: 'Nom',
    analysis:
        'Nom commun· féminin et masculin singulier· état absolu— '
        'Particule article défini',
  ),
  AtiWord(
    strong: 'H1961',
    translit: 'hā·yə·ṯāh',
    hebrew: 'הָיְתָ֥ה',
    gloss: 'était',
    grammar: 'Verbe',
    analysis: 'Verbe qal parfait (qatal)· 3ᵉ masculin singulier',
  ),
];

const verset1 = Verse(
  verse: '1:1',
  text: 'En un commencement créa Dieu les cieux et la terre.',
  textWithNotes: 'En un commencement créa Dieu les cieux et la terre.',
  mots: motsVerset1,
);

const verset2 = Verse(
  verse: '1:2',
  text: 'Et la terre était',
  textWithNotes: 'Et la terre était',
  mots: motsVerset2,
);

/// Les familles que ce golden juge, et qu'aucune autre suite ne charge :
/// Cardo compose l'hébreu, Crimson Pro — police de lecture par défaut de
/// l'écran (`app_preferences.dart`, repli de `reading.fontFamily`) — compose
/// les champs latins, et MaterialIcons dessine la flèche du renvoi de
/// glossaire. Sans elles, `flutter test` dessine chaque glyphe en carré plein :
/// le PNG montre des blocs au lieu de lettres, et ne juge rien.
///
/// Le chargement est ici plutôt que dans `flutter_test_config.dart` : la
/// suite partagée ne charge que les familles dont l'interface dépend, pour ne
/// pas payer ~15 Mo à chaque fichier de test.
Future<void> _chargerPolicesDuGolden() async {
  const familles = {'Cardo', 'Crimson Pro', 'MaterialIcons'};
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final famille = entry['family'] as String;
    if (!familles.contains(famille)) continue;
    final loader = FontLoader(famille);
    for (final font
        in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  testWidgets('Genèse 1:1-2 en colonnes de mots, sur un écran de téléphone', (
    tester,
  ) async {
    // `runAsync` : le chargement de police lit de vrais fichiers, et une
    // boucle *fake async* de `testWidgets` ne laisse jamais ces futures se
    // terminer — d'où un blocage sans erreur ni échec.
    await tester.runAsync(_chargerPolicesDuGolden);

    // Largeur de téléphone : le retour à la ligne des colonnes fait partie
    // de ce que l'image juge. Assez haut pour que le panneau tienne debout.
    tester.view.physicalSize = const Size(390, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BibleThemeScope(
          child: Scaffold(
            backgroundColor: const Color(0xFFFAF7F0),
            body: ChapterVerseList(
              chapter: const Chapter(chapter: 1, verses: [verset1, verset2]),
              showNotes: false,
              theme: bibleThemes.first,
            ),
          ),
        ),
      ),
    );
    // `pump()` et non `pumpAndSettle()` : BibleThemeScope tient un ticker de
    // transition de thème, que rien ne vient clore ici — le settle tournerait
    // jusqu'au timeout, comme le test SEF l'évite déjà.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/ati_interlinear.png'),
    );
  });
}
