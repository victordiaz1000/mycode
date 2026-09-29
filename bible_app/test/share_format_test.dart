import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/share_text.dart';

/// The formatting the reader copies and shares.
///
/// These are pure functions, and that is the point: the strings used to live in
/// `chapter_reader.dart`, twice, where nothing could test them without mounting a
/// reader — and they had drifted, « Partager » naming a downloaded version and
/// « Copier » not.
void main() {
  const bym = 'BYM';

  PassageRef v(int n, {String? text}) => PassageRef(
        reference: 'Genèse 1:$n',
        verse: n,
        text: text ?? 'texte $n',
      );

  group('le badge de version', () {
    test('le texte embarqué ne se nomme pas', () {
      expect(versionTag(bym, bym), isNull);
      expect(versionTag(null, bym), isNull);
    });

    test('une version téléchargée se nomme', () {
      expect(versionTag('DBY', bym), ' (DBY)');
    });
  });

  group('la forme « copier »', () {
    test('le nom de l\'app ouvre le bloc, la référence ouvre la ligne', () {
      expect(formatCitation(v(1)), '$appName\nGenèse 1:1 texte 1');
    });

    test('la version nommée suit la référence', () {
      expect(
        formatCitation(v(1), tag: ' (DBY)'),
        '$appName\nGenèse 1:1 (DBY) texte 1',
      );
    });

    test('une sélection porte le nom une seule fois, puis un verset par ligne', () {
      expect(formatCitations([v(1), v(2), v(3)]).split('\n'), [
        appName,
        'Genèse 1:1 texte 1',
        'Genèse 1:2 texte 2',
        'Genèse 1:3 texte 3',
      ]);
      expect(formatCitations(const []), isEmpty);
    });
  });

  group('la forme « partager »', () {
    test('les mots entre guillemets, la référence en dessous', () {
      expect(formatPassage(v(1)), '$appName\n« texte 1 »\n— Genèse 1:1');
    });

    test('la version nommée ferme la référence', () {
      expect(
        formatPassage(v(1), tag: ' (LSGS)'),
        '$appName\n« texte 1 »\n— Genèse 1:1 (LSGS)',
      );
    });
  });

  group('le nom de l\'app', () {
    test('ouvre chaque forme : copie comme partage, verset comme sélection', () {
      // Ce que l'app recopie circule orphelin sans sa source : la première
      // ligne doit être le nom, et ce dans les quatre chemins — un seul oublié
      // (la copie de sélection, qui passait par son propre join) suffirait à
      // renvoyer un texte sans signature.
      final formes = [
        formatCitation(v(1)),
        formatCitations([v(1), v(2)]),
        formatPassage(v(1)),
        formatSelection([v(1), v(2)]),
        formatSelection([v(3)]),
      ];
      for (final texte in formes) {
        expect(texte.split('\n').first, appName);
      }
    });
  });

  group('une sélection', () {
    test('un seul verset retombe sur la forme citation', () {
      // A one-verse selection must not print a range like « 1:1-1 ».
      expect(formatSelection([v(3)]), formatPassage(v(3)));
    });

    test('une suite se lit comme une plage', () {
      final texte = formatSelection([v(1), v(2), v(3)]);
      expect(texte, contains('« texte 1 »\n« texte 2 »\n« texte 3 »'));
      expect(
        texte,
        endsWith('— Genèse 1:1-3'),
        reason: 'le livre et le chapitre ne se répètent pas à chaque numéro',
      );
    });

    test('une sélection trouée énumère ses versets', () {
      // Writing « 1:1-5 » for verses 1, 3 and 5 would attribute words to a verse
      // nobody chose.
      final texte = formatSelection([v(1), v(3), v(5)]);
      expect(texte, endsWith('— Genèse 1:1, 3, 5'));
    });

    test('une sélection une version téléchargée nomme la version', () {
      final texte = formatSelection([v(1), v(2)], tag: ' (DBY)');
      expect(texte, endsWith('— Genèse 1:1-2 (DBY)'));
    });

    test('une sélection vide ne rend rien', () {
      expect(formatSelection(const []), isEmpty);
    });
  });
}
