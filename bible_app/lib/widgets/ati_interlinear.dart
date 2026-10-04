import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'verse_tile.dart';

/// L'interlinéaire de l'ATI : un verset en colonnes de mots, de droite à gauche.
///
/// Chaque mot hébreu occupe une colonne qui empile, du haut vers le bas :
/// l'hébreu vocalisé (police Cardo, seul l'embarquée à le couvrir), la
/// translittération, la glose française, l'étiquette grammaticale courte
/// (`cg`) et le renvoi de glossaire (`n12`). Le flux part de la droite parce
/// que c'est le sens du texte source ; à l'intérieur de chaque colonne, les
/// champs latins sont relus de gauche à droite, isolés du sens de lecture.
///
/// **Piloté par la donnée, pas par un drapeau**, comme la ligne grecque de la
/// SEF (`verse.grec != null`) : le verset porte ses mots (`verse.mots`) ou il
/// ne les porte pas, et seul un fichier ATI en porte. La tuile n'a donc rien à
/// savoir de la version active, et une version reconstituée depuis un favori
/// — laquelle n'a pas de mots — retombe seule sur son texte joint.
///
/// Ce que ce widget ne fait pas encore :
///
/// - **pas de tap sur un mot.** Le lexique Strong est déjà cliquable sur la
///   LSGS par un autre chemin (`onStrongTap`) ; brancher l'ATI dessus et y
///   accrocher les renvois de glossaire viendront avec la résolution des
///   notes, quand `notes.json` sera lu.
/// - **pas d'alignement de texte.** `VerseTile.textAlign` règle la ligne
///   courante ; un flux de colonnes a un sens de lecture, pas une
///   justification — l'ignorer est plus honnête que le simuler.
class AtiInterlinear extends StatelessWidget {
  const AtiInterlinear({
    super.key,
    required this.words,
    required this.rhythm,
    required this.theme,
  });

  /// Les mots du verset, dans l'ordre du texte source.
  final List<AtiWord> words;

  /// Le rythme vertical du lecteur : les tailles ci-dessous en dérivent, pour
  /// que l'interlinéaire suive « Taille du texte » et « Aération » comme tout
  /// le reste de la tuile.
  final ReadingRhythm rhythm;

  /// Les couleurs du thème de lecture en cours.
  final BibleTheme theme;

  /// La seule famille embarquée qui couvre les points-voyelles hébraïques.
  static const String cardoFamily = 'Cardo';

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final base = rhythm.fontSize;
    final mainStyle = materialTheme.textTheme.bodyLarge?.copyWith(
          fontSize: base,
          height: rhythm.lineHeight,
        ) ??
        TextStyle(fontSize: base, height: rhythm.lineHeight);

    return Directionality(
      // Le texte source se lit de la droite : les colonnes partent de là, et
      // la première colonne (la première mot du verset) tombe à droite.
      textDirection: TextDirection.rtl,
      child: Wrap(
        spacing: 10 * rhythm.s,
        runSpacing: 6 * rhythm.s,
        // Colonne du dessus contre colonne du dessus : un mot sans étiquette
        // grammaticale finit plus bas sans décaler les lignes d'hébreu.
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (final word in words)
            _WordColumn(
              word: word,
              base: base,
              gap: rhythm.s,
              mainStyle: mainStyle,
              theme: theme,
            ),
        ],
      ),
    );
  }
}

/// Un mot, empilé sur lui-même et centré sur sa propre largeur : la colonne
/// prend la largeur de son niveau le plus large, qui n'est pas le même d'un
/// mot à l'autre (« En un commencement » face à « et »).
class _WordColumn extends StatelessWidget {
  const _WordColumn({
    required this.word,
    required this.base,
    required this.gap,
    required this.mainStyle,
    required this.theme,
  });

  final AtiWord word;
  final double base;
  final double gap;
  final TextStyle mainStyle;
  final BibleTheme theme;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    // L'hébreu domine : c'est lui qu'on lit d'abord dans un interlinéaire,
    // et c'est lui dont la largeur donne le rythme de la ligne. Centre et
    // droite-à-gauche explicites : une glose latine placée plus bas ne doit
    // pas réordonner les ponctuations massorétiques (le sillonnage, le
    // maqqef) autour d'elle.
    final hebrew = word.hebrew;
    if (hebrew != null) {
      children.add(
        Text(
          hebrew,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: mainStyle.copyWith(
            fontFamily: AtiInterlinear.cardoFamily,
            fontSize: base * 1.5,
            height: 1.45,
          ),
        ),
      );
    }

    final translit = word.translit;
    if (translit != null) {
      children.add(
        Text(
          translit,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: mainStyle.copyWith(
            fontSize: base * .68,
            color: theme.noteColor,
            height: 1.35,
          ),
        ),
      );
    }

    // Glose lisible : les marqueurs `*` / `-` ne s'affichent pas, sous peine
    // de redessiner ici ce que la ligne jointe retire déjà.
    final gloss = word.readableGloss;
    if (gloss != null) {
      children.add(
        Text(
          gloss,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: mainStyle.copyWith(
            fontSize: base * .95,
            height: 1.4,
          ),
        ),
      );
    }

    final grammar = word.grammar;
    if (grammar != null) {
      children.add(
        Text(
          grammar,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: mainStyle.copyWith(
            fontSize: base * .62,
            color: theme.verseNumColor,
            height: 1.3,
          ),
        ),
      );
    }

    // Le renvoi de glossaire, tel que la source l'imprime : une référence, pas
    // un bouton — il n'y a rien encore à ouvrir tant que `notes.json` n'est
    // pas lu. Un bouton mort serait pire qu'un renvoi muet.
    final note = word.note;
    if (note != null) {
      children.add(
        Text(
          note,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          style: mainStyle.copyWith(
            fontSize: base * .55,
            color: theme.verseNumColor,
            height: 1.3,
          ),
        ),
      );
    }

    // Un mot sans aucun champ : rien à dessiner, jamais un rectangle vide.
    if (children.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}
