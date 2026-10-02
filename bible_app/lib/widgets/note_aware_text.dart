import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'bible_theme_scope.dart';

import '../data/app_preferences.dart';
import '../data/note_reference_linker.dart';
import '../data/reference_parser.dart';
import '../models/verse.dart';

/// Renders a verse text with its notes.
///
/// Two dispositions (maquette v3/v4):
/// - [NoteDisposition.inline]: the note follows the noted word, like
///   `textWithNotes`.
/// - [NoteDisposition.below]: the noted word carries a superscript $^$ and the
///   note is a numbered card under the verse.
///
/// The noted word is always located via `note.position` (char offset) with a
/// fallback search on `note.word`.
///
/// Note glyphs (superscript, inline note, note card) keep their v4 proportions
/// relative to the reading text size — see [_noteScaled].
class NoteAwareVerseText extends StatefulWidget {
  final Verse verse;
  final NoteDisposition disposition;
  final TextAlign textAlign;

  /// Called with a [BibleReference] when the reader taps a reference embedded
  /// in a note (« Voir Es. 45:18. »). Null renders the references as plain
  /// text.
  final ValueChanged<BibleReference>? onReferenceTap;

  const NoteAwareVerseText({
    super.key,
    required this.verse,
    required this.disposition,
    this.textAlign = TextAlign.left,
    this.onReferenceTap,
  });

  @override
  State<NoteAwareVerseText> createState() => _NoteAwareVerseTextState();
}

class _NoteAwareVerseTextState extends State<NoteAwareVerseText> {
  /// Recognizers owned by the inline-note spans. Cleared on each build (the
  /// previous spans are replaced wholesale), disposed with the widget.
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    final theme = Theme.of(context);
    final verse = widget.verse;
    final text = verse.text;
    final notes = verse.notes;
    final body = theme.textTheme.bodyLarge;

    if (notes.isEmpty || text.isEmpty) {
      return Text(text, style: body, textAlign: widget.textAlign);
    }

    final ranges = _Ranges(verse);
    if (ranges.isEmpty) {
      return Text(text, style: body, textAlign: widget.textAlign);
    }

    final readingTheme = BibleThemeScope.of(context);
    final accent = readingTheme.linkColor;
    final spans = <TextSpan>[];
    var cursor = 0;
    var i = 0;
    for (final r in ranges.sorted) {
      if (r.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r.start)));
      }
      // Le mot noté reste au corps du texte : ni surlignage, ni
      // soulignage, ni couleur. La graisse seule le signale dans la
      // phrase — la couleur est réservée à l'exposant qui suit.
      spans.add(
        TextSpan(
          text: text.substring(r.start, r.end),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      if (widget.disposition == NoteDisposition.below) {
        spans.add(
          TextSpan(
            text: '${i + 1}',
            style: TextStyle(
              fontSize: _noteScaled(body, .56),
              color: accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else {
        // « À la suite » : la note suit le mot, comme textWithNotes.
        final noteStyle = TextStyle(
          color: readingTheme.noteColor,
          fontSize: _noteScaled(body, .81),
        );
        spans.add(
          TextSpan(
            children: [
              const TextSpan(text: ' ('),
              ...linkifiedNoteSpans(
                text: r.note.note,
                style: noteStyle,
                accent: accent,
                onTap: widget.onReferenceTap,
                sink: _recognizers,
              ),
              const TextSpan(text: ')'),
            ],
            style: noteStyle,
          ),
        );
      }
      cursor = r.end;
      i++;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: spans),
          style: body,
          textAlign: widget.textAlign,
        ),
        if (widget.disposition == NoteDisposition.below)
          for (var k = 0; k < ranges.sorted.length; k++)
            NoteCard(
              index: k + 1,
              note: ranges.sorted[k].note,
              onReferenceTap: widget.onReferenceTap,
            ),
      ],
    );
  }
}

/// The note text with its Bible references turned into tappable spans.
///
/// References are only linked when [onTap] is set — otherwise the note stays
/// plain text (a recognizer that answers to nothing is a button-shaped lie).
/// Newly created recognizers are appended to [sink] so the owning widget can
/// dispose them. Public because the continuous-paragraph layout of the reader
/// weaves note texts into flowing spans too, with the same sink discipline.
List<InlineSpan> linkifiedNoteSpans({
  required String text,
  required TextStyle style,
  required Color accent,
  required ValueChanged<BibleReference>? onTap,
  required List<TapGestureRecognizer> sink,
}) {
  // Le texte source marque ses retours à la ligne par une paire d'antislashs :
  // elle devient un saut de ligne réel avant tout le reste (les positions des
  // références sont cherchées sur le texte déjà transformé).
  final display = text.replaceAll(r'\\', '\n');
  if (onTap == null) return [TextSpan(text: display, style: style)];
  final refs = findNoteReferences(display);
  if (refs.isEmpty) return [TextSpan(text: display, style: style)];

  final linkStyle = style.copyWith(
    color: accent,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline,
    decorationStyle: TextDecorationStyle.dotted,
  );
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final ref in refs) {
    if (ref.start > cursor) {
      spans.add(
        TextSpan(text: display.substring(cursor, ref.start), style: style),
      );
    }
    final recognizer = TapGestureRecognizer()
      ..onTap = () => onTap(ref.reference);
    sink.add(recognizer);
    spans.add(
      TextSpan(
        text: display.substring(ref.start, ref.end),
        style: linkStyle,
        recognizer: recognizer,
      ),
    );
    cursor = ref.end;
  }
  if (cursor < display.length) {
    spans.add(TextSpan(text: display.substring(cursor), style: style));
  }
  return spans;
}

/// Size of a note glyph, as a [factor] of the reading text size. The reference
/// ratios come from the v4 layout at its 16 pt body: 9 pt superscript, 13 pt
/// note text.
double _noteScaled(TextStyle? body, double factor) =>
    (body?.fontSize ?? 16) * factor;

class NoteCard extends StatefulWidget {
  final int index;
  final VerseNote note;
  final ValueChanged<BibleReference>? onReferenceTap;

  const NoteCard({
    super.key,
    required this.index,
    required this.note,
    this.onReferenceTap,
  });

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    final theme = Theme.of(context);
    final readingTheme = BibleThemeScope.of(context);
    final accent = readingTheme.linkColor;
    final size = _noteScaled(theme.textTheme.bodyLarge, .78);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        color: readingTheme.panelColor,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${widget.index} · ${widget.note.word} : ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: size,
                color: accent,
              ),
            ),
            ...linkifiedNoteSpans(
              text: widget.note.note,
              style: TextStyle(fontSize: size, color: readingTheme.noteColor),
              accent: accent,
              onTap: widget.onReferenceTap,
              sink: _recognizers,
            ),
          ],
        ),
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _Range {
  final int start;
  final int end;
  final VerseNote note;

  _Range(this.start, this.end, this.note);
}

class _Ranges {
  final List<_Range> _ranges = [];

  _Ranges(Verse verse) {
    final text = verse.text;
    for (final n in verse.notes) {
      var start = n.position;
      var end = start + n.word.length;
      if (start < 0 || start >= text.length) {
        final found = text.indexOf(n.word);
        if (found < 0) continue;
        start = found;
        end = start + n.word.length;
      }
      if (end <= text.length) {
        _ranges.add(_Range(start, end, n));
      }
    }
    _ranges.sort((a, b) => a.start.compareTo(b.start));
  }

  bool get isEmpty => _ranges.isEmpty;

  List<_Range> get sorted => _ranges;
}
