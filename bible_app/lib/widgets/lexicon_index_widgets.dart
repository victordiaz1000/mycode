import 'package:flutter/material.dart';

import 'premium_style.dart';

/// Les briques communes aux trois index de lexique/dictionnaire embarqués
/// (Notes BYM, Westphal 1932, Strong FR et le lecteur générique des
/// dictionnaires téléchargés) : puces alphabétiques, mention de source et
/// carte d'entrée. Chacun de ces écrans portait sa copie privée, qui dérivait
/// au fil des retouches.

/// Une puce de la barre alphabétique (« Toutes », A, B…).
class LexiconLetterChip extends StatelessWidget {
  final String label;
  final bool active;
  final Color accent;
  final VoidCallback onTap;

  const LexiconLetterChip({
    super.key,
    required this.label,
    required this.active,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? p.heroGradient : null,
          color: active ? null : p.surfaceAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? Colors.transparent
                : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: active
              ? premiumShadow(
                  accent,
                  opacity: .2,
                  blur: 12,
                  offset: const Offset(0, 4),
                )
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            active ? p.onPrimary : p.textDark,
          ),
        ),
      ),
    );
  }
}

/// Le champ de recherche des index : le voile de surface, le liseré **net** et
/// deux ombres — puis le liseré et la lueur qui montent dès que le champ prend
/// le focus (registre de l'écran Recherche).
///
/// Il garde ce que les tests attendent : un seul [TextField] par écran, le
/// bouton « Effacer » à droite quand quelque chose est saisi, et la hauteur
/// stable (grâce au plancher de 44 px) pour que le bouton n'enfle pas la
/// rangée à l'apparition.
class LexiconSearchField extends StatefulWidget {
  final String hint;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const LexiconSearchField({
    super.key,
    required this.hint,
    required this.controller,
    required this.onChanged,
  });

  @override
  State<LexiconSearchField> createState() => _LexiconSearchFieldState();
}

class _LexiconSearchFieldState extends State<LexiconSearchField> {
  final FocusNode _focus = FocusNode();
  bool _actif = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted && _actif != _focus.hasFocus) {
      setState(() => _actif = _focus.hasFocus);
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final saisi = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.surface, p.surfaceAlt],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: premiumCardBorder(context, opacity: _actif ? .55 : .18),
        ),
        boxShadow: [
          ...premiumShadow(
            p.primaryDark,
            opacity: _actif ? .12 : .07,
            blur: _actif ? 18 : 12,
            offset: const Offset(0, 5),
          ),
          ...premiumShadow(
            p.primary,
            opacity: _actif ? .22 : .06,
            blur: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: p.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: premiumText(context, 14, FontWeight.w500, p.textGrey),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (saisi)
            IconButton(
              tooltip: 'Effacer',
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.clear_rounded, size: 20),
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
              },
            ),
        ],
      ),
    );
  }
}

/// L'état « rien ne correspond » des quatre index : un disque halo teinté
/// plutôt qu'une icône nue, posé au centre du vide.
class LexiconEmptyState extends StatelessWidget {
  const LexiconEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: p.primarySoft,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: premiumCardBorder(context, opacity: .16)),
              boxShadow: premiumShadow(
                p.primaryDark,
                opacity: 0.10,
                blur: 16,
                offset: const Offset(0, 6),
              ),
            ),
            child: Icon(Icons.search_off_rounded, size: 36, color: p.primary),
          ),
          const SizedBox(height: 14),
          Text(
            'Aucune entrée trouvée',
            style: premiumText(context, 14, FontWeight.w600, p.textGrey),
          ),
        ],
      ),
    );
  }
}

/// La ligne « info » sous la recherche : ce que contient l'index et d'où ça
/// vient.
class LexiconSourceMention extends StatelessWidget {
  final String text;

  const LexiconSourceMention({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Row(
      children: [
        Icon(Icons.info_outline, size: 16, color: p.textGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
          ),
        ),
      ],
    );
  }
}

/// Une carte d'entrée : terme + extrait, tap → fiche. Le tap appartient à
/// l'écran (chaque index pousse sa propre fiche).
class LexiconEntryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const LexiconEntryCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Coquille sans forme côté Material : la lisière et les deux ombres sont
    // peintes par l'`Ink`, qu'un Material « façonné » rognerait au contour
    // arrondi.
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: premiumSurface(context, radius: 16, depth: 0.8),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: premiumText(
                          context,
                          15,
                          FontWeight.w800,
                          p.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                          context,
                          12,
                          FontWeight.w500,
                          p.textGrey,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: p.textGrey, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
