import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Les icônes dessinées de la barre d'onglets.
///
/// Rien n'est emprunté à Material : chaque motif est un tracé peint dans un
/// carré de [HolyIcon.box] unités puis mis à l'échelle demandée, ce qui garde
/// le trait net à toutes les tailles — 24 px sur un téléphone étroit, 30 px
/// dans la barre du bas. La couleur se lit dans l'[IconTheme] ambiant : l'or
/// de l'accent pour l'onglet choisi, le gris discret au repos. L'icône n'a
/// donc pas à savoir si elle est sélectionnée, et [NavigationBar] comme
/// [NavigationRail] s'en occupent tous deux pareil.
///
/// Un motif juif par onglet — choisi sur planche, tous tracés du même trait
/// fin :
///
///  - **Accueil** : les deux tables de pierre apportées du Sinaï, sommet
///    arrondi, gravées de deux lignes, couronnées de l'étoile de David ;
///  - **Lecture** : le livre ouvert, pages creusées vers la reliure, coiffé
///    de la couronne de la Torah ;
///  - **Recherche** : la ménorah à sept branches — les bras partent du fût,
///    plongent et remontent porter la coupe au même niveau ;
///  - **Bibliothèque** : l'arche sainte, fronton arrondi, cadre et doubles
///    portes à poignées ;
///  - **Réglages** : l'étoile de David à double trait.
enum HolyGlyph {
  tables,
  livre,
  menorah,
  arche,
  etoile,
}

/// Une icône dessinée, API calquée sur celle d'[Icon] : taille et couleur
/// viennent de l'[IconTheme], aucun style n'est écrit en dur.
class HolyIcon extends StatelessWidget {
  const HolyIcon(this.glyph, {super.key, this.size});

  final HolyGlyph glyph;

  /// Côté du carré dessiné ; 24, comme [Icon].
  final double? size;

  /// Le côté du carré de référence dans lequel les motifs sont tracés.
  static const double box = 24;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    return CustomPaint(
      size: Size.square(side),
      painter: HolyIconPainter(
        glyph,
        theme.color ?? const Color(0xFF000000),
      ),
    );
  }
}

/// Le peintre des [HolyGlyph].
///
/// Public — et non privé — pour que les tests puissent lire la couleur qu'un
/// contexte a réellement donnée à l'icône : c'est là que se joue l'or de
/// l'onglet sélectionné.
class HolyIconPainter extends CustomPainter {
  const HolyIconPainter(this.glyph, this.color);

  final HolyGlyph glyph;
  final Color color;

  /// Trait des contours, à l'échelle du carré de 24.
  static const double _line = 1.6;

  /// Trait des détails — gravures, étoiles, portes. Plus fin, pour qu'ils
  /// ne bouchent pas l'intérieur des formes qu'ils décorent.
  static const double _fine = 1.15;

