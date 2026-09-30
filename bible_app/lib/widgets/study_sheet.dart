import 'package:flutter/material.dart';

import '../models/user_data.dart';
import '../utils/hex_color.dart';
import 'premium_style.dart';

/// An action pressed in the study sheet — one that takes the reader somewhere
/// else. Highlight and favourite are **not** here: they are toggles applied on
/// the spot through the callbacks of [showStudySheet].
enum StudyAction { note, compare, references, copy, share, lexicon }

/// Bottom sheet study actions for a verse, au goût premium : carte d'en-tête
/// portant la référence et l'extrait, rangée de pastilles sous ruban doré,
/// puis tuiles d'actions verticales sur cartes.
///
/// Returns the action pressed, or null when the sheet is simply closed (the ✕,
/// a swipe down, the back button).
///
/// [onHighlight] and [onFavorite] fire **as the user taps**, not on close. They
/// used to be reported through the pop value, which lost every toggle the
/// reader did not follow with an action: picking a colour then closing the sheet
/// saved nothing, and the favourite star was never persisted at all.
Future<StudyAction?> showStudySheet(
  BuildContext context, {
  required String reference,
  required String excerpt,
  required bool isFavorite,
  required String? currentHighlight,
  required bool lexiqueEnabled, // enables the Lexique button
  required String lexiqueLabel, // what the button names, even when disabled
  required Future<void> Function(String? color) onHighlight,
  required Future<void> Function(bool value) onFavorite,
}) {
  return showModalBottomSheet<StudyAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: premiumBackground(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => Padding(
      // Android 3-button and gesture navigation can overlay modal routes.
      // Reserve that physical system area around the sheet itself, not merely
      // at the end of its scrollable content.
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom,
      ),
      // Panneau « premium affirmé » : voile vertical `surface → surfaceAlt`,
      // liseré net et deux ombres — le même fond que les trois autres feuilles
      // du lecteur. Les cartes de la feuille portent le même dégradé : c'est
      // leur liseré, tenu par le test de contraste, qui les détache du voile.
      child: Container(
        decoration: premiumSurface(context, radius: 24, depth: 1.3),
        child: _StudySheet(
          reference: reference,
          verse: excerpt,
          isFavorite: isFavorite,
          currentHighlight: currentHighlight,
          lexiqueEnabled: lexiqueEnabled,
          lexiqueLabel: lexiqueLabel,
          onHighlight: onHighlight,
          onFavorite: onFavorite,
        ),
      ),
    ),
  );
}

class _StudySheet extends StatefulWidget {
  final String reference;
  final String verse;
  final bool isFavorite;
  final String? currentHighlight;
  final bool lexiqueEnabled;
  final String lexiqueLabel;
  final Future<void> Function(String? color) onHighlight;
  final Future<void> Function(bool value) onFavorite;

  const _StudySheet({
    required this.reference,
    required this.verse,
    required this.isFavorite,
    required this.currentHighlight,
    required this.lexiqueEnabled,
    required this.lexiqueLabel,
    required this.onHighlight,
    required this.onFavorite,
  });

  @override
  State<_StudySheet> createState() => _StudySheetState();
}

class _StudySheetState extends State<_StudySheet> {
  late String? _activeColor = widget.currentHighlight;
  late bool _favorite = widget.isFavorite;

  /// Paints the verse behind the sheet, and stores it. Tapping the active colour
  /// again clears it, so the dots answer both ways without hunting for the
  /// eraser.
  Future<void> _pickColor(String? color) async {
    final next = color == _activeColor ? null : color;
    setState(() => _activeColor = next);
    await widget.onHighlight(next);
  }

