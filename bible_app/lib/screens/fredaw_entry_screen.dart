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

  /// Étape G : posée en volet d'un split-view, la fiche ne montre pas de
  /// retour — il dépilerait l'écran qui l'héberge. Vrai par défaut (route).
  final bool showBackButton;

  const FredawEntryScreen({
    super.key,
    required this.entry,
    this.onOpenVerse,
    this.showBackButton = true,
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
    // Famille `dico.*` : les dictionnaires gardent leurs réglages, séparés
    // de l'ouvrage (`fiche.*`) comme de l'étude (`etude.*`).
    return FicheTextScope(
      group: DisplayGroup.dico,
      builder: (context, style) {
        final p = premiumPalette(context);
        return Scaffold(
          backgroundColor: premiumBackground(context),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            foregroundColor: p.textDark,
            centerTitle: true,
            automaticallyImplyLeading: showBackButton,
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
            actions: const [FicheDisplayMenuButton(group: DisplayGroup.dico)],
          ),
          body: SafeArea(
            top: false,
            // Slivers : voir [DictionaryArticleView] — les articles Westphal
            // montent à 705 paragraphes, ils ne peuvent pas être construits
            // d'un bloc.
            child: CustomScrollView(
              slivers: [
                FredawArticleView(
                  entry: entry,
                  onTermTap: (term) => _openEntry(context, term),
                  onReferenceTap: onOpenVerse == null
                      ? null
                      : (BibleReference reference) => onOpenVerse!(
                          reference.bookIndex,
                          reference.chapter ?? 1,
                          reference.verse ?? 1,
                        ),
                  paragraphStyle: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(
                        height: 1.7,
                        fontSize: style.fontSize,
                        fontFamily: style.fontFamily,
                      ),
                  paragraphAlign: style.align,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}