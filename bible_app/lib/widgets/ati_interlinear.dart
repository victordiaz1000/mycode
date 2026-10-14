import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'verse_tile.dart';

/// L'interlinéaire de Biblia : un verset en colonnes de mots, aligné en lignes
/// comme la source l'imprime.
///
/// Deux grilles, une seule trame. L'ATI (hébreu) empile **cinq lignes** de
/// droite à gauche ; le NTI (grec) en empile **six** de gauche à droite. La
/// trame ne change pas : cellule sur lignes de hauteur fixe, filet entre les
/// voisines, gouttière du numéro dehors. Ce qui change, c'est le sens et le
/// nombre de lignes.
///
/// La maquette de l'ATI suit l'écran « Interlinéaire » de Biblia Universalis
/// (capture du 04/10/2026, `Downloads/capture`, Genèse 1:3-4) ; celle du NTI,
/// l'écran du même logiciel sur Matthieu 1:1-3, six rangées étiquetées.
///
/// **Les hauteurs sont constantes d'une cellule à l'autre** : c'est ce qui
/// aligne les lignes d'un bout à l'autre du verset, une colonne ne pouvant
/// pas être plus haute que sa voisine. Un champ absent **réserve** sa ligne
/// au lieu de la supprimer — sinon un mot à marqueur (glose `*`, 7 % du corpus
/// hébreu) ferait remonter les suivants et le verset se désalignerait sur ses
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
/// ne les porte pas, et seul un interlinéaire en porte. La tuile n'a donc rien
/// à savoir de la version active, et une version reconstituée depuis un favori
/// — laquelle n'a pas de mots — retombe seule sur son texte joint. Le sens de
/// lecture se décide de la même façon : un mot sans `modern` n'est pas un mot
/// du NTI ([AtiWord.greek]).
///
/// Ce que ce widget ne fait pas encore :
///
/// - **pas l'analyse développée (`ca`)** : la source la montre en `▶Hi` à
///   côté de l'étiquette, mais la nôtre est une phrase (« Verbe qal parfait
///   (qatal)· 3ᵉ masculin singulier », « Nature : Nom · Déclinaison :
///   Nominatif · … ») qui exploserait la largeur des cellules et, avec elle,
///   l'alignement. Elle appartient à la fiche — celle qu'ouvre le tap sur le
///   mot.
/// - **pas d'alignement de texte.** `VerseTile.textAlign` règle la ligne
///   courante ; un flux de colonnes a un sens de lecture, pas une
///   justification — l'ignorer est plus honnête que le simuler.
class AtiInterlinear extends StatelessWidget {
  const AtiInterlinear({
    super.key,
    required this.words,
    required this.rhythm,
    required this.theme,
    this.onWordTap,
  });

  /// Les mots du verset, dans l'ordre du texte source.
  final List<AtiWord> words;

  /// Le rythme vertical du lecteur : les tailles ci-dessous en dérivent, pour
  /// que l'interlinéaire suive « Taille du texte » et « Aération » comme tout
  /// le reste de la tuile.
  final ReadingRhythm rhythm;

  /// Les couleurs du thème de lecture en cours.
  final BibleTheme theme;

  /// Le tap sur un mot ouvre sa fiche. `null` : les cellules ne sont pas
  /// cliquables du tout — pas de zone morte à appui pour rien, et pas de
  /// feuille à ouvrir pour un mot qu'on n'a pas demandé.
  final void Function(AtiWord word)? onWordTap;

  /// La seule famille embarquée qui couvre les points-voyelles hébraïques —
  /// et le grec polytonique du NTI, dont elle dessine les accents et les
  /// esprits. Ce n'est pas un choix de police mais une contrainte de
  /// couverture : l'hébreu n'a nulle part ailleurs à se poser.
  static const String cardoFamily = 'Cardo';

  /// L'interligne appliqué à **chacune** des lignes, hébreues comme grecques :
  /// la hauteur d'une ligne est `corps × interligne`, donc identique dans
  /// toutes les cellules — la condition de l'alignement. Changer ce nombre
  /// change l'air du bloc, jamais sa trame.
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

