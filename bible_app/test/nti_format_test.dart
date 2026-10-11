import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/verse.dart';

/// Matthieu 1,1-2 tel que `NTI/nti_to_json.py` l'écrit — copié depuis
/// `NTI/json/40.json`, pas reconstitué : les pièges du format grec (la variante
/// de glose, le `˚` des formes construites, la crase de Koinè `=χυ`) ne se
/// voient que sur du vrai.
///
/// Le v. 2 est tronqué à ses six premiers mots — ceux que les tests lisent ;
/// le verset complet en porte dix-huit. Les tables `cg` / `ca` sont tronquées
/// aux seules entrées que ces versets utilisent ; le livre complet en porte 410.
const Map<String, dynamic> matthieu = {
  'bym_index': 40,
  'standard': 40,
  'book': 'Matthieu',
  'osis_id': 'MAT',
  'cg': ['N-NFS', 'N-GFS', 'N-GMS', 'N-NMS', 'V-IAA3S', 'E-AMS'],
  'ca': [
    'Nature : Nom · Déclinaison : Nominatif · Genre : féminin · Nombre : singulier',
    'Nature : Nom · Déclinaison : Génitif · Genre : féminin · Nombre : singulier',
    'Nature : Nom · Déclinaison : Génitif · Genre : masculin · Nombre : singulier',
    'Nature : Nom · Déclinaison : Nominatif · Genre : masculin · Nombre : singulier',
    'Nature : Verbe · Mode : Indicatif · Temps : Aoriste · Voix : Active · '
        'Personne : 3ème · Nombre : singulier',
    'Nature : Déterminant · Déclinaison : Accusatif · Genre : masculin · '
        'Nombre : singulier',
  ],
  'chapters': [
    {
      'chapter': 1,
      'verses': [
        {
          'verse': 1,
          'words': [
            {
              'm': 'Βίβλος',
              'l': 'βίβλος',
              'k': 'βιβλοσ',
              'f': 'Livre',
              's': 'G976',
              'g': 0,
              'a': 0,
            },
            // Variante de glose : la source propose deux lectures de la même
            // cellule, « de genèse » et « de généalogie ». 39 375 fois dans le
            // corpus.
            {
              'm': 'γενέσεως',
              'l': 'γένεσις',
              'k': 'γενεσεωσ',
              'f': 'de genèse',
              's': 'G1078',
              'f2': 'de généalogie',
              'g': 1,
              'a': 1,
            },
            // `˚` : le marqueur Biblia des formes construites. Il est gardé
            // tel quel, la maquette l'imprime.
            {
              'm': '˚Ἰησοῦ',
              'l': 'Ἰησοῦς',
              'k': '=ιυ',
              'f': 'de Jésus',
              's': 'G2424',
              'g': 2,
              'a': 2,
            },
            {
              'm': '˚Χριστοῦ',
              'l': 'χριστός',
              'k': '=χυ',
              'f': 'Christ',
              's': 'G5547',
              'g': 2,
              'a': 2,
            },
            {
              'm': 'υἱοῦ',
              'l': 'υἱός',
              'k': 'υιου',
              'f': 'fils',
              's': 'G5207',
              'g': 2,
              'a': 2,
            },
            {
              'm': 'Δαυὶδ',
              'l': 'Δαυίδ',
              'k': 'δαυειδ',
              'f': 'de David,',
              's': 'G1138',
              'g': 2,
              'a': 2,
            },
            {
              'm': 'υἱοῦ',
              'l': 'υἱός',
              'k': 'υιου',
              'f': 'fils',
              's': 'G5207',
              'g': 2,
              'a': 2,
            },
            {
              'm': 'Ἀβραάμ',
              'l': 'Ἀβραάμ',
              'k': 'αβρααμ',
              'f': "d'Abraham.",
              's': 'G11',
              'g': 2,
              'a': 2,
            },
          ],
        },
        {
          'verse': 2,
          'words': [
            {
              'm': 'ἐγέννησεν',
              'l': 'γεννάω',
              'k': 'εγεννησεν',
              'f': 'engendra',
              's': 'G1080',
              'g': 4,
              'a': 4,
            },
            {
              'm': 'τὸν',
              'l': 'ὁ',
              'k': 'τον',
              'f': 'le',
              's': 'G3588',
              'g': 5,
              'a': 5,
            },
            {
              'm': 'Ἰσαάκ',
              'l': 'Ἰσαάκ',
              'k': 'ισαακ',
              'f': 'Isaac,',
              's': 'G2408',
              'g': 2,
              'a': 2,
            },
            // Glose réduite à un marqueur : le mot n'a que sa variante à dire
            // (« - / or », 183 fois dans le corpus).
            {
              'm': 'δὲ',
              'l': 'δέ',
              'k': 'δε',
              'f': '-',
              's': 'G1161',
              'f2': 'or',
              'g': 7,
              'a': 7,
            },
            {
              'm': 'τὸν',
              'l': 'ὁ',
              'k': 'τον',
              'f': 'le',
              's': 'G3588',
              'g': 5,
              'a': 5,
            },
            {
              'm': 'Ἰακὼβ',
              'l': 'Ἰακώβ',
              'k': 'ιακωβ',
              'f': 'Jacob,',
              's': 'G2384',
              'g': 2,
              'a': 2,
            },
          ],
        },
      ],
    },
  ],
};

