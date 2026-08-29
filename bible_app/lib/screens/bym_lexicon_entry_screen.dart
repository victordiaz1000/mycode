import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/lexicon_index.dart';
import '../data/note_reference_linker.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/premium_style.dart';

/// A single entry of the BYM lexicon: the anchored word in a header card,
/// its note definition, and where it was first met. The reference opens the
/// verse in the reader through [onOpenVerse].
///
/// The Bible references embedded in the definition are rendered exactly like
/// the note references of the reading screen — accent colour, dotted
/// underline, background tint — and tappable towards the verse they name.
class BymLexiconEntryScreen extends StatefulWidget {
  final DictionaryEntry entry;

  /// Opens the referenced verse in a reader tab. Null when the screen stands
  /// alone (tests): the button then states the reference without navigating,
  /// and the definition keeps its references as plain text — a recognizer
  /// that answers to nothing is a button-shaped lie.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const BymLexiconEntryScreen({
    super.key,
    required this.entry,
    this.onOpenVerse,
  });

  @override
  State<BymLexiconEntryScreen> createState() => _BymLexiconEntryScreenState();
}

class _BymLexiconEntryScreenState extends State<BymLexiconEntryScreen> {
  /// Recognizers owned by the linked reference spans. Cleared on each build
  /// (the previous spans are replaced wholesale), disposed with the widget.
  final List<TapGestureRecognizer> _recognizers = [];

  String get _reference {
    final abbr = catalogEntry(widget.entry.bookIndex).abbreviation;
    return '$abbr ${widget.entry.chapter}:${widget.entry.verseNumber}';
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// The definition, wearing the same look as a note card of the reading
  /// screen — accent bar on the left, panel background, note-coloured text —
  /// with its Bible references turned into tappable spans like there. Plain
  /// text without a destination to offer. The size / typeface / alignment are
  /// the fiche-wide display settings.
  Widget _definition(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    final readingTheme = BibleThemeScope.of(context);
    if (widget.onOpenVerse == null) {
      return Text(
        widget.entry.definition,
        style: premiumText(
          context,
          style.fontSize,
          FontWeight.w500,
          p.textDark,
          height: 1.6,
        ).copyWith(fontFamily: style.fontFamily),
        textAlign: style.align,
      );
    }
    final refs = findNoteReferences(widget.entry.definition);
    if (refs.isEmpty) {
      return Text(
        widget.entry.definition,
        style: premiumText(
          context,
          style.fontSize,
          FontWeight.w500,
          p.textDark,
          height: 1.6,
        ).copyWith(fontFamily: style.fontFamily),
        textAlign: style.align,
      );
    }
    final size = style.fontSize;
    final base = TextStyle(
      color: readingTheme.noteColor,
      fontSize: size,
      fontFamily: style.fontFamily,
    );
    final linkStyle = TextStyle(
      color: readingTheme.linkColor,
      fontSize: size,
      fontFamily: style.fontFamily,
      fontWeight: FontWeight.w700,
      decoration: TextDecoration.underline,
      decorationStyle: TextDecorationStyle.dotted,
      backgroundColor: readingTheme.linkColor.withValues(alpha: .12),
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final ref in refs) {
      if (ref.start > cursor) {
        spans.add(
          TextSpan(
              text: widget.entry.definition.substring(cursor, ref.start)),
        );
      }
      final reference = ref.reference;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onOpenVerse!(
              reference.bookIndex,
              reference.chapter ?? 1,
              reference.verse ?? 1,
            );
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.entry.definition.substring(ref.start, ref.end),
          style: linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = ref.end;
    }
    if (cursor < widget.entry.definition.length) {
      spans.add(TextSpan(text: widget.entry.definition.substring(cursor)));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8, right: 10),
      decoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: readingTheme.linkColor, width: 3)),
        color: readingTheme.panelColor,
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(2)),
      ),
      child: Text.rich(
        TextSpan(children: spans),
        style: base,
        textAlign: style.align,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FicheTextScope(builder: (context, style) => _scaffold(context, style));
  }

  Widget _scaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        actions: const [FicheDisplayMenuButton()],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: p.heroGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: premiumShadow(
                    p.primaryDark,
                    opacity: 0.2,
                    blur: 16,
                    offset: const Offset(0, 6),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notes BYM Lexique',
                      style: premiumText(
                        context,
                        11,
                        FontWeight.w800,
                        p.onPrimary.withValues(alpha: .85),
                        spacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.entry.word,
                      style: premiumText(
                        context,
                        24,
                        FontWeight.w800,
                        p.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.entry.occurrences > 1
                          ? '$_reference · ${widget.entry.occurrences} occurrences'
                          : _reference,
                      style: premiumText(
                        context,
                        13,
                        FontWeight.w600,
                        p.onPrimary.withValues(alpha: .85),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Définition',
                style: premiumText(context, 12, FontWeight.w800, p.textGrey),
              ),
              const SizedBox(height: 8),
              _definition(context, style),
              const SizedBox(height: 24),
              if (widget.onOpenVerse != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      foregroundColor: p.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => widget.onOpenVerse!(
                      widget.entry.bookIndex,
                      widget.entry.chapter,
                      widget.entry.verseNumber,
                    ),
                    icon: const Icon(Icons.menu_book_rounded),
                    label: Text(
                      'Ouvrir le verset',
                      style: premiumText(
                        context,
                        15,
                        FontWeight.w700,
                        p.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
