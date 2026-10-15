import 'package:flutter/material.dart';

import 'premium_style.dart';

/// L'en-tête épinglée commune aux fiches de mot : le terme reste visible
/// pendant tout le défilement, avec son badge de provenance.
///
/// Généralisée depuis celle de la fiche dictionnaire pour servir les trois
/// familles — dictionnaire téléchargé, Westphal, Lexique BYM, fiche Strong.
/// C'est ce qui remplace, selon l'écran : une carte de tête centrée de 24 px de
/// padding, une carte à dégradé avec ombre portée, ou un en-tête de 128 lignes.
/// Toutes disparaissaient au premier geste de défilement, là où le lecteur a
/// justement besoin de savoir de quel mot on lui parle.
///
/// [title] est un widget et non une String : un lemme hébreu ou grec a sa
/// propre typographie ([StrongLemma]), un terme de dictionnaire est du texte
/// ordinaire.
class FicheHeader extends SliverPersistentHeaderDelegate {
  /// Le mot, déjà mis en forme par l'appelant.
  final Widget title;

  /// La provenance : « Westphal 1932 », « Notes BYM Lexique », « G746 · Grec ».
  final String badge;

  /// Petit texte gris avant le badge — un compteur, le plus souvent
  /// (« 705 § », « 56 occurrences »). Null quand il n'y a rien à signaler.
  final String? note;

  final PremiumPalette palette;

  /// Teinte du badge. Par défaut l'accent de la palette ; la fiche Strong y
  /// passe la couleur de la langue.
  final Color? badgeColor;

  const FicheHeader({
    required this.title,
    required this.badge,
    required this.palette,
    this.note,
    this.badgeColor,
  });

  @override
  double get minExtent => 54;

  @override
  double get maxExtent => 54;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final color = badgeColor ?? palette.primary;
    return Material(
      color: premiumBackground(context),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              // Le filet n'apparaît qu'une fois le texte passé dessous : en
              // haut de course, l'en-tête se fond dans la page. C'est aussi
              // lui qui porte la teinte de la famille, là où le Lexique BYM
              // posait un pavé à dégradé.
              color: color.withValues(
                alpha: shrinkOffset > 0 || overlaps ? 0.22 : 0,
              ),
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 10),
            if (note != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    note!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w700,
                      palette.textGrey,
                    ),
                  ),
                ),
              ),
            // Élastique lui aussi : un badge long (« Notes BYM Lexique »)
            // sur un téléphone de 320 px en gros texte se tronque avec des
            // points de suspension au lieu de déborder de la rangée.
            Flexible(child: FicheBadge(badge, color)),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant FicheHeader old) =>
      old.badge != badge ||
      old.note != note ||
      old.palette != palette ||
      old.badgeColor != badgeColor ||
      old.title != title;
}

/// La pastille de provenance d'une fiche.
class FicheBadge extends StatelessWidget {
  final String text;
  final Color color;

  const FicheBadge(this.text, this.color, {super.key});

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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
