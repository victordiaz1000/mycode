import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';

/// Genèse 1,1-2 tel que `ATI/ati_to_json.py` l'écrit — copié depuis
/// `ATI/json/1.json`, pas reconstitué : les deux pièges du format (les index de
/// tables, les gloses réduites à un marqueur) ne se voient que sur du vrai.
///
/// Les tables `cg` / `ca` sont tronquées aux seules entrées que ces deux versets
/// utilisent ; le livre complet en porte 23 et 999.
const Map<String, dynamic> genese = {
  'bym_index': 1,
  'standard': 1,
  'book': 'Genèse',
  'osis_id': 'GEN',
  'cg': ['Nom', 'Verbe', 'Accusatif', 'Préposition'],
  'ca': [
    'Nom commun· féminin singulier· état absolu— Préposition',
    'Verbe qal parfait (qatal)· 3ᵉ masculin singulier',
    'Nom commun· masculin pluriel· état absolu',
    'Particule marqueur d’objet direct',
    'Nom commun· masculin pluriel· état absolu— Particule article défini',
    'Particule marqueur d’objet direct— Conjonction',
    'Nom commun· féminin et masculin singulier· état absolu— '
        'Particule article défini',
  ],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            {
              's': 'H7225',
              't': 'bə·rê·šîṯ',
              'h': 'בְּרֵאשִׁ֖ית',
              'd': 'בְּ • רֵאשִׁ֖ית',
              'f': 'En un commencement',
              'n': 'n12',
              'g': 0,
              'a': 0,
            },
            {
              's': 'H1254',
              't': 'bā·rā',
              'h': 'בָּרָ֣א',
              'd': 'בְּרֹ֤א',
              'f': 'créa',
              'g': 1,
              'a': 1,
            },
            {
              's': 'H430',
              't': '’ĕ·lō·hîm;',
              'h': 'אֱלֹהִ֑ים',
              'd': 'אֱלֹהִ֑ים',
              'f': 'Dieu',
              'g': 0,
              'a': 2,
            },
            // Le marqueur d'accusatif : pas de glose française, la source écrit
            // « * ». 7 073 mots du corpus sont dans ce cas.
            {
              's': 'H853',
              't': '’êṯ',
              'h': 'אֵ֥ת',
              'd': 'אֵ֥ת',
              'f': '*',
              'n': 'r2',
              'g': 2,
              'a': 3,
            },
            {
              's': 'H8064',
              't': 'haš·šā·ma·yim',
              'h': 'הַשָּׁמַ֖יִם',
              'd': 'הַ • שָּׁמָֽיִם',
              'f': 'les cieux',
              'g': 0,
              'a': 4,
            },
            // Glose mixte : un mot utile et un marqueur, « et - ».
            {
              's': 'H853',
              't': 'wə·’êṯ',
              'h': 'וְאֵ֥ת',
              'd': 'וְ • אֵ֥ת',
              'f': 'et -',
              'g': 2,
              'a': 5,
            },
            {
              's': 'H776',
              't': 'hā·’ā·reṣ.',
              'h': 'הָאָֽרֶץ׃',
              'd': 'הָ • אָ֕רֶץ',
              'f': 'la terre.',
              'g': 0,
              'a': 6,
            },
          ],
        },
        {
          'verse': 2,
          'words': [
            {
              's': 'H776',
              't': 'wə·hā·’ā·reṣ,',
              'h': 'וְהָאָ֗רֶץ',
              'f': 'Et la terre',
              'g': 0,
              'a': 6,
            },
            // Mot d'un seul morphème : aucun découpage, donc pas de `d`. C'est
            // le cas qui faisait ranger l'analyse grammaticale en découpage
            // quand le parseur lisait les infobulles par leur ordre.
            {
              's': 'H1961',
              't': 'hā·yə·ṯāh',
              'h': 'הָיְתָ֥ה',
              'f': 'était',
              'g': 1,
              'a': 1,
            },
          ],
        },
      ],
    },
  ],
};

