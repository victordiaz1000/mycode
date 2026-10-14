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

  /// Les deux Darby sur l'appareil : les textes dans le faux store.
  Map<String, Map<int, Map<String, dynamic>>> lesDeuxDarby() => {
        'DBY': {1: getbibleBook(1)},
        'DBS': {1: dbsBook()},
      };

  Future<void> pumpDarby(
    WidgetTester tester, {
    Map<String, Map<int, Map<String, dynamic>>>? books,
    required String registre,
    VoidCallback? onOpenLibrary,
  }) async {
    // Le registre tel que la Bibliothèque l'écrit — c'est lui qui dit si la
    // DBS est là, pas les textes du faux store.
    SharedPreferences.setMockInitialValues({'library.installed': registre});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          initialVersionCode: 'DBY',
          store: FakeStore(books ?? lesDeuxDarby()),
          onOpenLibrary: onOpenLibrary,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("en Darby, la feuille d'étude ouvre le lexique", (tester) async {
    await pumpDarby(tester, registre: '{"DBY":[1],"DBS":[1]}');

    await tester.tap(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();

    // La feuille s'ouvre, et son bouton Lexique est actif — plus de ligne
    // « Disponible depuis les textes BYM et Darby. ».
    expect(find.text('Références'), findsOneWidget);
    final bouton = tester.widget<OutlinedButton>(find.widgetWithText(
      OutlinedButton,
      'Lexique & Dictionnaire — verset mot à mot',
    ));
    expect(bouton.onPressed, isNotNull);
    expect(
      find.text('Disponible depuis les textes BYM et Darby.'),
      findsNothing,
    );
  });

  testWidgets("en Darby, l'étude s'ouvre sur le corpus Darby", (tester) async {
    await pumpDarby(tester, registre: '{"DBY":[1],"DBS":[1]}');

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

    // Et le sélecteur ne connaît que lui : la BYM reste la seule version à
    // disposer de tous les corpus.
    await tester.tap(find.byTooltip('Corpus du lexique'));
    await tester.pumpAndSettle();
    expect(find.text('DBS — Darby + Strong'), findsOneWidget);
    expect(find.text('LSS — Segond Louis + Strong'), findsNothing);
    expect(find.text('LSGS — Segond 1910 + Strongs'), findsNothing);
  });

  testWidgets(
      "sans DBS téléchargée, le lexique invite vers la Bibliothèque",
      (tester) async {
    var opened = 0;
    await pumpDarby(
      tester,
      books: {
        'DBY': {1: getbibleBook(1)},
      },
      registre: '{"DBY":[1]}',
      onOpenLibrary: () => opened++,
    );

    await tester.tap(find.text('Texte téléchargé 1:1.'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Lexique & Dictionnaire — verset mot à mot'),
    );
    await tester.pumpAndSettle();

    // Pas d'étude sur un autre texte : une invitation, nommée, vers
    // l'endroit où le téléchargement se fait.
    expect(find.text('Corpus Darby manquant'), findsOneWidget);
    expect(find.text('Lexique hébreu & grec'), findsNothing);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
