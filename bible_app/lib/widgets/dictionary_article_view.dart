import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/reference_parser.dart';
import 'premium_style.dart';

/// L'article de dictionnaire : une en-tête épinglée, puis la définition
/// multi-paragraphes aux références et aux termes cliquables.
///
/// **C'est un sliver**, pas une boîte : à poser directement dans les `slivers`
/// d'un `CustomScrollView`. C'est tout l'objet de la bascule — la version
/// précédente était une `Column` dans un `SingleChildScrollView`, donc sans
/// aucune paresse : tous les paragraphes étaient construits *et mis en page*
/// d'un coup. Mesuré sur le corpus Westphal : l'article « PROPHÈTE 6. » fait
/// 140 121 caractères sur **705 paragraphes**, et six autres dépassent 55 000
/// caractères. Taper « Lire la suite » y déclenchait, dans une seule frame,
/// 705 widgets, 705 passes de RegExp, un millier de `TapGestureRecognizer` et
/// la mise en page de tout le texte.
///
/// En `SliverList.builder`, un article de 705 paragraphes s'ouvre aussi vite
/// qu'un de trois — et le bouton « Lire la suite / Réduire » n'a plus de
/// raison d'être : il n'existait que pour contenir ce coût. Il est donc
/// supprimé, son rôle d'avertissement (« cet article est un traité ») passant
/// au compteur de l'en-tête.
///
/// Générique sur le dictionnaire qui la sert : badge, sous-titre et mention de
/// source viennent de l'appelant (Westphal 1932, Bailly…), et le motif de
/// liens croisés est chargé par [linkPatternLoader].
///
/// Partagée par [FredawEntryScreen] (via `FredawArticleView`) et
/// [DictionaryEntryScreen] — ses deux seuls appelants.
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
  ///
  /// Le motif est une alternation de plusieurs milliers de termes. Mesuré :
  /// 0,12 ms par paragraphe, et une tokenisation + `Set` serait ~30 % plus
  /// lente — Dart compile les grosses alternations en automate efficace.
  /// **Ne pas « optimiser » ce point**, l'intuition contraire est trompeuse.
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
  /// The case-insensitive cross-link pattern: every word of the article that
  /// is itself a dictionary entry becomes a link. Null until the lexicon is
  /// loaded (paragraphs then stay plain text).
  RegExp? _linkPattern;

  /// `findReferences` coûte cher (recherche livre + tolérance typo) : un
  /// article se rebuild à chaque frappe de réglage, chaque arrivée du pattern,
  /// chaque changement de taille. Sans cache, chaque paragraphe repaye le
  /// parsing à chaque frame — d'où le défilement lourd.
  final Map<String, List<TextReference>> _refsCache = {};

  /// Découpé une fois par article, et non plus à chaque `build` : la version
  /// précédente appelait le getter `_paragraphes` deux fois par construction,
  /// soit deux `split` d'un texte qui peut peser 140 000 caractères.
  late List<String> _paragraphes;

  @override
  void initState() {
    super.initState();
    _paragraphes = _split(widget.definition);
    _loadLinks();
  }

  @override
  void didUpdateWidget(covariant DictionaryArticleView old) {
    super.didUpdateWidget(old);
    if (widget.definition != old.definition) {
      _paragraphes = _split(widget.definition);
      _refsCache.clear();
    }
  }

  static List<String> _split(String definition) => [
    for (final p in definition.split('\n\n'))
      if (p.trim().isNotEmpty) p.trim(),
  ];

  Future<void> _loadLinks() async {
    final pattern = await widget.linkPatternLoader();
    if (!mounted) return;
    setState(() => _linkPattern = pattern);
  }

  /// Les références d'un paragraphe, mémorisées : le même texte ne repaye
  /// jamais deux fois le parsing, et `_LinkifiedText` reçoit la même instance
  /// tant que le paragraphe ne change pas — son cache reste valide.
  List<TextReference> _refsFor(String paragraph) {
    if (widget.onReferenceTap == null) return const <TextReference>[];
    return _refsCache.putIfAbsent(paragraph, () => findReferences(paragraph));
  }

  /// Sous ce seuil, un bloc est traité comme une **ligne** et non comme un
  /// paragraphe.
  ///
  /// Le corpus Westphal sépare les citations poétiques vers par vers, chaque
  /// vers devenant un « paragraphe » à part entière : sur les 705 blocs de
  /// « PROPHÈTE 6. », 549 font moins de 70 caractères et 152 seulement sont de
  /// la prose. L'écart uniforme de 14 px les disloquait — un poème s'affichait
  /// aéré comme une suite de paragraphes indépendants.
  static const int _shortLine = 70;

  /// L'écart sous le bloc [i] : resserré entre deux lignes courtes
  /// consécutives, normal partout ailleurs. Règle locale et prudente — une
  /// erreur de jugement ne coûte qu'un écart de 4 px au lieu de 14, jamais un
  /// paragraphe de prose collé au suivant.
  double _gapAfter(int i) {
    if (i >= _paragraphes.length - 1) return 0;
    final tight = _paragraphes[i].length < _shortLine &&
        _paragraphes[i + 1].length < _shortLine;
    return tight ? 4 : 14;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final paragraphStyle =
        widget.paragraphStyle ??
        Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.7);
    final linkStyle = TextStyle(
      color: p.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: p.primary,
    );
    return SliverMainAxisGroup(
      slivers: [
        // L'en-tête reste épinglée : le terme et le dictionnaire accompagnent
        // la lecture d'un article qui peut faire des centaines d'écrans. La
        // carte de tête d'avant — badge, terme en 24 pt, filet d'accent,
        // sous-titre, puis un titre de section « Article » et un cadre
        // imbriqué — repoussait le premier mot sous la ligne de flottaison
        // d'un téléphone, et disparaissait au premier geste de défilement.
        SliverPersistentHeader(
          pinned: true,
          delegate: DictionaryFicheHeader(
            term: widget.term,
            badge: widget.badge,
            paragraphCount: _paragraphes.length,
            palette: p,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          sliver: SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    widget.subtitle,
                    style: premiumText(
                      context,
                      12,
                      FontWeight.w500,
                      p.textGrey,
                      italic: FontStyle.italic,
                    ),
                  ),
                ),
              ),
              // Le cœur du changement : un paragraphe n'est construit qu'à
              // l'approche du viewport.
              SliverList.builder(
                itemCount: _paragraphes.length,
                itemBuilder: (context, i) {
                  final paragraph = _paragraphes[i];
                  return Padding(
                    padding: EdgeInsets.only(bottom: _gapAfter(i)),
                    child: _LinkifiedText(
                      text: paragraph,
                      style: paragraphStyle,
                      align: widget.paragraphAlign ?? TextAlign.justify,
                      linkStyle: linkStyle,
                      pattern: _linkPattern,
                      references: _refsFor(paragraph),
                      onTermTap: widget.onTermTap,
                      onReferenceTap: widget.onReferenceTap,
                    ),
                  );
                },
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Text(
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
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// L'en-tête épinglée de la fiche : le terme, le dictionnaire, et le nombre de
/// paragraphes quand l'article est long.
///
/// Ce compteur reprend le seul service que rendait « Lire la suite (703
/// paragraphes) » : avertir que l'entrée ouverte est un traité et non une
/// définition. La différence est qu'il informe sans rien cacher.
class DictionaryFicheHeader extends SliverPersistentHeaderDelegate {
  final String term;
  final String badge;
  final int paragraphCount;
  final PremiumPalette palette;

  const DictionaryFicheHeader({
    required this.term,
    required this.badge,
    required this.paragraphCount,
    required this.palette,
  });

  /// Au-delà, l'en-tête affiche le compteur de paragraphes.
  static const int _longArticle = 25;

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final long = paragraphCount > _longArticle;
    return Material(
      color: premiumBackground(context),
      child: Container(
        height: 54,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: palette.primary.withValues(
                // Le filet n'apparaît qu'une fois le texte passé dessous :
                // en haut de course, l'en-tête se fond dans la page.
                alpha: shrinkOffset > 0 || overlaps ? 0.22 : 0,
              ),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: premiumText(
                  context,
                  18,
                  FontWeight.w800,
                  palette.textDark,
                  spacing: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (long)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '$paragraphCount §',
                  style: premiumText(
                    context,
                    11,
                    FontWeight.w700,
                    palette.textGrey,
                  ),
                ),
              ),
            _Badge(badge, palette.primary),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant DictionaryFicheHeader old) =>
      old.term != term ||
      old.badge != badge ||
      old.paragraphCount != paragraphCount ||
      old.palette != palette;
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .30)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
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
  /// Un recognizer par lien : recréés uniquement quand le texte, le pattern
  /// ou les références changent — jamais à chaque build. Avant, `build`
  /// faisait `_recognizers.clear()` sans `dispose` (fuite) puis recréait tout
  /// en plein build, en relançant le gros RegExp à chaque frame.
  final List<TapGestureRecognizer> _recognizers = [];
  List<({int start, int end, String? word, BibleReference? reference})>
  _links = const [];

  @override
  void initState() {
    super.initState();
    _syncLinks();
  }

  @override
  void didUpdateWidget(covariant _LinkifiedText old) {
    super.didUpdateWidget(old);
    if (widget.text != old.text ||
        !identical(widget.pattern, old.pattern) ||
        !identical(widget.references, old.references)) {
      _syncLinks();
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  /// Recalcule [_links] et les recognizers, en disposant les anciens
  /// d'abord. Appelé depuis `initState` / `didUpdateWidget` uniquement :
  /// `build` reste pur et ne relance plus le RegExp à chaque frame.
  void _syncLinks() {
    _disposeRecognizers();
    final collected = _collectLinks(widget.text, widget.pattern, widget.references);
    for (final link in collected) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (link.reference != null) {
            widget.onReferenceTap?.call(link.reference!);
          } else {
            widget.onTermTap?.call(link.word!.toUpperCase());
          }
        };
      _recognizers.add(recognizer);
    }
    _links = collected;
  }

  /// The links to render, sorted by start and de-overlapped. A reference wins
  /// over a dictionary word at the same spot (« Jean 3:16 » links the whole
  /// reference, not just the word « Jean »). Pure : ne touche ni aux
  /// recognizers ni à l'état.
  static List<({int start, int end, String? word, BibleReference? reference})>
  _collectLinks(String text, RegExp? pattern, List<TextReference> references) {
    final links =
        <({int start, int end, String? word, BibleReference? reference})>[];
    if (pattern != null) {
      for (final match in pattern.allMatches(text)) {
        links.add((
          start: match.start,
          end: match.end,
          word: match.group(0),
          reference: null,
        ));
      }
    }
    for (final ref in references) {
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

  /// Assemble les spans depuis [_links] : pur, sans RegExp ni allocation de
  /// recognizer — le scroll ne repaye plus rien.
  List<InlineSpan> _buildSpans() {
    if (_links.isEmpty) return [TextSpan(text: widget.text)];
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (var i = 0; i < _links.length; i++) {
      final link = _links[i];
      if (link.start > cursor) {
        spans.add(TextSpan(text: widget.text.substring(cursor, link.start)));
      }
      spans.add(
        TextSpan(
          text: widget.text.substring(link.start, link.end),
          style: widget.linkStyle,
          recognizer: _recognizers[i],
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
    return RepaintBoundary(
      child: Text.rich(
        TextSpan(style: widget.style, children: _buildSpans()),
        textAlign: widget.align,
      ),
    );
  }
}
