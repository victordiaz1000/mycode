import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/lsgs_repository.dart';
import '../data/strong_occurrences.dart';
import '../models/lsgs.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';

/// One occurrence row: the reference and the full verse text with the Strong
/// word in occurrence highlighted (a tinted background — never bold, never a
/// link). Shared by the fiche preview and the per-book list. Au goût premium.
class StrongOccurrenceCard extends StatelessWidget {
  final StrongOccurrence occ;
  final String reference;

  /// The verse tokens; the one bearing [highlight] is emphasised.
  final List<LsgsToken> tokens;

  /// The Strong code to highlight within [tokens]. Null disables emphasis.
  final String? highlight;

  final VoidCallback? onTap;
  final Color accent;

  const StrongOccurrenceCard({
    super.key,
    required this.occ,
    required this.reference,
    required this.tokens,
    required this.accent,
    this.highlight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.07,
            blur: 16,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.menu_book_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reference,
                        style: premiumText(
                          context,
                          15,
                          FontWeight.w700,
                          p.textDark,
                        ),
                      ),
                      if (tokens.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        _OccurrenceVerseText(
                          tokens: tokens,
                          highlight: highlight,
                          style: premiumText(
                            context,
                            13,
                            FontWeight.w500,
                            p.textGrey,
                            height: 1.4,
                          ),
                          highlightStyle: TextStyle(
                            backgroundColor: accent.withValues(alpha: .25),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: p.textGrey,
                    size: 22,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The full verse text of an occurrence, word by word, with the token bearing
/// [highlight] emphasised — a highlight, never a link.
class _OccurrenceVerseText extends StatelessWidget {
  final List<LsgsToken> tokens;

  /// The Strong code to emphasise within [tokens]. Null disables emphasis.
  final String? highlight;

  final TextStyle? style;
  final TextStyle? highlightStyle;

  const _OccurrenceVerseText({
    required this.tokens,
    required this.highlight,
    required this.style,
    required this.highlightStyle,
  });

  @override
  Widget build(BuildContext context) {
    final segments = LsgsRepository.segments(tokens, target: highlight);
    if (segments.isEmpty) return const SizedBox.shrink();
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.start,
      runSpacing: 2,
      children: [
        for (final segment in segments)
          Text(segment.text, style: segment.isTarget ? highlightStyle : style),
      ],
    );
  }
}

/// The « Voir plus » destination: the books of the LSGS corpus that contain a
/// Strong code, each with the number of verses bearing it. Tapping a book
/// opens [StrongBookOccurrencesScreen], the verse-by-verse list of that book.
class StrongOccurrencesScreen extends StatelessWidget {
  final String code;
  final List<StrongOccurrence> occurrences;

  /// Opens a verse in a reader tab. Null when the chain stands alone: cards
  /// then just state their reference.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const StrongOccurrencesScreen({
    super.key,
    required this.code,
    required this.occurrences,
    this.onOpenVerse,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final grouped = <int, List<StrongOccurrence>>{};
    for (final occ in occurrences) {
      grouped.putIfAbsent(occ.bookIndex, () => []).add(occ);
    }
    final books = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Occurrences — $code',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${occurrences.length} verset${occurrences.length > 1 ? 's' : ''} '
              'réparti${occurrences.length > 1 ? 's' : ''} dans '
              '${books.length} livre${books.length > 1 ? 's' : ''}',
              style: premiumText(context, 13, FontWeight.w500, p.textGrey),
            ),
            const SizedBox(height: 12),
            for (final book in books)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _BookCard(
                  name: catalogEntry(book).shortName,
                  count: grouped[book]!.length,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StrongBookOccurrencesScreen(
                        bookIndex: book,
                        bookName: catalogEntry(book).shortName,
                        occurrences: grouped[book]!,
                        highlight: code,
                        onOpenVerse: onOpenVerse,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// All the verses of one book that carry the code, in reading order, each with
/// its text (the book is loaded once and indexed by `chapitre:verset`).
class StrongBookOccurrencesScreen extends StatefulWidget {
  final int bookIndex;
  final String bookName;
  final List<StrongOccurrence> occurrences;

  /// The Strong code to emphasise in each verse. Null disables emphasis.
  final String? highlight;
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const StrongBookOccurrencesScreen({
    super.key,
    required this.bookIndex,
    required this.bookName,
    required this.occurrences,
    this.highlight,
    this.onOpenVerse,
  });

  @override
  State<StrongBookOccurrencesScreen> createState() =>
      _StrongBookOccurrencesScreenState();
}

class _StrongBookOccurrencesScreenState
    extends State<StrongBookOccurrencesScreen> {
  final Map<String, List<LsgsToken>> _tokens = {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final book = await LsgsRepository().loadBook(widget.bookIndex);
    final tokens = <String, List<LsgsToken>>{};
    for (final chapter in book.chapters) {
      for (final verse in chapter.verses) {
        tokens['${chapter.chapter}:${verse.verse}'] = verse.tokens;
      }
    }
    if (!mounted) return;
    setState(() {
      _tokens.addAll(tokens);
      _ready = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          widget.bookName,
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: !_ready
            // Les versets d'occurrences arrivent en liste : le même squelette
            // que les autres écrans de liste, pas un spinner nu.
            ? const ListLoadingSkeleton(padding: EdgeInsets.all(20))
            : ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: widget.occurrences.length,
                itemBuilder: (context, index) {
                  final occ = widget.occurrences[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: StrongOccurrenceCard(
                      occ: occ,
                      reference: occ.reference,
                      tokens:
                          _tokens['${occ.chapter}:${occ.verse}'] ?? const [],
                      highlight: widget.highlight,
                      accent: accent,
                      onTap: widget.onOpenVerse == null
                          ? null
                          : () => widget.onOpenVerse!(
                              occ.bookIndex,
                              occ.chapter,
                              occ.verse,
                            ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final String name;
  final int count;
  final VoidCallback onTap;

  const _BookCard({
    required this.name,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.07,
            blur: 16,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.menu_book_rounded, size: 18, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: premiumText(
                      context,
                      15,
                      FontWeight.w700,
                      p.textDark,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: premiumText(context, 12, FontWeight.w800, accent),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: p.textGrey, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
