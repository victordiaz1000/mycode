import 'dart:ui' show Size;

/// Le châssis de navigation retenu pour une taille d'écran : où vivent les
/// cinq destinations, et sous quelle forme.
///
/// Distinct de la **classe d'appareil** ([AppBreakpoints.isTablet]) à dessein.
/// Un téléphone couché reçoit un rail — il a la largeur pour, et la hauteur
/// lui manque — mais il reste un téléphone : ni grille d'accueil, ni
/// master/detail, ni panneau d'étude épinglé. Confondre les deux, c'était le
/// bug d'origine.
enum AppChassis {
  /// Barre du bas : téléphone debout.
  bottomBar,

  /// Rail minimal de 52 px, sans libellés ni emblème : téléphone couché.
  ///
  /// Le rail *étendu* de 190 px que recevaient ces écrans avant que les
  /// paliers passent sur le côté court était inutilisable — 190 px de
  /// libellés dans 390 px de hauteur. Celui-ci rend la hauteur au texte tout
  /// en gardant les destinations visibles d'un coup d'œil.
  miniRail,

  /// Rail compact, icônes et libellés courts : tablette sous [AppBreakpoints.expanded].
  rail,

  /// Rail étendu : tablette à partir de [AppBreakpoints.expanded].
  extendedRail,
}

// Paliers responsive uniques de l'application (maquettes tablette/desktop).
//
// Source unique : ne plus comparer `width >= 600` / `>= 840` en dur dans les
// écrans — passer par ici pour que les seuils bougent en un seul endroit.
//
// Deux familles de décisions, et c'est tout l'objet de ce fichier :
//
//  * le **châssis** ([AppChassis], via [AppBreakpoints.chassisFor]) répond à
//    « rail ou barre du bas, et de quelle largeur ». Il tient compte de
//    l'orientation : un téléphone debout a la hauteur pour une barre, couché
//    il a la largeur pour un rail minimal.
//  * la **classe d'appareil** ([AppBreakpoints.isTablet] et ses dérivés)
//    répond à « cet écran mérite-t-il une mise en page de tablette » :
//    master/detail, grilles, panneaux épinglés. Mesurée sur le **côté court**,
//    donc stable en rotation. Mesurée sur la largeur, un iPhone 14 en paysage
//    fait 844 px — au-dessus de [AppBreakpoints.expanded] — et recevait
//    grilles et master/detail comme un petit desktop.
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
  /// navigation — c'est [chassisFor] qui en décide : un téléphone couché a un
  /// rail sans être pour autant une tablette.
  static bool isTablet(Size size) => size.shortestSide >= tablet;

  /// Le châssis de navigation pour cette taille d'écran.
  ///
  /// Une tablette a toujours un rail, debout comme couchée. Un téléphone a
  /// une barre du bas debout, et un rail minimal couché : en paysage la
  /// hauteur est la ressource rare, et une barre du bas y coûte ~56 px sur
  /// 390, là où un rail de 52 px ne coûte que de la largeur, dont il reste
  /// 800 px.
  static AppChassis chassisFor(Size size) {
    if (isTablet(size)) {
      return size.width >= expanded ? AppChassis.extendedRail : AppChassis.rail;
    }
    return size.width > size.height
        ? AppChassis.miniRail
        : AppChassis.bottomBar;
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
