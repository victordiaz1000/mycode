import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/fredaw_article_view.dart';
import '../widgets/premium_style.dart';

/// A single Westphal 1932 article: the term in a header card, then the
/// definition (multi-paragraph) with a « Lire la suite / Réduire » toggle.
///
/// The body is the reusable [FredawArticleView]; this screen only adds the
/// AppBar.
class FredawEntryScreen extends StatelessWidget {
  final FreDawEntry entry;

  /// Ouvre la référence biblique d'un article dans la lecture. Null hors
  /// coquille (tests) : les références restent du texte plat.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const FredawEntryScreen({
    super.key,
    required this.entry,
    this.onOpenVerse,
  });

  Future<void> _openEntry(BuildContext context, String term) async {
    final entry = await FreDawLexicon.instance.lookup(term);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FredawEntryScreen(
          entry: entry,
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
            // Pas de titre : « Westphal 1932 » est déjà le badge du corps, et
            // un test le compte à l'unité. Le voile d'accent suffit.
            flexibleSpace: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    p.primary.withValues(alpha: .12),
                    p.primary.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            actions: const [FicheDisplayMenuButton()],
          ),
          body: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: FredawArticleView(
                entry: entry,
                onTermTap: (term) => _openEntry(context, term),
                onReferenceTap: onOpenVerse == null
                    ? null
                    : (BibleReference reference) => onOpenVerse!(
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