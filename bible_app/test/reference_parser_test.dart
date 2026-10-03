// La référence biblique se lit en français, en abrégé **et** sous les noms de
// la BYM — hébreu pour l'Ancien Testament, grec pour les Évangiles et les
// Épîtres — avec une tolérance aux fautes : une translittération n'est pas un
// mot qu'un lecteur français épelle de mémoire.
//
// Deux familles : les noms que le catalogue ne porte qu'à part (`bymName`,
// jamais dans `name`), et ceux déjà en tête du catalogue. Le français et les
// abréviations sont là pour prouver que rien n'a reculé.
import 'package:bible_app/data/reference_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('noms de la BYM', () {
    test('les livres dont le catalogue ne porte pas le nom BYM dans `name`',
        () {
      // `bymName` only — `name` reads « Matthieu », « Romains », « Hébreux ».
      expect(parseReference('Mattithyah 5')?.bookIndex, 40);
      expect(parseReference('Markos 1')?.bookIndex, 41);
      expect(parseReference('Loukas 2')?.bookIndex, 42);
      expect(parseReference('Roma 8')?.bookIndex, 51);
      expect(parseReference('Ivriyim 12')?.bookIndex, 62);
      expect(parseReference('Diakonos 2')?.bookIndex, 44);
      expect(parseReference('Apokalupsis 22')?.bookIndex, 66);
      expect(parseReference('Amowc 9')?.bookIndex, 17);
      expect(parseReference('1 Tesalonika 4')?.bookIndex, 47);
    });

    test('le chapitre de la requête suit le nom BYM', () {
      final ref = parseReference('Mattithyah 5:3');
      expect(ref?.chapter, 5);
      expect(ref?.verse, 3);
      expect(parseReference('Roma 8:28')?.verse, 28);
      expect(parseReference('Bereshit 1')?.chapter, 1);
    });

    test('les noms déjà en tête du catalogue restent résolus', () {
      expect(parseReference('Bereshit 1')?.bookIndex, 1);
      expect(parseReference('Shemot 2')?.bookIndex, 2);
      expect(parseReference('Tehilim 23')?.bookIndex, 27);
      expect(parseReference('Shir Hashirim 1')?.bookIndex, 30);
      expect(parseReference('Daniye\'l 6')?.bookIndex, 35);
    });
  });

  group('français et abréviations', () {
    test('le français continue de résoudre, accents compris', () {
      expect(parseReference('Genèse 1')?.bookIndex, 1);
      expect(parseReference('Matthieu 5')?.bookIndex, 40);
      expect(parseReference('1 Corinthiens 13')?.bookIndex, 49);
      expect(searchBooks('Esaie').first, 12, reason: 'sans accent');
    });

    test('les abréviations se lisent sans espace ni point', () {
      // The catalogue prints « 1 Co. » — typed « 1Co », spaces and periods
      // are not something a reader reproduces.
      expect(searchBooks('1Co').first, 49);
      expect(searchBooks('2Th').first, 48);
      expect(searchBooks('Ps').first, 27);
      expect(searchBooks('Mt').first, 40);
      expect(parseReference('Ps 23')?.chapter, 23);
      expect(parseReference('1 Co 13')?.bookIndex, 49);
    });

    test('une abréviation exacte passe devant les noms qui commencent pareil',
        () {
      // « Na » is Nahum's abbreviation; Naaman is no book.
      expect(searchBooks('Na').first, 21);
    });
  });

  group('tolérance aux fautes', () {
    test('une translittération mal orthographiée retombe sur le bon livre', () {
      expect(searchBooks('Berchit').first, 1);
      expect(searchBooks('Psames').first, 27);
      expect(searchBooks('Mattityah').first, 40);
      expect(searchBooks('Semaot').first, 2);
      expect(searchBooks('Geneze').first, 1, reason: 'le français aussi');
    });

    test('la faute passe à travers le chapitre', () {
      final ref = parseReference('Psames 23');
      expect(ref?.bookIndex, 27);
      expect(ref?.chapter, 23);
    });

    test('la tolérance ne déloge jamais un nom juste', () {
      // Strict pass first, always: « Jean » is Jean, not whatever sits at the
      // same edit distance from a misspelling.
      expect(searchBooks('Jean').first, 43);
      expect(searchBooks('Amos').first, 17);
      expect(searchBooks('Mattithyah').first, 40);
    });

    test('rien n’invente un livre quand aucune lettre ne rapproche', () {
      expect(searchBooks('zzzz'), isEmpty);
      expect(parseReference('zzzz 1'), isNull);
    });

    test('trop court pour se permettre une faute', () {
      // Four letters and under, tolerance would match half the catalogue.
      expect(searchBooks('ps'), isNotEmpty);
      expect(searchBooks('zz'), isEmpty);
    });
  });
}
