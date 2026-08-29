import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import 'dictionary_article_view.dart';

/// The rich Westphal 1932 article: the term in a header card, then the
/// definition (multi-paragraph, cross-linked) with a « Lire la suite /
/// Réduire » toggle and the source mention.
///
/// A thin Westphal-specific shell over the reusable [DictionaryArticleView]:
/// the badge, subtitle and source mention are fixed to Westphal 1932, and the
/// cross-link pattern comes from the FreDAW lexicon. Every other dictionary
/// renders through the same generic widget.
///
/// Callers own the scroll view and its padding; this widget is the content
/// column only.
class FredawArticleView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return DictionaryArticleView(
      term: entry.term,
      definition: entry.definition,
      badge: 'Westphal 1932',
      subtitle: 'Dictionnaire encyclopédique de la Bible',
      sourceMention: 'Extrait du Dictionnaire encyclopédique de la Bible\n'
          'Auguste Westphal, 1932',
      linkPatternLoader: () => FreDawLexicon.instance.linkPattern(),
      onTermTap: onTermTap,
      onReferenceTap: onReferenceTap,
      paragraphStyle: paragraphStyle,
      paragraphAlign: paragraphAlign,
    );
  }
}
