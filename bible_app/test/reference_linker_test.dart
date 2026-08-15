import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/reference_parser.dart';

void main() {
  group('findReferences', () {
    test('parses a full-name reference', () {
      final refs = findReferences('Voir Jean 3:16 pour la suite.');
      expect(refs, hasLength(1));
      final ref = refs.single;
      expect(ref.reference.bookIndex, 43);
      expect(ref.reference.chapter, 3);
      expect(ref.reference.verse, 16);
      expect('Jean 3:16', _slice('Voir Jean 3:16 pour la suite.', ref));
    });

    test('resolves a Westphal abbreviation (Lu)', () {
      final refs = findReferences('voir (Lu 1:13,60) Jean-Baptiste.');
      expect(refs, hasLength(1));
      expect(refs.single.reference.bookIndex, 42);
      expect(refs.single.reference.chapter, 1);
      expect(refs.single.reference.verse, 13);
    });

    test('resolves a compact ordinal abbreviation (1Ch)', () {
      final refs = findReferences('d\'Issacar (1Ch 7:2).');
      expect(refs, hasLength(1));
      expect(refs.single.reference.bookIndex, 38);
      expect(refs.single.reference.chapter, 7);
      expect(refs.single.reference.verse, 2);
    });

    test('resolves a spaced ordinal abbreviation (1 Co)', () {
      final refs = findReferences('selon 1 Co 13:1.');
      expect(refs, hasLength(1));
      expect(refs.single.reference.bookIndex, 49);
    });

    test('a chapter-only reference keeps verse null', () {
      final refs = findReferences('Psaume 23 est le psaume du berger.');
      expect(refs, hasLength(1));
      expect(refs.single.reference.bookIndex, 27);
      expect(refs.single.reference.chapter, 23);
      expect(refs.single.reference.verse, isNull);
    });

    test('does not link the continuation verse of a range', () {
      final refs = findReferences('de Jn 1:42 21:15-17, alors que Mt 16:17');
      expect(refs, hasLength(2));
      expect(refs[0].reference.bookIndex, 43);
      expect('Jn 1:42', _slice('de Jn 1:42 21:15-17, alors que Mt 16:17', refs[0]));
      expect(refs[1].reference.bookIndex, 40);
    });

    test('ignores numbers inside bigger numbers', () {
      expect(findReferences('L\'événement date de 1948.'), isEmpty);
    });

    test('ignores a book bound inside a word or a compound', () {
      expect(findReferences('saint-Jean 3:16.'), isEmpty);
      expect(findReferences('le mot Abelard'), isEmpty);
    });

    test('ignores a bare book without a chapter', () {
      expect(findReferences('l\'apôtre Jean est fidèle.'), isEmpty);
    });

    test('ignores books absent from the 66-book corpus (2Ma)', () {
      expect(findReferences('voir (2Ma 14:19).'), isEmpty);
    });

    test('finds several references in one paragraph', () {
      final refs =
          findReferences('Genèse 1:1 puis Exode 2:3, et enfin Jean 21:15.');
      expect(refs, hasLength(3));
      expect(refs[0].reference.bookIndex, 1);
      expect(refs[1].reference.bookIndex, 2);
      expect(refs[2].reference.bookIndex, 43);
      for (var i = 1; i < refs.length; i++) {
        expect(refs[i].start, greaterThan(refs[i - 1].end));
      }
    });
  });
}

String _slice(String text, TextReference ref) => text.substring(ref.start, ref.end);
