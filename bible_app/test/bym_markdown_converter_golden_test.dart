import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/bym_markdown_converter.dart';

/// Le test qui porte tout le système de mise à jour.
///
/// Depuis que les mises à jour viennent des `.md` du dépôt GitLab, le JSON servi
/// au lecteur est fabriqué par [BymMarkdownConverter] et non plus par
/// `md_to_json.py`. Rien ne garantit l'équivalence des deux implémentations sauf
/// ceci : convertir les 66 livres de `appCodebar/bym_md/` en Dart et comparer
/// **octet pour octet** aux 66 JSON embarqués dans `assets/bible/bym/`, qui sont
/// la sortie de Python. Une divergence d'un seul caractère fait échouer le test,
/// avec sa position et son contexte.
///
/// Les deux références sont suivies par git, donc ce test tourne sur un clone
/// neuf sans rien régénérer.
void main() {
  final md = Directory('../appCodebar/bym_md');
  final golden = Directory('assets/bible/bym');

  // Livre converti et JSON encodé, une seule fois pour tous les contrôles.
  final books = <String, Map<String, Object?>>{};
  final encoded = <String, String>{};

  setUpAll(() {
    if (!md.existsSync()) {
      fail('Corpus source introuvable : ${md.absolute.path}. '
          'Lancer les tests depuis bible_app/.');
    }
    for (var n = 1; n <= bookCatalog.length; n++) {
      final name = catalogEntry(n).file.replaceAll('.json', '');
      final source = File('${md.path}/$name.md').readAsStringSync();
      final book = BymMarkdownConverter.convert(source);
      books[name] = book;
      encoded[name] = BymMarkdownConverter.encode(book);
    }
  });

  group('parité avec md_to_json.py', () {
    test('les 66 livres sont identiques octet pour octet', () {
      for (var n = 1; n <= bookCatalog.length; n++) {
        final name = catalogEntry(n).file.replaceAll('.json', '');
        final expected = File('${golden.path}/$name.json').readAsBytesSync();
        _expectSameBytes(utf8.encode(encoded[name]!), expected, '$name.json');
      }
    });

    test('66 livres et 31 169 versets, comme la sortie Python', () {
      var total = 0;
      for (final book in books.values) {
        total += BymMarkdownConverter.verseCount(book);
      }
      expect(books.length, 66);
      expect(total, 31169);
    });
  });

  group('invariants des notes', () {
    // Une note affichée au mauvais endroit est invisible en relecture mais
    // fausse dans l'application : c'est exactement ce que le `\w` ASCII de Dart
    // produirait sur un mot accentué.
    test('text[position … position+word.length] vaut toujours word', () {
      var checked = 0;
      for (final entry in books.entries) {
        for (final chapter in entry.value['chapters'] as List) {
          for (final verse in (chapter as Map)['verses'] as List) {
            final notes = (verse as Map)['notes'];
            if (notes is! List) continue;
            final text = verse['text'] as String;
            for (final note in notes) {
              final word = (note as Map)['word'] as String;
              if (word.isEmpty) continue;
              final position = note['position'] as int;
              expect(
                text.substring(position, position + word.length),
                word,
                reason: '${entry.key} ${verse['verse']} — note « $word »',
              );
              checked++;
            }
          }
        }
      }
      // Sans ce compte, un bug qui viderait toutes les notes rendrait le test
      // vert. 5 753 est aussi le compte de la sortie Python ; il suit le corpus,
      // donc `sync_bym_source.py` peut le faire bouger — le remesurer alors,
      // mais ne jamais le remplacer par un `greaterThan`.
      expect(checked, 5753);
    });

    test('un mot accentué garde son mot et sa position (piège du \\w ASCII)',
        () {
      // Avec `\w` (ASCII en Dart), « ténèbre » se découperait en « t », « n »,
      // « bre » : la note se rattacherait à « bre », ailleurs dans le verset.
      final note = _noteOf(books['01-Genese']!, '1:2', 2);
      expect(note['word'], 'ténèbre');
      expect(note['position'], 33);

      // L'apostrophe et le trait d'union font partie du mot.
      expect(_noteOf(books['02-Exode']!, '1:12', 0)['word'], "d'Israël");
      expect(_noteOf(books['03-Levitique']!, '19:18', 1)['word'], 'toi-même');
    });

    test('le seul signe hébreu du corpus reste dans sa note', () {
      // Lévitique 19:18 porte un sheva (U+05B0) dans le corps de la note. Il
      // n'est atteint par aucun balayage de mots, mais il a déjà fait échouer
      // un portage : le garder sous test coûte trois lignes.
      final note = _noteOf(books['03-Levitique']!, '19:18', 0);
      expect(note['word'], 'prochain');
      expect(note['position'], 87);
      expect(note['note'], contains('[לְ]'));
    });
  });

  group('structure', () {
    test('chaque livre a son titre, son abréviation et ses métadonnées', () {
      // Le titre vient du Markdown et n'est **pas** celui de `book_catalog.dart`
      // (« Shemot (Noms) : Exode » contre « Shemot (Exode) ») : le catalogue est
      // une liste curatée pour l'interface, 43 titres et 7 abréviations
      // divergent volontairement. Les aligner serait une régression.
      for (var n = 1; n <= bookCatalog.length; n++) {
        final book = books[catalogEntry(n).file.replaceAll('.json', '')]!;
        expect(book['book'], isNotEmpty, reason: 'livre $n sans titre');
        expect(book['abbreviation'], isNotEmpty, reason: 'livre $n sans abrév.');
        expect(book['metadata'], isNotEmpty, reason: 'livre $n sans <h>');
      }
      expect((books['01-Genese']!['metadata'] as Map)['signification'],
          isNotEmpty);
    });

    test('la section n\'est portée que par le premier verset qui la suit', () {
      // Choix utilisateur inscrit dans le format : la répéter gonflerait les
      // fichiers et ferait afficher un titre à chaque verset.
      var withSection = 0;
      var verses = 0;
      for (final chapter in books['01-Genese']!['chapters'] as List) {
        for (final verse in (chapter as Map)['verses'] as List) {
          verses++;
          if ((verse as Map).containsKey('section')) withSection++;
        }
      }
      expect(withSection, greaterThan(0));
      expect(withSection, lessThan(verses ~/ 4));
    });

    test('un Markdown sans titre est refusé, pas converti à vide', () {
      // Sans cette levée, un fichier tronqué en transit donnerait un livre vide
      // que la mise à jour installerait sans rien remarquer.
      expect(() => BymMarkdownConverter.convert('## Chapitre 1\n1:1\tTexte.'),
          throwsA(isA<FormatException>()));
      expect(() => BymMarkdownConverter.convert('   \n'),
          throwsA(isA<FormatException>()));
    });
  });
}

