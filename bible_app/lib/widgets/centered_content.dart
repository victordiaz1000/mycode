import 'package:flutter/material.dart';

import '../utils/breakpoints.dart';

/// Plafonne et centre une page sur tablette et au-delà.
///
/// C'est la pièce qui manquait : [AppBreakpoints.contentMaxWidth] était écrit
/// et personne ne l'appelait, donc le contenu prenait toute la largeur contre
/// le rail — des lignes de 120 caractères et plus à 1280 px.
///
/// `LayoutBuilder` + `Padding` plutôt que `Center` + `ConstrainedBox`, le même
/// idiome que la colonne de lecture : l'enfant garde des contraintes serrées,
/// et une `ListView` conserve son défilement paresseux. Sous le palier
/// tablette — téléphone, dans les deux orientations — l'enfant passe tel quel :
/// aucune régression possible sur petit écran.
class CenteredContent extends StatelessWidget {
  final Widget child;

  /// Plafond imposé, pour une page qui en veut un autre que celui du palier.
  final double? maxWidth;

  const CenteredContent({super.key, required this.child, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final max =
        maxWidth ?? AppBreakpoints.contentMaxWidth(MediaQuery.sizeOf(context));
    if (max == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || constraints.maxWidth <= max) {
          return child;
        }
        final pad = (constraints.maxWidth - max) / 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: child,
        );
      },
    );
  }
}
