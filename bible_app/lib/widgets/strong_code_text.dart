import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/book_catalog.dart';

/// Renders [text] while highlighting the Strong codes it contains (e.g. the
/// « H1 » / « H4236 » references inside an etymology) as tappable links.
///
/// When [linkBareNumbers] is on, a Strong code written **without** its letter
/// (« Vient de 5975 ») is linked the same way.
///
/// The code spans are reported through [onStrongTap] **unpadded**, as written
/// in the source text; the caller decides how to interpret them (the lexicon
/// keys are zero-padded to 4 digits, hence [padToFour]).
class StrongCodeText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  /// Non-null makes the codes tappable; null keeps them as plain highlighted
  /// spans.
  final void Function(String strong)? onStrongTap;

  /// Links bare Strong numbers (no G/H letter) as well. Useful for
  /// etymologies that write « 5975 » instead of « H5975 ».
  final bool linkBareNumbers;

  const StrongCodeText({
    super.key,
    required this.text,
    this.style,
    this.onStrongTap,
    this.linkBareNumbers = false,
  });

  static final RegExp _codePattern =
      RegExp(r'(?<!\w)((?:[GH]\d{1,4})|(\d{1,4}))(?!\w)');
  static final RegExp _tokenPattern = RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ]+");

  /// Zero-pads a code written in the source to the lexicon key format:
  /// `H1` → `H0001`, `G716` → `G0716`, `H4236` stays.
  static String padToFour(String strong) {
    if (strong.length >= 5) return strong;
    final prefix = strong[0];
    final digits = strong.substring(1);
    return '$prefix${digits.padLeft(4, '0')}';
  }

  /// French Bible book names as folded tokens (« samuel », « rois » …),
  /// derived from the canonical catalog. A bare number whose last alphabetic
  /// predecessor is one of these is a chapter/verse reference (« 1 Samuel
  /// 9.1 »), not a Strong code.
  static final Set<String> _bookTokens = () {
    final set = <String>{};
    for (final book in bookCatalog) {
      for (final token in foldAccents(book.shortName).split(' ')) {
        if (token.isNotEmpty) set.add(token);
      }
    }
    set.addAll(const {'psaume', 'cantique'});
    return set;
  }();

  /// Strips the diacritics and lowercases [value] for accent-insensitive
  /// comparisons without needing an intl when() table.
  static String foldAccents(String value) {
    const from = 'àâäéèêëîïôöùûüçÀÂÄÉÈÊËÎÏÔÖÙÛÜÇ';
    const to = 'aaaeeeeiioouuucAAAEEEEIIOOUUUC';
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      final index = from.indexOf(char);
      buffer.write(index >= 0 ? to[index] : char);
    }
    return buffer.toString().toLowerCase();
  }

  /// A bare number is a Strong code only when it is neither the privative
  /// « 1 » / book-ordinal « 2 », nor the tail of a verse reference.
  bool _isLinkedBareNumber(int start, int end) {
    final digits = text.substring(start, end);
    if (digits == '1' || digits == '2') return false;
    final before = text.substring(0, start);
    final tokens = _tokenPattern.allMatches(before).toList();
    if (tokens.isEmpty) return true;
    return !_bookTokens.contains(foldAccents(tokens.last.group(0)!));
  }

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final matches = _codePattern.allMatches(text);
    if (matches.isEmpty) return Text(text, style: baseStyle);

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(
          text: text.substring(cursor, match.start),
          style: baseStyle,
        ));
      }
      final strong = match.group(1)!;
      final isBare = match.group(2) != null;
      final linked = isBare
          ? linkBareNumbers && _isLinkedBareNumber(match.start, match.end)
          : true;
      final callback = onStrongTap;
      TapGestureRecognizer? recognizer;
      if (callback != null && linked) {
        recognizer = TapGestureRecognizer()
          ..onTap = () => callback(strong);
      }
      spans.add(TextSpan(
        text: strong,
        style: baseStyle.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          decoration: linked && onStrongTap != null
              ? TextDecoration.underline
              : null,
          decorationStyle:
              linked && onStrongTap != null ? TextDecorationStyle.dotted : null,
          decorationColor: accent,
        ),
        recognizer: recognizer,
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }
    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      softWrap: true,
    );
  }
}