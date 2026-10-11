import 'package:flutter/material.dart';

import '../data/ati_notes.dart';
import '../data/strong_lexicon.dart';
import '../data/theme_catalog.dart';
import '../models/ati.dart';
import 'ati_interlinear.dart' show AtiInterlinear;
import 'bible_theme_scope.dart';
import 'premium_style.dart';

/// Ouvre la fiche d'un mot de l'interlinéaire — le tap sur une cellule.
///
/// Ce qu'elle montre : **tous les champs que le mot porte**. L'ATI en donne
/// sept (`s`, `t`, `h`, `d`, `f`, `g`, `a`, `n` — l'analyse venant après
/// l'étiquette) ; le NTI en remplace trois par ses propres lignes (`m` le mot
/// imprimé, `l` le lemme, `k` la Koinè) et en ajoute une (`f2`, la variante de
/// glose). Aucun n'est jamais inventé : un champ absent ne fait pas de ligne.
/// Ce que la cellule ne pouvait pas montrer y trouve sa place — l'analyse
/// développée, qui exploserait l'alignement, et le découpage morphologique.
///
/// Deux sortes de lien, comme dans la source : le numéro Strong ouvre la
/// fiche du lexique (la même que la LSGS, servie par le même lexique), le
/// renvoi de glossaire ouvre la page de `notes.json` qui le résout. Les deux
/// ferment la feuille d'abord : pousser une route derrière une feuille
/// modale, c'est la cacher.
Future<void> showAtiWordSheet(
  BuildContext context, {
  required String reference,
  required AtiWord word,
  Future<void> Function(String strong)? onStrongTap,
  Future<void> Function(String noteId)? onNoteTap,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: premiumBackground(context),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
    child: Container(
      decoration: premiumSurface(context, radius: 24, depth: 1.3),
      child: _AtiWordSheet(
        reference: reference,
        word: word,
        onStrongTap: onStrongTap,
        onNoteTap: onNoteTap,
      ),
    ),
  ),
);

class _AtiWordSheet extends StatefulWidget {
  const _AtiWordSheet({
    required this.reference,
    required this.word,
    required this.onStrongTap,
    required this.onNoteTap,
  });

  final String reference;
  final AtiWord word;
  final Future<void> Function(String strong)? onStrongTap;
  final Future<void> Function(String noteId)? onNoteTap;

  @override
  State<_AtiWordSheet> createState() => _AtiWordSheetState();
}

class _AtiWordSheetState extends State<_AtiWordSheet> {
  /// Le renvoi résolu — `null` tant que le glossaire n'a pas répondu, ou
  /// quand l'identifiant n'y a pas de page.
  AtiNote? _note;

