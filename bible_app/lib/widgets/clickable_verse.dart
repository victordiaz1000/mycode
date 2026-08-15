import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/lsgs.dart';

/// Opens the fiche of the tapped Strong word. The index is the position of the
/// token in the list, so the caller can navigate between the strong words of the
/// verse (« Mot X / N du verset »).
typedef StrongTapCallback = void Function(int tokenIndex, String strong);

class ClickableVerse extends StatelessWidget {
  final List<LsgsToken> tokens;
  final StrongTapCallback onStrongTap;
  final int? selectedTokenIndex;

  const ClickableVerse({
    super.key,
    required this.tokens,
    required this.onStrongTap,
    this.selectedTokenIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final defaultStyle = theme.textTheme.bodyLarge;
    final accent = theme.colorScheme.primary;

    final spans = <InlineSpan>[];
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.strong == null || token.strong!.isEmpty) {
        spans.add(TextSpan(text: token.text, style: defaultStyle));
        continue;
      }

      final selected = i == selectedTokenIndex;
      final index = i;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onStrongTap(index, token.strong!);

      spans.add(TextSpan(
        text: token.text,
        style: defaultStyle?.copyWith(
          color: selected ? theme.colorScheme.onPrimaryContainer : accent,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          decorationColor: accent,
          decorationThickness: selected ? 2 : 1.4,
          backgroundColor: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
        semanticsLabel: '${token.text.trim()}, Strong ${token.strong}',
        recognizer: recognizer,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      textAlign: TextAlign.start,
    );
  }
}