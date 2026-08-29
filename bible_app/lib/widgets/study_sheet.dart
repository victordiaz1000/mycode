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
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(16),
              // Un liseré, pas seulement une ombre : c'est la plus grande carte
              // de la feuille et, sur les thèmes clairs et chauds, son fond ne
              // se distingue de celui de la feuille que de quelques pourcents
              // (voir [premiumCardBorder]). Elle n'avait pour contour qu'un flou
              // de 12 px à 5 % — un bord fait de flou.
              border: Border.all(
                color: premiumCardBorder(context, opacity: .2),
              ),
              boxShadow: premiumShadow(p.primaryDark, opacity: .05, blur: 12),
            ),
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.lexiqueEnabled
                  ? () => Navigator.of(context).pop(StudyAction.lexicon)
                  : null,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: p.primary, width: 1.8),
                foregroundColor: p.primary,
                backgroundColor: p.primarySoft.withValues(alpha: .45),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.auto_stories_rounded),
              label: Text(
                widget.lexiqueLabel,
                textAlign: TextAlign.center,
                style: premiumText(context, 13.5, FontWeight.w800, p.primary),
              ),
            ),
          ),
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

/// Intitulé de section : pastille d'icône + libellé capitulé espacé, le même
/// langage que les intertitres des autres feuilles.
Widget _sectionLabel(BuildContext context, IconData icon, String label) {
  final p = premiumPalette(context);
  return Row(
    children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: p.primarySoft,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: p.primary),
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
    return Material(
      color: tint ? p.primarySoft : p.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tint
                  ? p.primary.withValues(alpha: .5)
                  : premiumCardBorder(context),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: iconColor ?? p.primary),
              const SizedBox(height: 6),
              // `Flexible` : la cellule de la grille tient sa hauteur d'un
              // `childAspectRatio`, donc elle ne grandit pas avec la police,
              // alors que l'icône + le libellé si. Sans lui la `Column` déborde
              // dès que la ligne de texte dépasse ~21 px (police de repli, ou
              // réglage système poussé sur un écran étroit). Avec lui elle plie
              // au lieu de rompre : aucun effet quand la place est là.
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
    );
  }
}
