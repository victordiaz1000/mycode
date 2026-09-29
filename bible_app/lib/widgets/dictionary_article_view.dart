import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/reference_parser.dart';
import 'premium_style.dart';

/// The rich dictionary article: the term in a header card, then the definition
/// (multi-paragraph, cross-linked) with a « Lire la suite / Réduire » toggle and
/// the source mention.
///
/// Generic over the dictionary that serves it: the badge, subtitle and source
/// mention come from the caller (Westphal 1932, Bailly…), and the cross-link
/// pattern is loaded by [linkPatternLoader] — the set of terms that are
/// themselves entries of the same dictionary.
///
/// Shared by the library fiche ([FredawEntryScreen], [DictionaryEntryScreen])
/// so that every dictionary renders the *same* up-to-date article.
///
/// Callers own the scroll view and its padding; this widget is the content
/// column only.
class DictionaryArticleView extends StatefulWidget {
  final String term;
  final String definition;

  /// The dictionary name shown in the header badge.
  final String badge;

  /// The line under the term — the dictionary description.
  final String subtitle;

  /// The footer line naming the source and its rights.
  final String sourceMention;

  /// Builds the cross-link pattern: every word of the article that is itself
  /// a dictionary entry becomes a link. Null keeps the paragraphs plain.
  final Future<RegExp?> Function() linkPatternLoader;

  /// A word of the article that is itself a dictionary entry. Null disables
  /// cross-linking (the caller does not browse the lexicon).
  final ValueChanged<String>? onTermTap;

  /// A Bible reference found in the article. Null keeps references plain.
  final ValueChanged<BibleReference>? onReferenceTap;

  /// Overrides the paragraph style (reader text size / colour). Defaults to
  /// the fiche's `bodyLarge` with line height 1.7.
  final TextStyle? paragraphStyle;

  /// Overrides the paragraph alignment (reader preference).
  final TextAlign? paragraphAlign;

  const DictionaryArticleView({
    super.key,
    required this.term,
    required this.definition,
    required this.badge,
    required this.subtitle,
    required this.sourceMention,
    required this.linkPatternLoader,
    this.onTermTap,
    this.onReferenceTap,
    this.paragraphStyle,
    this.paragraphAlign = TextAlign.justify,
  });

  @override
  State<DictionaryArticleView> createState() => _DictionaryArticleViewState();
}

class _DictionaryArticleViewState extends State<DictionaryArticleView> {
  static const int _limite = 2;
  bool _toutLire = false;

  /// The case-insensitive cross-link pattern: every word of the article that
  /// is itself a dictionary entry becomes a link. Null until the lexicon is
  /// loaded (paragraphs then stay plain text).
  RegExp? _linkPattern;

  @override
  void initState() {
    super.initState();
    _loadLinks();
  }

  Future<void> _loadLinks() async {
    final pattern = await widget.linkPatternLoader();
    if (!mounted) return;
    setState(() => _linkPattern = pattern);
  }

  List<String> get _paragraphes => [
    for (final p in widget.definition.split('\n\n'))
      if (p.trim().isNotEmpty) p.trim(),
  ];

