import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_mapping.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/widgets/verse_tile.dart' show strongCodePattern;

/// Genèse 1:1-2 tel que `DBS/dbs_to_json.py` l'écrit — copié depuis
/// `DBS/json/1.json`, pas reconstitué : le test verrouille le schéma
/// téléchargeable (getbible + Strong inline) et le pont vers la lecture.
const Map<String, dynamic> genese1 = {
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
          'text':
              'Au commencement H7225 Dieu H0430 créa H1254 les cieux H8064 et la terre H0776.',
        },
        {
          'chapter': '1',
          'verse': '2',
          'name': 'Genèse 1:2',
          'text':
              'Et la terre H0776 était H1961 désolation H8414 et vide H0922, et il y avait des ténèbres H2822.',
        },
      ],
    },
  ],
};

void main() {
  group('the DBS Darby + Strong', () {
    test('is a downloadable French Strong version on the GitHub host', () {
      final dbs = versionByCode('DBS')!;
      expect(dbs.availability, VersionAvailability.downloadable);
      expect(dbs.fetchable, isTrue);
      // Schéma getbible nu : le texte porte déjà les codes inline, comme la
      // LSGS embarquée — aucun nouveau format à ajouter au test des parsers.
      expect(dbs.format, VersionFormat.getbible);
      expect(dbs.hasStrong, isTrue);
      expect(dbs.carriesNotes, isFalse);
      expect(dbs.languageCode, 'FR');
      expect(dbs.bookCount, 66);
      expect(
        dbs.urlTemplate,
        'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/dbs/{book}.json',
      );
      // Le Darby est libre de droit ; le taggage vient de Biblia — même
      // mention que la LSS, sortie du même logiciel.
      expect(dbs.rights, contains('Libre de droit'));
      expect(dbs.rights, contains('Biblia Universalis'));
    });

    test('maps the BYM index to the standard file number', () {
      final dbs = versionByCode('DBS')!;
      // BYM 38 = 1 Chroniques, standard 13 — le fichier DBS/json/13.json.
      expect(bymToStandard(38), 13);
      expect(
        DownloadService.bookUri(dbs, bymToStandard(38)).toString(),
        'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/dbs/13.json',
      );
    });

    test('parses as getbible text with clickable Strong codes', () {
      final book = bookFromGetbible(genese1, bymIndex: 1);
      expect(book.chapters, hasLength(1));
      expect(book.chapters.first.verses, hasLength(2));
      final v1 = book.chapters.first.verses.first;
      expect(v1.text, contains('Dieu H0430'));
      // Les codes suivent le format qu'attend le lecteur ([A-Z][0-9]{4}).
      final codes = strongCodePattern
          .allMatches(v1.text)
          .map((m) => m.group(0))
          .toList();
      expect(codes, containsAll(['H7225', 'H0430', 'H1254', 'H8064', 'H0776']));
      // Le nom vient du catalogue BYM, pas du JSON — la version fournit le
      // texte, pas le vocabulaire.
      expect(book.book, 'Genèse');
    });

    test('inline Strong text reads back as study tokens', () {
      // Le pont vers l'étude de verset : le texte téléchargé redevient des
      // tokens, le code accroché à son mot darbyen.
      const text =
          'Au commencement H7225 Dieu H0430 créa H1254 les cieux H8064 et la terre H0776.';
      final tokens = LsgsRepository.splitStrongText(text);
      expect(
        tokens.map((t) => t.strong).whereType<String>(),
        ['H7225', 'H0430', 'H1254', 'H8064', 'H0776'],
      );
      expect(tokens.firstWhere((t) => t.strong == 'H0430').text, 'Dieu');
      // Aller-retour : la jointure retrouve le texte d'origine.
      expect(
        LsgsRepository.joinTokens(tokens, includeStrong: true),
        text,
      );
    });

    test('a French word carrying two codes keeps both', () {
      // « 23 » porte le vingt et le trois (1 Ch 2:22) : le second code n'a
      // pas de mot à lui — pastille isolée, comme les mots non traduits LSS.
      final tokens =
          LsgsRepository.splitStrongText('et il eut H1961 23 H6242 H7969 villes H5892.');
      expect(
        tokens.map((t) => t.strong).whereType<String>(),
        ['H1961', 'H6242', 'H7969', 'H5892'],
      );
      expect(tokens.firstWhere((t) => t.strong == 'H6242').text, '23');
      expect(tokens.firstWhere((t) => t.strong == 'H7969').text, isEmpty);
    });
  });
}
