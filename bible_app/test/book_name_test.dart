import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/book_catalog.dart';

/// The BYM names its books `Bereshit`, `Shemot`, `Shir Hashirim`; every
/// translation on the catalogue is French. That difference is the one thing on
/// screen that answers « which text am I reading? » — so it has to hold for all
/// 66 books, and it has to be reached through one function rather than by
/// rewriting `catalogEntry(i).name` at each call site.
void main() {
  const bym = 'BYM';

  group('le catalogue', () {
    test('compte 66 livres', () {
      expect(bookCatalog.length, 66);
    });

    test('tout livre porte un nom BYM', () {
      for (var i = 1; i <= 66; i++) {
        final entry = catalogEntry(i);
        expect(entry.hebrewName.trim(), isNotEmpty, reason: 'livre $i');
        expect(entry.shortName.trim(), isNotEmpty, reason: 'livre $i');
      }
    });

    test('aucun nom BYM ne se confond avec son nom français', () {
      // This is the whole point of the change: a name identical to the French one
      // differentiates nothing, and the reader would have no way of telling which
      // text is on screen.
      final identiques = <String>[];
      for (var i = 1; i <= 66; i++) {
        final entry = catalogEntry(i);
        if (entry.hebrewName == entry.shortName) {
          identiques.add('${entry.shortName} (#$i)');
        }
      }
      expect(identiques, isEmpty, reason: 'noms BYM identiques au français');
    });

    test('les noms BYM sont uniques', () {
      final vus = <String>{};
      for (var i = 1; i <= 66; i++) {
        final nom = catalogEntry(i).hebrewName;
        expect(vus.add(nom), isTrue, reason: '« $nom » est en double (livre $i)');
      }
    });

    test('la forme bilingue double chaque rangée de la feuille Livres', () {
      // La feuille lit `bilingualName` : chaque ligne porte la tête BYM puis
      // le français entre parenthèses. Sans elle, Évangiles et Testament de
      // Yehoshoua — les deux sections que le catalogue ne nommait qu'en
      // français — affichaient du français seul.
      for (var i = 1; i <= 66; i++) {
        final entry = catalogEntry(i);
        expect(
          entry.bilingualName,
          '${entry.hebrewName} (${entry.shortName})',
          reason: 'livre $i',
        );
      }
      expect(catalogEntry(1).bilingualName, 'Bereshit (Genèse)');
      expect(catalogEntry(21).bilingualName, 'Nahoum (Nahum)');
      expect(catalogEntry(40).bilingualName, 'Mattithyah (Matthieu)');
      expect(catalogEntry(51).bilingualName, 'Roma (Romains)');
      expect(catalogEntry(62).bilingualName, 'Ivriyim (Hébreux)');
    });

    test('un nom BYM trop long pour la pastille est raccourci', () {
      // The pill has one width for every book. `Divrei Hayamim 1` is wider than
      // « 1 Chroniques », so without this the reading bar overflows on the BYM —
      // which is the version everyone opens the app on.
      for (var i = 1; i <= 66; i++) {
        final entry = catalogEntry(i);
        expect(
          entry.hebrewBarLabel.length,
          lessThanOrEqualTo(entry.barLabel.length + 6),
          reason: '${entry.hebrewName} déborde la pastille',
        );
      }
      expect(catalogEntry(38).hebrewBarLabel, '1 Hay. d.');
    });
  });

  group('le nom affiché', () {
    test('la BYM lit en BYM', () {
      expect(bookDisplayName(1, code: bym, embeddedCode: bym), 'Bereshit');
      expect(bookDisplayName(40, code: bym, embeddedCode: bym), 'Mattithyah');
    });

    test('une traduction se lit en français', () {
      expect(bookDisplayName(1, code: 'DBY', embeddedCode: bym), 'Genèse');
      expect(bookDisplayName(40, code: 'KJV', embeddedCode: bym), 'Matthieu');
    });

    test('sans version, le français — jamais le BYM', () {
      // The surfaces that gather across versions (favourites, notes, recherche)
      // have none. Defaulting them to Hebrew would rename a Darby highlight to
      // `Bereshit`, and the reader could no longer find it by typing « Genèse ».
      expect(bookDisplayName(1, embeddedCode: bym), 'Genèse');
      expect(bookDisplayName(40, embeddedCode: bym), 'Matthieu');
    });

    test('la pastille est la forme courte du même nom', () {
      expect(
        bookDisplayLabel(1, code: bym, embeddedCode: bym),
        catalogEntry(1).hebrewBarLabel,
      );
      expect(
        bookDisplayLabel(49, code: bym, embeddedCode: bym),
        catalogEntry(49).hebrewBarLabel,
      );
      expect(bookDisplayLabel(49, code: 'DBY', embeddedCode: bym), '1 Cor.');
    });

    test('`isBymVersion` ne prend pas « aucune version » pour la BYM', () {
      expect(isBymVersion(bym, bym), isTrue);
      expect(isBymVersion('LSGS', bym), isFalse);
      expect(isBymVersion(null, bym), isFalse);
    });
  });
}
