import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import 'bible_theme_scope.dart';

/// The rich Westphal 1932 article: the term in a header card, then the
/// definition (multi-paragraph, cross-linked) with a « Lire la suite /
/// Réduire » toggle and the source mention.
///
/// Shared by the library fiche ([FredawEntryScreen]) and the reader's
/// dictionary tab so that both render the *same* up-to-date article — the tab
/// is not a stale « article seul », it is the full fiche body.
///
/// Callers own the scroll view and its padding; this widget is the content
/// column only.
class FredawArticleView extends StatefulWidget {
  final FreDawEntry entry;

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

  const FredawArticleView({
    super.key,
    required this.entry,
    this.onTermTap,
    this.onReferenceTap,
    this.paragraphStyle,
    this.paragraphAlign = TextAlign.justify,
  });

  @override
  State<FredawArticleView> createState() => _FredawArticleViewState();
}

class _FredawArticleViewState extends State<FredawArticleView> {
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
    final pattern = await FreDawLexicon.instance.linkPattern();
    if (!mounted) return;
    setState(() => _linkPattern = pattern);
  }

  List<String> get _paragraphes => [
        for (final p in widget.entry.definition.split('\n\n'))
          if (p.trim().isNotEmpty) p.trim(),
      ];

  List<String> get _visibles =>
      _toutLire ? _paragraphes : _paragraphes.take(_limite).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    final accent = bibleTheme.accentColor;
    final paras = _paragraphes;
    final paragraphStyle =
        widget.paragraphStyle ??
        theme.textTheme.bodyLarge?.copyWith(height: 1.7);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              _Badge('Westphal 1932', accent),
              const SizedBox(height: 14),
              Text(
                widget.entry.term,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Dictionnaire encyclopédique de la Bible',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
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
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
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
        const _SourceMention(),
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
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
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
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent.withValues(alpha: .4)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(
          toutLire ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
          color: accent,
        ),
        label: Text(
          toutLire
              ? 'Réduire'
              : 'Lire la suite ($restants paragraphes)',
          style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _SourceMention extends StatelessWidget {
  const _SourceMention();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Extrait du Dictionnaire encyclopédique de la Bible\nAuguste Westphal, 1932',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
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
    final links = <({int start, int end, String? word, BibleReference? reference})>[];
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
      return (a.reference != null ? 0 : 1).compareTo(b.reference != null ? 0 : 1);
    });
    final kept = <({int start, int end, String? word, BibleReference? reference})>[];
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
      spans.add(TextSpan(
        text: widget.text.substring(link.start, link.end),
        style: widget.linkStyle,
        recognizer: recognizer,
      ));
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
      TextSpan(
        style: widget.style,
        children: _buildSpans(),
      ),
      textAlign: widget.align,
    );
  }
}