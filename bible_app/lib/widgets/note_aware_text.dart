import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../models/verse.dart';

/// Renders a verse text with its notes.
///
/// Two dispositions (maquette v3/v4):
/// - [NoteDisposition.inline]: the note follows the noted word, like
///   `textWithNotes`.
/// - [NoteDisposition.below]: the noted word carries a superscript ¹²³ and the
///   note is a numbered card under the verse.
///
/// The noted word is always located via `note.position` (char offset) with a
/// fallback search on `note.word`.
///
/// Note glyphs (superscript, inline note, note card) keep their v4 proportions
/// relative to the reading text size — see [_noteScaled].
class NoteAwareVerseText extends StatelessWidget {
  final Verse verse;
  final NoteDisposition disposition;

  const NoteAwareVerseText({
    super.key,
    required this.verse,
    required this.disposition,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = verse.text;
    final notes = verse.notes;
    final body = theme.textTheme.bodyLarge;

    if (notes.isEmpty || text.isEmpty) {
      return Text(text, style: body);
    }

    final ranges = _Ranges(verse);
    if (ranges.isEmpty) {
      return Text(text, style: body);
    }

    final accent = theme.colorScheme.primary;
    final spans = <TextSpan>[];
    var cursor = 0;
    var i = 0;
    for (final r in ranges.sorted) {
      if (r.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, r.start)));
      }
      spans.add(TextSpan(
        text: text.substring(r.start, r.end),
        style: TextStyle(
          color: accent,
          fontWeight: FontWeight.bold,
          decoration: TextDecoration.underline,
          decorationStyle: TextDecorationStyle.dotted,
          backgroundColor: accent.withValues(alpha: .12),
        ),
      ));
      if (disposition == NoteDisposition.below) {
        spans.add(TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            fontSize: _noteScaled(body, .56),
            color: accent,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else {
        // « À la suite » : la note suit le mot, comme textWithNotes.
        spans.add(TextSpan(
          text: ' (${r.note.note})',
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: .75),
            fontSize: _noteScaled(body, .81),
          ),
        ));
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
        Text.rich(TextSpan(children: spans), style: body),
        if (disposition == NoteDisposition.below)
          for (var k = 0; k < ranges.sorted.length; k++)
            _NoteCard(index: k + 1, note: ranges.sorted[k].note),
      ],
    );
  }
}

/// Size of a note glyph, as a [factor] of the reading text size. The reference
/// ratios come from the v4 layout at its 16 pt body: 9 pt superscript, 13 pt
/// note text.
double _noteScaled(TextStyle? body, double factor) =>
    (body?.fontSize ?? 16) * factor;

class _NoteCard extends StatelessWidget {
  final int index;
  final VerseNote note;

  const _NoteCard({required this.index, required this.note});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final size = _noteScaled(theme.textTheme.bodyLarge, .78);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(left: 10, top: 6, bottom: 6),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: accent, width: 3)),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$index · ${note.word} : ',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: size,
                color: accent,
              ),
            ),
            TextSpan(
              text: note.note,
              style: TextStyle(fontSize: size),
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