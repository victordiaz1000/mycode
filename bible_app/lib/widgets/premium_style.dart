import 'package:flutter/material.dart';

import 'bible_theme_scope.dart';

/// Langage visuel commun des écrans « premium » (maquettes `interfaces/`) :
/// fond crème, cartes blanches à ombre douce, dégradés d'accent, typographie
/// Plus Jakarta Sans. Tout dérive du thème biblique actif pour que les écrans
/// restent en phase avec la lecture et l'Accueil.

/// Famille typographique de l'interface, telle que déclarée dans `pubspec.yaml`.
///
/// C'est une famille embarquée, nommée directement : l'application ne dépend
/// plus de `google_fonts`. Ce paquet cherchait `PlusJakartaSans-Regular.ttf`
/// (sa convention de nommage), fichier que le dossier n'a jamais contenu — le
/// régulier y est la police variable `PlusJakartaSans.ttf`. Résultat, avec
/// `allowRuntimeFetching = false` le poids 400 ne se chargeait jamais et
/// retombait sur la police système. Nommer la famille supprime d'un coup ce
/// trou, le chargement asynchrone et tout chemin réseau.
const String kUiFontFamily = 'Plus Jakarta Sans';

/// Fond crème des écrans premium (maquette `ecran_accueil.dart`).
Color premiumBackground(BuildContext context) {
  final bt = BibleThemeScope.of(context);
  return bt.usesLightText
      ? Color.lerp(bt.backgroundTone, Colors.black, .55)!
      : Color.lerp(bt.backgroundTone, Colors.white, .72)!;
}

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
  final Color surface;
  final Color surfaceAlt;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color onPrimary;
  final Color greek;
  final Color hebrew;
  final Color favorite;

  const PremiumPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.textDark,
    required this.textGrey,
    required this.heroGradient,
    required this.surface,
    required this.surfaceAlt,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.onPrimary,
    required this.greek,
    required this.hebrew,
    required this.favorite,
  });
}

PremiumPalette premiumPalette(BuildContext context) {
  final bt = BibleThemeScope.of(context);
  final accent = bt.accentColor;
  final dark = bt.usesLightText;
  final surface = dark
      ? Color.lerp(bt.backgroundTone, Colors.black, .42)!
      : Color.lerp(bt.backgroundTone, Colors.white, .58)!;
  final surfaceAlt = dark
      ? Color.lerp(bt.backgroundTone, Colors.black, .30)!
      : Color.lerp(bt.backgroundTone, Colors.white, .45)!;
  return PremiumPalette(
    primary: accent,
    primaryDark: Color.lerp(accent, Colors.black, 0.35)!,
    primarySoft: accent.withValues(alpha: 0.14),
    textDark: bt.titleColor,
    textGrey: bt.textColor.withValues(alpha: 0.62),
    surface: surface,
    surfaceAlt: surfaceAlt,
    onSurface: dark ? Colors.white : bt.textColor,
    onSurfaceMuted: dark ? Colors.white70 : bt.textColor.withValues(alpha: .62),
    onPrimary: accent.computeLuminance() > .45 ? Colors.black87 : Colors.white,
    greek: Color.lerp(bt.accentColor, bt.linkColor, .55)!,
    hebrew: Color.lerp(bt.accentColor, bt.verseNumColor, .55)!,
    favorite: Color.lerp(bt.accentColor, bt.highlightRef, .45)!,
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

/// Liseré d'une carte premium : le bord **net** qui la détache de la page.
///
/// Les cartes prennent `p.surface` et la page [premiumBackground] : deux lerps
/// du même ton de fond (58 % et 72 % de blanc). Sur les palettes claires et
/// chaudes l'écart tombe à presque rien — rapport de contraste 1,015 sur Brume,
/// 1,020 sur Oliveraie, 1,024 sur Papier clair, 1,047 sur Cacao, 1,084 sur
/// Sinaï. Une ombre douce ne délimite alors plus la carte : elle en fait un bord
/// flou, la carte se lit comme une tache. D'où ce liseré, tiré de la couleur du
/// texte pour rester neutre quelle que soit la palette (un liseré d'accent
/// tournerait au cerne coloré sur les thèmes chauds).
///
/// [opacity] .16 est la valeur historique des tuiles d'action ; les grandes
/// surfaces demandent un peu plus.
Color premiumCardBorder(BuildContext context, {double opacity = .16}) =>
    premiumPalette(context).textGrey.withValues(alpha: opacity);

List<BoxShadow> premiumShadow(
  Color color, {
  double opacity = 0.08,
  double blur = 18,
  Offset offset = const Offset(0, 8),
}) => [
  BoxShadow(
    color: color.withValues(alpha: opacity),
    blurRadius: blur,
    offset: offset,
  ),
];

/// La surface habillée d'une carte : un voile vertical, le liseré **net** de
/// [premiumCardBorder] et deux ombres — l'ambiante large qui décolle la carte,
/// la serrée qui la pose sur la page.
///
/// C'est le registre « premium affirmé » des écrans d'étude du verset et de
/// recherche : la même syntaxe pour tous les panneaux, sur toutes les
/// palettes. [depth] pousse les deux ombres pour les grandes surfaces (une
/// carte de verset) et les laisse au calme pour les rangées serrées.
BoxDecoration premiumSurface(
  BuildContext context, {
  double radius = 16,
  double depth = 1,
}) {
  final p = premiumPalette(context);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [p.surface, p.surfaceAlt],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: premiumCardBorder(context, opacity: .18)),
    boxShadow: [
      ...premiumShadow(
        p.primaryDark,
        opacity: .08 * depth,
        blur: 20,
        offset: const Offset(0, 10),
      ),
      ...premiumShadow(
        p.primaryDark,
        opacity: .10 * depth,
        blur: 3,
        offset: const Offset(0, 2),
      ),
    ],
  );
}

TextStyle premiumText(
  BuildContext context,
  double size,
  FontWeight weight,
  Color color, {
  double? spacing,
  double? height,
  FontStyle? italic,
}) => TextStyle(
  fontFamily: kUiFontFamily,
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