/// La note [index] du verset [reference] d'un livre converti.
Map<String, Object?> _noteOf(
    Map<String, Object?> book, String reference, int index) {
  for (final chapter in book['chapters'] as List) {
    for (final verse in (chapter as Map)['verses'] as List) {
      if ((verse as Map)['verse'] == reference) {
        return ((verse['notes'] as List)[index] as Map).cast<String, Object?>();
      }
    }
  }
  fail('verset $reference introuvable');
}

/// Compare deux contenus et, en cas d'écart, pointe le premier octet fautif avec
/// son contexte : afficher 400 Ko de JSON ne dirait rien.
void _expectSameBytes(List<int> actual, List<int> expected, String label) {
  if (actual.length == expected.length) {
    var same = true;
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != expected[i]) {
        same = false;
        break;
      }
    }
    if (same) return;
  }

  final limit = actual.length < expected.length ? actual.length : expected.length;
  var i = 0;
  while (i < limit && actual[i] == expected[i]) {
    i++;
  }
  final from = i - 80 < 0 ? 0 : i - 80;
  String window(List<int> bytes) {
    final to = i + 80 < bytes.length ? i + 80 : bytes.length;
    return utf8.decode(bytes.sublist(from, to), allowMalformed: true);
  }

  fail('$label diverge de la sortie Python à l\'octet $i '
      '(Dart ${actual.length} octets, Python ${expected.length}).\n'
      'Dart   : …${window(actual)}…\n'
      'Python : …${window(expected)}…');
}
