import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'reader_version_test.dart' show FakeStore;
import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';
import 'version_repository_test.dart' show getbibleBook;

/// En lecture Darby, la feuille d'étude ouvre son Lexique — grisé avant, il
/// ne l'est plus — et l'étude s'ouvre sur le corpus Darby quand il est
/// téléchargé : le corpus suit la version lue.
void main() {
  /// Un livre DBS tel que `DBS/dbs_to_json.py` l'écrit : schéma getbible nu,
  /// codes Strong inline dans le texte.
  Map<String, dynamic> dbsBook() => {
        'translation': 'Darby + Strong',
        'abbreviation': 'DBS',
        'lang': 'fr',
        'nr': 1,
        'name': 'Genèse',
        'chapters': [
          {
            'chapter': 1,
            'name': 'Genèse 1',
            'verses': [
              {
                'chapter': '1',
                'verse': '1',
                'name': 'Genèse 1:1',
                'text': 'Au commencement H7225 Dieu H0430 créa.',
              },
            ],
          },
        ],
      };

  setUp(() {
    // Les deux Darby sur l'appareil : le registre tel que la Bibliothèque
    // l'écrit, les textes dans le faux store.
    SharedPreferences.setMockInitialValues({
      'library.installed': '{"DBY":[1],"DBS":[1]}',
    });
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpDarby(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          initialVersionCode: 'DBY',
          store: FakeStore({
            'DBY': {1: getbibleBook(1)},
            'DBS': {1: dbsBook()},
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("en Darby, la feuille d'étude ouvre le lexique", (tester) async {
    await pumpDarby(tester);

    await tester.tap(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();

    // La feuille s'ouvre, et son bouton Lexique est actif — plus de ligne
    // « Disponible depuis le texte BYM. ».
    expect(find.text('Références'), findsOneWidget);
    final bouton = tester.widget<OutlinedButton>(find.widgetWithText(
      OutlinedButton,
      'Lexique & Dictionnaire — verset mot à mot',
    ));
    expect(bouton.onPressed, isNotNull);
    expect(find.text('Disponible depuis le texte BYM.'), findsNothing);
  });

  testWidgets("en Darby, l'étude s'ouvre sur le corpus Darby", (tester) async {
    await pumpDarby(tester);

    await tester.tap(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Lexique & Dictionnaire — verset mot à mot'),
    );
    await tester.pumpAndSettle();

    // Le corpus en vigueur est la DBS, et les cartes portent ses codes : le
    // verset est découpé sur les mots darbyens, pas sur le Segond.
    expect(find.text('DBS'), findsOneWidget);
    expect(find.text('Définition - H7225'), findsOneWidget);

    // Le choix est enregistré : la navigation précédent / suivant le relit
    // sans rouvrir l'écran, comme tout autre corpus.
    expect((await EtudePreferences.load()).versionCode, 'DBS');
  });
}