    // Le sens et le nombre de lignes se lisent dans les mots, pas dans la
    // version : un mot sans `modern` n'est pas un mot du NTI.
    final grec = words.any((word) => word.greek);

    return Directionality(
      // Le texte source impose son sens : l'hébreu part de la droite, la
      // première colonne tombe donc à droite ; le grec de la gauche.
      textDirection: grec ? TextDirection.ltr : TextDirection.rtl,
      child: Wrap(
        // Des cartes posées côte à côte côté grec, pas un tableau : un blanc
        // les sépare, et chacune prend sa hauteur naturelle. L'hébreu garde
        // ses filets jointifs — ni espacement horizontal ni vertical, sinon
        // le tableau se lirait en colonnes isolées.
        spacing: grec ? 3 * rhythm.s : 0.0,
        runSpacing: grec ? 3 * rhythm.s : 0.0,
        // Haut de cellule contre haut de cellule : le retour à la ligne d'un
        // verset long garde la même trame que sa première ligne.
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (final word in words)
            grec
                ? _CelluleGrecque(
                    word: word,
                    mainStyle: mainStyle,
                    gap: rhythm.s,
                    theme: theme,
                    onTap: onWordTap == null ? null : () => onWordTap!(word),
                  )
                : _WordCell(
                    word: word,
                    mainStyle: mainStyle,
                    lignes: _Lignes(
                      strong: base * .62 * _interligne,
                      translit: base * .68 * _interligne,
                      hebreu: base * 1.5 * _interligne,
                      glose: base * .95 * _interligne,
                      grammaire: base * .62 * _interligne,
                    ),
                    gap: rhythm.s,
                    theme: theme,
                    onTap: onWordTap == null ? null : () => onWordTap!(word),
                  ),
        ],
      ),
    );
  }
}

/// Les cinq hauteurs de ligne de l'ATI, une par niveau : un simple paquet de
/// `double`, produit de `rhythm.fontSize` par le widget, pour que les cinq
/// circulent ensemble d'une cellule à l'autre.
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

/// Une ligne de cellule : hauteur donnée, contenu posé dedans — ou rien, mais
/// **la hauteur est quand même posée**, sinon les lignes suivantes
/// remonteraient dans cette cellule-là seulement (c'est ce qui tient la
/// grille hébraïque alignée d'un mot à l'autre).
///
/// Pas d'`Align` : la boîte a exactement la hauteur du texte qu'elle
/// contient (`corps × interligne` des deux côtés), et un `Align` non borné
/// s'alignerait sur la largeur maximale de la contrainte — chaque cellule
/// prendrait toute la ligne et les colonnes s'empileraient.
Widget _ligne(double hauteur, Widget? contenu) =>
    SizedBox(height: hauteur, child: contenu);

