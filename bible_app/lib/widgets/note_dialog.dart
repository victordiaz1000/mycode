import 'package:flutter/material.dart';

/// What the note editor reports when it closes.
enum NoteDialogResultKind { cancelled, saved, deleted }

/// The outcome of a [NoteDialog]: the trimmed text when saved, nothing
/// otherwise.
class NoteDialogResult {
  final NoteDialogResultKind kind;
  final String text;

  const NoteDialogResult.saved(this.text)
      : kind = NoteDialogResultKind.saved;
  const NoteDialogResult.cancelled()
      : text = '',
        kind = NoteDialogResultKind.cancelled;
  const NoteDialogResult.deleted()
      : text = '',
        kind = NoteDialogResultKind.deleted;
}

/// The note editor opened by the study sheet's « Note » action.
///
/// The [TextEditingController] lives in the dialog's own `State` and is
/// disposed there — not by the caller right after `showDialog` returns. A route
/// pops *before* its exit transition ends, so a controller disposed from the
/// awaiting side is still attached to the TextField fading out, and the fade
/// (`_AnimatedState.didUpdateWidget` re-subscribing its listeners) then touches
/// the disposed controller: `A TextEditingController was used after being
/// disposed` → the red error screen. Owning the controller in the dialog
/// guarantees it outlives the animation.
class NoteDialog extends StatefulWidget {
  final String title;
  final String initialText;

  /// Whether the « Supprimer » button is offered (an existing note).
  final bool showDelete;

  const NoteDialog({
    super.key,
    required this.title,
    this.initialText = '',
    this.showDelete = false,
  });

  @override
  State<NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<NoteDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close(NoteDialogResult result) {
    // [showDialog] pops *before* its exit fade animates out. Disposing the
    // TextEditingController the instant the route closes used to crash: the
    // fading-out TextField's _AnimatedState re-subscribes its listeners and
    // touches a controller already disposed — "A TextEditingController was
    // used after being disposed", the red error screen. Posting the pop to the
    // next frame keeps the controller alive through the frame that touches it,
    // and [dispose] runs only after the route has finished leaving the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pop(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        maxLines: 6,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Écrire une note…'),
      ),
      actions: [
        if (widget.showDelete)
          TextButton(
            onPressed: () => _close(const NoteDialogResult.deleted()),
            child: const Text('Supprimer'),
          ),
        TextButton(
          onPressed: () => _close(const NoteDialogResult.cancelled()),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final text = _controller.text.trim();
            _close(text.isEmpty
                ? const NoteDialogResult.cancelled()
                : NoteDialogResult.saved(text));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}