import 'package:flutter/material.dart';

import 'premium_style.dart';

/// Les briques communes aux trois index de lexique/dictionnaire embarqués
/// (Notes BYM, Westphal 1932, Strong FR et le lecteur générique des
/// dictionnaires téléchargés) : puces alphabétiques, mention de source et
/// carte d'entrée. Chacun de ces écrans portait sa copie privée, qui dérivait
/// au fil des retouches.

/// Une puce de la barre alphabétique (« Toutes », A, B…).
class LexiconLetterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const LexiconLetterChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? p.heroGradient : null,
          color: active ? null : p.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: active
              ? premiumShadow(
                  accent,
                  opacity: .2,
                  blur: 12,
                  offset: const Offset(0, 4),
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            active ? p.onPrimary : p.textDark,
          ),
        ),
      ),
    );
  }
}

/// La ligne « info » sous la recherche : ce que contient l'index et d'où ça
/// vient.
class LexiconSourceMention extends StatelessWidget {
  final String text;

  const LexiconSourceMention({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: p.textGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
          ),
        ),
      ],
    );
  }
}

/// Une carte d'entrée : terme + extrait, tap → fiche. Le tap appartient à
/// l'écran (chaque index pousse sa propre fiche).
class LexiconEntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const LexiconEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: premiumShadow(
              p.primaryDark,
              opacity: 0.05,
              blur: 12,
              offset: const Offset(0, 4),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: premiumText(
                        context,
                        15,
                        FontWeight.w800,
                        p.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: premiumText(
                        context,
                        12,
                        FontWeight.w500,
                        p.textGrey,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: p.textGrey, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