  Future<void> _toggleFavorite() async {
    final next = !_favorite;
    setState(() => _favorite = next);
    await widget.onFavorite(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Échelle réellement appliquée au texte (réglage système déjà borné par
    // `ResponsiveTextScaling`) : la grille d'actions s'en sert pour donner plus
    // de hauteur à ses cellules quand la police grandit.
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .58,
      minChildSize: .34,
      maxChildSize: .88,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        children: [
          // ---- En-tête : référence en badge + extrait du verset ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            // `spaceBetween` plutôt qu'un `Spacer` : le badge est désormais
            // `Flexible`, et un `Spacer` à côté de lui se partagerait la place
            // libre moitié-moitié, rétrécissant la référence même quand l'écran
            // a de quoi l'afficher en entier.
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Souple, car un enfant non-flex d'une `Row` est mesuré sous une
              // largeur infinie : le badge ne se replie jamais tout seul et
              // sortait de l'écran sur les longues références (« 1 Chroniques
              // 12:18 ») en 320 px ou à police agrandie.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: p.heroGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: premiumShadow(p.primary, opacity: .25, blur: 10),
                  ),
                  child: Text(
                    widget.reference,
                    style: premiumText(
                      context,
                      14,
                      FontWeight.w800,
                      p.onPrimary,
                    ),
                  ),
                ),
              ),
              _RoundClose(onClose: () => Navigator.of(context).pop()),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.verse,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: premiumText(
              context,
              13.5,
              FontWeight.w500,
              p.textGrey,
              height: 1.5,
              italic: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 16),

          // ---- Surlignage : 16 couleurs + gomme ----
          _sectionLabel(context, Icons.format_color_fill, 'Surligner'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            // Un liseré, pas seulement une ombre : c'est la plus grande carte
            // de la feuille et, sur les thèmes clairs et chauds, son fond ne
            // se distingue de celui du voile que de quelques pourcents (voir
            // [premiumCardBorder]). Ce qui la détache n'est donc pas son flou
            // — un bord fait de flou — mais le liseré net du registre premium.
            decoration: premiumSurface(context, radius: 16, depth: .9),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final color in highlightColors)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: _ColorDot(
                              color: hexToColor(color),
                              selected: _activeColor == color,
                              accent: p.primary,
                              onTap: () => _pickColor(color),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Effacer le surlignage',
                  onPressed: _activeColor == null
                      ? null
                      : () => _pickColor(null),
                  style: IconButton.styleFrom(
                    backgroundColor: _activeColor == null
                        ? Colors.transparent
                        : p.primarySoft,
                  ),
                  icon: Icon(
                    Icons.format_color_reset,
                    color: _activeColor == null ? p.textGrey : p.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ---- Actions ----
          _sectionLabel(context, Icons.bolt_rounded, 'Actions'),
          const SizedBox(height: 10),
          // Le lexique mot à mot n'existe que pour le texte au format BYM (voir
          // le garde-fou côté `chapter_reader`) : sur les autres versions le
          // bouton doit **se voir** fermé, pas seulement rester sourd.
          //
          // Les trois couleurs sont décidées ici état par état, parce qu'aucune
          // ne grisonne d'elle-même : `styleFrom(side:)` passe par `allOrNull`
          // (un seul liseré pour tous les états), la couleur en dur du libellé
          // l'emporte sur le `foregroundColor` du bouton, et un
          // `disabledBackgroundColor` nul retombe sur le défaut du thème. Le
          // bouton gardait donc liseré, fond et texte dorés, avec pour seul
          // indice une icône grise — il avait l'air actif et cassé.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.lexiqueEnabled
                  ? () => Navigator.of(context).pop(StudyAction.lexicon)
                  : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: widget.lexiqueEnabled
                      ? p.primary
                      // Le liseré neutre des cartes, pas l'accent : le même
                      // langage que les pastilles de couleur non choisies.
                      : premiumCardBorder(context, opacity: .34),
                  width: widget.lexiqueEnabled ? 1.8 : 1.2,
                ),
                foregroundColor: p.primary,
                // Porte l'icône, qui n'a pas de couleur explicite : sans elle
                // Material la peindrait en `onSurface` à 38 %, un gris étranger
                // à la palette et différent de celui du libellé.
                disabledForegroundColor: p.textGrey,
                backgroundColor: p.primarySoft.withValues(alpha: .45),
                disabledBackgroundColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_stories_rounded),
              label: Text(
                widget.lexiqueLabel,
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  13.5,
                  FontWeight.w800,
                  widget.lexiqueEnabled ? p.primary : p.textGrey,
                ),
              ),
            ),
          ),
          if (!widget.lexiqueEnabled) ...[
            const SizedBox(height: 6),
            // Grisé seul, le lecteur voit que c'est fermé sans savoir pourquoi
            // ni comment l'ouvrir. Le libellé au-dessus nomme la fonction dans
            // les deux états ; cette ligne dit la seule chose qu'il ne dit pas —
            // d'où elle s'ouvre.
            Text(
              'Disponible depuis le texte BYM.',
              textAlign: TextAlign.center,
              style: premiumText(context, 11.5, FontWeight.w600, p.textGrey),
            ),
          ],
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // Une cellule de `GridView.count` tient sa hauteur du ratio, jamais
            // de son contenu : à police agrandie l'icône et le libellé montent,
            // la cellule non, et la tuile débordait par le bas. Le ratio suit
            // donc l'échelle du texte — 1.35 tel quel à taille normale, cellule
            // d'autant plus haute ensuite. Borné à 1.4 pour ne pas verser dans
            // des tuiles plus hautes que larges.
            childAspectRatio: 1.35 / textScale.clamp(1.0, 1.4),
            children: [
              _ActionTile(
                icon: Icons.edit_note_rounded,
                label: 'Note',
                onTap: () => Navigator.of(context).pop(StudyAction.note),
              ),
              _ActionTile(
                icon: _favorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                label: _favorite ? 'Favori ✓' : 'Favori',
                tint: _favorite,
                iconColor: _favorite ? p.favorite : null,
                onTap: _toggleFavorite,
              ),
              _ActionTile(
                icon: Icons.compare_arrows_rounded,
                label: 'Comparer',
                onTap: () => Navigator.of(context).pop(StudyAction.compare),
              ),
              _ActionTile(
                icon: Icons.account_tree_rounded,
                label: 'Références',
                onTap: () => Navigator.of(context).pop(StudyAction.references),
              ),
              _ActionTile(
                icon: Icons.copy_rounded,
                label: 'Copier',
                onTap: () => Navigator.of(context).pop(StudyAction.copy),
              ),
              _ActionTile(
                icon: Icons.share_rounded,
                label: 'Partager',
                onTap: () => Navigator.of(context).pop(StudyAction.share),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Intitulé de section : pastille d'icône en dégradé + libellé capitulé
/// espacé, puis un filet d'accent qui se perd vers la droite — le même langage
/// que les intertitres des autres écrans, ici en version « séparateur ».
Widget _sectionLabel(BuildContext context, IconData icon, String label) {
  final p = premiumPalette(context);
  return Row(
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          gradient: p.heroGradient,
          borderRadius: BorderRadius.circular(8),
          boxShadow: premiumShadow(p.primary, opacity: .25, blur: 10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: p.onPrimary),
      ),
      const SizedBox(width: 8),
      Text(
        label.toUpperCase(),
        style: premiumText(
          context,
          11.5,
          FontWeight.w800,
          p.primary,
          spacing: 1.2,
        ),
      ),
      const SizedBox(width: 10),
      // Le filet n'est pas un `Divider` : il part de l'intertitre et s'efface
      // vers la droite, assez pour séparer sans fermer la rangée.
      Expanded(
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                p.primary.withValues(alpha: .45),
                p.primary.withValues(alpha: 0),
              ],
            ),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    ],
  );
}