  /// Le code existe-t-il dans le lexique ? La fiche Strong n'ouvre que ce
  /// qu'elle peut servir : un code sans entrée reste un chiffre à lire.
  bool _strongKnown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var strongKnown = false;
    final strong = widget.word.strong;
    if (strong != null) {
      strongKnown = await StrongLexicon.instance.contains(strong);
    }
    final noteId = widget.word.note;
    final note = noteId == null ? null : await AtiNotes.instance.lookup(noteId);
    if (!mounted) return;
    setState(() {
      _strongKnown = strongKnown;
      _note = note;
    });
  }

  /// Ouvrir la fiche Strong : la feuille se ferme d'abord, la route part
  /// ensuite du lecteur — derrière une feuille modale, une poussée ne se
  /// verrait pas.
  void _openStrong(String strong) {
    Navigator.of(context).pop();
    widget.onStrongTap?.call(strong);
  }

  void _openNote(String noteId) {
    Navigator.of(context).pop();
    widget.onNoteTap?.call(noteId);
  }

  @override
  Widget build(BuildContext context) {
    final bt = BibleThemeScope.of(context);
    final p = premiumPalette(context);
    final word = widget.word;
    final glose = word.readableGloss;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, p),
          const SizedBox(height: 16),
          // Les deux lignes grecques que la cellule empilait sans les nommer.
          // La grille n'a que six étiquettes, dont deux se ressemblent (« Lemme »
          // et « Koinè ») ; la fiche les appelle, dans l'ordre de la source.
          if (word.lemma != null) ...[
            const _Label('Lemme'),
            const SizedBox(height: 4),
            Text(
              word.lemma!,
              textDirection: TextDirection.ltr,
              style: _source(context, p, 17, FontWeight.w600),
            ),
            const SizedBox(height: 14),
          ],
          if (word.koine != null) ...[
            const _Label('Koinè'),
            const SizedBox(height: 4),
            Text(
              word.koine!,
              textDirection: TextDirection.ltr,
              style: _source(
                context,
                p,
                17,
                FontWeight.w500,
                couleur: p.textGrey,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (glose != null) ...[
            const _Label('Glose'),
            const SizedBox(height: 4),
            _glose(context, bt),
            const SizedBox(height: 14),
          ],
          if (word.grammar != null) ...[
            const _Label('Étiquette'),
            const SizedBox(height: 4),
            Text(
              word.grammar!,
              textDirection: TextDirection.ltr,
              style: premiumText(context, 15, FontWeight.w600, bt.grammarColor),
            ),
            const SizedBox(height: 14),
          ],
          if (word.analysis != null) ...[
            const _Label('Analyse'),
            const SizedBox(height: 4),
            Text(
              word.analysis!,
              textDirection: TextDirection.ltr,
              style: premiumText(context, 15, FontWeight.w500, p.textDark),
            ),
            const SizedBox(height: 14),
          ],
          if (word.split != null) ...[
            const _Label('Découpage'),
            const SizedBox(height: 4),
            Text(
              word.split!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: premiumText(
                context,
                17,
                FontWeight.w600,
                p.textDark,
              ).copyWith(fontFamily: AtiInterlinear.cardoFamily),
            ),
            const SizedBox(height: 14),
          ],
          if (word.strong != null) _strongRow(context, bt),
          if (word.note != null) _noteRow(context, p),
          if (word.strong == null && word.note == null)
            // Rien à relier : la fiche dit simplement d'où vient la page.
            Text(
              'Champs portés par la source — aucun lien.',
              style: premiumText(context, 12, FontWeight.w500, p.textGrey),
            ),
        ],
      ),
    );
  }

  /// L'en-tête : la référence en petit, le mot source en grand — hébreu pointé
  /// ou grec polytonique, chacun dans le sens où il se lit —, et chez l'ATI la
  /// translittération dessous. La même ordonnance que la carte de la fiche
  /// Strong, où l'on reconnaît le mot avant de le lire.
  Widget _header(BuildContext context, PremiumPalette p) {
    final word = widget.word;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: premiumSurface(context, radius: 18, depth: .9),
      child: Column(
        children: [
          Text(
            widget.reference,
            style: premiumText(context, 12, FontWeight.w600, p.textGrey),
          ),
          const SizedBox(height: 6),
          if (word.hebrew != null)
            Text(
              word.hebrew!,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                30,
                FontWeight.w600,
                p.textDark,
              ).copyWith(fontFamily: AtiInterlinear.cardoFamily, height: 1.45),
            )
          else if (word.modern != null)
            // Le NTI n'a pas de translittération à afficher sous le mot — le
            // lemme a sa propre ligne, plus bas, avec son étiquette.
            Text(
              word.modern!,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                30,
                FontWeight.w600,
                p.textDark,
              ).copyWith(fontFamily: AtiInterlinear.cardoFamily, height: 1.45),
            ),
          if (word.translit != null)
            Text(
              word.translit!,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                15,
                FontWeight.w500,
                p.textGrey,
                italic: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  /// Une ligne de la fiche qui porte du texte source : Cardo, la seule
  /// famille qui dessine l'hébreu pointé et le grec polytonique.
  TextStyle _source(
    BuildContext context,
    PremiumPalette p,
    double taille,
    FontWeight graisse, {
    Color? couleur,
  }) =>
      premiumText(context, taille, graisse, couleur ?? p.textDark)
          .copyWith(fontFamily: AtiInterlinear.cardoFamily);

  /// La glose, et sa variante en italique quand il y en a une — le même
  /// partage que la cellule de la grille, en plus grand. La variante n'est
  /// pas un second mot : c'est la même proposition relue autrement (« de
  /// genèse / de généalogie »), et l'italique dit laquelle des deux la source
  /// propose en second.
  Widget _glose(BuildContext context, BibleTheme bt) {
    final glose = widget.word.readableGloss!;
    final variante = widget.word.readableVariant;
    final style = premiumText(context, 17, FontWeight.w700, bt.glossColor);
    if (variante == null) {
      return Text(glose, textDirection: TextDirection.ltr, style: style);
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
    );
  }

  /// Le numéro Strong : cliquable comme sur la LSGS, quand le lexique en
  /// porte l'entrée. Le code reste affiché dans les deux cas — il dit quelque
  /// chose même sans fiche.
  Widget _strongRow(BuildContext context, BibleTheme bt) {
    final strong = widget.word.strong!;
    final linkable = _strongKnown && widget.onStrongTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Strong'),
          const SizedBox(height: 4),
          if (linkable)
            InkWell(
              onTap: () => _openStrong(strong),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      strong,
                      style: premiumText(
                        context,
                        16,
                        FontWeight.w800,
                        bt.strongColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: bt.strongColor,
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              strong,
              textDirection: TextDirection.ltr,
              style: premiumText(context, 16, FontWeight.w800, bt.strongColor),
            ),
        ],
      ),
    );
  }

  /// Le renvoi de glossaire, résolu en direct : `n12` se lit « Note 12 —
  /// Mot rare, hapax… » et mène à la page. Tant que le glossaire n'a pas
  /// répondu, l'identifiant de source s'affiche, tel quel.
  Widget _noteRow(BuildContext context, PremiumPalette p) {
    final id = widget.word.note!;
    final note = _note;
    final linkable = note != null && widget.onNoteTap != null;
    final texte = note == null ? id : '${note.name} — ${note.heading}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('Glossaire'),
          const SizedBox(height: 4),
          if (linkable)
            InkWell(
              onTap: () => _openNote(id),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 2, bottom: 2),
                child: Row(
                  children: [
                    Icon(Icons.play_arrow_rounded, size: 18, color: p.primary),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        texte,
                        overflow: TextOverflow.ellipsis,
                        style:
                            premiumText(
                              context,
                              15,
                              FontWeight.w600,
                              p.primary,
                            ).copyWith(
                              decoration: TextDecoration.underline,
                              decorationStyle: TextDecorationStyle.dotted,
                              decorationColor: p.primary.withValues(alpha: .7),
                            ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: p.primary,
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 16, color: p.textGrey),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    texte,
                    overflow: TextOverflow.ellipsis,
                    style: premiumText(
                      context,
                      15,
                      FontWeight.w600,
                      p.textDark,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// L'étiquette d'un champ, la même voix que les labels de la fiche Strong :
/// petit, gras, gris — elle nomme, elle ne dit pas.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Text(
      text,
      style: premiumText(context, 12, FontWeight.w500, p.textGrey),
    );
  }
}
