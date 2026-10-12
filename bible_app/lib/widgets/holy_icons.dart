import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icônes de la barre d'onglets — v3, nouvelles bases.
///
///  - **Accueil** : maison-temple, toit à fronton, porte en arche ;
///  - **Lecture** : rouleau d'Écriture horizontal, deux montants à boutons,
///    deux lignes de texte ;
///  - **Recherche** : loupe simple, manche diagonal ;
///  - **Bibliothèque** : téléchargement — flèche dans un bac ;
///  - **Réglages** : vrai engrenage à huit dents, moyeu circulaire.
enum HolyGlyph {
  maison,
  rouleau,
  loupe,
  telechargement,
  engrenage,
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
  static const double _line = 1.75;

  /// Trait des détails intérieurs.
  static const double _detail = 1.4;

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
    final detail = _paint(_detail);
    final dot = Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.fill;

    switch (glyph) {
      case HolyGlyph.maison:
        _maison(canvas, line, detail);
      case HolyGlyph.rouleau:
        _rouleau(canvas, line, detail, dot);
      case HolyGlyph.loupe:
        _loupe(canvas, line);
      case HolyGlyph.telechargement:
        _telechargement(canvas, line);
      case HolyGlyph.engrenage:
        _engrenage(canvas, line, detail);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HolyIconPainter old) =>
      old.glyph != glyph || old.color != color;

  /// Maison-temple : corps rectangulaire, toit à fronton débordant, porte
  /// en arche. Recentré après retrait de la croix pour garder le poids.
  void _maison(Canvas c, Paint line, Paint detail) {
    // Toit : 4,10 -> 12,4.5 -> 20,10, ouvert.
    c.drawPath(
      Path()
        ..moveTo(4.0, 10.0)
        ..lineTo(12, 4.5)
        ..lineTo(20.0, 10.0),
      line,
    );
    // Corps : 6,10 -> 6,20.5 -> 18,20.5 -> 18,10.
    c.drawPath(
      Path()
        ..moveTo(6.0, 10.0)
        ..lineTo(6.0, 20.5)
        ..lineTo(18.0, 20.5)
        ..lineTo(18.0, 10.0),
      line,
    );
    // Porte en arche : 10.2-13.8, base 20.5, épaules 16.5.
    final door = Path()
      ..moveTo(10.2, 20.5)
      ..lineTo(10.2, 16.5)
      ..arcTo(
        Rect.fromCircle(center: const Offset(12, 16.5), radius: 1.8),
        math.pi,
        math.pi,
        false,
      )
      ..lineTo(13.8, 20.5);
    c.drawPath(door, detail);
  }

  /// Rouleau d'Écriture : feuille tendue entre deux montants à boutons
  /// pleins, deux lignes de texte. Aucun livre, aucune couronne : base neuve.
  void _rouleau(Canvas c, Paint line, Paint detail, Paint dot) {
    // Feuille : haut 9, bas 15, de 5.5 à 18.5.
    c.drawLine(const Offset(5.5, 9.0), const Offset(18.5, 9.0), line);
    c.drawLine(const Offset(5.5, 15.0), const Offset(18.5, 15.0), line);
    // Montants : verticaux 7-17.
    c.drawLine(const Offset(5.5, 7.0), const Offset(5.5, 17.0), line);
    c.drawLine(const Offset(18.5, 7.0), const Offset(18.5, 17.0), line);
    // Boutons pleins, r 1.1.
    for (final p in const [
      Offset(5.5, 6.2),
      Offset(5.5, 17.8),
      Offset(18.5, 6.2),
      Offset(18.5, 17.8),
    ]) {
      c.drawCircle(p, 1.1, dot);
    }
    // Texte : deux lignes 8-16.
    c.drawLine(const Offset(8.2, 11.2), const Offset(15.8, 11.2), detail);
    c.drawLine(const Offset(8.2, 13.4), const Offset(15.8, 13.4), detail);
  }

  /// Loupe simple : lentille généreuse, manche détaché par un jour d'1 px
  /// pour un rendu net à 24 px.
  void _loupe(Canvas c, Paint line) {
    c.drawCircle(const Offset(10.2, 10.2), 6.8, line);
    c.drawLine(const Offset(15.4, 15.4), const Offset(20.6, 20.6), line);
  }

  /// Téléchargement : flèche plongeant dans un bac. Remplace l'étagère,
  /// sur demande — la Bibliothèque gère les ouvrages à télécharger.
  void _telechargement(Canvas c, Paint line) {
    // Flèche : fût 12,3.5-14, tête en V 8.4,10.4 -> 12,14.2 -> 15.6,10.4.
    c.drawLine(const Offset(12, 3.5), const Offset(12, 14.0), line);
    c.drawPath(
      Path()
        ..moveTo(8.4, 10.4)
        ..lineTo(12, 14.2)
        ..lineTo(15.6, 10.4),
      line,
    );
    // Bac : 5,5,14.5 -> 5,5,20 -> 18,5,20 -> 18,5,14.5.
    c.drawPath(
      Path()
        ..moveTo(5.5, 14.5)
        ..lineTo(5.5, 20.0)
        ..lineTo(18.5, 20.0)
        ..lineTo(18.5, 14.5),
      line,
    );
  }

  /// Vrai engrenage de réglages : corps r 5.2, huit dents jusqu'à 7.6,
  /// moyeu circulaire r 2.3.
  void _engrenage(Canvas c, Paint line, Paint detail) {
    const center = Offset(12, 12);
    c.drawCircle(center, 5.2, line);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final dx = math.cos(a);
      final dy = math.sin(a);
      c.drawLine(
        Offset(12 + dx * 5.2, 12 + dy * 5.2),
        Offset(12 + dx * 7.6, 12 + dy * 7.6),
        line,
      );
    }
    c.drawCircle(center, 2.3, detail);
  }
}
