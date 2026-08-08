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
    } else if (highlightColor != null) {
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
                        : Text(verse.text, style: theme.textTheme.bodyLarge),
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

class ChapterVerseList extends StatelessWidget {
  final Chapter chapter;
  final bool showNotes;
  final NoteDisposition disposition;
  final Widget? header;
  final void Function(Verse verse)? onVerseTap;
  final void Function(Verse verse)? onVerseLongPress;

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