import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../data/app_preferences.dart';
import '../data/reference_parser.dart';
import '../data/theme_catalog.dart';
import '../models/chapter.dart';
import '../models/verse.dart';
import '../utils/hex_color.dart';
import 'ati_interlinear.dart';
import 'note_aware_text.dart';

/// The inline Strong codes of an LSGS verse (`G2316`, `H0430`), bounded by
/// non-word characters. One pattern for the whole file — tile and continuous
/// block renderers must agree on what is a code.
final RegExp strongCodePattern = RegExp(r'(?<!\w)([A-Z][0-9]{4})(?!\w)');

/// How long the verse a jump landed on stays washed in the theme's accent.
///
/// The reader arms it only once the verse is actually on screen, so this is
/// time spent looking, not scrolling. The historical 900 ms read as a blink at
/// the end of a long scroll — the eye arrived after the colour had left.
const Duration kVerseFlashHold = Duration(milliseconds: 1700);

/// Fade of that wash: quick in as the verse lands, slower out so it reads as
/// something leaving rather than a repaint glitch. A flat on/off was the whole
/// « animation » before.
const Duration kVerseFlashFadeIn = Duration(milliseconds: 200);
const Duration kVerseFlashFadeOut = Duration(milliseconds: 520);

/// The vertical rhythm of the reading area, derived from the body font size
/// and the « Aération » preference.
///
/// Why it exists: only the glyphs used to grow with the size setting — every
/// gap stayed in fixed pixels, so zooming in made the text feel denser (a
/// 12 px gap is half a line at 16 pt, a quarter at 30 pt) and zooming out
/// accidentally airy. Here every gap is expressed relative to the default
/// 16 pt layout, so the breathing room scales WITH the text; [ReadingSpacing]
/// then tightens or loosens the whole thing to taste.
class ReadingRhythm {
  final double fontSize;
  final ReadingSpacing spacing;

  static const _baseSize = 16.0;

  const ReadingRhythm({
    this.fontSize = _baseSize,
    this.spacing = ReadingSpacing.normal,
  });

  /// Scale of every vertical gap: 1.0 at the historical default (16 pt,
  /// Normal) — the getters below reproduce those exact pixel values there.
  double get s => (fontSize / _baseSize) * spacing.gapFactor;

  /// Body line height: the reading measure of the Qwen maquette (1.62 at its
  /// 19 pt) written as a base of 1.6 that loosens a touch as glyphs grow
  /// (large type reads better with extra leading), modulated by the aération
  /// choice.
  double get lineHeight =>
      (1.6 + 0.12 * ((fontSize - _baseSize) / 14).clamp(0.0, 1.0)) *
      spacing.leadingFactor;

  /// Tracking follows the size too: the theme's absolute letter spacing reads
  /// proportionally tighter as the type grows.
  double get letterSpacing => 0.5 * (fontSize / _baseSize);

  double get tilePadV => 2 * s;
  double get textPadV => 4 * s;
  double get gutterRightPad => 8 * s;
  double get gutterTopPad => 2 * s;
  double get sectionTopPad => 14 * s;
  double get sectionBottomPad => 4 * s;
}

class VerseTile extends StatelessWidget {
  final Verse verse;
  final bool showNotes;
  final int verseNumber;
  final VoidCallback? onTap;
  final GestureLongPressCallback? onLongPress;

  /// Called with the Strong number when the reader taps it (LSGS: the codes are
  /// clickable). Null on versions whose text has no Strong numbers.
  final void Function(String strong)? onStrongTap;

  /// Called with a [BibleReference] when the reader taps a reference embedded
  /// in a note (« Voir Es. 45:18. »). Null renders the references as plain text.
  final ValueChanged<BibleReference>? onReferenceTap;

  /// User state: highlight color hex (or null), favorite, has-note.
  final String? highlightColor;
  final bool isFavorite;
  final bool hasNote;
  final bool isSelected;

  /// Transient accent wash while the reader lands on this verse — see
  /// [BibleTheme.jumpFlashColor] and [kVerseFlashHold].
  final bool isFlashing;

  /// True while the verse matches the find-in-page query: a light accent wash
  /// marks every hit so they are visible while scrolling, not just the one the
  /// reader is jumped to.
  final bool isSearchMatch;
  final NoteDisposition disposition;
  final TextAlign textAlign;

  /// Vertical rhythm of the reading area: every gap below scales with the
  /// font size (and the aération setting) instead of staying in fixed pixels.
  final ReadingRhythm rhythm;

  /// The selected reading theme for the verse area.
  final BibleTheme theme;

