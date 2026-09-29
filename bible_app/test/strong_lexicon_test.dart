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

  test('the gloss the exporter used to drop is back as a signification',
      () async {
    final lexicon = StrongLexicon.instance;

    // The source line sits before the list of senses (« Paul ou Paulus =
    // petit ») and was read away with the <item>s it introduces.
    final g3972 = await lexicon.lookup('G3972');
    expect(g3972.signification, 'Paul ou Paulus = petit');

    // An entry the source gives no gloss to keeps the field away.
    final g2316 = await lexicon.lookup('G2316');
    expect(g2316.signification, isNull);
  });

  test('a Hebrew verb keeps its stems and its numbering as a tree', () async {
    final lexicon = StrongLexicon.instance;

    // H7200 (ra’ah) : (Qal) puis 1a1)…1a6), (Nifal) puis 1b1)…1b3).
    final h7200 = await lexicon.lookup('H7200');
    expect(h7200.outline, isNotEmpty);

    final qal = h7200.outline.firstWhere((node) => node.label == 'Qal');
    expect(qal.kind, StrongOutlineKind.header);
    expect(qal.level, 0);

    final nifal = h7200.outline.firstWhere((node) => node.label == 'Nifal');
    expect(nifal.level, qal.level,
        reason: 'les stems restent tous au même niveau');

    final rung =
        h7200.outline.firstWhere((node) => node.text.startsWith('1a1)'));
    expect(rung.kind, StrongOutlineKind.number);
    expect(rung.level, greaterThan(qal.level),
        reason: '« 1a1) voir » s’indente sous « (Qal) »');

    // A name the source never numbers keeps its plain list of bullets.
    expect((await lexicon.lookup('G3972')).outline, isEmpty);
  });

  test('a parent sense no longer folds its children into itself', () async {
    final lexicon = StrongLexicon.instance;

    // H1285 : <item>entre hommes</item> porte une <list> de 1a1) à 1a5). Le
    // texte du parent recopiait ses enfants, puis les reprenait un à un.
    final h1285 = await lexicon.lookup('H1285');
    expect(h1285.senses.first, 'entre hommes');
    expect(h1285.senses, contains('1a1) traité, alliance, ligue'));
    expect(
      h1285.senses.where(
          (sense) => sense.startsWith('entre') && sense.contains('1a1)')),
      isEmpty,
      reason: 'le parent ne recopie plus le détail de ses enfants',
    );

    // The outline says the same thing, level by level.
    expect(h1285.outline.first.text, 'entre hommes');
    expect(h1285.outline[1].text, '1a1) traité, alliance, ligue');
    expect(h1285.outline[1].level, greaterThan(h1285.outline.first.level));
    // …and the label the source puts between its two lists is kept.
    expect(h1285.outline.any((node) => node.text == '(phrases)'), isTrue);
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

  test('a token carrying two Strong codes answers the first one known',
      () async {
    final lexicon = StrongLexicon.instance;

    // Un mot du corpus porte parfois deux codes à la fois (Jean 18.35).
    expect(StrongLexicon.codesOf(' G3588 G4674 '), ['G3588', 'G4674']);
    expect(StrongLexicon.codesOf('H0001'), ['H0001']);
    expect((await lexicon.lookup('G3588 G4674')).strong, 'G3588');

    // Chaque code reste cherchable pour lui-même.
    expect((await lexicon.lookup('G4674')).strong, 'G4674');
    expect(await lexicon.contains('G3588 G4674'), isTrue);
    expect(await lexicon.contains('H99999 G4674'), isTrue);
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