void main() {
  group('AtiBook.fromJson', () {
    test('lit l\'en-tête du livre', () {
      final book = AtiBook.fromJson(genese);

      expect(book.bymIndex, 1);
      expect(book.book, 'Genèse');
      expect(book.osisId, 'GEN');
      expect(book.chapters, hasLength(1));
      expect(book.chapters.first.chapter, 1);
      expect(book.chapters.first.verses, hasLength(2));
    });

    test('un mot porte ses sept champs', () {
      final mot = AtiBook.fromJson(genese)
          .chapters
          .first
          .verses
          .first
          .words
          .first;

      expect(mot.strong, 'H7225');
      expect(mot.translit, 'bə·rê·šîṯ');
      expect(mot.hebrew, 'בְּרֵאשִׁ֖ית');
      expect(mot.split, 'בְּ • רֵאשִׁ֖ית');
      expect(mot.gloss, 'En un commencement');
      expect(mot.note, 'n12');
      // Résolus contre les tables : personne hors du modèle ne voit un index.
      expect(mot.grammar, 'Nom');
      expect(mot.analysis,
          'Nom commun· féminin singulier· état absolu— Préposition');
    });

    test('un champ absent de la source est null, jamais un substitut', () {
      final mot =
          AtiBook.fromJson(genese).chapters.first.verses[1].words[1];

      expect(mot.split, isNull, reason: 'un seul morphème, pas de découpage');
      expect(mot.hebrew, isNotNull);
    });

    test('le même index rend le même libellé pour deux mots', () {
      final mots = AtiBook.fromJson(genese).chapters.first;
      // « était » (v. 2) et « créa » (v. 1) partagent l'analyse 1.
      expect(mots.verses.first.words[1].analysis,
          mots.verses[1].words[1].analysis);
    });

    test('un index hors table donne null plutôt qu\'une exception', () {
      // Un fichier abîmé doit se lire en partie : perdre une étiquette
      // grammaticale est préférable à perdre le livre.
      final mot = AtiWord.fromJson(
        const {'s': 'H1', 'g': 99, 'a': -1},
        grammarTable: const ['Nom'],
        analysisTable: const ['Nom commun'],
      );

      expect(mot.strong, 'H1');
      expect(mot.grammar, isNull);
      expect(mot.analysis, isNull);
    });

    test('un JSON vide se lit sans lever', () {
      final book = AtiBook.fromJson(const {});

      expect(book.bymIndex, 0);
      expect(book.book, isEmpty);
      expect(book.chapters, isEmpty);
    });
  });

  group('bookFromAti', () {
    test('Gn 1,1 porte les gloses jointes, marqueurs retirés', () {
      final book = bookFromAti(genese, bymIndex: 1);
      final verset = book.chapters.first.verses.first;

      expect(verset.verse, '1:1');
      expect(verset.text,
          'En un commencement créa Dieu les cieux et la terre.');
      // Pas de notes dans une version téléchargée : le texte nu des deux côtés.
      expect(verset.textWithNotes, verset.text);
    });

    test('le nom vient du catalogue BYM, pas du JSON', () {
      final book = bookFromAti(genese, bymIndex: 1);

      expect(book.number, 1);
      expect(book.book, catalogEntry(1).shortName);
      expect(book.abbreviation, catalogEntry(1).abbreviation);
    });

    test('les versets gardent leur numérotation « chapitre:verset »', () {
      final book = bookFromAti(genese, bymIndex: 1);

      expect(book.chapters.first.verses.map((v) => v.verse), ['1:1', '1:2']);
    });

    test('le verset porte ses mots pour l’interlinéaire', () {
      final verset =
          bookFromAti(genese, bymIndex: 1).chapters.first.verses.first;

      // La ligne jointe ne porte que les gloses ; les colonnes lisent les mots.
      // Les deux viennent du même verset, sinon le lecteur verrait deux textes
      // différents selon l'écran.
      expect(verset.mots, hasLength(7));
      expect(verset.mots!.first.hebrew, 'בְּרֵאשִׁ֖ית');
      expect(verset.mots!.first.grammar, 'Nom');
      expect(verset.mots!.first.note, 'n12');
      // Le marqueur d'accusatif garde son mot, et sa glose reste brute dans le
      // modèle : c'est `readableGloss` qui décide de ne pas l'afficher.
      expect(verset.mots![3].gloss, '*');
      expect(verset.mots![3].readableGloss, isNull);
    });
  });

  group('joinAtiGlosses', () {
    List<AtiWord> gloses(List<String?> valeurs) =>
        [for (final v in valeurs) AtiWord(gloss: v)];

    test('un mot dont la glose n\'est qu\'un marqueur disparaît', () {
      expect(joinAtiGlosses(gloses(['créa', '*', 'Dieu'])), 'créa Dieu');
      expect(joinAtiGlosses(gloses(['créa', '-', 'Dieu'])), 'créa Dieu');
    });

    test('le marqueur isolé saute aussi au milieu d\'une glose', () {
      expect(joinAtiGlosses(gloses(['et -'])), 'et');
    });

    test('un trait d\'union interne est protégé', () {
      // Le découpage par blancs, et non par caractère : « Ramoth-de - » est un
      // vrai cas du corpus.
      expect(joinAtiGlosses(gloses(['Ramoth-de -'])), 'Ramoth-de');
    });

    test('un mot sans glose est absent de la ligne', () {
      expect(joinAtiGlosses(gloses(['créa', null, 'Dieu'])), 'créa Dieu');
    });

    test('un verset sans aucune glose donne une chaîne vide', () {
      expect(joinAtiGlosses(gloses(['*', '-', null])), isEmpty);
    });
  });

  group('catalogue', () {
    test('ATI est téléchargeable, Ancien Testament seul, au format ati', () {
      final entry = versionByCode('ATI');

      expect(entry, isNotNull);
      expect(entry!.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      expect(entry.otOnly, isTrue);
      expect(entry.bookCount, 39);
      expect(entry.containsBook(39), isTrue, reason: 'Malachie');
      expect(entry.containsBook(40), isFalse, reason: 'Matthieu');
      // Le copyright de Biblia Universalis est porté sur la carte : c'est la
      // condition à laquelle le corpus est servi.
      expect(entry.rights, contains('Biblia Universalis'));
      // Le drapeau décrit le texte aplati, où aucun code n'est inséré.
      expect(entry.hasStrong, isFalse);
      // Pas de notes : `carriesNotes` est réservé au format BYM.
      expect(entry.carriesNotes, isFalse);
    });

    test('l\'ancienne entrée INT a bien disparu', () {
      expect(versionByCode('INT'), isNull);
    });
  });
}
