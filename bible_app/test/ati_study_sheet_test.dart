import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/widgets/ati_interlinear.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'reader_version_test.dart' show FakeStore;
import 'support/fake_bible_bundle.dart';

/// La feuille d'étude ne s'ouvre plus sur l'ATI : le tap sur le verset
/// n'ouvre rien, la fiche du mot étant la seule porte. Le témoin est la BYM,
/// où le même tap ouvre la feuille — sans lui, un tap raté donnerait le même
/// résultat qu'un verrou tenu.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    VersionRepository.clearCache();
  });

  /// Un livre ATI d'un chapitre et deux mots : la forme que `bookFromAti` lit
  /// telle quelle, sans rien inventer.
  Map<String, dynamic> atiBook() => {
        'bym_index': 1,
        'book': 'Genesis',
        'osis_id': 'Gen',
        'chapters': [
          {
            'chapter': 1,
            'verses': [
              {
                'verse': 1,
                'words': [
                  {
                    't': 'bə·rê·šîṯ',
                    'h': 'רֵאשִׁית',
                    'f': 'En un commencement',
                  },
                  {'t': 'ĕ·lō·hîm', 'h': 'אֱלֹהִים', 'f': 'Dieu'},
                ],
              },
            ],
          },
        ],
      };

  Future<void> pumpAti(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            initialVersionCode: 'ATI',
            store: FakeStore({
              'ATI': {1: atiBook()},
            }),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets("sur l'ATI, le tap verset n'ouvre rien", (tester) async {
    await pumpAti(tester);

    // L'interlinéaire est bien à l'écran : ce n'est pas une version manquante
    // qui rendrait le test muet.
    expect(find.byType(AtiInterlinear), findsOneWidget);

    // Le numéro de verset, hors des cellules de mots : c'est là que le tap
    // rejoint la tuile, et la feuille d'étude avec elle.
    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();

    expect(find.text('Références'), findsNothing);
    expect(
      find.text('Ge. 1:1'),
      findsNothing,
      reason: "aucune feuille ne s'ouvre sur un tap verset",
    );

    // Le témoin, dans la même lecture : le tap mot ouvre encore la fiche du
    // mot — c'est elle, la seule porte.
    await tester.tap(find.text('En un commencement'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ge. 1:1'),
      findsOneWidget,
      reason: 'la fiche du mot s’ouvre toujours',
    );
  });

  testWidgets("sur la BYM, le même tap ouvre la feuille d'étude", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 2)),
      ),
    );
    await tester.pumpAndSettle();

    // Chapitre 2 : pas d'en-tête de livre, le premier verset est à l'écran.
    await tester.tap(find.text('Verset de test Ge. 2:1.'));
    await tester.pumpAndSettle();

    expect(
      find.text('Références'),
      findsOneWidget,
      reason: "la feuille existe toujours — c'est l'ATI qui ne l'appelle plus",
    );
  });
}
