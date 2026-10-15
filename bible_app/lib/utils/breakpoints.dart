import 'dart:ui' show Size;

// Paliers responsive uniques de l'application (maquettes tablette/desktop).
//
// Source unique : ne plus comparer `width >= 600` / `>= 840` en dur dans les
// écrans — passer par ici pour que les seuils bougent en un seul endroit.
//
// Deux familles de décisions, et c'est tout l'objet de ce fichier :
//
//  * le **châssis** (rail latéral ou barre du bas) se décide sur le **côté
//    court** de l'écran. C'est une propriété de l'appareil, pas de son
//    orientation : un téléphone couché reste un téléphone. Mesuré sur la
//    largeur, un iPhone 14 en paysage fait 844 px — au-dessus de [expanded] —
//    et recevait le rail *étendu* de 190 px avec ses libellés dans 390 px de
//    haut, plus l'accueil en grille deux colonnes.
//  * le **contenu** (master/detail, grille, panneau d'étude) se décide sur la
//    **largeur réelle**, mais seulement à l'intérieur d'un châssis tablette.
//    D'où le `isTablet(size) &&` qui ouvre [isExpanded], [isDesktop] et [isXl] :
//    sans lui, les trois reviendraient vraies sur un téléphone en paysage.
abstract final class AppBreakpoints {
  /// Tablette portrait : le shell passe en rail latéral.
  static const double tablet = 600;

  /// Tablette paysage / petit desktop : rail étendu + master-detail.
  static const double expanded = 840;

  /// Desktop : panneau d'étude latéral au lieu des bottom-sheets.
  ///
  /// 1040 et non 1200 : à 1200, une fenêtre de bureau ouverte sur la moitié
  /// d'un écran 13 pouces (~1100 px) retombait en bottom-sheet alors qu'elle
  /// a la place du panneau.
  static const double desktop = 1040;

  /// Très grand écran : une troisième colonne (sommaire du livre) rejoint la
  /// lecture et le panneau d'étude, au lieu de laisser le plafond de contenu
  /// border deux bandes de crème.
  static const double xl = 1600;

  /// Largeur max du contenu centré sur tablette portrait.
  static const double maxNarrow = 720;

  /// Largeur max du contenu centré sur paysage/desktop.
  static const double maxWide = 1120;

  /// Le châssis : rail latéral à partir d'ici, barre du bas en dessous.
  ///
  /// Sur le côté court, donc stable en rotation — c'est ce qui garde la barre
  /// du bas sur un téléphone en paysage et le rail sur un iPad debout.
  static bool isTablet(Size size) => size.shortestSide >= tablet;

  /// Master/detail et grilles : la largeur décide, le châssis autorise.
  static bool isExpanded(Size size) => isTablet(size) && size.width >= expanded;

  /// Panneaux latéraux épinglés au lieu des modales.
  static bool isDesktop(Size size) => isTablet(size) && size.width >= desktop;

  /// Trois zones : sommaire + lecture + étude.
  static bool isXl(Size size) => isTablet(size) && size.width >= xl;

  /// Plafond de la colonne de contenu pour une taille d'écran donnée.
  /// Régime phone (côté court < 600) : pas de plafond — la page prend toute
  /// la largeur, comme avant, y compris en paysage.
  /// Tablette sous 840 : 720. Au-delà : 1120.
  static double? contentMaxWidth(Size size) {
    if (!isTablet(size)) return null;
    if (size.width < expanded) return maxNarrow;
    return maxWide;
  }

  /// Largeur du panneau latéral épinglé (fiche Strong, feuille d'étude).
  ///
  /// Une proportion bornée plutôt que les 372 px en dur d'avant : à 1040 le
  /// panneau prend 320 px et laisse 700 px au texte ; à 1920 il monte à 420
  /// sans jamais manger la colonne de lecture.
  static double sidePanelWidth(double width) =>
      (width * 0.30).clamp(320.0, 420.0);
}
