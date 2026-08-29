import 'package:flutter/material.dart';

/// Borne la police système et applique la réduction propre aux écrans étroits.
///
/// Cette règle vit ici, et non en ligne dans le `builder` de `MaterialApp`, pour
/// une raison de test : les balayages de mise en page doivent éprouver la
/// *vraie* règle. Recopiée dans les tests, elle aurait dérivé du jour où le
/// plafond bouge, et le balayage se serait mis à signaler des débordements que
/// l'application ne connaît pas — ou à taire les siens.
class ResponsiveTextScaling extends StatelessWidget {
  const ResponsiveTextScaling({super.key, required this.child});

  final Widget child;

  /// Plafond de la police système. Au-delà, la mise en page ne tient plus : on
  /// laisse l'agrandissement monter jusque-là, pas plus. Les tailles de lecture
  /// propres à l'application (`ReadingTextSize`) restent, elles, sans plafond.
  static const double maxScaleFactor = 1.18;

  /// Réduction par palier de largeur, pour que les mêmes maquettes tiennent d'un
  /// 320 px à une tablette.
  ///
  /// Elle ne doit exister qu'ICI. Elle a vécu un temps en double — une échelle
  /// `ReadingTextSize.responsiveFontSize` *et* ce facteur — mêmes seuils, mêmes
  /// valeurs, toutes deux appliquées au corps du verset : les deux se
  /// composaient en une coupe de 19 % là où 10 % était voulu.
  static double deviceFactor(double width) => width < 360
      ? .90
      : width < 400
      ? .95
      : width < 480
      ? .98
      : 1.0;

  /// L'échelle effective pour un [media] donné : la police système bornée, puis
  /// pondérée par la largeur.
  ///
  /// Le plancher suit l'échelle demandée quand elle est inférieure à 1 : un
  /// lecteur qui *réduit* sa police système doit être suivi, pas ramené à 1.
  static TextScaler resolve(MediaQueryData media) {
    final requested = media.textScaler.scale(1);
    final bounded = media.textScaler.clamp(
      minScaleFactor: requested < 1 ? requested : 1,
      maxScaleFactor: maxScaleFactor,
    );
    return TextScaler.linear(bounded.scale(1) * deviceFactor(media.size.width));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: resolve(media)),
      child: child,
    );
  }
}
