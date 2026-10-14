import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'verse_tile.dart';

/// L'interlinéaire de Biblia : un verset en cartes de mots, une par mot,
/// dans le sens de sa langue — l'hébreu part de la droite, le grec de la
/// gauche.
///
/// Chaque carte dit l'essentiel : le mot en gras, son numéro Strong en
/// pastille, puis sa translittération (hébreu seul) et sa glose quand il en
/// porte. Le reste — lemme, Koinè, étiquette, analyse développée — vit dans
/// la fiche qu'ouvre le tap, pas dans la grille : c'est ce qui rend la
/// lecture respirable au lieu d'un tableau de six rangées.
///
/// La maquette de l'ATI suit l'écran « Interlinéaire » de Biblia Universalis
/// (capture du 04/10/2026, `Downloads/capture`, Genèse 1:3-4) ; celle du NTI,
/// l'écran du même logiciel sur Matthieu 1:1-3 — allégées toutes deux en
/// cartes, sans la colonne d'étiquettes de la source.
///
/// La glose est bornée à une ligne : une glose qui en ferait deux casserait
/// la régularité des cartes.
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
        // Des cartes posées côte à côte, pas un tableau : un blanc les
        // sépare, et chacune prend sa hauteur naturelle.
        spacing: 3 * rhythm.s,
        runSpacing: 3 * rhythm.s,
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
                    gap: rhythm.s,
                    theme: theme,
                    onTap: onWordTap == null ? null : () => onWordTap!(word),
                  ),
        ],
      ),
    );
  }
}

/// Le haut de la pastille : `7225` puis, quand le mot en porte une, la
/// flèche et l'identifiant de glossaire (`▶n12`) — comme la source les
/// imprime sur la même ligne. Le préfixe du Strong saute (`H`, `G`) : la
/// source n'imprime que le nombre, et la lettre ne dit rien au lecteur.
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

/// Un mot hébreu en carte aérée : le mot en gras, son numéro Strong en
/// pastille, sa translittération puis sa glose — et rien d'autre.
///
/// Même pacte que la carte grecque : l'étiquette grammaticale et l'analyse
/// développée vivent dans la fiche qu'ouvre le tap, pas dans la grille. La
/// translittération, elle, reste : sans elle, qui ne lit pas l'alphabet
/// hébreu n'aurait que des carrés vaguement familiers.
class _WordCell extends StatelessWidget {
  const _WordCell({
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

    // Un mot sans rien à montrer : jamais une carte vide.
    if (word.hebrew == null &&
        word.translit == null &&
        word.strong == null &&
        word.note == null &&
        glose == null) {
      return const SizedBox.shrink();
    }

    final base = mainStyle.fontSize ?? 16;

    TextStyle ligne(double corps, Color couleur) => mainStyle.copyWith(
      fontSize: corps,
      height: AtiInterlinear._interligne,
      color: couleur,
    );

    // Numéro Strong et renvoi de glossaire (`▶n12`) sur la même pastille :
    // [_hautDuMot] ne dessine rien quand le mot n'en porte ni l'un ni l'autre.
    final haut = _hautDuMot(word, mainStyle, theme, gap);

    final carte = Container(
      padding: EdgeInsets.symmetric(horizontal: 4 * gap, vertical: 2 * gap),
      decoration: BoxDecoration(
        border: Border.all(color: theme.columnRuleColor, width: .8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (word.hebrew != null)
            Text(
              word.hebrew!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ligne(
                base * 1.4,
                theme.textColor,
              ).copyWith(
                fontFamily: AtiInterlinear.cardoFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (word.strong != null || word.note != null)
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
              child: haut,
            ),
          if (word.translit != null)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: Text(
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
          if (glose != null)
            Padding(
              padding: EdgeInsets.only(top: gap),
              child: _gloseFrancaise(
                glose,
                word.readableVariant,
                ligne(base * .85, theme.glossColor),
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return carte;
    // Carte cliquable sur toute sa hauteur : c'est le **mot** qu'on demande
    // à voir, pas l'un de ses champs. L'appui ne déforme rien au rendu — sans
    // tap, pas d'encre, la carte reste telle qu'imprimée.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: carte,
    );
  }
}

/// Un mot grec en carte aérée : le mot en gras, son numéro Strong en
/// pastille, sa glose quand il en porte une — et rien d'autre.
///
/// Même trame que la cellule hébraïque : deux cartes à hauteur naturelle.
/// Lemme, Koinè et analyse vivent dans la fiche qu'ouvre le tap, pas dans
/// la grille : c'est ce qui rend la lecture respirable, SES surtout, dont
/// trois rangées sur six resteraient sinon vides.
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
