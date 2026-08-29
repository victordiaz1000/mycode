import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/note_reference_linker.dart';
import 'package:bible_app/data/reference_parser.dart';

/// The note-reference linker (`regles-liens-references-bibliques.md`):
/// table-driven abbreviations, `,` / `;` / « et » continuations, `-` ranges,
/// atomic `1 S.`-style blocks — and nothing else ever linked.
void main() {
  /// The links of [text] as (visible span, resolved target) pairs.
  List<({String span, BibleReference ref})> links(String text) =>
      findNoteReferences(text)
          .map((r) => (span: text.substring(r.start, r.end), ref: r.reference))
          .toList();

  group('specification cases', () {
    test('Es. 7:14 → one link', () {
      final got = links('Voir Es. 7:14.');
      expect(got, hasLength(1));
      expect(got.single.span, 'Es. 7:14');
      expect(got.single.ref,
          const BibleReference(bookIndex: 12, chapter: 7, verse: 14));
    });

    test('semicolon chain with a comma continuation', () {
      final text = 'Jos. 22:22 ; 2 S. 22:32 ; Es. 9:5, 10:21, 43:12';
      expect(links(text), [
        (
          span: 'Jos. 22:22',
          ref: const BibleReference(bookIndex: 6, chapter: 22, verse: 22)
        ),
        (
          span: '2 S. 22:32',
          ref: const BibleReference(bookIndex: 9, chapter: 22, verse: 32)
        ),
        (
          span: 'Es. 9:5',
          ref: const BibleReference(bookIndex: 12, chapter: 9, verse: 5)
        ),
        (
          span: '10:21',
          ref: const BibleReference(bookIndex: 12, chapter: 10, verse: 21)
        ),
        (
          span: '43:12',
          ref: const BibleReference(bookIndex: 12, chapter: 43, verse: 12)
        ),
      ]);
    });

    test('De. 6:13, 10:20 → two links, second keeps the book', () {
      final got = links('De. 6:13, 10:20');
      expect(got, [
        (
          span: 'De. 6:13',
          ref: const BibleReference(bookIndex: 5, chapter: 6, verse: 13)
        ),
        (
          span: '10:20',
          ref: const BibleReference(bookIndex: 5, chapter: 10, verse: 20)
        ),
      ]);
    });

    test('long Exode chain changes chapter only on a colon', () {
      final got = links(
          'Ex. 25:12,14, 26:20,26-27,35, 27:7, 30:4, 36:25,31-32, '
          '37:3,5,27, 38:7');
      final expected = const [
        (25, 12),
        (25, 14),
        (26, 20),
        (26, 26),
        (26, 35),
        (27, 7),
        (30, 4),
        (36, 25),
        (36, 31),
        (37, 3),
        (37, 5),
        (37, 27),
        (38, 7),
      ];
      expect(got.map((l) => (l.ref.chapter!, l.ref.verse!)), expected);
      expect(got.map((l) => l.ref.bookIndex), everyElement(2));
    });

    test('« et » acts as a comma', () {
      final got = links('Voir Ge. 5:32 et 7:11.');
      expect(got.map((l) => l.span), ['Ge. 5:32', '7:11']);
      expect(got.last.ref,
          const BibleReference(bookIndex: 1, chapter: 7, verse: 11));
    });

    test('« Adam et Ève » is never touched', () {
      expect(links('Adam et Ève au commencement.'), isEmpty);
    });
  });

  group('atomic numeric-prefixed abbreviations', () {
    test('2 S. stays one block after an « et »', () {
      final got = links('voir Mi. 5:1 et 2 Pi. 1:19.');
      expect(got, [
        (
          span: 'Mi. 5:1',
          ref: const BibleReference(bookIndex: 20, chapter: 5, verse: 1)
        ),
        (
          span: '2 Pi. 1:19',
          ref: const BibleReference(bookIndex: 59, chapter: 1, verse: 19)
        ),
      ]);
    });

    test('a digit that opens an unknown book-shaped token refuses', () {
      // `3 X.` n'est pas dans la table : le 3 ne doit pas passer pour un
      // verset d'Ésaïe, et la chaîne s'arrête sur Ésaïe 9:5.
      final got = links('Es. 9:5, 3 X. 1:1');
      expect(got, hasLength(1));
      expect(got.single.span, 'Es. 9:5');
    });

    test('bare verses still parse when no book shape is around', () {
      final got = links('Es. 53:11, 12 et 2 S. 22:32');
      expect(got.map((l) => l.span), ['Es. 53:11', '12', '2 S. 22:32']);
      expect(got[1].ref,
          const BibleReference(bookIndex: 12, chapter: 53, verse: 12));
    });
  });

  group('corpus forms', () {
    test('chapter-only references are linked', () {
      final got = links('le jour de YHWH (Za. 14).');
      expect(got.single.span, 'Za. 14');
      expect(got.single.ref,
          const BibleReference(bookIndex: 25, chapter: 14));
    });

    test('chapter ranges stay inside the run', () {
      final got = links('(Ez. 38-39 ; Za. 14)');
      expect(got.map((l) => l.span), ['Ez. 38-39', 'Za. 14']);
      expect(got.first.ref, const BibleReference(bookIndex: 14, chapter: 38));
    });

    test('after a chapter-only item, a bare number is a chapter', () {
      final got = links('Lé. 13 et 15.');
      expect(got.map((l) => (l.ref.bookIndex, l.ref.chapter)),
          [(3, 13), (3, 15)]);
    });

    test('verses then chapters then a new chapter over a semicolon', () {
      final got = links('De. 16:13, 14 et 16 ; 31:10.');
      expect(got.map((l) => l.span),
          ['De. 16:13', '14', '16', '31:10']);
      expect(got.map((l) => (l.ref.chapter!, l.ref.verse)),
          [(16, 13), (16, 14), (16, 16), (31, 10)]);
      expect(got.map((l) => l.ref.bookIndex), everyElement(5));
    });

    test('multi-book semicolon chain with « et » inside', () {
      final got =
          links('1 R. 11:5-7 et 33 ; 2 R. 17:33, 23:11-13 ; Jé. 19:13.');
      expect(got.map((l) => (l.ref.bookIndex, l.ref.chapter!, l.ref.verse)), [
        (10, 11, 5),
        (10, 11, 33),
        (11, 17, 33),
        (11, 23, 11),
        (13, 19, 13),
      ]);
    });

    test('« et » before another book switches book', () {
      final got = links('Voir Ex. 12 et 1 Co. 5:7.');
      expect(got.map((l) => l.span), ['Ex. 12', '1 Co. 5:7']);
      expect(got.first.ref,
          const BibleReference(bookIndex: 2, chapter: 12));
      expect(got.last.ref,
          const BibleReference(bookIndex: 49, chapter: 5, verse: 7));
    });

    test('Apocalypse verse enumeration', () {
      final got = links('Ap. 1:8, 21:6 et 22:13.');
      expect(got.map((l) => (l.ref.chapter!, l.ref.verse)),
          [(1, 8), (21, 6), (22, 13)]);
    });

    test('the real Genèse 2:21 note (flanc/côte)', () {
      const note = 'Le mot hébreu « tsela » généralement traduit en français '
          'par « côte » en Ge. 2:21-22 signifie d\'abord « côté ». Partout '
          'ailleurs, ce mot a été traduit non par « côte » mais par '
          '« côté » : voir Ex. 25:12,14, 26:20,26-27,35, 27:7, 30:4, '
          '36:25,31-32, 37:3,5,27, 38:7 et Job. 18:12. Ce mot a été traduit '
          'par « flanc » en 2 S. 16:13. Voir Ge. 1:27.';
      final got = links(note);
      expect(got, hasLength(17));
      expect(got.first.span, 'Ge. 2:21-22');
      expect(got[14].ref,
          const BibleReference(bookIndex: 29, chapter: 18, verse: 12));
      expect(got[14].span, 'Job. 18:12');
      expect(got[15].ref,
          const BibleReference(bookIndex: 9, chapter: 16, verse: 13));
      expect(got.last.ref,
          const BibleReference(bookIndex: 1, chapter: 1, verse: 27));
    });
  });

  group('table is the source of truth', () {
    test('note abbreviations that differ from the catalog resolve', () {
      int? book(String t) => links(t).single.ref.bookIndex;
      expect(book('Lu. 1:78'), 42); // Luc — le catalogue écrit « Lc. »
      expect(book('Jud. 1:5-7'), 61); // Jude — le catalogue écrit « Jd. »
      expect(book('Job. 31:33'), 29); // la table écrit « Job. »
      expect(book('Joë. 1:15'), 16);
      expect(book('Né. 2:1'), 37);
    });
  });

  group('guard rails', () {
    test('numbers never reached through a run stay plain', () {
      expect(links('Il avait 500 ans quand ses fils sont nés.'), isEmpty);
      expect(links('le jour commence le soir à 18 heures'), isEmpty);
      expect(links('Aleph Tav apparaît plus de 7 000 fois dans le Tanakh.'),
          isEmpty);
      expect(links('Note de test 1:1. Voir Es. 45:18.'), hasLength(1));
      expect(links('Le siège s\'est déroulé en 587 et 586 av. J.-C.'),
          isEmpty);
    });

    test('a run stops on prose, even across commas', () {
      final got =
          links('En 2 S. 24:14, David, en parlant de lui-même, utilise un '
              'pluriel (tombons).');
      expect(got.single.span, '2 S. 24:14');
    });

    test('a stray colon after the verse closes the run', () {
      final got = links('De. 6:4 : « Shema Yisrael YHWH elohénou ». '
          'YHWH est un et indivisible.');
      expect(got.single.span, 'De. 6:4');
      expect(got.single.ref,
          const BibleReference(bookIndex: 5, chapter: 6, verse: 4));
    });

    test('an abbreviation without its numbers is not a reference', () {
      expect(links('selon Ge. et Ex., les deux livres.'), isEmpty);
    });

    test('spans never overlap and cover their sub-token exactly', () {
      const text = 'Jos. 22:22 ; 2 S. 22:32 ; Es. 9:5, 10:21, 43:12.';
      final refs = findNoteReferences(text);
      for (var i = 1; i < refs.length; i++) {
        expect(refs[i].start, greaterThanOrEqualTo(refs[i - 1].end));
      }
      for (final r in refs) {
        expect(text.substring(r.start, r.end).trim(), isNot(startsWith(',')));
        expect(text.substring(r.start, r.end), isNot(contains(';')));
      }
    });
  });
}
