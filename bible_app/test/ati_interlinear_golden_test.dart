import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// L'interlinéaire de l'ATI, tel qu'il doit paraître dans le lecteur :
/// Genèse 1:1-2 en colonnes de mots, de droite à gauche, hébreu Cardo au-dessus
/// des gloses — et non plus la ligne de gloses aplatie, que la tuile ne pose
/// plus pour cette version.
///
/// Un golden et non un détail de tracé : ce qui est jugé ici est l'image —
/// le sens de lecture, l'alignement des lignes d'hébreu, la tenue du retour
/// à la ligne sur un écran de téléphone, la lisibilité des quatre niveaux.
///
/// Se régénère par
/// `flutter test --update-goldens test/ati_interlinear_golden_test.dart`.

/// Genèse 1:1-2, copiés depuis `ATI/json/1.json` (comme dans
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
    analysis: 'Nom commun· masculin pluriel· état absolu— '
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
    analysis: 'Nom commun· féminin et masculin singulier· état absolu— '
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
    analysis: 'Nom commun· féminin et masculin singulier· état absolu— '
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

/// Cardo ne fait pas partie des deux familles que la suite charge d'office
/// (`flutter_test_config.dart`) : ici elle est indispensable, puisque c'est
/// elle qui compose l'hébreu — sans elle le golden jugerait des carrés.
Future<void> _chargerCardo() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    if (entry['family'] != 'Cardo') continue;
    final loader = FontLoader('Cardo');
    for (final font in (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

void main() {
  testWidgets('Genèse 1:1-2 en colonnes de mots, sur un écran de téléphone',
      (tester) async {
    // `runAsync` : le chargement de police lit de vrais fichiers, et une
    // boucle *fake async* de `testWidgets` ne laisse jamais ces futures se
    // terminer — d'où un blocage sans erreur ni échec.
    await tester.runAsync(_chargerCardo);

    // Largeur de téléphone : le retour à la ligne des colonnes fait partie
    // de ce que l'image juge.
    tester.view.physicalSize = const Size(390, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BibleThemeScope(
          child: Scaffold(
            backgroundColor: const Color(0xFFFAF7F0),
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  VerseTile(
                    verse: const Verse(
                      verse: '1:1',
                      text: 'En un commencement créa Dieu les cieux et la terre.',
                      textWithNotes:
                          'En un commencement créa Dieu les cieux et la terre.',
                      mots: motsVerset1,
                    ),
                    showNotes: false,
                    verseNumber: 1,
                    theme: bibleThemes.first,
                  ),
                  VerseTile(
                    verse: const Verse(
                      verse: '1:2',
                      text: 'Et la terre était',
                      textWithNotes: 'Et la terre était',
                      mots: motsVerset2,
                    ),
                    showNotes: false,
                    verseNumber: 2,
                    theme: bibleThemes.first,
                  ),
                ],
              ),
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
