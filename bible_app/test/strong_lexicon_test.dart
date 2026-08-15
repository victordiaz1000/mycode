import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LSGS is exposed as an embedded Strong-capable version', () {
    final entry = versionByCode('LSGS');
    expect(entry, isNotNull);
    expect(entry!.embedded, isTrue);
    // LSGS gives Strong tokens but no BYM metadata, sections or notes: the
    // reader hides the book header and the « Texte + notes » toggle for it.
    expect(entry.carriesNotes, isFalse);
  });

  test('the embedded lexicon holds French definitions for H and G', () async {
    final lexicon = StrongLexicon.instance;

    final h0001 = await lexicon.lookup('H0001');
    expect(h0001.strong, 'H0001');
    expect(h0001.definition, contains('père'));
    expect(h0001.language, 'hebrew');
    expect(h0001.lemma, isNotEmpty);
    expect(h0001.senses, isNotEmpty);

    final g2316 = await lexicon.lookup('G2316');
    expect(g2316.strong, 'G2316');
    expect(g2316.definition, contains('Dieu'));
  });

  test('the lexicon is complete enough to cover both testaments', () async {
    final lexicon = StrongLexicon.instance;
    await lexicon.lookup('H0001');

    // ~8 674 Hebrew + ~5 521 Greek definitions from the SWORD modules.
    expect(lexicon.size, greaterThan(13000));
    expect(await lexicon.contains('H7225'), isTrue);
    expect(await lexicon.contains('G2424'), isTrue);
  });

  test('an unknown code answers a readable placeholder', () async {
    final result = await StrongLexicon.instance.lookup('H99999');
    expect(result.strong, 'H99999');
    expect(result.definition, contains('non disponible'));
  });

  test('search ranks an exact code first', () async {
    final lexicon = StrongLexicon.instance;
    final results = await lexicon.search('H0430');
    expect(results, isNotEmpty);
    expect(results.first.strong, 'H0430');
  });

  test('search finds a code by its definition', () async {
    final lexicon = StrongLexicon.instance;
    // This phrase should uniquely identify H0001 in the embedded Strong lexicon.
    final results = await lexicon.search('Dieu père de son peuple');
    expect(results, isNotEmpty);
    expect(results.first.strong, 'H0001');
  });

  test('search also finds a Strong entry by a common definition word', () async {
    final lexicon = StrongLexicon.instance;
    final results = await lexicon.search('père');
    expect(results, isNotEmpty);
    expect(results.any((r) => r.strong == 'H0001'), isTrue);
    expect(results.first.definition.toLowerCase(), contains('père'));
  });
}