/// The ✕ in its tinted circle, same look as the fiche headers.
class _RoundClose extends StatelessWidget {
  final VoidCallback onClose;
  const _RoundClose({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return IconButton(
      onPressed: onClose,
      style: IconButton.styleFrom(backgroundColor: p.surfaceAlt),
      icon: Icon(Icons.close, size: 20, color: p.textDark),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            width: selected ? 3 : 1.5,
            // Un liseré neutre quand la pastille n'est pas choisie : la bordure
            // valait sa propre couleur à 55 %, donc rien du tout — seize pastels
            // clairs posés sur une carte crème n'avaient aucun bord, et la
            // rangée entière paraissait hors de mise au point.
            color: selected ? accent : premiumCardBorder(context, opacity: .34),
          ),
          // Un anneau net plutôt qu'une lueur : les 8 px de flou sans décalage
          // bavaient sur les palettes chaudes et claires, où l'accent est brun
          // ou ocre et la pastille très pâle. Le halo reste, resserré.
          boxShadow: selected
              ? [BoxShadow(color: accent.withValues(alpha: .30), blurRadius: 4)]
              : null,
        ),
        // Les seize couleurs de la palette sont toutes claires : la coche était
        // en blanc à 70 %, invisible sur un jaune pâle. Elle est donc sombre.
        child: selected
            ? Icon(
                Icons.check_rounded,
                size: 18,
                color: Colors.black.withValues(alpha: .62),
              )
            : null,
      ),
    );
  }
}

/// Une action verticale sur carte : icône dans sa pastille teintée, puis le
/// libellé. [_tint] marque un état actif (le favori étoilé).
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool tint;
  final Color? iconColor;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.tint = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Coquille sans forme côté Material : le voile, la lisière et les ombres
    // sont peintes par l'`Ink`, qu'un Material « façonné » rognerait. Le ripple,
    // lui, se découpe tout seul via `InkWell(borderRadius:)`.
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: tint
            // Le favori étoilé garde sa teinte : un marqueur d'état, jamais un
            // liseré d'accent — l'accent ne borde pas une carte (règle 2).
            ? BoxDecoration(
                color: p.primarySoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: premiumCardBorder(context, opacity: .34),
                ),
                boxShadow: premiumShadow(
                  p.primary,
                  opacity: .30,
                  blur: 10,
                  offset: const Offset(0, 4),
                ),
              )
            : premiumSurface(context, radius: 16, depth: .5),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: iconColor ?? p.primary),
                const SizedBox(height: 6),
                // `Flexible` : la cellule de la grille tient sa hauteur d'un
                // `childAspectRatio`, donc elle ne grandit pas avec la police,
                // alors que l'icône + le libellé si. Sans lui la `Column`
                // déborde dès que la ligne de texte dépasse ~21 px (police de
                // repli, ou réglage système poussé sur un écran étroit). Avec
                // lui elle plie au lieu de rompre : aucun effet quand la place
                // est là.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: premiumText(
                      context,
                      12,
                      FontWeight.w700,
                      tint ? p.primary : p.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
