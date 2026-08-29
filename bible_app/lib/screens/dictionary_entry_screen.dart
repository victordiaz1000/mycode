import 'package:flutter/material.dart';

import '../data/dictionary_catalog.dart';
import '../data/dictionary_reader.dart';
import '../widgets/dictionary_article_view.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/premium_style.dart';

/// A single entry of a downloaded dictionary: the term in a header card
/// (badge = the dictionary name), then the definition as a multi-paragraph,
/// cross-linked article — the same fiche as Westphal 1932
/// ([DictionaryArticleView]), fed by the downloaded [DictionaryReader].
class DictionaryEntryScreen extends StatelessWidget {
  final DictionaryEntry entry;
  final DictionaryArticle article;
  final DictionaryReader reader;

  /// Ouvre la référence biblique d'un article dans la lecture. Null hors
  /// coquille (tests) : les références restent du texte plat plutôt que des
  /// boutons morts.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const DictionaryEntryScreen({
    super.key,
    required this.entry,
    required this.article,
    required this.reader,
    this.onOpenVerse,
  });

  Future<void> _openEntry(BuildContext context, String term) async {
    final target = reader.lookup(term);
    if (target == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DictionaryEntryScreen(
          entry: entry,
          article: target,
          reader: reader,
          onOpenVerse: onOpenVerse,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FicheTextScope(
      builder: (context, style) {
        final p = premiumPalette(context);
        return Scaffold(
          backgroundColor: premiumBackground(context),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: p.textDark,
            centerTitle: true,
            actions: const [FicheDisplayMenuButton()],
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: DictionaryArticleView(
                term: article.term,
                definition: article.definition,
                badge: entry.name,
                subtitle: entry.description,
                sourceMention: entry.rights,
                linkPatternLoader: () async => reader.linkPattern(),
                onTermTap: (term) => _openEntry(context, term),
                onReferenceTap: onOpenVerse == null
                    ? null
                    : (reference) => onOpenVerse!(
                        reference.bookIndex,
                        reference.chapter ?? 1,
                        reference.verse ?? 1,
                      ),
                paragraphStyle: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                      height: 1.7,
                      fontSize: style.fontSize,
                      fontFamily: style.fontFamily,
                    ),
                paragraphAlign: style.align,
              ),
            ),
          ),
        );
      },
    );
  }
}
