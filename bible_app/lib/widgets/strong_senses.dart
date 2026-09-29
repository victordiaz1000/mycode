import 'package:flutter/material.dart';

import '../data/strong_lexicon.dart';

/// The senses of a Strong entry, as the body of a card.
///
/// The source numbers its own senses — stems (« Qal », « Hifil ») and rungs
/// (« 1a1) », « 2b1) ») — and [StrongDefinition.outline] keeps that ladder.
/// Where an entry carries one, this renders it as an indented tree; where the
/// source lists plain bullets, they are rendered as they always were, numbered
/// by the caller when it asks for it.
class StrongSenses extends StatelessWidget {
  const StrongSenses({
    super.key,
    required this.outline,
    required this.senses,
    required this.accent,
    required this.textStyle,
    required this.markerStyle,
    this.align = TextAlign.start,
    this.numbered = false,
    this.rowGap = 16,
  });

  /// The source's outline, empty for a flat entry.
  final List<StrongOutlineNode> outline;

  /// The flat senses, used when [outline] is empty.
  final List<String> senses;

  /// Colour of the bullet and of the codes the source writes.
  final Color accent;

  /// Body of a line, and the style of what marks it: a stem, a numbering code.
  final TextStyle textStyle;
  final TextStyle markerStyle;

  final TextAlign align;

  /// Prefix each flat sense with its rank (« 1) », « 2) ») instead of the
  /// bullet. The fiche bullets; the verse-study card has always numbered.
  final bool numbered;

  /// Space between two lines.
  final double rowGap;

  /// Indent of one rung. The source goes five rungs deep at most; the cap
  /// keeps a narrow screen from pushing the text off the card.
  static const double _rung = 16;

  /// Width of the marker column: the bullet and its gap, or as much room left
  /// for the lines that carry no bullet, so a level always starts in one place.
  static const double _marker = 18;

  static final RegExp _leadingCode = RegExp(r'^(\d+(?:[A-Za-z]+\d*)*\)?)');

  @override
  Widget build(BuildContext context) {
    final rows = outline.isNotEmpty
        ? [for (final node in outline) _outlineRow(node)]
        : [for (var i = 0; i < senses.length; i++) _flatRow(senses[i], i)];
    final children = <Widget>[];
    for (final row in rows) {
      if (children.isNotEmpty) children.add(SizedBox(height: rowGap));
      children.add(row);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _flatRow(String sense, int index) {
    if (numbered) {
      return Text('${index + 1}) $sense', textAlign: align, style: textStyle);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(sense, textAlign: align, style: textStyle)),
      ],
    );
  }

  /// One line of the source's outline, indented by its rung: a stem reads as
  /// a heading, a numbering code sets itself apart, a sense keeps its bullet.
  Widget _outlineRow(StrongOutlineNode node) {
    final indent = (node.level > 4 ? 4 : node.level) * _rung;

    Widget line(TextSpan span) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: indent),
            if (node.kind == StrongOutlineKind.sense) ...[
              Container(
                margin: const EdgeInsets.only(top: 6),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: _marker),
            Expanded(child: Text.rich(span, textAlign: align)),
          ],
        );

    switch (node.kind) {
      case StrongOutlineKind.header:
        // The label carries the emphasis; the source's own spacing between it
        // and what follows is kept as it wrote it.
        return line(TextSpan(children: [
          if (node.label != null)
            TextSpan(text: '(${node.label})', style: markerStyle)
          else
            TextSpan(text: node.text, style: markerStyle),
          if (node.label != null && node.text.isNotEmpty)
            TextSpan(text: node.text, style: textStyle),
        ]));
      case StrongOutlineKind.number:
        final code = _leadingCode.firstMatch(node.text)?.group(0) ?? '';
        return line(TextSpan(children: [
          if (code.isNotEmpty) TextSpan(text: code, style: markerStyle),
          TextSpan(text: node.text.substring(code.length), style: textStyle),
        ]));
      case StrongOutlineKind.sense:
        return line(TextSpan(text: node.text, style: textStyle));
    }
  }
}
