import 'package:flutter/material.dart';

import '../models/user_data.dart';

/// An action pressed in the study sheet — one that takes the reader somewhere
/// else. Highlight and favourite are **not** here: they are toggles applied on
/// the spot through the callbacks of [showStudySheet].
enum StudyAction {
  note,
  compare,
  references,
  listen,
  copy,
  share,
  lexicon,
}

/// Bottom sheet study actions for a verse (maquette v5).
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
  required bool hasNotes, // enables the Lexique button
  required int noteCount,
  required Future<void> Function(String? color) onHighlight,
  required Future<void> Function(bool value) onFavorite,
}) {
  return showModalBottomSheet<StudyAction>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _StudySheet(
      reference: reference,
      verse: excerpt,
      isFavorite: isFavorite,
      currentHighlight: currentHighlight,
      hasNotes: hasNotes,
      noteCount: noteCount,
      onHighlight: onHighlight,
      onFavorite: onFavorite,
    ),
  );
}

class _StudySheet extends StatefulWidget {
  final String reference;
  final String verse;
  final bool isFavorite;
  final String? currentHighlight;
  final bool hasNotes;
  final int noteCount;
  final Future<void> Function(String? color) onHighlight;
  final Future<void> Function(bool value) onFavorite;

  const _StudySheet({
    required this.reference,
    required this.verse,
    required this.isFavorite,
    required this.currentHighlight,
    required this.hasNotes,
    required this.noteCount,
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
  /// again clears it, so the four dots answer both ways without hunting for the
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
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .5,
      minChildSize: .3,
      maxChildSize: .85,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        // Same reason as the reading sheets: the sheet is sized as a fraction
        // of the screen, so its last row lands under the Android gesture bar
        // without the system inset added back.
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.reference,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(widget.verse,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(height: 20),
          // Surlignage 4 couleurs + gomme
          Text('Surligner', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final color in highlightColors)
                _ColorDot(
                  color: _parse(color),
                  selected: _activeColor == color,
                  onTap: () => _pickColor(color),
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Effacer le surlignage',
                onPressed: _activeColor == null ? null : () => _pickColor(null),
                icon: Icon(Icons.format_color_reset,
                    color: _activeColor == null ? null : accent),
              ),
            ],
          ),
          const Divider(height: 24),
          // Actions
          Text('Actions', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _ActionGrid(
            hasNotes: widget.hasNotes,
            noteCount: widget.noteCount,
            favorite: _favorite,
            onFavorite: _toggleFavorite,
            onAction: (action) => Navigator.of(context).pop(action),
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            width: selected ? 3 : 1,
            color: selected ? Colors.black54 : Colors.black26,
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  final bool hasNotes;
  final int noteCount;
  final bool favorite;
  final VoidCallback onFavorite;
  final void Function(StudyAction) onAction;

  const _ActionGrid({
    required this.hasNotes,
    required this.noteCount,
    required this.favorite,
    required this.onFavorite,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Bouton Lexique pleine largeur
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: hasNotes
                ? () => onAction(StudyAction.lexicon)
                : null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: theme.colorScheme.primary, width: 2),
              foregroundColor: theme.colorScheme.primary,
            ),
            icon: const Icon(Icons.menu_book),
            label: Text(hasNotes
                ? 'Lexique — $noteCount mot${noteCount > 1 ? 's' : ''} annoté${noteCount > 1 ? 's' : ''}'
                : 'Lexique (aucun mot annoté)'),
          ),
        ),
        _ActionChip(
          icon: Icons.edit_note,
          label: 'Note',
          onTap: () => onAction(StudyAction.note),
        ),
        _ActionChip(
          icon: favorite ? Icons.star : Icons.star_border,
          label: favorite ? 'Favori ✓' : 'Favori',
          onTap: onFavorite,
        ),
        _ActionChip(
          icon: Icons.compare_arrows,
          label: 'Comparer',
          onTap: () => onAction(StudyAction.compare),
        ),
        _ActionChip(
          icon: Icons.copyright,
          label: 'Références',
          onTap: () => onAction(StudyAction.references),
        ),
        _ActionChip(
          icon: Icons.headphones,
          label: 'Écouter',
          onTap: () => onAction(StudyAction.listen),
        ),
        _ActionChip(
          icon: Icons.copy,
          label: 'Copier',
          onTap: () => onAction(StudyAction.copy),
        ),
        _ActionChip(
          icon: Icons.share,
          label: 'Partager',
          onTap: () => onAction(StudyAction.share),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}
Color _parse(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xFFF3B0;
  return Color(0xFF000000 | v);
}