/// Le haut de la colonne : `7225` puis, quand le mot en porte une, la
/// flèche et l'identifiant de glossaire (`▶n12`) — comme la source les
/// imprime sur la même ligne. Le préfixe du Strong saute (`H`, `G`) : la
/// source n'imprime que le nombre, et la lettre ne dit rien au lecteur.
///
/// En LTR explicite : le bloc pousse dans un flux de droite à gauche, et
/// sans isolation on lirait « n12 ▶ 7225 ».
Widget _hautDuMot(AtiWord word, TextStyle mainStyle, BibleTheme theme, double gap) {
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

/// La glose française, et sa variante en italique quand il y en a une.
///
/// Le « / » de la source sert de séparateur ; il ne sert à rien de le garder
/// entre deux `TextSpan`, l'italique suffit à dire lequel des deux est la
/// variante. La variante n'existe que sur le NTI — l'hébreu passe donc ici
/// sans rien changer à son rendu, un `Text` pour un `Text`.
///
/// Bornée à une ligne comme la ligne qu'elle tient : une glose de deux lignes
/// ferait sauter l'alignement de tout le verset.
Widget _gloseFrancaise(
  String glose,
  String? variante,
  TextStyle style,
) {
  if (variante == null) {
    return Text(
      glose,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  return Text.rich(
    TextSpan(
      text: glose,
      style: style,
      children: [
        TextSpan(
          text: ' / $variante',
          style: style.copyWith(fontStyle: FontStyle.italic),
        ),
      ],
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
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
    this.onTap,
  });

  final AtiWord word;
  final TextStyle mainStyle;
  final _Lignes lignes;
  final double gap;
  final BibleTheme theme;

  /// Ouvre la fiche du mot — `null` quand personne ne l'attend.
  final VoidCallback? onTap;

  /// Le haut de la colonne : numéro Strong et renvoi de glossaire. Définition
  /// partagée avec la cellule grecque, qui n'en a que le premier — voir
  /// [_hautDuMot].
  Widget _haut() => _hautDuMot(word, mainStyle, theme, gap);

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
                : _gloseFrancaise(
                    glose,
                    word.readableVariant,
                    ligne(base * .95, theme.glossColor),
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

    if (onTap == null) return cell;
    // Cellule cliquable sur toute sa hauteur : c'est le **mot** qu'on demande
    // à voir, pas l'un de ses champs. L'appui ne déforme rien au rendu — sans
    // tap, pas d'encre, la colonne reste telle qu'imprimée.
    return InkWell(onTap: onTap, child: cell);
  }
}

/// Un mot grec en carte aérée : le mot en gras, son numéro Strong en
/// pastille, sa glose quand il en porte une — et rien d'autre.
///
/// Même trame que la cellule hébraïque, en plus léger : là où l'hébreu empile
/// cinq lignes de hauteur fixe (l'alignement d'un bout à l'autre du verset),
/// le grec pose une carte par mot, à hauteur naturelle. Lemme, Koinè et
/// analyse vivent dans la fiche qu'ouvre le tap, pas dans la grille : c'est
/// ce qui rend la lecture respirable, SES surtout, dont trois rangées sur six
/// resteraient sinon vides.
class _CelluleGrecque extends StatelessWidget {
  const _CelluleGrecque({
    required this.word,
    required this.mainStyle,
    required this.gap,
    required this.theme,
    this.onTap,
  });

  final AtiWord word;
  final TextStyle mainStyle;
  final double gap;
  final BibleTheme theme;

  /// Ouvre la fiche du mot — `null` quand personne ne l'attend.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final glose = word.readableGloss;
    final variante = word.readableVariant;

    // Un mot sans rien à montrer : jamais une carte vide.
    if (word.modern == null &&
        word.strong == null &&
        glose == null &&
        variante == null) {
      return const SizedBox.shrink();
    }

    final base = mainStyle.fontSize ?? 16;

    // Cardo dessine le grec polytonique — accents, esprits, sous-respirations.
    TextStyle ligne(double corps, Color couleur) => mainStyle.copyWith(
      fontSize: corps,
      height: AtiInterlinear._interligne,
      color: couleur,
      fontFamily: AtiInterlinear.cardoFamily,
    );

    // Le préfixe du Strong saute (`G976` → `976`) : la source n'imprime que
    // le nombre, et la lettre ne dit rien au lecteur. Le champ brut garde son
    // préfixe, c'est la clé du lexique au tap.
    final numero =
        word.strong?.replaceFirst(RegExp(r'^[A-Za-z]+'), '');

    final carte = Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * gap, vertical: 2 * gap),
      decoration: BoxDecoration(
        border: Border.all(color: theme.columnRuleColor, width: .8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (word.modern != null)
            Text(
              word.modern!,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // La seule ligne en gras : c'est le mot, le reste n'en est que
              // la description.
              style: ligne(base * 1.1, theme.textColor)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          if (numero != null)
            Container(
              margin: EdgeInsets.only(top: gap),
              padding: EdgeInsets.symmetric(
                horizontal: 2 * gap,
                vertical: gap / 2,
              ),
              decoration: BoxDecoration(
                color: theme.strongColor.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                numero,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: ligne(base * .62, theme.strongColor),
              ),
            ),
          if (glose != null)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: _gloseFrancaise(
                glose,
                variante,
                ligne(base * .85, theme.glossColor),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return carte;
    // Même pacte que la cellule hébraïque : tout le mot est cliquable, et
    // l'appui ne laisse aucune trace.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: carte,
    );
  }
}
