import 'package:flutter/material.dart';

import 'premium_style.dart';

/// The word of a Strong entry, at the head of a card.
///
/// It is written the way the verse-study card has always written it — the
/// platform serif, heavy, read right-to-left for Hebrew — and the fiche
/// follows, asking only for a [size] its own room can hold, so that every
/// letter of a Hebrew or Greek lemma stays readable. A lemma is often a
/// single word without space, so the size shrinks — never under 18 — to the
/// widest token that fits, and a long word cannot run off the card.
class StrongLemma extends StatelessWidget {
  const StrongLemma({
    super.key,
    required this.lemma,
    required this.strong,
    required this.language,
    this.size = 26,
    this.align = TextAlign.left,
  });

  /// The lemma as the source writes it, possibly absent.
  final String? lemma;

  /// The Strong code, written when the entry carries no lemma.
  final String strong;

  /// A `hebrew` lemma is read from the right, as the study card reads it.
  final String? language;

  /// Height of the letters: the study card writes at 26, the fiche has the
  /// room — and the wish — to write larger.
  final double size;

  /// Each card lines the word up with the text around it: the study card
  /// runs its lines from the left, the fiche centres its header.
  final TextAlign align;

  /// Floor under a lemma that does not fit even shrunk.
  static const double _minSize = 18;

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final text = lemma != null && lemma!.isNotEmpty ? lemma! : strong;
    // The row gives the word the full width of the card, so a wrapped lemma
    // still lines up where the card lines its own text up.
    return Directionality(
      textDirection:
          language == 'hebrew' ? TextDirection.rtl : TextDirection.ltr,
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth;
                var widest = 0.0;
                for (final token in text.split(RegExp(r'\s+'))) {
                  final tp = TextPainter(
                    text: TextSpan(text: token, style: _style(p.textDark, size)),
                    textDirection: TextDirection.ltr,
                  )..layout();
                  if (tp.width > widest) widest = tp.width;
                }
                final fitted = widest > maxWidth
                    ? (size * maxWidth / widest)
                        .clamp(_minSize, size)
                        .toDouble()
                    : size;
                return Text(
                  text,
                  textAlign: align,
                  style: _style(p.textDark, fitted),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _style(Color color, double fontSize) => TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
        fontFamily: 'serif',
      );
}