  List<String> get _visibles =>
      _toutLire ? _paragraphes : _paragraphes.take(_limite).toList();

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final accent = p.primary;
    final paras = _paragraphes;
    final paragraphStyle =
        widget.paragraphStyle ??
        Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: premiumSurface(context, radius: 20, depth: 1.1),
          child: Column(
            children: [
              _Badge(widget.badge, accent),
              const SizedBox(height: 14),
              Text(
                widget.term,
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  24,
                  FontWeight.w800,
                  p.textDark,
                  spacing: 1.5,
                ),
              ),
              const SizedBox(height: 10),
              // Filet d'accent centré sous le terme : la tête d'article a son
              // propre repère, comme les cartes de l'étude du verset.
              Center(
                child: Container(
                  width: 56,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: LinearGradient(
                      colors: [accent, accent.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.subtitle,
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  13,
                  FontWeight.w500,
                  p.textGrey,
                  italic: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _SectionTitle('Article', Icons.article_rounded, accent),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: premiumSurface(context, radius: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final paragraph in _visibles) ...[
                _LinkifiedText(
                  text: paragraph,
                  style: paragraphStyle,
                  align: widget.paragraphAlign ?? TextAlign.justify,
                  linkStyle: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: accent,
                  ),
                  pattern: _linkPattern,
                  references: widget.onReferenceTap == null
                      ? const <TextReference>[]
                      : findReferences(paragraph),
                  onTermTap: widget.onTermTap,
                  onReferenceTap: widget.onReferenceTap,
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        if (paras.length > _limite) ...[
          const SizedBox(height: 12),
          _LirePlusButton(
            toutLire: _toutLire,
            restants: paras.length - _limite,
            accent: accent,
            onPressed: () => setState(() => _toutLire = !_toutLire),
          ),
        ],
        const SizedBox(height: 28),
        Text(
          widget.sourceMention,
          textAlign: TextAlign.center,
          style: premiumText(
            context,
            12,
            FontWeight.w500,
            p.textGrey,
            italic: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionTitle(this.title, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: p.primarySoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: .28)),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: premiumText(context, 16, FontWeight.w800, p.textDark),
        ),
      ],
    );
  }
}

class _LirePlusButton extends StatelessWidget {
  final bool toutLire;
  final int restants;
  final Color accent;
  final VoidCallback onPressed;

  const _LirePlusButton({
    required this.toutLire,
    required this.restants,
    required this.accent,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent.withValues(alpha: .45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: p.primarySoft.withValues(alpha: .35),
        ),
        icon: Icon(
          toutLire
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
          color: accent,
        ),
        label: Text(
          toutLire ? 'Réduire' : 'Lire la suite ($restants paragraphes)',
          style: premiumText(context, 15, FontWeight.w700, accent),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

/// An article paragraph where every word that is itself a dictionary entry and
/// every Bible reference are rendered as tappable links. Stateful only to own
/// the tap recognizers: they must be disposed once the widget leaves the tree.
class _LinkifiedText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign align;
  final TextStyle? linkStyle;

  /// Null disables cross-linking (lexicon not loaded yet).
  final RegExp? pattern;

  /// The Bible references to link (empty when no reference callback is wired).
  final List<TextReference> references;
  final ValueChanged<String>? onTermTap;
  final ValueChanged<BibleReference>? onReferenceTap;

  const _LinkifiedText({
    required this.text,
    required this.style,
    required this.align,
    required this.linkStyle,
    required this.pattern,
    required this.references,
    required this.onTermTap,
    required this.onReferenceTap,
  });

  @override
  State<_LinkifiedText> createState() => _LinkifiedTextState();
}

class _LinkifiedTextState extends State<_LinkifiedText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  /// The links to render, sorted by start and de-overlapped. A reference wins
  /// over a dictionary word at the same spot (« Jean 3:16 » links the whole
  /// reference, not just the word « Jean »).
  List<({int start, int end, String? word, BibleReference? reference})>
  _collectLinks() {
    final links =
        <({int start, int end, String? word, BibleReference? reference})>[];
    final pattern = widget.pattern;
    if (pattern != null) {
      for (final match in pattern.allMatches(widget.text)) {
        links.add((
          start: match.start,
          end: match.end,
          word: match.group(0),
          reference: null,
        ));
      }
    }
    for (final ref in widget.references) {
      links.add((
        start: ref.start,
        end: ref.end,
        word: null,
        reference: ref.reference,
      ));
    }
    links.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      final byLength = (b.end - b.start).compareTo(a.end - a.start);
      if (byLength != 0) return byLength;
      return (a.reference != null ? 0 : 1).compareTo(
        b.reference != null ? 0 : 1,
      );
    });
    final kept =
        <({int start, int end, String? word, BibleReference? reference})>[];
    var lastEnd = -1;
    for (final link in links) {
      if (link.start < lastEnd) continue;
      kept.add(link);
      lastEnd = link.end;
    }
    return kept;
  }

  List<InlineSpan> _buildSpans() {
    final links = _collectLinks();
    if (links.isEmpty) return [TextSpan(text: widget.text)];
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (link.reference != null) {
            widget.onReferenceTap?.call(link.reference!);
          } else {
            widget.onTermTap?.call(link.word!.toUpperCase());
          }
        };
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: widget.text.substring(link.start, link.end),
          style: widget.linkStyle,
          recognizer: recognizer,
        ),
      );
      cursor = link.end;
    }
    if (cursor < widget.text.length) {
      spans.add(TextSpan(text: widget.text.substring(cursor)));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    _recognizers.clear();
    return Text.rich(
      TextSpan(style: widget.style, children: _buildSpans()),
      textAlign: widget.align,
    );
  }
}
