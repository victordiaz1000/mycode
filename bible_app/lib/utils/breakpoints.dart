import 'dart:ui' show Size;

/// Où vit la navigation, et sous quelle forme.
///
/// Volontairement **indépendant** de la classe d'appareil
/// ([AppBreakpoints.isTablet]) : c'est toute la leçon de ce fichier. Dès qu'un
/// écran est assez large, le rail est préférable à la barre du bas, téléphone
/// couché compris — c'est le comportement d'origine de l'app, et il convient.
/// Ce qui ne convenait pas, c'est que ce même seuil de largeur décidait *aussi*
/// de la mise en page du contenu, et donnait grilles et master/detail à un
/// iPhone en paysage.
enum AppChassis {
  /// Barre du bas : sous [AppBreakpoints.tablet] de large.
  bottomBar,

  /// Rail compact, icônes et libellés : à partir de [AppBreakpoints.tablet].
  rail,

  /// Rail étendu : à partir de [AppBreakpoints.expanded].
  extendedRail,
}

// Paliers responsive uniques de l'application (maquettes tablette/desktop).
//
// Source unique : ne plus comparer `width >= 600` / `>= 840` en dur dans les
// écrans — passer par ici pour que les seuils bougent en un seul endroit.
//
// Deux familles de décisions, séparées à dessein — les confondre était le bug
// d'origine, et il faut résister à l'envie de les refusionner :
//
//  * le **châssis** ([AppChassis], via [AppBreakpoints.chassisFor]) répond à
//    « rail ou barre du bas ». Il se décide sur la **largeur réelle**, comme
//    depuis toujours : un écran large mérite un rail, même s'il appartient à
//    un téléphone couché.
//  * la **classe d'appareil** ([AppBreakpoints.isTablet] et ses dérivés)
//    répond à « cet écran mérite-t-il une mise en page de tablette » —
//    master/detail, grilles, panneau d'étude épinglé, plafond de contenu.
//    Mesurée sur le **côté court**, donc stable en rotation. Mesurée sur la
//    largeur, un iPhone 14 en paysage fait 844 px — au-dessus de [expanded] —
//    et recevait l'accueil en grille deux colonnes et le master/detail comme
//    un petit desktop.
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

  /// La classe d'appareil : mise en page de tablette à partir d'ici.
  ///
  /// Sur le côté court, donc stable en rotation. Ne dit **pas** où vit la
  /// navigation — c'est [chassisFor] qui en décide, sur la largeur : un
  /// téléphone couché garde son rail sans devenir une tablette pour autant.
  static bool isTablet(Size size) => size.shortestSide >= tablet;

  /// Le châssis de navigation, sur la largeur réelle — le comportement
  /// d'origine de l'app, qu'il n'y avait aucune raison de changer.
  static AppChassis chassisFor(Size size) {
    if (size.width >= expanded) return AppChassis.extendedRail;
    if (size.width >= tablet) return AppChassis.rail;
    return AppChassis.bottomBar;
  }

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
