import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'verse_tile.dart';

/// L'interlinéaire de Biblia : un verset en colonnes de mots, aligné en lignes
/// comme la source l'imprime.
///
/// Deux grilles, une seule trame. L'ATI (hébreu) empile **cinq lignes** de
/// droite à gauche ; le NTI (grec) en empile **six** de gauche à droite, et
/// leur donne en plus une colonne d'étiquettes — Moderne, Lemme, Koinè, Strong,
/// Français, Analyse — que la source imprime elle aussi, un tableau par verset.
/// La trame ne change pas : cellule sur lignes de hauteur fixe, filet entre les
/// voisines, gouttière du numéro dehors. Ce qui change, c'est le sens, le
/// nombre de lignes et le fait que le grec a deux lignes de texte (imprimé et
/// lemme) là où l'hébreu n'en a qu'une.
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
      // première colonne tombe donc à droite ; le grec de la gauche, et ses
      // étiquettes avec lui.
      textDirection: grec ? TextDirection.ltr : TextDirection.rtl,
      child: Wrap(
        // Les filets des cellules voisines doivent se toucher : ni espacement
        // horizontal ni vertical entre elles, sinon le tableau se lit en
        // colonnes isolées. C'est la gouttière du numéro, dehors, qui porte
        // le blanc.
        spacing: 0,
        runSpacing: 0,
        // Haut de cellule contre haut de cellule : le retour à la ligne d'un
        // verset long garde la même trame que sa première ligne.
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          // La colonne d'étiquettes n'a qu'une place : en tête du verset,
          // comme la source la pose. Elle ne revient pas sur les lignes
          // suivantes d'un verset qui déborde — Biblia non plus.
          if (grec) _Etiquettes(lignes: _lignesGrec(base), mainStyle: mainStyle, gap: rhythm.s, theme: theme),
          for (final word in words)
            grec
                ? _CelluleGrecque(
                    word: word,
                    mainStyle: mainStyle,
                    lignes: _lignesGrec(base),
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

  /// Les six hauteurs du NTI, toutes `corps × interligne` comme chez l'ATI.
  ///
  /// L'écart entre elles est plus serré qu'à l'hébreu : le grec n'a pas de
  /// points à laisser respirer, et ses deux lignes de texte se partagent la
  /// place que l'hébreu donne à une seule. La ligne « Moderne » reste la plus
  /// haute et la seule en gras — c'est elle qui se lit.
  static _LignesGrec _lignesGrec(double base) => _LignesGrec(
    moderne: base * 1.2 * _interligne,
    lemme: base * .8 * _interligne,
    koine: base * .7 * _interligne,
    strong: base * .62 * _interligne,
    glose: base * .95 * _interligne,
    grammaire: base * .62 * _interligne,
  );
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

/// Les six hauteurs du NTI, dans l'ordre où la source imprime ses rangées.
class _LignesGrec {
  _LignesGrec({
    required this.moderne,
    required this.lemme,
    required this.koine,
    required this.strong,
    required this.glose,
    required this.grammaire,
  });

  final double moderne;
  final double lemme;
  final double koine;
  final double strong;
  final double glose;
  final double grammaire;
}

/// Une ligne de cellule : hauteur donnée, contenu posé dedans — ou rien, mais
/// **la hauteur est quand même posée**, sinon les lignes suivantes
/// remonteraient dans cette cellule-là seulement.
///
/// Pas d'`Align` : la boîte a exactement la hauteur du texte qu'elle
/// contient (`corps × interligne` des deux côtés), et un `Align` non borné
/// s'alignerait sur la largeur maximale de la contrainte — chaque cellule
/// prendrait toute la ligne et les colonnes s'empileraient. (La colonne
/// d'étiquettes, elle, en a besoin pour descendre son libellé au milieu de
/// sa ligne : elle le borne de deux côtés, `widthFactor` et la hauteur déjà
/// donnée, pour qu'il n'en profite pas.)
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

/// La colonne d'étiquettes du NTI : les six noms de rangée, posés à gauche
/// des mots.
///
/// La source les imprime elle-même — un `<table>` d'étiquettes par verset,
/// avant les mots — et sans elles la grille grecque perd le nom de deux de
/// ses lignes : « Lemme » et « Koinè » ne se distinguent que par là, et
/// « Koinè » moins encore, qui n'est le texte qu'écrit sans accents.
///
/// Les hauteurs sont celles du mot, ligne pour ligne : c'est ce qui les
/// aligne sur ce qu'elles nomment. Le libellé, lui, est mis au milieu de sa
/// ligne — plus petit que le texte qu'il nomme, il ne toucherait ni le haut
/// ni le bas autrement.
class _Etiquettes extends StatelessWidget {
  const _Etiquettes({
    required this.lignes,
    required this.mainStyle,
    required this.gap,
    required this.theme,
  });

  final _LignesGrec lignes;
  final TextStyle mainStyle;
  final double gap;
  final BibleTheme theme;

  /// Les six noms, dans l'ordre de la source — un nom par rangée, du haut en
  /// bas, comme Biblia les imprime.
  static const List<String> _noms = [
    'Moderne',
    'Lemme',
    'Koinè',
    'Strong',
    'Français',
    'Analyse',
  ];

  @override
  Widget build(BuildContext context) {
    final hauteurs = [
      lignes.moderne,
      lignes.lemme,
      lignes.koine,
      lignes.strong,
      lignes.glose,
      lignes.grammaire,
    ];
    // Gris de lecture, comme la source les met en `color:grey` : ce sont des
    // étiquettes, elles ne se lisent pas avant le mot.
    final style = mainStyle.copyWith(
      fontSize: (mainStyle.fontSize ?? 16) * .62,
      height: AtiInterlinear._interligne,
      color: theme.textColor.withValues(alpha: .6),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5 * gap, vertical: 2 * gap),
      // Le même filet que les cellules : la source encadre aussi son tableau
      // d'étiquettes (`frame="lhs"`), et sans trait la colonne se
      // détacherait du tableau au lieu d'en être le bord.
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: theme.columnRuleColor, width: .8),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        // Contre le bord du verset : les six noms partent tous du même x.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _noms.length; i++)
            _ligne(
              hauteurs[i],
              Align(
                // Borné en largeur : sans `widthFactor`, l'`Align` prendrait
                // toute la largeur de la contrainte et la colonne pousserait
                // le premier mot hors de sa ligne.
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text(
                  _noms[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
        ],
      ),
    );
  }
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

/// Un mot grec, empilé sur lui-même — la cellule du NTI, six lignes.
///
/// Même trame que la cellule hébraïque, dont elle ne diffère que par ses
/// lignes : deux de texte au lieu d'une (la forme imprimée, en gras, puis le
/// lemme), une troisième qui n'est que la même forme sans accents, et
/// l'analyse à la place de l'étiquette seule.
///
/// Les deux lignes de texte se justifient : la source imprime en « Moderne »
/// le mot **tel qu'il est écrit dans le texte**, avec l'accent de contexte
/// qu'il y prend (`κλητὸς`), et en « Lemme » la forme du dictionnaire
/// (`κλητός`). Sans les deux, un lecteur ne saurait pas lequel des deux il
/// a sous les yeux — et la rangée « Koinè », qui n'est que le même mot privé
/// de ses accents, ne l'aurait pas aidé.
class _CelluleGrecque extends StatelessWidget {
  const _CelluleGrecque({
    required this.word,
    required this.mainStyle,
    required this.lignes,
    required this.gap,
    required this.theme,
    this.onTap,
  });

  final AtiWord word;
  final TextStyle mainStyle;
  final _LignesGrec lignes;
  final double gap;
  final BibleTheme theme;

  /// Ouvre la fiche du mot — `null` quand personne ne l'attend.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final glose = word.readableGloss;
    final variante = word.readableVariant;

    // Un mot sans aucun champ : rien à dessiner, jamais un rectangle vide ni
    // un filet isolé. Un mot du NTI en a toujours trois — ses lignes de
    // texte — donc cette condition ne le concerne que si la source l'a
    // entièrement laissé de côté.
    if (!word.greek &&
        word.strong == null &&
        glose == null &&
        variante == null &&
        word.grammar == null) {
      return const SizedBox.shrink();
    }

    final base = mainStyle.fontSize ?? 16;

    // Cardo dessine le grec polytonique — accents, esprits, sous-respirations —
    // et c'est la même famille que l'hébreu d'à côté : les deux grilles ne
    // changent pas de fonte pour changer de script.
    TextStyle ligne(double corps, Color couleur) => mainStyle.copyWith(
      fontSize: corps,
      height: AtiInterlinear._interligne,
      color: couleur,
      fontFamily: AtiInterlinear.cardoFamily,
    );

    final cell = Container(
      padding: EdgeInsets.symmetric(horizontal: 5 * gap, vertical: 2 * gap),
      // Filet en tête de cellule : le « début » est à gauche dans un flux de
      // gauche à droite, donc le trait tombe entre chaque mot et celui qui le
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
          _ligne(
            lignes.moderne,
            word.modern == null
                ? null
                : Text(
                    word.modern!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // La seule ligne en gras : c'est le mot, les autres
                    // n'en sont que la description.
                    style: ligne(base * 1.2, theme.textColor)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
          ),
          _ligne(
            lignes.lemme,
            word.lemma == null
                ? null
                : Text(
                    word.lemma!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ligne(base * .8, theme.textColor),
                  ),
          ),
          _ligne(
            lignes.koine,
            word.koine == null
                ? null
                : Text(
                    word.koine!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // Gris de lecture, comme la translittération chez
                    // l'ATI : la graphie de base se lit après le mot.
                    style: ligne(
                      base * .7,
                      theme.textColor.withValues(alpha: .78),
                    ),
                  ),
          ),
          _ligne(lignes.strong, _hautDuMot(word, mainStyle, theme, gap)),
          _ligne(
            lignes.glose,
            glose == null
                ? null
                : _gloseFrancaise(
                    glose,
                    variante,
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
    // Même pacte que la cellule hébraïque : tout le mot est cliquable, et
    // l'appui ne laisse aucune trace.
    return InkWell(onTap: onTap, child: cell);
  }
}
