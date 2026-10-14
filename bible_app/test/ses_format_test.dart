import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_mapping.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Genèse 1:1 tel que `SES/ses_to_json.py` l'écrit — copié depuis
/// `SES/json/1.json`, pas reconstitué : le test verrouille le schéma
/// (grec + Strong + analyse, sans français) et le pont vers la lecture.
const Map<String, dynamic> genese1 = {
  'bym_index': 1,
  'standard': 1,
  'book': 'Genèse',
  'osis_id': 'Gen',
  'ca': [
    'Nature: préposition',
    'Nature: nom · Cas: datif · Nombre: singulier · Genre: féminin',
  ],
  'cg': ['PREP', 'N-DSF'],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            {'m': 'Ἐν', 's': 'G1722', 'g': 0, 'a': 0},
            {'m': 'ἀρχῇ', 's': 'G746', 'g': 1, 'a': 1},
          ],
        },
      ],
    },
  ],
};

void main() {
  group('canon de la SES', () {
    test('SES est téléchargeable, Ancien Testament seul, au format ati', () {
      final entry = versionByCode('SES');

      expect(entry, isNotNull);
      expect(entry!.availability, VersionAvailability.downloadable);
      expect(entry.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      expect(entry.otOnly, isTrue);
      expect(entry.ntOnly, isFalse);
      expect(entry.interlinear, isTrue, reason: 'grille de colonnes de mots');
      expect(entry.bookCount, 39);
      expect(entry.containsBook(1), isTrue, reason: 'Genèse');
      expect(entry.containsBook(39), isTrue, reason: 'Malachie');
      expect(entry.containsBook(40), isFalse, reason: 'Matthieu inexistant');
      expect(entry.canonOnly, 'l\'Ancien Testament');
      // Même signature que l'ATI, sortie du même logiciel.
      expect(entry.rights, contains('Biblia Universalis'));
      expect(
        entry.urlTemplate,
        'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/ses/{book}.json',
      );
      // Le drapeau décrit le texte aplati : sans glose française, aucun code
      // n'y est inséré — les numéros se cliquent dans les colonnes.
      expect(entry.hasStrong, isFalse);
      expect(entry.carriesNotes, isFalse);
      expect(entry.languageCode, 'FR');
    });

    test('le fichier servi suit la numérotation standard', () {
      final entry = versionByCode('SES')!;
      // BYM 38 = 1 Chroniques, standard 13 — le fichier SES/json/13.json.
      expect(bymToStandard(38), 13);
      expect(
        DownloadService.bookUri(entry, bymToStandard(38)).toString(),
        'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/ses/13.json',
      );
    });
  });

  group('lecture de la SES', () {
    test('un livre SES se lit en colonnes, sans ligne de texte', () {
      final book = bookFromAti(genese1, bymIndex: 1);

      expect(book.chapters, hasLength(1));
      final verse = book.chapters.first.verses.first;
      // Pas de français dans le corpus : la ligne aplatie est vide, et ce
      // sont les mots que le rendu interlinéaire pose en colonnes.
      expect(verse.text, isEmpty);
      expect(verse.mots, isNotNull);
      expect(verse.mots, hasLength(2));

      final premier = verse.mots!.first;
      expect(premier.modern, 'Ἐν');
      expect(premier.strong, 'G1722');
      expect(premier.greek, isTrue, reason: 'lecture de gauche à droite');
      expect(premier.readableGloss, isNull);
    });

    test('grammaire et analyse sont résolues contre les tables du livre', () {
      final book = AtiBook.fromJson(genese1);
      final mot = book.chapters.first.verses.first.words.first;

      expect(mot.grammar, 'PREP');
      expect(mot.analysis, 'Nature: préposition');
    });
  });
}
