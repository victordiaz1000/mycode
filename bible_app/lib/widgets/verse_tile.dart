import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../models/chapter.dart';
import '../models/verse.dart';
import 'note_aware_text.dart';

class VerseTile extends StatelessWidget {
  final Verse verse;
  final bool showNotes;
  final int verseNumber;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;

  /// Called with the Strong number when the reader taps it (LSGS: the codes are
  /// clickable). Null on versions whose text has no Strong numbers.
  final void Function(String strong)? onStrongTap;

  /// User state: highlight color hex (or null), favorite, has-note.
  final String? highlightColor;
  final bool isFavorite;
  final bool hasNote;
  final bool isSelected;

  /// Transient gold background while the reader scrolls to this verse.
  final bool isFlashing;
  final NoteDisposition disposition;

  const VerseTile({
    super.key,
    required this.verse,
    required this.showNotes,
    required this.verseNumber,
    this.onTap,
    this.onLongPress,
    this.onStrongTap,
    this.highlightColor,
    this.isFavorite = false,
    this.hasNote = false,
    this.isSelected = false,
    this.isFlashing = false,
    this.disposition = NoteDisposition.below,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasNotes = verse.notes.isNotEmpty;

    Color? bg;
    if (isSelected) {
      bg = theme.colorScheme.primary.withValues(alpha: .15);
    } else if (isFlashing) {
      bg = const Color(0x66D3A94F);
    } else if (highlightColor != null && highlightColor!.isNotEmpty) {
      // Empty means « no highlight », not « the fallback colour »: without the
      // guard `_parseColor` cannot parse it and returns amber, so a cleared
      // verse would look highlighted.
      bg = _parseColor(highlightColor!).withValues(alpha: .55);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verse.section != null)
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 4),
                child: Text(
                  verse.section!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$verseNumber',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasNotes)
                          Text(
                            '✦',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: showNotes
                        ? NoteAwareVerseText(
                            verse: verse, disposition: disposition)
                        : _StrongAwareText(
                            text: verse.text,
                            style: theme.textTheme.bodyLarge,
                            strongStyle: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) * 0.72,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                            onStrongTap: onStrongTap,
                          ),
                  ),
                  if (isFavorite || hasNote)
                    Column(
                      children: [
                        if (isFavorite)
                          Icon(Icons.star,
                              size: 14, color: theme.colorScheme.primary),
                        if (hasNote)
                          Icon(Icons.edit_note,
                              size: 14, color: theme.colorScheme.primary),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String hex) {
    final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xFFF3B0;
    return Color(0xFF000000 | v);
  }
}

class _StrongAwareText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? strongStyle;

  /// Non-null makes the Strong codes tappable (LSGS): the reader reports the
  /// number through it. Null keeps them as plain styled spans.
  final void Function(String strong)? onStrongTap;

  const _StrongAwareText({
    required this.text,
    this.style,
    this.strongStyle,
    this.onStrongTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final strongPattern = RegExp(r'(?<!\w)([A-Z][0-9]{4})(?!\w)');
    final matches = strongPattern.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start), style: baseStyle));
      }
      final strong = match.group(0)!;
      final recognizer = onStrongTap == null ? null : _strongRecognizer(strong);
      spans.add(TextSpan(
        text: strong,
        style: (strongStyle ?? baseStyle).copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          decoration: onStrongTap == null ? null : TextDecoration.underline,
          decorationStyle: onStrongTap == null
              ? null
              : TextDecorationStyle.dotted,
        ),
        recognizer: recognizer,
      ));
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return RichText(text: TextSpan(style: baseStyle, children: spans));
  }

  TapGestureRecognizer _strongRecognizer(String strong) {
    final recognizer = TapGestureRecognizer();
    recognizer.onTap = () {
      final callback = onStrongTap;
      if (callback != null) callback(strong);
    };
    return recognizer;
  }
}

class ChapterVerseList extends StatelessWidget {
  final Chapter chapter;
  final bool showNotes;
  final NoteDisposition disposition;
  final Widget? header;
  final void Function(Verse verse)? onVerseTap;
  final void Function(Verse verse)? onVerseLongPress;

  /// Called with the Strong number when the reader taps it (LSGS). Null on
  /// versions without Strong numbers.
  final void Function(Verse verse, String strong)? onStrongTap;

  /// Per-verse user state (highlight color, favorite, has-note).
  final String? Function(int verseNumber)? highlightOf;
  final bool Function(int verseNumber)? isFavoriteOf;
  final bool Function(int verseNumber)? hasNoteOf;
  final Set<int>? selectedVerses;

  /// Verse number to attach [jumpKey] to (for scrolling to it).
  final int? jumpVerse;

  /// Global key placed on the target verse so the reader can scroll to it.
  final GlobalKey? jumpKey;

  /// Verse numbers briefly shown with a gold flash after a jump.
  final Set<int>? flashingVerses;

  /// Controller of the verse list, so the reader can drive it towards a verse
  /// that has not been built yet (see `_ChapterReaderState._scrollToTarget`).
  final ScrollController? controller;

  /// Point size of the verse body text (see [ReadingTextSize]). It is applied
  /// by overriding `bodyLarge` for the whole list — the verse body and its
  /// note spans follow. Everything else (verse numbers, section headings,
  /// icons, the ✦ glyph) stays at the theme default.
  final double fontSize;

  const ChapterVerseList({
    super.key,
    required this.chapter,
    required this.showNotes,
    this.disposition = NoteDisposition.below,
    this.header,
    this.onVerseTap,
    this.onVerseLongPress,
    this.onStrongTap,
    this.highlightOf,
    this.isFavoriteOf,
    this.hasNoteOf,
    this.selectedVerses,
    this.jumpVerse,
    this.jumpKey,
    this.flashingVerses,
    this.fontSize = 16,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.copyWith(
          bodyLarge: (theme.textTheme.bodyLarge ?? const TextStyle())
              .copyWith(fontSize: fontSize),
        ),
      ),
      child: ListView.builder(
        controller: controller,
        padding: const EdgeInsets.all(16),
        itemCount: chapter.verses.length + (header != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (header != null && i == 0) return header!;
          final idx = header != null ? i - 1 : i;
          final verse = chapter.verses[idx];
          final vn = verse.number == 0 ? idx + 1 : verse.number;
          return VerseTile(
            key: jumpVerse == vn ? jumpKey : null,
            verse: verse,
            showNotes: showNotes,
            disposition: disposition,
            verseNumber: vn,
            onTap: onVerseTap == null ? null : () => onVerseTap!(verse),
            onLongPress: onVerseLongPress == null
                ? null
                : () => onVerseLongPress!(verse),
            onStrongTap: onStrongTap == null
                ? null
                : (strong) => onStrongTap!(verse, strong),
            highlightColor: highlightOf?.call(vn),
            isFavorite: isFavoriteOf?.call(vn) ?? false,
            hasNote: hasNoteOf?.call(vn) ?? false,
            isSelected: selectedVerses?.contains(vn) ?? false,
            isFlashing: flashingVerses?.contains(vn) ?? false,
          );
        },
      ),
    );
  }
}