  Paint _paint(double width) => Paint()
    ..isAntiAlias = true
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / HolyIcon.box);
    final line = _paint(_line);
    final fine = _paint(_fine);
    final dot = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case HolyGlyph.tables:
        _tables(canvas, line, fine);
      case HolyGlyph.livre:
        _livre(canvas, line);
        _couronne(canvas, line);
      case HolyGlyph.menorah:
        _menorah(canvas, line, dot);
      case HolyGlyph.arche:
        _arche(canvas, line, fine);
      case HolyGlyph.etoile:
        _etoile(canvas, line, fine);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HolyIconPainter old) =>
      old.glyph != glyph || old.color != color;

  /// Les deux tables, un rien abaissées pour laisser respirer l'emblème qui
  /// les surmonte ; demi-cercle en tête, base franche, deux lignes gravées
  /// par table — assez espacées pour ne pas se souder au trait.
  void _tables(Canvas c, Paint line, Paint fine) {
    Path tablet(double left, double right) {
      final radius = (right - left) / 2;
      return Path()
        ..moveTo(left, 21.4)
        ..lineTo(left, 10.4)
        ..arcTo(
          Rect.fromCircle(center: Offset(left + radius, 10.4), radius: radius),
          math.pi,
          math.pi,
          false,
        )
        ..lineTo(right, 21.4)
        ..close();
    }

    c.drawPath(tablet(3.4, 11.4), line);
    c.drawPath(tablet(12.6, 20.6), line);
    for (final x in const [5.6, 14.8]) {
      c.drawLine(Offset(x, 14.4), Offset(x + 3.6, 14.4), fine);
      c.drawLine(Offset(x, 17.6), Offset(x + 3.6, 17.6), fine);
    }
    c.drawPath(_star(const Offset(12, 3), 2.8), line);
  }

  /// Le livre ouvert : deux pages qui se creusent vers la reliure, le tout
  /// fermé sur lui-même pour que la silhouette tienne à 24 px. C'est le seul
  /// motif dont le dessin vient d'avant la grande refonte — après trois essais
  /// de rouleau (échelle, pile, panneau) aucun ne se lisait à cette taille —
  /// mais il porte désormais la couronne : il n'est plus le seul de la barre
  /// sans filiation juive.
  void _livre(Canvas c, Paint line) {
    // Une page, la reliure à droite (x = 12) ; l'autre page est le miroir.
    Path page({required bool mirror}) {
      double x(double v) => mirror ? 24 - v : v;
      return Path()
        ..moveTo(x(12), 9.4)
        ..quadraticBezierTo(x(8.2), 6.6, x(3.4), 7)
        ..lineTo(x(3.4), 17)
        ..quadraticBezierTo(x(8.2), 16.6, x(12), 19.4)
        ..close();
    }

    c.drawPath(page(mirror: false), line);
    c.drawPath(page(mirror: true), line);
  }

  /// La couronne de la Torah : trois pointes, deux creux, base franche.
  void _couronne(Canvas c, Paint line) {
    c.drawPath(
      Path()
        ..moveTo(5.8, 4.6)
        ..lineTo(5.8, 2)
        ..lineTo(9.2, 3.6)
        ..lineTo(12, .8)
        ..lineTo(14.8, 3.6)
        ..lineTo(18.2, 2)
        ..lineTo(18.2, 4.6)
        ..close(),
      line,
    );
  }

  /// La ménorah : les bras partent du fût, plongent et remontent porter la
  /// coupe au même niveau — la fontaine, pas le parasol que donnent des
  /// arcs attachés la pointe en bas. Piédestal à deux degrés, lampe au
  /// sommet du fût.
  void _menorah(Canvas c, Paint line, Paint dot) {
    const top = 7.0; // niveau commun des six coupes
    for (final r in const [2.6, 5.0, 7.4]) {
      final rect = Rect.fromCircle(center: const Offset(12, top), radius: r);
      c.drawArc(rect, math.pi / 2, math.pi / 2, false, line); // bras gauche
      c.drawArc(rect, math.pi / 2, -math.pi / 2, false, line); // bras droit
    }
    c.drawLine(const Offset(12, 6.4), const Offset(12, 18.4), line);
    c.drawCircle(const Offset(12, 5.2), 1.1, dot);
    c.drawLine(const Offset(8.6, 18.4), const Offset(15.4, 18.4), line);
    c.drawLine(const Offset(7, 20.6), const Offset(17, 20.6), line);
    c.drawLine(const Offset(10.4, 18.4), const Offset(10.4, 20.6), line);
    c.drawLine(const Offset(13.6, 18.4), const Offset(13.6, 20.6), line);
  }

  /// L'arche sainte : caisse à fronton arrondi, cadre en dedans, doubles
  /// portes à poignées, socle plus large que l'armoire. Le rideau du premier
  /// jet faisait un visage sur la porte : le cadre dit l'objet sans prétendre
  /// au rideau.
  void _arche(Canvas c, Paint line, Paint fine) {
    Path arch(double left, double right, double base, double shoulder) =>
        Path()
          ..moveTo(left, base)
          ..lineTo(left, shoulder)
          ..quadraticBezierTo(12, 2.6, right, shoulder)
          ..lineTo(right, base)
          ..close();

    c.drawPath(arch(4.6, 19.4, 20.6, 9.6), line);
    c.drawPath(arch(6.6, 17.4, 20.6, 10.6), fine);
    c.drawLine(const Offset(12, 9.2), const Offset(12, 20.6), line);
    c.drawLine(const Offset(10.4, 14.4), const Offset(10.4, 16.4), fine);
    c.drawLine(const Offset(13.6, 14.4), const Offset(13.6, 16.4), fine);
    c.drawLine(const Offset(3.2, 20.6), const Offset(20.8, 20.6), line);
  }

  /// L'étoile de David, deux fois : le trait plein, puis son jumeau au
  /// centre, qui lui donne son épaisseur de sceau.
  void _etoile(Canvas c, Paint line, Paint fine) {
    c.drawPath(_star(const Offset(12, 12), 8.6), line);
    c.drawPath(_star(const Offset(12, 12), 4.4), fine);
  }

  /// L'étoile de David : deux triangles superposés, l'un à l'autre.
  static Path _star(Offset c, double r) {
    final horizontal = r * 0.866;
    return Path()
      ..moveTo(c.dx, c.dy - r)
      ..lineTo(c.dx + horizontal, c.dy + r / 2)
      ..lineTo(c.dx - horizontal, c.dy + r / 2)
      ..close()
      ..moveTo(c.dx, c.dy + r)
      ..lineTo(c.dx + horizontal, c.dy - r / 2)
      ..lineTo(c.dx - horizontal, c.dy - r / 2)
      ..close();
  }
}