  const VerseTile({
    super.key,
    required this.verse,
    required this.showNotes,
    required this.verseNumber,
    this.rhythm = const ReadingRhythm(),
    this.onTap,
    this.onLongPress,
    this.onStrongTap,
    this.onReferenceTap,
    this.highlightColor,
    this.isFavorite = false,
    this.hasNote = false,
    this.isSelected = false,
    this.isFlashing = false,
    this.isSearchMatch = false,
    this.disposition = NoteDisposition.below,
    this.textAlign = TextAlign.left,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final hasNotes = verse.notes.isNotEmpty;

    Color? bg;
    if (isSelected) {
      bg = theme.accentColor.withAlpha(0x26);
    } else if (isFlashing) {
      bg = theme.jumpFlashColor;
    } else if (highlightColor != null && highlightColor!.isNotEmpty) {
      bg = hexToColor(highlightColor!).withAlpha(0x8C);
    } else if (isSearchMatch) {
      // Under the explicit states: a match never paints over a chosen color.
      bg = theme.accentColor.withAlpha(0x1A);
    }

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      // Animated so the jump wash fades in and out instead of popping: the
      // colour is the only sign the reader gets that *this* is the verse the
      // link pointed at. `Colors.transparent` rather than a null colour so
      // there is always something to tween towards — a null decoration snaps.
      // Padding stays outside: it moves with the font size, and animating it
      // would make a text-size change slide the whole chapter around.
      child: AnimatedContainer(
        duration: isFlashing ? kVerseFlashFadeIn : kVerseFlashFadeOut,
        curve: Curves.easeOut,
        color: bg ?? Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: rhythm.tilePadV,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (verse.section != null)
                Padding(
                  padding: EdgeInsets.only(
                    top: rhythm.sectionTopPad,
                    bottom: rhythm.sectionBottomPad,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      verse.section!,
                      textAlign: textAlign,
                      style: materialTheme.textTheme.titleMedium?.copyWith(
                        // Le titre suit « Taille du texte » : posé sur le 16
                        // de `titleMedium`, il tombait sous le corps dès
                        // « très grand » (22) — l'écart d'origine était de
                        // titre égal au corps, à corps choisi.
                        fontSize: rhythm.fontSize,
                        color: theme.titleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: rhythm.textPadV),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.only(
                        right: rhythm.gutterRightPad,
                        top: rhythm.gutterTopPad,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$verseNumber',
                            style: materialTheme.textTheme.bodySmall?.copyWith(
                              // Comme tout le rythme, le chiffre suit la
                              // taille du texte (×0.7, borné 11–16) : figé à
                              // 12, il tombait à 0.55× le corps au défaut de
                              // 22 et ne bougeait plus avec « Texte ».
                              fontSize:
                                  (rhythm.fontSize * .7).clamp(11.0, 16.0),
                              color: theme.verseNumColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (hasNotes)
                            Text(
                              '✦',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.verseNumColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      // SEF: the Greek line rides above the translation and the
                      // second French translation trails it — both extra to
                      // the BYM note machinery, both data-gated (null =
                      // nothing drawn).
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (verse.grec != null)
                            Padding(
                              padding: EdgeInsets.only(bottom: 3 * rhythm.s),
                              child: Text(
                                verse.grec!,
                                textAlign: textAlign,
                                style:
                                    materialTheme.textTheme.bodyLarge?.copyWith(
                                  fontSize: rhythm.fontSize * .88,
                                  color: theme.noteColor,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          // L'interlinéaire remplace la ligne : ses colonnes
                          // portent déjà les gloses du verset, et l'ATI ne
                          // porte pas de notes BYM (`carriesNotes` y est
                          // faux), de sorte que `showNotes` ne peut pas
                          // entrer en conflit avec lui. Donnée d'abord, comme
                          // `verse.grec` au-dessus — aucun savoir sur la
                          // version active n'est nécessaire ici.
                          if (verse.mots?.isNotEmpty ?? false)
                            AtiInterlinear(
                              words: verse.mots!,
                              rhythm: rhythm,
                              theme: theme,
                            )
                          else if (showNotes)
                            NoteAwareVerseText(
                                  verse: verse,
                                  disposition: disposition,
                                  onReferenceTap: onReferenceTap,
                                  textAlign: textAlign,
                                )
                          else
                            _StrongAwareText(
                                  text: verse.text,
                                  style: materialTheme.textTheme.bodyLarge,
                                  strongStyle:
                                      materialTheme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontSize:
                                                (materialTheme
                                                        .textTheme
                                                        .bodyLarge
                                                        ?.fontSize ??
                                                    16) *
                                                0.72,
                                            color: theme.accentColor,
                                            fontWeight: FontWeight.w700,
                                          ),
                                  onStrongTap: onStrongTap,
                                  textAlign: textAlign,
                                ),
                          if (verse.alexandrie != null)
                            Padding(
                              padding: EdgeInsets.only(top: 3 * rhythm.s),
                              child: Text(
                                verse.alexandrie!,
                                textAlign: textAlign,
                                style:
                                    materialTheme.textTheme.bodyLarge?.copyWith(
                                  fontSize: rhythm.fontSize * .88,
                                  color: theme.noteColor,
                                  height: 1.35,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (isFavorite || hasNote)
                      Column(
                        children: [
                          if (isFavorite)
                            Icon(
                              Icons.star,
                              size: 14,
                              color: theme.accentColor,
                            ),
                          if (hasNote)
                            Icon(
                              Icons.edit_note,
                              size: 14,
                              color: theme.accentColor,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StrongAwareText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? strongStyle;
  final TextAlign textAlign;

  /// Non-null makes the Strong codes tappable (LSGS): the reader reports the
  /// number through it. Null keeps them as plain styled spans.
  final void Function(String strong)? onStrongTap;

  const _StrongAwareText({
    required this.text,
    this.style,
    this.strongStyle,
    this.textAlign = TextAlign.left,
    this.onStrongTap,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final matches = strongCodePattern.allMatches(text);
    if (matches.isEmpty) {
      return Text(text, style: baseStyle, textAlign: textAlign);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
        );
      }
      final strong = match.group(0)!;
      final recognizer = onStrongTap == null ? null : _strongRecognizer(strong);
      spans.add(
        TextSpan(
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
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return RichText(
      textAlign: textAlign,
      // `RichText` ne met PAS à l'échelle par défaut (contrairement à `Text`) :
      // sans ce scaler, un verset porteur de codes Strong rendrait plus petit
      // que ses voisins sans code, dans la même tuile.
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(style: baseStyle, children: spans),
    );
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

class ChapterVerseList extends StatefulWidget {
  final Chapter chapter;
  final bool showNotes;
  final NoteDisposition disposition;
  final Widget? header;
  final void Function(Verse verse)? onVerseTap;
  final void Function(Verse verse)? onVerseLongPress;

  /// Called with the Strong number when the reader taps it (LSGS). Null on
  /// versions without Strong numbers.
  final void Function(Verse verse, String strong)? onStrongTap;

  /// Called with a [BibleReference] when the reader taps a reference embedded
  /// in a note. Null renders the references as plain text.
  final ValueChanged<BibleReference>? onReferenceTap;

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

  /// Verses matching the find-in-page query, drawn with a light accent wash.
  final Set<int>? searchMatches;

  /// Rendered after the last verse (the « continuer au chapitre suivant »
  /// tile). Null = nothing appended; the item count math of the reader's jump
  /// loop stays chapter-only because it never targets the footer.
  final Widget? footer;

  /// Controller of the verse list, so the reader can drive it towards a verse
  /// that has not been built yet (see `_ChapterReaderState._scrollToTarget`).
  final ScrollController? controller;

  /// Point size of the verse body text (see [ReadingTextSize]). It is applied
  /// by overriding `bodyLarge` for the whole list — the verse body and its
  /// note spans follow. Everything else (verse numbers, section headings,
  /// icons, the ? glyph) stays at the theme default.
  final double fontSize;
  final ReadingFont readingFont;
  final TextAlign textAlign;

  /// How verses are laid out: one tile each ([ReadingLayout.tiles]) or a
  /// continuous paragraph flow cut by section titles
  /// ([ReadingLayout.paragraph]).
  final ReadingLayout layout;

  /// Stroke weight of the verse body, applied to BOTH layouts identically so
  /// « Texte continu » always matches « Versets séparés ».
  final FontWeight fontWeight;

  /// When provided, THE resolved verse-body style: the scoped `bodyLarge`
  /// override and the paragraph blocks both use it verbatim, so every layout
  /// (and the header intro) renders the exact same typography.
  final TextStyle? bodyStyle;

  /// Vertical airiness of the reading area; drives the [ReadingRhythm] that
  /// scales every gap with the font size.
  final ReadingSpacing spacing;

  /// The selected reading theme for the chapter body.
  final BibleTheme theme;

  /// Opacity of the semi-transparent panel the verses sit on (the reader's
  /// « Opacité du panneau » preference). Lower = background shows through.
  final double panelOpacity;

  const ChapterVerseList({
    super.key,
    required this.chapter,
    required this.showNotes,
    this.disposition = NoteDisposition.below,
    this.header,
    this.onVerseTap,
    this.onVerseLongPress,
    this.onStrongTap,
    this.onReferenceTap,
    this.highlightOf,
    this.isFavoriteOf,
    this.hasNoteOf,
    this.selectedVerses,
    this.jumpVerse,
    this.jumpKey,
    this.flashingVerses,
    this.searchMatches,
    this.footer,
    this.fontSize = 16,
    this.readingFont = ReadingFont.crimson,
    this.textAlign = TextAlign.left,
    this.controller,
    this.layout = ReadingLayout.tiles,
    this.fontWeight = FontWeight.w400,
    this.bodyStyle,
    this.spacing = ReadingSpacing.normal,
    this.panelOpacity = .80,
    required this.theme,
  });

  /// Static jump metrics shared with the reader's scroll-to-verse machinery:
  /// which list slot holds [verseNumber], and how many content slots exist.
  /// The footer is deliberately excluded from the count — a jump never
  /// targets it, and keeping it out preserves the inverse fraction used to
  /// report the reading position.
  static ({int itemCount, int itemIndex})? jumpMetricsFor({
    required Chapter chapter,
    required ReadingLayout layout,
    required bool hasHeader,
    required int verseNumber,
  }) {
    final headerOffset = hasHeader ? 1 : 0;
    if (layout == ReadingLayout.tiles) {
      var idx = -1;
      for (var i = 0; i < chapter.verses.length; i++) {
        final v = chapter.verses[i];
        final n = v.number == 0 ? i + 1 : v.number;
        if (n == verseNumber) {
          idx = i;
          break;
        }
      }
      if (idx < 0) return null;
      return (
        itemCount: chapter.verses.length + headerOffset,
        itemIndex: idx + headerOffset,
      );
    }
    final segments = paragraphSegments(chapter);
    var cursor = headerOffset;
    var found = -1;
    for (final segment in segments) {
      if (segment.title != null) cursor++;
      if (found < 0 && segment.numbers.contains(verseNumber)) {
        found = cursor;
      }
      cursor++;
    }
    if (found < 0) return null;
    return (itemCount: cursor, itemIndex: found);
  }

  @override
  State<ChapterVerseList> createState() => ChapterVerseListState();
}

/// One continuous run of verses between two section titles: the unit the
/// paragraph layout renders as flowing text ([_ParagraphBlock]).
class ParagraphSegment {
  final String? title;

  /// The verses of the run, in reading order.
  final List<Verse> verses;

  /// Their resolved numbers (a verse without an explicit number counts its
  /// position), aligned with [verses].
  final List<int> numbers;

  ParagraphSegment({
    required this.title,
    required this.verses,
    required this.numbers,
  });
}

/// Cuts a chapter into paragraph runs: every verse carrying a `section` opens
/// a new run titled by it; the other verses append to the current run. Most
/// chapters have few sections, so they render as one long flow — exactly the
/// printed-Bible feel the paragraph layout is here for.
List<ParagraphSegment> paragraphSegments(Chapter chapter) {
  final segments = <ParagraphSegment>[];
  for (var i = 0; i < chapter.verses.length; i++) {
    final verse = chapter.verses[i];
    final number = verse.number == 0 ? i + 1 : verse.number;
    if (verse.section != null || segments.isEmpty) {
      segments.add(
        ParagraphSegment(
          title: verse.section,
          verses: [verse],
          numbers: [number],
        ),
      );
    } else {
      final last = segments.last;
      last.verses.add(verse);
      last.numbers.add(number);
    }
  }
  return segments;
}

class ChapterVerseListState extends State<ChapterVerseList> {
  /// Keys of the paragraph blocks currently laid out, aligned with
  /// [paragraphSegmentCount] of the last build. Powers
  /// [verseNearViewportTop]: the reader asks *which verse* sits near the top
  /// of the viewport, and in a one-block chapter only geometry can answer.
  final List<GlobalKey<_ParagraphBlockState>> _blockKeys = [];

  int get paragraphSegmentCount => paragraphSegments(widget.chapter).length;

  /// Grows or shrinks [_blockKeys] to [count] so each segment of the current
  /// chapter owns a stable key across rebuilds.
  void _syncBlockKeys(int count) {
    while (_blockKeys.length < count) {
      _blockKeys.add(GlobalKey<_ParagraphBlockState>());
    }
    if (_blockKeys.length > count) {
      _blockKeys.removeRange(count, _blockKeys.length);
    }
  }

  /// The verse whose text sits nearest below [fraction] of the viewport
  /// height, or null when nothing is built there yet. Used to persist the
  /// reading position while scrolling the continuous layout, where the
  /// tile-mode item math has no meaning (one block can span the whole
  /// chapter).
  int? verseNearViewportTop() {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return null;
    final viewport = scrollable.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    final probeGlobal =
        viewport.localToGlobal(Offset.zero).dy + viewport.size.height * .18;
    for (final key in _blockKeys) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (probeGlobal >= top - 40 && probeGlobal <= bottom + 40) {
        return key.currentState?.verseAtLocalDy(probeGlobal - top);
      }
    }
    return null;
  }

  /// Maps a flat list slot of the paragraph layout to its content: the book
  /// header, a section title, a continuous block, or the footer.
  Widget _buildParagraphItem(
    int i, {
    required Widget? header,
    required Widget? footer,
    required int paragraphItemCount,
    required List<ParagraphSegment> segments,
    required List<int?> titleSlotOf,
    required List<int> blockSlotOf,
    required BibleTheme theme,
    required String family,
    required TextStyle? baseStyle,
    required bool showNotes,
    required bool hasStrong,
    required int? jumpVerse,
    required GlobalKey? jumpKey,
    required Set<int>? flashingVerses,
    required Set<int>? searchMatches,
    required Set<int>? selectedVerses,
    required String? Function(int)? highlightOf,
    required bool Function(int)? isFavoriteOf,
    required bool Function(int)? hasNoteOf,
    required void Function(Verse)? onVerseTap,
    required void Function(Verse)? onVerseLongPress,
    required void Function(Verse, String)? onStrongTap,
    required ValueChanged<BibleReference>? onReferenceTap,
    required TextAlign textAlign,
    required ReadingRhythm rhythm,
  }) {
    if (header != null && i == 0) return header;
    if (footer != null && i == paragraphItemCount) return footer;

    for (var s = 0; s < segments.length; s++) {
      final titleSlot = titleSlotOf[s];
      if (titleSlot == i) {
        return Padding(
          padding: EdgeInsets.only(
            top: rhythm.sectionTopPad,
            bottom: rhythm.sectionBottomPad,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              segments[s].title!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                // Idem la tuile : le titre prend le corps choisi, pas le 16
                // figé de `titleMedium`.
                fontSize: rhythm.fontSize,
                color: theme.titleColor,
                fontWeight: FontWeight.w600,
                fontFamily: family,
              ),
            ),
          ),
        );
      }
      if (blockSlotOf[s] == i) {
        final segment = segments[s];
        // When this segment holds the jump target, the reader's GlobalKey
        // rides ON the block (replacing the pool key for a frame) so the
        // anchor state is reachable through it.
        final isJumpSegment =
            jumpVerse != null && segment.numbers.contains(jumpVerse);
        return _ParagraphBlock(
          key: isJumpSegment && jumpKey != null ? jumpKey : _blockKeys[s],
          segment: segment,
          theme: theme,
          family: family,
          baseStyle: baseStyle,
          lineHeight: rhythm.lineHeight,
          showNotes: showNotes,
          hasStrong: hasStrong,
          textAlign: textAlign,
          flashingVerses: flashingVerses,
          searchMatches: searchMatches,
          selectedVerses: selectedVerses,
          highlightOf: highlightOf,
          isFavoriteOf: isFavoriteOf,
          hasNoteOf: hasNoteOf,
          onVerseTap: onVerseTap,
          onVerseLongPress: onVerseLongPress,
          onStrongTap: onStrongTap,
          onReferenceTap: onReferenceTap,
        );
      }
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final chapter = w.chapter;
    final header = w.header;
    final footer = w.footer;
    final showNotes = w.showNotes;
    final disposition = w.disposition;
    final fontSize = w.fontSize;
    final readingFont = w.readingFont;
    final textAlign = w.textAlign;
    final theme = w.theme;
    final controller = w.controller;
    final jumpVerse = w.jumpVerse;
    final jumpKey = w.jumpKey;
    final flashingVerses = w.flashingVerses;
    final searchMatches = w.searchMatches;
    final selectedVerses = w.selectedVerses;
    final highlightOf = w.highlightOf;
    final isFavoriteOf = w.isFavoriteOf;
    final hasNoteOf = w.hasNoteOf;
    final onVerseTap = w.onVerseTap;
    final onVerseLongPress = w.onVerseLongPress;
    final onStrongTap = w.onStrongTap;
    final onReferenceTap = w.onReferenceTap;
    final layout = w.layout;
    final fontWeight = w.fontWeight;
    final spacing = w.spacing;
    final bodyStyle = w.bodyStyle;
    final panelOpacity = w.panelOpacity;

    // Paragraph layout: cut the chapter into continuous runs between section
    // titles, then precompute which list slot holds each title / block. The
    // lazy builder stays a flat indexed list — only the mapping changes.
    final segments = layout == ReadingLayout.paragraph
        ? paragraphSegments(chapter)
        : <ParagraphSegment>[];
    _syncBlockKeys(segments.length);
    final headerSlots = header != null ? 1 : 0;
    var blockCursor = headerSlots;
    final titleSlotOf = List<int?>.filled(segments.length, null);
    final blockSlotOf = List<int>.filled(segments.length, 0);
    for (var s = 0; s < segments.length; s++) {
      if (segments[s].title != null) {
        titleSlotOf[s] = blockCursor++;
      }
      blockSlotOf[s] = blockCursor++;
    }
    final paragraphItemCount = blockCursor;

    final materialTheme = Theme.of(context);
    // La police commune des écrans premium : la lecture la partage pour ne pas
    // basculer de typographie entre le lecteur et le reste de l'application.
    final family = readingFont.fontFamily;
    // The vertical rhythm: gaps and leading scale with the font size so large
    // type keeps the air of small type, then the aération setting dials it.
    final rhythm = ReadingRhythm(fontSize: fontSize, spacing: spacing);
    // The ONE body style, shared by tiles and blocks: when the reader supplies
    // it, the scoped override is that object verbatim.
    final effectiveBodyStyle =
        (bodyStyle ??
                (materialTheme.textTheme.bodyLarge ?? const TextStyle())
                    .copyWith(
                      fontSize: fontSize,
                      color: theme.textColor,
                      fontFamily: family,
                      fontWeight: fontWeight,
                    ))
            .copyWith(
              fontSize: fontSize,
              fontWeight: fontWeight,
              height: rhythm.lineHeight,
              letterSpacing: rhythm.letterSpacing,
            );
    return Theme(
      data: materialTheme.copyWith(
        textTheme: materialTheme.textTheme.copyWith(
          bodyLarge: effectiveBodyStyle,
          bodyMedium: (materialTheme.textTheme.bodyMedium ?? const TextStyle())
              .copyWith(color: theme.textColor, fontFamily: family),
          bodySmall: (materialTheme.textTheme.bodySmall ?? const TextStyle())
              .copyWith(color: theme.textColor, fontFamily: family),
          titleMedium:
              (materialTheme.textTheme.titleMedium ?? const TextStyle())
                  .copyWith(color: theme.titleColor, fontFamily: family),
          labelSmall: (materialTheme.textTheme.labelSmall ?? const TextStyle())
              .copyWith(color: theme.textColor, fontFamily: family),
        ),
        colorScheme: materialTheme.colorScheme.copyWith(
          primary: theme.accentColor,
          secondary: theme.verseNumColor,
          onSurface: theme.textColor,
          surfaceContainerHighest: theme.panelColor,
        ),
      ),
      child: Container(
        decoration: theme.hasBackground
            ? BoxDecoration(image: theme.decorationImage())
            : null,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            // La mesure, pas la largeur : ~74 signes par ligne à toutes les
            // tailles. 820 figés donnaient 102 signes à 16 pt sur grand
            // écran et suivaient mal le corps. Sur téléphone la fenêtre
            // décide, la contrainte ne s'applique jamais.
            constraints: BoxConstraints(
              maxWidth: (fontSize * 37).clamp(600.0, 860.0),
            ),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.readingPanelColor(panelOpacity),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: theme.panelBorderColor),
              ),
              child: Stack(
                children: [
                  ListView.builder(
                    // Pas de ValueKey ici non plus : il détruirait le ScrollPosition.
                    controller: controller,
                    // Marge de texte : 20 aux côtés, comme partout ailleurs
                    // dans l'app (feuilles, réglages), 16 en haut et 26 en
                    // bas pour que le dernier verset respire — le maquette
                    // Qwen donne 16/24/26.
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 26),
                    itemCount: layout == ReadingLayout.paragraph
                        ? paragraphItemCount + (footer != null ? 1 : 0)
                        : chapter.verses.length +
                              (header != null ? 1 : 0) +
                              (footer != null ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (layout == ReadingLayout.paragraph) {
                        return _buildParagraphItem(
                          i,
                          header: header,
                          footer: footer,
                          paragraphItemCount: paragraphItemCount,
                          segments: segments,
                          titleSlotOf: titleSlotOf,
                          blockSlotOf: blockSlotOf,
                          theme: theme,
                          family: family,
                          // THE same object as the tiles' bodyLarge: the
                          // continuous flow can never drift from « Versets
                          // séparés » (nor from the header intro).
                          baseStyle: effectiveBodyStyle,
                          showNotes: showNotes,
                          hasStrong: onStrongTap != null,
                          jumpVerse: jumpVerse,
                          jumpKey: jumpKey,
                          flashingVerses: flashingVerses,
                          searchMatches: searchMatches,
                          selectedVerses: selectedVerses,
                          highlightOf: highlightOf,
                          isFavoriteOf: isFavoriteOf,
                          hasNoteOf: hasNoteOf,
                          onVerseTap: onVerseTap,
                          onVerseLongPress: onVerseLongPress,
                          onStrongTap: onStrongTap,
                          onReferenceTap: onReferenceTap,
                          textAlign: textAlign,
                          rhythm: rhythm,
                        );
                      }
                      if (header != null && i == 0) return header;
                      if (footer != null &&
                          i ==
                              chapter.verses.length +
                                  (header != null ? 1 : 0)) {
                        return footer;
                      }
                      final idx = i - (header != null ? 1 : 0);
                      final verse = chapter.verses[idx];
                      final vn = verse.number == 0 ? idx + 1 : verse.number;
                      // VerseTile must rebuild when display prefs change (textAlign,
                      // fontSize, readingFont, etc.) — without a key the lazy
                      // ListView reuses the old Element and the new textAlign never
                      // reaches the Text widget (see debug: ChapterVerseList=center
                      // but VerseTile=justify). A ValueKey that includes the prefs
                      // forces a new Element. The jump target keeps its GlobalKey
                      // so Scrollable.ensureVisible can still find it.
                      final isJump = jumpVerse == vn;
                      return VerseTile(
                        key: isJump
                            ? jumpKey
                            : ValueKey(
                                '${textAlign}_${fontSize}_${readingFont.name}_${disposition.name}_${showNotes}_${theme.id}_${spacing.name}_$vn',
                              ),
                        verse: verse,
                        showNotes: showNotes,
                        disposition: disposition,
                        verseNumber: vn,
                        rhythm: rhythm,
                        onTap: onVerseTap == null
                            ? null
                            : () => onVerseTap(verse),
                        onLongPress: onVerseLongPress == null
                            ? null
                            : () => onVerseLongPress(verse),
                        onStrongTap: onStrongTap == null
                            ? null
                            : (strong) => onStrongTap(verse, strong),
                        onReferenceTap: onReferenceTap,
                        highlightColor: highlightOf?.call(vn),
                        isFavorite: isFavoriteOf?.call(vn) ?? false,
                        hasNote: hasNoteOf?.call(vn) ?? false,
                        isSelected: selectedVerses?.contains(vn) ?? false,
                        isFlashing: flashingVerses?.contains(vn) ?? false,
                        isSearchMatch: searchMatches?.contains(vn) ?? false,
                        theme: theme,
                        textAlign: textAlign,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anything a jump target can live inside. The reader holds a [GlobalKey]
/// whose current context may be a plain tile (then [Scrollable.ensureVisible]
/// is enough) or a paragraph block (then the exact verse must be revealed
/// inside flowing text, which only the block's own geometry can do).
abstract interface class VerseAnchor {
  /// Brings [verseNumber] into view, driving [controller] if needed.
  Future<void> revealVerse(int verseNumber, ScrollController controller);
}

/// A continuous run of verses rendered as one flowing text: exposant verse
/// numbers, per-verse highlight backgrounds and gestures, BYM notes woven
/// inline or as cards under the block.
///
/// One block = one [ParagraphSegment]. Most chapters hold a single section
/// break or none at all, so the whole chapter flows as printed text; a lazy
/// list item per *verse* would defeat that.
class _ParagraphBlock extends StatefulWidget {
  final ParagraphSegment segment;
  final BibleTheme theme;
  final String family;
  final TextStyle? baseStyle;
  final bool showNotes;
  final bool hasStrong;
  final Set<int>? flashingVerses;
  final Set<int>? searchMatches;
  final Set<int>? selectedVerses;
  final String? Function(int)? highlightOf;
  final bool Function(int)? isFavoriteOf;
  final bool Function(int)? hasNoteOf;
  final void Function(Verse)? onVerseTap;
  final void Function(Verse)? onVerseLongPress;
  final void Function(Verse, String)? onStrongTap;
  final ValueChanged<BibleReference>? onReferenceTap;
  final TextAlign textAlign;

  /// Body line height from the reading rhythm; the flow used to hardcode
  /// 1.55 to breathe like the tiles' per-verse padding — now it follows the
  /// same size- and aération-derived leading as everything else.
  final double lineHeight;

  const _ParagraphBlock({
    super.key,
    required this.segment,
    required this.theme,
    required this.family,
    required this.baseStyle,
    required this.lineHeight,
    required this.showNotes,
    required this.hasStrong,
    required this.textAlign,
    this.flashingVerses,
    this.searchMatches,
    this.selectedVerses,
    this.highlightOf,
    this.isFavoriteOf,
    this.hasNoteOf,
    this.onVerseTap,
    this.onVerseLongPress,
    this.onStrongTap,
    this.onReferenceTap,
  });

  @override
  State<_ParagraphBlock> createState() => _ParagraphBlockState();
}

class _ParagraphBlockState extends State<_ParagraphBlock>
    implements VerseAnchor {
  final GlobalKey _paraKey = GlobalKey();

  /// Per-verse recognizers, keyed by the verse ordinal inside the segment:
  /// created lazily, reused across rebuilds (the verse set of a segment never
  /// changes within a chapter), disposed with the State.
  final Map<int, TapGestureRecognizer> _taps = {};

  /// Recognizers of note-reference and Strong spans: rebuilt with the spans on
  /// every build — cleared without disposing here, exactly like
  /// [NoteAwareVerseText] does, and all disposed together in [dispose].
  final List<TapGestureRecognizer> _refs = [];

  /// Rendered-string char offset where each verse starts, in reading order.
  /// [WidgetSpan] markers count as one U+FFFC each, like the text engine sees
  /// them. Powers the caret math of [revealVerse] and the long-press → verse
  /// resolution of [_handleLongPressStart].
  List<(int start, int verse)> _verseOffsets = const [];
  Map<int, int> get _charOffsets => {
    for (final (start, verse) in _verseOffsets) verse: start,
  };

  TapGestureRecognizer _tapFor(int slot) =>
      _taps.putIfAbsent(slot, TapGestureRecognizer.new);

  /// Resolves a long-press at [local] inside the paragraph to its verse: the
  /// char offset under the finger, then the last verse starting at or before
  /// it. Fires the reader's multi-selection entry.
  void _handleLongPressStart(LongPressStartDetails details) {
    final cb = widget.onVerseLongPress;
    if (cb == null || _verseOffsets.isEmpty) return;
    final para = _renderPara;
    if (para == null) return;
    final pos = para.getPositionForOffset(details.localPosition).offset;
    var best = _verseOffsets.first;
    for (final entry in _verseOffsets) {
      if (entry.$1 <= pos) {
        best = entry;
      } else {
        break;
      }
    }
    final verseIndex = widget.segment.numbers.indexOf(best.$2);
    if (verseIndex >= 0) {
      HapticFeedback.mediumImpact();
      cb(widget.segment.verses[verseIndex]);
    }
  }

  @override
  void dispose() {
    for (final r in _taps.values) {
      r.dispose();
    }
    for (final r in _refs) {
      r.dispose();
    }
    super.dispose();
  }

  RenderParagraph? get _renderPara {
    final ctx = _paraKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    return ro is RenderParagraph ? ro : null;
  }

  /// Local dy of a verse start inside the paragraph, or null when the render
  /// object or the offset is not available yet.
  double? _caretDy(int verseNumber) {
    final para = _renderPara;
    final offset = _charOffsets[verseNumber];
    if (para == null || offset == null || !para.attached) return null;
    return para
        .getOffsetForCaret(
          TextPosition(offset: offset),
          const Rect.fromLTWH(0, -1, 1, 1),
        )
        .dy;
  }

  @override
  Future<void> revealVerse(int verseNumber, ScrollController controller) async {
    if (!mounted) return;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      // No scrollable around: coarse fallback.
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.35,
      );
      return;
    }
    // The lazy list's maxScrollExtent starts tiny and grows as tiles get
    // measured, so the first computed offset under-shoots by far. Each jump
    // reveals more content, refining the extent — hence the convergence loop,
    // stopped once a frame moves nothing (or safety cap).
    for (var attempt = 0; attempt < 10; attempt++) {
      if (!mounted) return;
      final dy = _caretDy(verseNumber);
      final para = _renderPara;
      if (dy == null || para == null || !para.attached) return;
      final viewport = scrollable.context.findRenderObject();
      if (viewport is! RenderBox || !viewport.attached) return;
      // Caret local → global, then absolute scroll offset: the verse line
      // lands at 35% of the viewport height, like the tile jump.
      final caretGlobal = para.localToGlobal(Offset(0, dy));
      final vpTop = viewport.localToGlobal(Offset.zero).dy;
      final desired = caretGlobal.dy - vpTop - viewport.size.height * .35;
      final p = controller.position;
      final current = controller.offset;
      final next = (current + desired).clamp(
        p.minScrollExtent,
        p.maxScrollExtent,
      );
      if ((next - current).abs() < 1 && attempt > 0) return;
      controller.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// Which verse sits at [localDy] inside this block (viewport-top probing
  /// for position reporting). Nearest verse whose caret is above the probe,
  /// with one-line tolerance so a probe between lines still resolves.
  int? verseAtLocalDy(double localDy) {
    final para = _renderPara;
    if (para == null || !para.attached) return null;
    final bodySize = widget.baseStyle?.fontSize ?? 16;
    int? best;
    double? bestDy;
    for (final entry in _charOffsets.entries) {
      final dy = _caretDy(entry.key);
      if (dy == null) continue;
      if (dy <= localDy + bodySize * 1.3 && (bestDy == null || dy >= bestDy)) {
        best = entry.key;
        bestDy = dy;
      }
    }
    return best;
  }

  Paint? _backgroundFor(int verseNumber) {
    Color? color;
    if (widget.selectedVerses?.contains(verseNumber) ?? false) {
      color = widget.theme.accentColor.withAlpha(0x26);
    } else if (widget.flashingVerses?.contains(verseNumber) ?? false) {
      // Same accent wash as the tiles, but without their fade: here the colour
      // rides on the spans' `background` Paint, so animating it would mean
      // rebuilding the whole flow — and its note/Strong recognizers, which are
      // appended to a sink that only [dispose] empties — on every frame. The
      // wash still appears and leaves on [kVerseFlashHold]; only the transition
      // is instant.
      color = widget.theme.jumpFlashColor;
    } else {
      final hex = widget.highlightOf?.call(verseNumber);
      if (hex != null && hex.isNotEmpty) {
        color = hexToColor(hex).withAlpha(0x8C);
      } else if (widget.searchMatches?.contains(verseNumber) ?? false) {
        color = widget.theme.accentColor.withAlpha(0x1A);
      }
    }
    return color == null ? null : (Paint()..color = color);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final body = (widget.baseStyle ?? DefaultTextStyle.of(context).style)
        .copyWith(
          fontFamily: widget.family,
          // The intro's airiness: same size, same leading. Without it the flow
          // packs tighter than the tiles (no per-verse padding to breathe) and
          // reads darker/bigger at the exact same point size.
          height: widget.lineHeight,
        );
    final baseSize = body.fontSize ?? 16;
    // Exposant number: the maquette sets its verse numbers at w800 — 700 is
    // the serif reading of that weight, present enough to anchor each verse
    // without turning the whole line bold.
    final numStyle = body.copyWith(
      fontSize: baseSize * .58,
      color: theme.verseNumColor,
      fontWeight: FontWeight.w700,
    );

    final children = <InlineSpan>[];
    final offsets = <int, int>{};
    var rendered = 0;

    for (var idx = 0; idx < widget.segment.verses.length; idx++) {
      final verse = widget.segment.verses[idx];
      final vn = widget.segment.numbers[idx];
      offsets[vn] = rendered;

      final content = <InlineSpan>[];
      var contentChars = 0;
      // The tap recognizer is attached to every literal piece of THIS verse
      // (one shared instance): TextSpan hit-testing dispatches only to the
      // spans actually containing the touch point, so wrapping the verse in a
      // recognizer-carrying parent would never fire.
      final verseTap = widget.onVerseTap == null
          ? null
          : (_tapFor(idx)..onTap = () => widget.onVerseTap!(verse));
      void push(String text, TextStyle style, [GestureRecognizer? rec]) {
        if (text.isEmpty) return;
        content.add(
          TextSpan(text: text, style: style, recognizer: rec ?? verseTap),
        );
        contentChars += text.length;
      }

      // Exposant verse number, tappable like the rest of the verse.
      push('$vn ', numStyle);

      // SEF: the Greek line gets its own line above the translation, muted
      // and a touch smaller, same as in the tile layout.
      final grec = verse.grec;
      if (grec != null && grec.isNotEmpty) {
        push(
          grec,
          body.copyWith(fontSize: baseSize * .88, color: theme.noteColor),
        );
        push('\n', body);
      }

      // Le mot noté garde le corps du texte : ni graisse, ni couleur, ni
      // surlignage. Un souligné en pointillé le détache — le flux n'a pas
      // d'exposant, la note entre parenthèses marque l'endroit.
      final notedStyle = body.copyWith(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dotted,
      );
      final noteStyle = body.copyWith(
        fontSize: baseSize * .81,
        color: theme.noteColor,
      );

      final ranges = _resolveNoteRanges(verse);
      if (widget.showNotes && ranges.isNotEmpty) {
        // The continuous flow knows a single way to carry a note: woven into
        // the sentence, in parentheses. `NoteDisposition` is a tiles-only
        // choice and this block never receives it — « Texte + notes » is the
        // whole condition.
        var cursor = 0;
        for (final range in ranges) {
          if (range.start > cursor) {
            push(verse.text.substring(cursor, range.start), body);
          }
          push(verse.text.substring(range.start, range.end), notedStyle);
          push(' (', noteStyle);
          // The linkified spans keep their OWN reference recognizers: added
          // verbatim (never rebuilt through [push], which would attach the
          // verse-tap and drop theirs).
          final spans = linkifiedNoteSpans(
            text: range.note.note,
            style: noteStyle,
            accent: theme.linkColor,
            onTap: widget.onReferenceTap,
            sink: _refs,
          );
          for (final span in spans) {
            final ts = span as TextSpan;
            content.add(ts);
            contentChars += ts.text?.length ?? 0;
          }
          push(')', noteStyle);
          cursor = range.end;
        }
        if (cursor < verse.text.length) {
          push(verse.text.substring(cursor), body);
        }
      } else if (widget.hasStrong && verse.text.isNotEmpty) {
        // LSGS-style inline Strong codes, same look as the tile renderer.
        final strongStyle = body.copyWith(
          fontSize: baseSize * .72,
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
          decoration: widget.onStrongTap == null
              ? null
              : TextDecoration.underline,
          decorationStyle: widget.onStrongTap == null
              ? null
              : TextDecorationStyle.dotted,
        );
        final pattern = strongCodePattern;
        var cursor = 0;
        for (final match in pattern.allMatches(verse.text)) {
          if (match.start > cursor) {
            push(verse.text.substring(cursor, match.start), body);
          }
          final code = match.group(0)!;
          if (widget.onStrongTap != null) {
            final recognizer = TapGestureRecognizer();
            recognizer.onTap = () => widget.onStrongTap!(verse, code);
            _refs.add(recognizer);
            content.add(
              TextSpan(text: code, style: strongStyle, recognizer: recognizer),
            );
          } else {
            content.add(TextSpan(text: code, style: strongStyle));
          }
          contentChars += code.length;
          cursor = match.end;
        }
        if (cursor < verse.text.length) {
          push(verse.text.substring(cursor), body);
        }
      } else {
        push(verse.text, body);
      }

      // SEF: the second French translation takes its own line under the main
      // one, in the muted style of the Greek line above. It then hands a line
      // break to the next verse, which would otherwise trail it — see the
      // separator at the end of this loop.
      final alexandrie = verse.alexandrie;
      var lineBreakAfter = false;
      if (alexandrie != null && alexandrie.isNotEmpty) {
        push('\n', body);
        push(
          alexandrie,
          body.copyWith(fontSize: baseSize * .88, color: theme.noteColor),
        );
        lineBreakAfter = true;
      }

      // End-of-verse markers: user favourite / user note as tiny icons. The
      // BYM ✦ hint is deliberately absent here — the continuous flow asked to
      // stay clean when the notes are hidden.
      if (widget.isFavoriteOf?.call(vn) ?? false) {
        content.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                Icons.star,
                size: baseSize * .7,
                color: theme.accentColor,
              ),
            ),
          ),
        );
        contentChars += 1;
      }
      if (widget.hasNoteOf?.call(vn) ?? false) {
        content.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Icon(
                Icons.edit_note,
                size: baseSize * .8,
                color: theme.accentColor,
              ),
            ),
          ),
        );
        contentChars += 1;
      }
      // Verse separator: a space inside the flow — except after a verse that
      // ended on its own line (second translation), which passes a line break
      // so the next verse's number doesn't trail the translation. The last
      // verse keeps the trailing space, as every verse did before.
      push(
        lineBreakAfter && idx < widget.segment.verses.length - 1 ? '\n' : ' ',
        body,
      );

      children.add(
        TextSpan(
          style: body.copyWith(background: _backgroundFor(vn)),
          children: content,
        ),
      );
      rendered += contentChars;
    }

    _verseOffsets =
        (offsets.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))
            .map((e) => (e.value, e.key))
            .toList();

    // Long-press anywhere in the flow resolves to its verse via geometry:
    // span recognizers cannot carry two gestures, so selection lives here
    // while taps ride on the text pieces themselves.
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onLongPressStart: _handleLongPressStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              key: _paraKey,
              text: TextSpan(style: body, children: children),
              textAlign: widget.textAlign,
              // Le flux dessine avec `RichText`, dont le `textScaler` vaut
              // `TextScaler.noScaling` par défaut : il n'interroge jamais le
              // `MediaQuery`, là où `Text` / `Text.rich` (les tuiles « Versets
              // séparés » ET l'introduction du livre) le font. Sans ce scaler,
              // le corps continu perdait l'échelle de lecture globale posée
              // dans `main.dart` (échelle système bornée × facteur d'écran) et
              // divergeait de son intro — plus petit quand l'échelle dépasse 1
              // (~14 % sur un téléphone à grande police système), plus gros
              // en dessous. À taille de police et graisse identiques dans le
              // style : plus serré, donc lu comme « plus noir ».
              textScaler: MediaQuery.textScalerOf(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// A noted word located by `note.position` (char offset) with the same
/// fallback-on-search rule as the tile renderer.
class _PNoteRange {
  final int start;
  final int end;
  final VerseNote note;
  const _PNoteRange(this.start, this.end, this.note);
}

List<_PNoteRange> _resolveNoteRanges(Verse verse) {
  final out = <_PNoteRange>[];
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
      out.add(_PNoteRange(start, end, n));
    }
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}
