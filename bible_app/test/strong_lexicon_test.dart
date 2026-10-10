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

  test('a code written without its zero still finds its entry', () async {
    // L'ATI imprime « H853 » comme sa source l'affiche, la LSGS imprime
    // « H0853 » : mêmes chiffres, deux écritures, une seule entrée au
    // lexique. Sans cette borne, un code valide d'une version est introuvable
    // dans l'autre et la fiche se tait — 21 % des mots de l'ATI perdaient
    // leur lien pour une histoire de zéros.
    expect(StrongLexicon.canonique('h853'), 'H0853');
    expect(StrongLexicon.canonique('H4236'), 'H4236');
    expect(StrongLexicon.canonique('H7225'), 'H7225');
    expect(StrongLexicon.canonique('5975'), '5975',
        reason: "un nombre nu n'a pas de lettre à compléter");
    expect(StrongLexicon.codesOf('H853 H7225'), ['H0853', 'H7225']);

    final lexicon = StrongLexicon.instance;
    expect(await lexicon.contains('H853'), isTrue);
    final definition = await lexicon.lookup('H853');
    expect(definition.strong, 'H0853');
    expect(definition.definition, isNotEmpty);

    // Ce que le lexique ne porte pas le reste inconnu. La plage hébreu
    // étendue, elle, est désormais couverte — H8818 y est « Afel », un
    // binyan araméen ; l'ATI l'écrivait à la place du numéro, et le corpus
    // ne l'émet plus depuis la correction du parseur. La plage grecque ne
    // l'est que partiellement : G5625 reste muet.
    expect(await lexicon.contains('H8818'), isTrue);
    expect(await lexicon.contains('G5625'), isFalse);
  });

  test('an extended code answers with the form it names', () async {
    final lexicon = StrongLexicon.instance;

    // Le lexique standard s'arrête à H8674, mais Biblia numérote jusqu'à
    // 8853 — son aide l'annonce. Ces codes ne sont pas des lexies : ils
    // décrivent une forme, un binyan croisé avec un mode. La fiche le dit
    // au lieu de renvoyer la notice « hors lexique ».
    final h8799 = await lexicon.lookup('H8799');
    expect(h8799.strong, 'H8799');
    expect(h8799.introuvable, isFalse);
    expect(h8799.etendu, isTrue);
    expect(h8799.definition, contains('Radical Qal, mode imparfait'));
    expect(h8799.partOfSpeech, isNotEmpty);

    // Le grec de la même famille : un temps et un mode, pas une lexie.
    final g5719 = await lexicon.lookup('G5719');
    expect(g5719.etendu, isTrue);
    expect(g5719.definition, contains('Temps Présent, mode indicatif'));

    // Les fiches de forme restent hors de la liste des lexies : chercher
    // « père » ne remonte pas un binyan.
    expect(lexicon.formesCount, greaterThan(300));
    expect(lexicon.size, greaterThan(13000));
  });

  test('a code the SWORD modules lack still gets a lexicon fiche', () async {
    final lexicon = StrongLexicon.instance;

    // G2994 (Λαοδικεύς) et G2995 (λάρυγξ) : cités par la LSS comme par la
    // LSGS, absentes des modules SWORD. La fusion les construit, mais la
    // fusion complète ne peut pas être embarquée — elles viennent donc
    // d'un fichier à part, qui ne porte que celles-là.
    final g2994 = await lexicon.lookup('G2994');
    expect(g2994.introuvable, isFalse);
    expect(g2994.lemma, 'Λαοδικεύς');
    expect(g2994.definition, contains('Laodicée'));
    expect(g2994.senses, isNotEmpty);

    final g2995 = await lexicon.lookup('G2995');
    expect(g2995.introuvable, isFalse);
    expect(g2995.lemma, 'λάρυγξ');
    expect(g2995.definition, contains('gorge'));
    expect(g2995.outline, isNotEmpty,
        reason: 'les sens numérotés de la source restent une arborescence');

    // Ce sont des lexies : elles ne portent pas l'intitulé « Forme
    // grammaticale » des codes de forme, et elles entrent dans la recherche
    // comme toutes les autres.
    expect(g2994.etendu, isFalse);
    expect(g2995.etendu, isFalse);
    expect(
      (await lexicon.search('Laodicéen')).map((entry) => entry.strong),
      contains('G2994'),
    );
    expect(await lexicon.contains('G2995'), isTrue);
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
    final lexicon = StrongLexicon.instance;

    // H99999 est au-delà du Strong standard : c'est un code de la
    // numérotation étendue de Biblia, et la fiche l'explique — particule non
    // rendue en français, aucune définition nulle part — plutôt que de rester
    // muette.
    final etendu = await lexicon.lookup('H99999');
    expect(etendu.strong, 'H99999');
    expect(etendu.introuvable, isTrue);
    expect(etendu.definition, contains('numérotation étendue'));

    // Un code qui n'est pas de facture Strong : la phrase lisible suffit.
    final autre = await lexicon.lookup('X0042');
    expect(autre.strong, 'X0042');
    expect(autre.introuvable, isTrue);
    expect(autre.definition, contains('aucune définition'));
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