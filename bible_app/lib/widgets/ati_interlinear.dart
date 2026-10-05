import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'verse_tile.dart';

/// L'interlinéaire de l'ATI : un verset en colonnes de mots, de droite à
/// gauche, aligné en lignes comme la source l'imprime.
///
/// La maquette suit l'écran « Interlinéaire » de Biblia Universalis (capture
/// du 04/10/2026, `Downloads/capture`, Genèse 1:3-4) : chaque mot est une
/// cellule empilée sur **cinq lignes de hauteur fixe** — numéro Strong avec
/// son renvoi de glossaire, translittération, hébreu vocalisé, glose
/// française, étiquette grammaticale — séparée de sa voisine par un filet.
///
/// **Les hauteurs sont constantes d'une cellule à l'autre** : c'est ce qui
/// aligne les lignes d'un bout à l'autre du verset, une colonne ne pouvant
/// pas être plus haute que sa voisine. Un champ absent **réserve** sa ligne
/// au lieu de la supprimer — sinon un mot à marqueur (glose `*`, 7 % du
/// corpus) ferait remonter les suivants et le verset se désalignerait sur ses
/// propres mots. La glose est bornée à une ligne : une glose qui en ferait
/// deux ferait sauter l'alignement de tout ce qui suit.
///
/// Couleurs calquées sur la source : le rouge de la glose, le vert de
/// l'étiquette, le bleu du Strong — chacune dans sa variante selon le thème de
/// lecture en cours ([BibleTheme.glossColor] et les voisines), la source
/// n'ayant qu'un fond à éclairer.
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

  /// L'interligne appliqué à **chacune** des cinq lignes : la hauteur d'une
  /// ligne est `corps × interligne`, donc identique dans toutes les cellules
  /// — la condition de l'alignement. Changer ce nombre change l'air du bloc,
  /// jamais sa trame.
  static const double _interligne = 1.5;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final base = rhythm.fontSize;
    final mainStyle =
        materialTheme.textTheme.bodyLarge?.copyWith(
          fontSize: base,
          height: rhythm.lineHeight,
        ) ??
        TextStyle(fontSize: base, height: rhythm.lineHeight);

    final lignes = _Lignes(
      strong: base * .62 * _interligne,
      translit: base * .68 * _interligne,
      hebreu: base * 1.5 * _interligne,
      glose: base * .95 * _interligne,
      grammaire: base * .62 * _interligne,
    );

    return Directionality(
      // Le texte source se lit de la droite : les colonnes partent de là, et
      // la première colonne (le premier mot du verset) tombe à droite.
      textDirection: TextDirection.rtl,
      child: Wrap(
        // Les filets des cellules voisines doivent se toucher : ni espacement
        // horizontal ni vertical entre elles, sinon le tableau se lit en
        // colonnes isolées. C'est la gouttière du numéro, dehors, qui porte
        // le blanc à droite.
        spacing: 0,
        runSpacing: 0,
        // Haut de cellule contre haut de cellule : le retour à la ligne d'un
        // verset long garde la même trame que sa première ligne.
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (final word in words)
            _WordCell(
              word: word,
              mainStyle: mainStyle,
              lignes: lignes,
              gap: rhythm.s,
              theme: theme,
            ),
        ],
      ),
    );
  }
}

/// Les cinq hauteurs de ligne, une par niveau : un simple paquet de `double`,
/// produit de `rhythm.fontSize` par le widget, pour que les cinq circulent
/// ensemble d'une cellule à l'autre.
class _Lignes {
  _Lignes({
    required this.strong,
    required this.translit,
    required this.hebreu,
    required this.glose,
    required this.grammaire,
  });

  final double strong;
  final double translit;
  final double hebreu;
  final double glose;
  final double grammaire;
}

/// Un mot, empilé sur lui-même et centré sur sa propre largeur : la cellule
/// prend la largeur de son niveau le plus large, qui n'est pas la même d'un
/// mot à l'autre (« En un commencement » face à « et »).
class _WordCell extends StatelessWidget {
  const _WordCell({
    required this.word,
    required this.mainStyle,
    required this.lignes,
    required this.gap,
    required this.theme,
  });

