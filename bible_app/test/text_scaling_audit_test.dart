import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/widgets/responsive_text_scaling.dart';

/// Audit of the text scale across screen sizes.
///
/// Ce fichier ne garde plus que l'échelle de lecture elle-même : le balayage
/// anti-débordement qu'il contenait est remplacé par
/// `responsive_overflow_test.dart`, strictement plus large.
///
/// Il ne s'agissait pas d'un doublon mais d'un test qui *certifiait à tort*. Il
/// est resté vert alors que l'Accueil débordait sur trois angles morts :
///
/// 1. Il ne défilait jamais. Les sections de l'Accueil vivent dans une
///    `ListView` paresseuse : celles sous la ligne de flottaison ne sont ni
///    mises en page ni peintes, donc leurs débordements sont invisibles. La
///    pastille `_badge` sortait de 21 px sur un 320 px sans que rien ne le dise.
/// 2. Ses hauteurs (780 px sous 480 de large, 1000 au-delà) ne descendaient
///    jamais assez bas pour éprouver l'axe vertical. Le squelette de démarrage
///    de l'Accueil, haut de 659 px figés, débordait sous ~660 px de hauteur
///    utile — donc sur un 360x640, très courant, et en paysage.
/// 3. Il naviguait par `find.text('Lecture')`, or sous 480 px le shell masque
///    les libellés de la barre (`labelBehavior: alwaysHide`). Le finder revenait
///    vide, le `continue` sautait la destination : sur téléphone, ce test ne
///    visitait en réalité *que* l'Accueil.
void main() {
  /// Representative surfaces, from the narrowest Android phone still in the
  /// wild to a tablet in landscape.
  const widths = <double>[320, 360, 390, 412, 480, 800, 1024];

  group('reading size ladder', () {
    test('every step stays distinct and ordered', () {
      final sizes = [for (final step in ReadingTextSize.values) step.fontSize];
      for (var i = 1; i < sizes.length; i++) {
        expect(
          sizes[i],
          greaterThan(sizes[i - 1]),
          reason: '« ${ReadingTextSize.values[i].label} » (${sizes[i]}) '
              'ne dépasse pas « ${ReadingTextSize.values[i - 1].label} » '
              '(${sizes[i - 1]})',
        );
      }
    });

    /// The narrow-screen reduction must live in exactly ONE place. It used to
    /// live in two — a `ReadingTextSize.responsiveFontSize` ladder AND the
    /// `deviceFactor` folded into `main.dart`'s `textScaler` — with identical
    /// breakpoints and identical factors, both landing on the verse body. The
    /// two compounded to a 19 % cut where 10 % was intended. This pins the
    /// single surviving reduction to the range the code means.
    ///
    /// Le facteur est lu sur `ResponsiveTextScaling`, pas recopié : ce test
    /// traquait la duplication tout en en portant une — sa copie locale de
    /// l'échelle restait verte quelle que soit la dérive du code réel.
    test('the narrow-screen reduction is applied exactly once', () {
      for (final step in ReadingTextSize.values) {
        for (final width in widths) {
          final effective =
              step.fontSize * ResponsiveTextScaling.deviceFactor(width);
          expect(
            effective / step.fontSize,
            greaterThanOrEqualTo(0.90),
            reason: '« ${step.label} » à ${width.toInt()} px : '
                '${effective.toStringAsFixed(2)} pt pour ${step.fontSize} pt '
                'nominal — une seconde réduction s\'est glissée quelque part',
          );
        }
      }
    });
  });
}
