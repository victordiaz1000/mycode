import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/fredaw_lexicon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('FreDaw lexicon loads embedded entries and returns a definition', () async {
    final lexicon = FreDawLexicon.instance;

    final entry = await lexicon.lookup('AARON');

    expect(entry.term, 'AARON');
    expect(entry.definition, contains('Frère aîné de Moïse'));
  });

  test('FreDaw lexicon search finds matching terms', () async {
    final lexicon = FreDawLexicon.instance;

    final results = await lexicon.search('ABBA', limit: 10);

    expect(results, isNotEmpty);
    expect(results.any((entry) => entry.term == 'ABBA'), isTrue);
  });

  test('FreDaw lexicon returns a readable placeholder for unknown terms', () async {
    final lexicon = FreDawLexicon.instance;

    final entry = await lexicon.lookup('TERM_INEXISTANT');

    expect(entry.term, 'TERM_INEXISTANT');
    expect(entry.definition, contains('non disponible'));
  });

  test('linkPattern matches entry words, boundaries respected', () async {
    final lexicon = FreDawLexicon.instance;

    final pattern = await lexicon.linkPattern();

    expect(pattern, isNotNull);
    expect(pattern!.hasMatch('ABBA'), isTrue);
    expect(pattern.hasMatch('Voir abba'), isTrue,
        reason: 'the match is case-insensitive');
    expect(pattern.hasMatch("l'ABBA"), isTrue,
        reason: 'the apostrophe is not a word char, the elided word links');
    expect(pattern.hasMatch('ABELARD'), isFalse,
        reason: 'a term inside a longer word is not a link');
    expect(pattern.hasMatch('ABEL-BETH'), isFalse,
        reason: 'a term bound to a hyphenated compound is not a link');
    expect(pattern.hasMatch('zqxjkvbnm'), isFalse,
        reason: 'a word absent from the dictionary is plain');
  });
}