  final AtiWord word;
  final TextStyle mainStyle;
  final _Lignes lignes;
  final double gap;
  final BibleTheme theme;

  /// Une ligne de la cellule : hauteur donnée, contenu posé dedans — ou rien,
  /// mais **la hauteur est quand même posée**, sinon les lignes suivantes
  /// remonteraient dans cette cellule-là seulement.
  ///
  /// Pas d'`Align` : la boîte a exactement la hauteur du texte qu'elle
  /// contient (`corps × interligne` des deux côtés), et un `Align` non borné
  /// s'alignerait sur la largeur maximale de la contrainte — chaque cellule
  /// prendrait toute la ligne et les colonnes s'empileraient.
  Widget _ligne(double hauteur, Widget? contenu) =>
      SizedBox(height: hauteur, child: contenu);

  /// Le haut de la colonne : `7225` puis, quand le mot en porte une, la
  /// flèche et l'identifiant de glossaire (`▶n12`) — comme la source les
  /// imprime sur la même ligne. Le `H` du Strong saute : la source
  /// n'imprime que le nombre, et la lettre ne dit rien au lecteur.
  ///
  /// En LTR explicite : le bloc pousse dans un flux de droite à gauche, et
  /// sans isolation on lirait « n12 ▶ 7225 ».
  Widget _haut() {
    final brut = word.strong;
    final numero = brut?.replaceFirst(RegExp(r'^[A-Za-z]+'), '');
    final note = word.note;
    if (numero == null && note == null) return const SizedBox.shrink();

    final corps = (mainStyle.fontSize ?? 16) * .62;
    TextStyle style() => mainStyle.copyWith(
      fontSize: corps,
      height: AtiInterlinear._interligne,
      color: theme.strongColor,
    );

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (numero != null)
            Text(numero, textAlign: TextAlign.center, style: style()),
          if (note != null) ...[
            if (numero != null) SizedBox(width: 2 * gap),
            Icon(
              Icons.play_arrow_rounded,
              size: corps,
              color: theme.strongColor,
            ),
            Text(note, textAlign: TextAlign.center, style: style()),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final glose = word.readableGloss;

    // Un mot sans aucun champ : rien à dessiner, jamais un rectangle vide ni
    // un filet isolé.
    if (word.strong == null &&
        word.translit == null &&
        word.hebrew == null &&
        glose == null &&
        word.grammar == null &&
        word.note == null) {
      return const SizedBox.shrink();
    }

    final base = mainStyle.fontSize ?? 16;

    TextStyle ligne(double corps, Color couleur) => mainStyle.copyWith(
      fontSize: corps,
      height: AtiInterlinear._interligne,
      color: couleur,
    );

    final cell = Container(
      padding: EdgeInsets.symmetric(horizontal: 5 * gap, vertical: 2 * gap),
      // Filet en tête de cellule : dans un flux de droite à gauche, le « début »
      // est à droite, donc le trait tombe entre chaque mot et celui qui le
      // précède — un tableau, pas des colonnes qui se touchent.
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: theme.columnRuleColor, width: .8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ligne(lignes.strong, _haut()),
          _ligne(
            lignes.translit,
            word.translit == null
                ? null
                : Text(
                    word.translit!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Gris de lecture, pas l'accent : la translittération
                    // se lit après l'hébreu, elle ne doit pas rivaliser.
                    style: ligne(
                      base * .68,
                      theme.textColor.withValues(alpha: .78),
                    ),
                  ),
          ),
          _ligne(
            lignes.hebreu,
            word.hebrew == null
                ? null
                : Text(
                    word.hebrew!,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: ligne(
                      base * 1.5,
                      theme.textColor,
                    ).copyWith(fontFamily: AtiInterlinear.cardoFamily),
                  ),
          ),
          _ligne(
            lignes.glose,
            glose == null
                ? null
                : Text(
                    glose,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ligne(base * .95, theme.glossColor),
                  ),
          ),
          _ligne(
            lignes.grammaire,
            word.grammar == null
                ? null
                : Text(
                    word.grammar!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ligne(base * .62, theme.grammarColor),
                  ),
          ),
        ],
      ),
    );
    return cell;
  }
}