/// Un mot « non réf. » du corpus — Marc 16:8, celui que la source ne rattache
/// à aucun Strong : ses lemmes ne sont que des marqueurs, et son glose porte
/// les crochets du bloc de variantes textuelles.
const Map<String, dynamic> sansRef = {
  'm': '[[[Πάντα',
  'l': '-',
  'k': '-',
  'f': '[[[Toutes *',
};

void main() {
  group('AtiBook.fromJson (grec)', () {
    test('lit l\'en-tête du livre', () {
      final book = AtiBook.fromJson(matthieu);

      expect(book.bymIndex, 40);
      expect(book.book, 'Matthieu');
      expect(book.osisId, 'MAT');
      expect(book.chapters, hasLength(1));
      expect(book.chapters.first.chapter, 1);
      expect(book.chapters.first.verses, hasLength(2));
    });

    test('un mot porte ses six rangées, tables résolues', () {
      final mot =
          AtiBook.fromJson(matthieu).chapters.first.verses.first.words[1];

      expect(mot.modern, 'γενέσεως');
      expect(mot.lemma, 'γένεσις');
      expect(mot.koine, 'γενεσεωσ');
      expect(mot.gloss, 'de genèse');
      expect(mot.variant, 'de généalogie');
      expect(mot.strong, 'G1078');
      // Résolus contre les tables, comme à l'hébreu : personne hors du modèle
      // ne voit un index.
      expect(mot.grammar, 'N-GFS');
      expect(
        mot.analysis,
        'Nature : Nom · Déclinaison : Génitif · Genre : féminin · '
        'Nombre : singulier',
      );
    });

    test('un mot est grec, un mot hébreu ne l\'est pas', () {
      final grec =
          AtiBook.fromJson(matthieu).chapters.first.verses.first.words.first;
      final hebreu = const AtiWord(hebrew: 'בְּרֵאשִׁ֖ית', gloss: 'créa');

      expect(grec.greek, isTrue);
      expect(hebreu.greek, isFalse);
      // Le discriminateur se pose sur les trois lignes : un mot sans Strong ni
      // glose garde quand même son grec à afficher.
      expect(const AtiWord(lemma: 'δέ').greek, isTrue);
      expect(const AtiWord(strong: 'G1161', gloss: 'ou').greek, isFalse);
    });

    test('le `˚` des formes construites est conservé', () {
      final mots =
          AtiBook.fromJson(matthieu).chapters.first.verses.first.words;

      expect(mots[2].modern, '˚Ἰησοῦ');
      // Et la crase de Koinè aussi : `=χυ` est la forme abrégée du lemme, pas
      // un défaut d'encodage à réparer.
      expect(mots[3].koine, '=χυ');
    });

    test('un champ absent de la source est null, jamais un substitut', () {
      final mot = AtiBook.fromJson(matthieu).chapters.first.verses[1].words[3];

      expect(mot.gloss, '-');
      expect(mot.readableGloss, isNull, reason: 'marqueur seul : rien à dire');
      expect(mot.readableVariant, 'or', reason: 'la variante fait la glose');
      expect(mot.note, isNull, reason: 'le NTI n\'a aucun renvoi de glossaire');
      expect(mot.split, isNull, reason: 'pas de découpage dans le schéma grec');
      expect(mot.translit, isNull, reason: 'ni translittération');
    });

    test('un mot « non réf. » reste lisible sans son Strong', () {
      final mot = AtiWord.fromJson(sansRef);

      expect(mot.strong, isNull);
      expect(mot.greek, isTrue);
      // Les marqueurs du lemme ne sont pas des lemmes : le champ brut les garde,
      // comme la source les imprime.
      expect(mot.lemma, '-');
      // La glose, elle, se nettoie : les crochets restent (texte utile), l'étoile
      // saute.
      expect(mot.readableGloss, '[[[Toutes');
    });

    test('un index hors table donne null plutôt qu\'une exception', () {
      final mot = AtiWord.fromJson(
        const {'m': 'Βίβλος', 'g': 99, 'a': -1},
        grammarTable: const ['N-NFS'],
        analysisTable: const ['Nature : Nom'],
      );

      expect(mot.modern, 'Βίβλος');
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
    test('Mt 1,1 joint les gloses et leurs variantes, marqueurs retirés', () {
      final book = bookFromAti(matthieu, bymIndex: 40);
      final verset = book.chapters.first.verses.first;

      expect(verset.verse, '1:1');
      expect(
        verset.text,
        'Livre de genèse de généalogie de Jésus Christ fils de David, '
        "fils d'Abraham.",
      );
      // Pas de notes dans une version téléchargée : le texte nu des deux côtés.
      expect(verset.textWithNotes, verset.text);
    });

    test('la variante rejoint la ligne à la suite de la glose', () {
      final verset = bookFromAti(matthieu, bymIndex: 40).chapters.first.verses[1];

      // Le mot « δὲ » n'a que sa variante : sans elle, il rejoindrait la ligne
      // sans rien dire de français.
      expect(verset.text, 'engendra le Isaac, or le Jacob,');
    });

    test('le nom vient du catalogue BYM, pas du JSON', () {
      final book = bookFromAti(matthieu, bymIndex: 40);

      expect(book.number, 40);
      expect(book.book, catalogEntry(40).shortName);
      expect(book.abbreviation, catalogEntry(40).abbreviation);
    });

    test('le verset porte ses mots pour l’interlinéaire', () {
      final verset =
          bookFromAti(matthieu, bymIndex: 40).chapters.first.verses.first;

      expect(verset.mots, hasLength(8));
      expect(verset.mots!.first.modern, 'Βίβλος');
      expect(verset.mots!.first.grammar, 'N-NFS');
      expect(verset.motsGrecs, isTrue, reason: 'le sens de lecture en découle');
      // Les colonnes lisent les mots, jamais la chaîne jointe.
      expect(verset.mots!.last.modern, 'Ἀβραάμ');
      expect(verset.mots!.last.greek, isTrue);
    });

    test('un verset sans mots ne prétend pas au grec', () {
      const verset = Verse(verse: '1:1', text: 'Livre', textWithNotes: 'Livre');

      expect(verset.motsGrecs, isFalse);
      expect(
        const Verse(verse: '1:1', text: '', textWithNotes: '', mots: []).motsGrecs,
        isFalse,
      );
    });
  });

  group('joinAtiGlosses', () {
    List<AtiWord> mots(List<Map<String, dynamic>> valeurs) =>
        [for (final v in valeurs) AtiWord.fromJson(v)];

    test('la variante suit la glose, séparée par un blanc', () {
      expect(
        joinAtiGlosses(mots([
          {'m': 'γενέσεως', 'f': 'de genèse', 'f2': 'de généalogie'},
        ])),
        'de genèse de généalogie',
      );
    });

    test('un mot qui n\'a que sa variante la joint quand même', () {
      expect(
        joinAtiGlosses(mots([{'m': 'δὲ', 'f': '-', 'f2': 'or'}])),
        'or',
      );
    });

    test('la variante seule disparaît aussi si elle n\'est qu\'un marqueur', () {
      expect(
        joinAtiGlosses(mots([{'m': 'δὲ', 'f': '-', 'f2': '-'}])),
        isEmpty,
      );
    });

    test('un mot sans glose ni variante est absent de la ligne', () {
      expect(joinAtiGlosses(mots([{'m': 'τὸν'}, {'f': 'engendra'}])),
          'engendra');
    });
  });

  group('canon du NTI', () {
    test('NTI est téléchargeable, Nouveau Testament seul, au format ati', () {
      final entry = versionByCode('NTI');

      expect(entry, isNotNull);
      expect(entry!.format, VersionFormat.ati);
      expect(entry.fetchable, isTrue);
      expect(entry.ntOnly, isTrue);
      expect(entry.otOnly, isFalse);
      expect(entry.interlinear, isTrue, reason: 'grille de colonnes de mots');
      expect(entry.bookCount, 27);
      expect(entry.containsBook(40), isTrue, reason: 'Matthieu');
      expect(entry.containsBook(66), isTrue, reason: 'Apocalypse');
      expect(entry.containsBook(39), isFalse, reason: 'Malachie');
      expect(entry.canonOnly, 'le Nouveau Testament');
      // Le copyright de Biblia Universalis est porté sur la carte : c'est la
      // condition à laquelle le corpus est servi.
      expect(entry.rights, contains('Biblia Universalis'));
      expect(entry.urlTemplate, contains('/nti/'));
      // Le drapeau décrit le texte aplati, où aucun code n'est inséré.
      expect(entry.hasStrong, isFalse);
      expect(entry.carriesNotes, isFalse);
    });

    test('l\'ATI et le NTI se complètent sans se chevaucher', () {
      final ati = versionByCode('ATI')!;
      final nti = versionByCode('NTI')!;

      expect(ati.bookCount + nti.bookCount, 66);
      expect(ati.containsBook(39), isTrue);
      expect(nti.containsBook(39), isFalse);
      expect(nti.containsBook(40), isTrue);
      expect(ati.containsBook(40), isFalse);
    });

    test('le message d\'un livre hors canon nomme le bon testament', () {
      expect(
        const BookNotInVersion('NTI', 1).message,
        contains('le Nouveau Testament'),
      );
      expect(
        const BookNotInVersion('ATI', 40).message,
        contains('l\'Ancien Testament'),
      );
    });

    test('une version ne peut pas porter les deux canons', () {
      // Expression non const exprès : une constante ne passerait même pas la
      // compilation, et c'est le but — l'assert est la garantie au moment de
      // l'exécution que le catalogue ne s'y trompe pas.
      // ignore: prefer_const_constructors
      expect(
        () => VersionEntry(
          code: 'XX',
          name: 'X',
          rights: 'X',
          otOnly: true,
          ntOnly: true,
        ),
        throwsAssertionError,
      );
    });
  });
}
