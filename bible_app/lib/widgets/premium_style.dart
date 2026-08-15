import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'bible_theme_scope.dart';

/// Langage visuel commun des écrans « premium » (maquettes `interfaces/`) :
/// fond crème, cartes blanches à ombre douce, dégradés d'accent, typographie
/// Plus Jakarta Sans. Tout dérive du thème biblique actif pour que les écrans
/// restent en phase avec la lecture et l'Accueil.

/// Fond crème des écrans premium (maquette `ecran_accueil.dart`).
const Color kPremiumBackground = Color(0xFFFAF9F6);

/// Couleur du cœur des favoris (maquette `ecran_favoris.dart`).
const Color kPremiumCoeur = Color(0xFFC0564C);

/// Palette dérivée du thème biblique actif.
class PremiumPalette {
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color textDark;
  final Color textGrey;
  final LinearGradient heroGradient;

  const PremiumPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.textDark,
    required this.textGrey,
    required this.heroGradient,
  });
}

PremiumPalette premiumPalette(BuildContext context) {
  final bt = BibleThemeScope.of(context);
  final accent = bt.accentColor;
  return PremiumPalette(
    primary: accent,
    primaryDark: Color.lerp(accent, Colors.black, 0.35)!,
    primarySoft: accent.withValues(alpha: 0.14),
    textDark: bt.titleColor,
    textGrey: bt.textColor.withValues(alpha: 0.62),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(accent, Colors.white, 0.26)!,
        Color.lerp(accent, Colors.black, 0.30)!,
      ],
    ),
  );
}

List<BoxShadow> premiumShadow(
  Color color, {
  double opacity = 0.08,
  double blur = 18,
  Offset offset = const Offset(0, 8),
}) =>
    [
      BoxShadow(
        color: color.withValues(alpha: opacity),
        blurRadius: blur,
        offset: offset,
      ),
    ];

TextStyle premiumText(
  BuildContext context,
  double size,
  FontWeight weight,
  Color color, {
  double? spacing,
  double? height,
  FontStyle? italic,
}) =>
    GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: height,
      fontStyle: italic,
    );

/// Puce de section « premium » : petit label sur fond teinté d'accent, comme
/// les en-têtes de sections de l'Accueil.
Widget premiumBadge(BuildContext context, String label) {
  final p = premiumPalette(context);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: p.primarySoft,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: premiumText(context, 11, FontWeight.w800, p.primary, spacing: 1.2),
    ),
  );
}