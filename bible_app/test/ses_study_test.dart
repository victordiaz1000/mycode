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

/// En lecture Septante (SEF), la feuille d'étude ouvre son Lexique — et sur
/// le corpus grec SES quand il est téléchargé : même texte grec, même
/// versification.
void main() {
  /// Un livre SES tel que `SES/ses_to_json.py` l'écrit : mots grecs avec
  /// Strong, sans français.
  Map<String, dynamic> sesBook() => {
        'bym_index': 1,
        'standard': 1,
        'book': 'Genèse',
        'osis_id': 'Gen',
        'ca': ['Nature: préposition'],
        'cg': ['PREP'],
        'chapters': [
          {
            'chapter': 1,
            'verses': [
              {
                'verse': 1,
                'words': [
                  {'m': 'Ἐν', 's': 'G1722', 'g': 0, 'a': 0},
                ],
              },
            ],
          },
        ],
      };

  /// Un chapitre SEF minimal : le français affiché et sa ligne grecque.
  Map<String, dynamic> sefBook() => {
        'translation': 'Septuaginta',
        'abbreviation': 'SEF',
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
                'text': 'Au commencement.',
                'grec': 'Ἐν ἀρχῇ.',
              },
            ],
          },
        ],
      };

  setUp(() {
    LocalRepository.useBundle(FakeBibleBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle({
      'G1722': 'Définition test de G1722.',
    }));
    FreDawLexicon.useBundle(FakeFreDawBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpSeptante(
    WidgetTester tester, {
    Map<String, Map<int, Map<String, dynamic>>>? books,
    required String registre,
    VoidCallback? onOpenLibrary,
  }) async {
    SharedPreferences.setMockInitialValues({'library.installed': registre});
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          initialVersionCode: 'SEF',
          store: FakeStore(books ??
              {
                'SEF': {1: sefBook()},
                'SES': {1: sesBook()},
              }),
          onOpenLibrary: onOpenLibrary,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets("en SEF, la feuille d'étude ouvre le lexique", (tester) async {
    await pumpSeptante(tester, registre: '{"SEF":[1],"SES":[1]}');

    await tester.tap(find.text('Au commencement.'));
    await tester.pumpAndSettle();

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

  testWidgets("en SEF, l'étude s'ouvre sur le corpus grec SES", (tester) async {
    await pumpSeptante(tester, registre: '{"SEF":[1],"SES":[1]}');

    await tester.tap(find.text('Au commencement.'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Lexique & Dictionnaire — verset mot à mot'),
    );
    await tester.pumpAndSettle();

    // Le corpus en vigueur est la SES, et les cartes portent ses codes grecs.
    expect(find.text('SES'), findsOneWidget);
    expect(find.text('Définition - G1722'), findsOneWidget);
    expect((await EtudePreferences.load()).versionCode, 'SES');

    // Et le sélecteur ne connaît qu'elle : la SEF n'a que son propre corpus.
    await tester.tap(find.byTooltip('Corpus du lexique'));
    await tester.pumpAndSettle();
    expect(find.text('SES — Septuaginta grec + Strong'), findsOneWidget);
    expect(find.text('LSS — Segond Louis + Strong'), findsNothing);
    expect(find.text('DBS — Darby + Strong'), findsNothing);
  });

  testWidgets(
      "sans SES téléchargée, le lexique invite vers la Bibliothèque",
      (tester) async {
    var opened = 0;
    await pumpSeptante(
      tester,
      books: {
        'SEF': {1: sefBook()},
      },
      registre: '{"SEF":[1]}',
      onOpenLibrary: () => opened++,
    );

    await tester.tap(find.text('Au commencement.'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.text('Lexique & Dictionnaire — verset mot à mot'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Corpus grec manquant'), findsOneWidget);
    expect(find.text('Lexique hébreu & grec'), findsNothing);

    await tester.tap(find.text('Bibliothèque'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });
}
