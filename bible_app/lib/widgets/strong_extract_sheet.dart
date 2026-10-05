import 'package:flutter/material.dart';

import '../data/strong_lexicon.dart';
import 'premium_style.dart';
import 'strong_lemma.dart';

/// Ouvre l'extrait du détail Strong — le tap sur un code de la LSGS.
///
/// Ce qu'elle montre : ce qui suffit pour reconnaître l'entrée — badges de
/// langue et de nature, lemma, translittération, numéro, prononciation — puis
/// ce que la source en dit en deux lignes, la définition brève et la
/// signification quand il y en a une. Ce qu'elle ne montre pas — les sens
/// développés, l'origine, les occurrences — vit dans la fiche, qu'un bouton
/// ouvre : l'extrait répond au premier regard, la fiche à l'étude.
///
/// Le même geste que la feuille d'un mot de l'interlinéaire : un extrait
/// d'abord, la fiche ensuite, jamais l'écran complet au premier tap.
/// [onOpenFull] part une fois la feuille fermée — derrière une feuille
/// modale, une poussée ne se verrait pas.
Future<void> showStrongExtractSheet(
  BuildContext context, {
  required StrongDefinition strong,
  required Future<void> Function() onOpenFull,
}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: premiumBackground(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Container(
          decoration: premiumSurface(context, radius: 24, depth: 1.3),
          child: _StrongExtractSheet(strong: strong, onOpenFull: onOpenFull),
        ),
      ),
    );

class _StrongExtractSheet extends StatelessWidget {
  const _StrongExtractSheet({
    required this.strong,
    required this.onOpenFull,
  });

  final StrongDefinition strong;
  final Future<void> Function() onOpenFull;

  /// La langue de l'entrée, lue comme la fiche la lit — le badge s'en teinte.
  bool get _isGreek =>
      strong.language == 'greek' || strong.strong.startsWith('G');

  /// La définition brève : le premier sens, ou la première ligne de la
  /// définition quand l'entrée n'a pas de sens structurés — la même lecture
  /// que la carte « Définition brève » de la fiche.
  String get _breve {
    final lines = strong.senses.isNotEmpty
        ? strong.senses
        : strong.definition
            .split(RegExp(r'[•\n]'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty);
    return lines.isEmpty ? '' : lines.first;
  }

  /// Ouvrir la fiche complète : la feuille se ferme d'abord, la route part
  /// ensuite du lecteur — derrière une feuille modale, une poussée ne se
  /// verrait pas.
  void _openFull(BuildContext context) {
    Navigator.of(context).pop();
    onOpenFull();
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final breve = _breve;
    final signification = strong.signification;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, p),
          if (breve.isNotEmpty) ...[
            const SizedBox(height: 14),
            const _Label('Définition brève'),
            const SizedBox(height: 4),
            Text(
              breve,
              style: premiumText(
                context,
                15,
                FontWeight.w500,
                p.textDark,
                height: 1.5,
              ),
            ),
          ],
          if (signification != null) ...[
            const SizedBox(height: 14),
            const _Label('Signification'),
            const SizedBox(height: 4),
            Text(
              signification,
              style: premiumText(
                context,
                15,
                FontWeight.w600,
                p.textDark,
                height: 1.45,
              ),
            ),
          ],
          if (breve.isEmpty && signification == null)
            Text(
              "Définition absente de l'entrée — la fiche porte le reste.",
              style: premiumText(context, 12, FontWeight.w500, p.textGrey),
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openFull(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: p.primary, width: 1.8),
                foregroundColor: p.primary,
                backgroundColor: p.primarySoft.withValues(alpha: .45),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.menu_book_rounded),
              label: Text(
                'Voir la fiche complète',
                textAlign: TextAlign.center,
                style: premiumText(context, 13.5, FontWeight.w800, p.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// L'en-tête : la même ordonnance que la carte de la fiche Strong — les
  /// badges de langue et de nature, le mot en grand, la translittération
  /// dessous, puis le numéro et la prononciation de part et d'autre d'un filet.
  /// On reconnaît l'entrée avant de la lire.
  Widget _header(BuildContext context, PremiumPalette p) {
    final partOfSpeech = strong.partOfSpeech;
    final transliteration = strong.transliteration;
    final pronunciation = strong.pronunciation;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: premiumSurface(context, radius: 18, depth: .9),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(
                _isGreek ? 'Grec' : 'Hébreu',
                _isGreek ? p.greek : p.hebrew,
              ),
              if (partOfSpeech != null && partOfSpeech.isNotEmpty) ...[
                const SizedBox(width: 8),
                _Badge(partOfSpeech, p.textGrey),
              ],
            ],
          ),
          const SizedBox(height: 12),
          StrongLemma(
            lemma: strong.lemma,
            strong: strong.strong,
            language: strong.language,
            size: 30,
            align: TextAlign.center,
          ),
          if (transliteration != null && transliteration.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              transliteration,
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                15,
                FontWeight.w500,
                p.textGrey,
                italic: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // Filet qui se perd vers les bords plutôt que le trait plein : la
          // carte garde sa ligne de partage sans se couper en deux.
          Container(
            width: double.infinity,
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.textGrey.withValues(alpha: 0),
                  p.textGrey.withValues(alpha: .35),
                  p.textGrey.withValues(alpha: 0),
                ],
                stops: const [0, .5, 1],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Numéro Strong',
                      style: premiumText(
                        context,
                        12,
                        FontWeight.w500,
                        p.textGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strong.strong,
                      style: premiumText(context, 16, FontWeight.w800, p.primary),
                    ),
                  ],
                ),
              ),
              if (pronunciation != null && pronunciation.isNotEmpty)
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Prononciation',
                        style: premiumText(
                          context,
                          12,
                          FontWeight.w500,
                          p.textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pronunciation,
                        textAlign: TextAlign.end,
                        style: premiumText(
                          context,
                          14,
                          FontWeight.w500,
                          p.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// L'étiquette d'un champ, la même voix que les labels de la fiche Strong :
/// petit, gras, gris — elle nomme, elle ne dit pas.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Text(
      text,
      style: premiumText(context, 12, FontWeight.w500, p.textGrey),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        text,
        style: premiumText(context, 12, FontWeight.w700, color),
      ),
    );
  }
}
