import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../models/user_data.dart';
import '../utils/date_format.dart';
import 'premium_style.dart';

/// Bottom clearance for sheets: gesture bar + breathing room. `padding` is
/// already consumed by a modal route, so `viewPadding` is the one to read.
double sheetBottomInset(BuildContext context) =>
    24 + MediaQuery.viewPaddingOf(context).bottom;

/// What the note surface reports once closed.
enum NoteEditorOutcome { saved, deleted, untouched }

/// Sentinel returned by [showVerseNotesPicker] when the user asks for a new
/// note rather than editing one of the existing ones.
const Object kNewNoteRequest = 'new-note';

/// Opens the right note surface for a verse: straight into the editor when
/// the verse holds no note yet, through the picker when it already holds
/// some (several notes per verse are supported). Returns what last happened,
/// or null when the reader backed out before anything changed.
Future<NoteEditorOutcome?> editVerseNotes({
  required BuildContext context,
  required AppDatabase db,
  required int bookIndex,
  required int chapter,
  required int verse,
  required String reference,
  String verseText = '',
}) async {
  final notes = await db.notesForVerse(bookIndex, chapter, verse);
  if (!context.mounted) return null;

  UserNote? target;
  if (notes.isNotEmpty) {
    final choice = await showVerseNotesPicker(
      context: context,
      notes: notes,
      reference: reference,
    );
    if (!context.mounted) return null;
    if (choice == null) return null;
    target = identical(choice, kNewNoteRequest) ? null : choice as UserNote;
  }

  return showNoteEditorSheet(
    context: context,
    db: db,
    reference: reference,
    verseText: verseText,
    note: target,
    bookIndex: bookIndex,
    chapter: chapter,
    verse: verse,
  );
}

/// The chooser shown when the verse already carries at least one note:
/// every existing note is listed (tap to edit), plus one « Nouvelle note ».
Future<Object?> showVerseNotesPicker({
  required BuildContext context,
  required List<UserNote> notes,
  required String reference,
}) {
  return showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: premiumPalette(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: premiumCardBorder(context, opacity: .18)),
    ),
    builder: (sheetContext) {
      final p = premiumPalette(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
            maxWidth: 560,
          ),
          child: Padding(
            padding:
                EdgeInsets.fromLTRB(20, 8, 20, sheetBottomInset(sheetContext)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  reference,
                  style: premiumText(sheetContext, 16, FontWeight.w800, p.textDark),
                ),
                const SizedBox(height: 4),
                Text(
                  '${notes.length} note${notes.length > 1 ? 's' : ''} sur ce verset',
                  style: premiumText(sheetContext, 12.5, FontWeight.w500, p.textGrey),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final n in notes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _PickerCard(note: n),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  key: const ValueKey('note-picker-new'),
                  onPressed: () =>
                      Navigator.of(sheetContext).pop(kNewNoteRequest),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Nouvelle note'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _PickerCard extends StatelessWidget {
  final UserNote note;
  const _PickerCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('note-picker-${note.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(note),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? note.text : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          premiumText(context, 13.5, FontWeight.w700, p.textDark),
                    ),
                  ),
                  Text(
                    formatRelativeDate(
                      DateTime.fromMillisecondsSinceEpoch(note.updatedAt),
                    ),
                    style: premiumText(context, 11, FontWeight.w600, p.textGrey),
                  ),
                ],
              ),
              if (note.title.isNotEmpty && note.text.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  note.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: premiumText(context, 12.5, FontWeight.w500, p.textGrey,
                      height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the editor for one note ([note] null = creating).
///
/// The sheet OWNS persistence: whatever was typed is saved when the sheet
/// closes — ✕, drag-down, back gesture — so a long draft can never be lost
/// by closing. An empty body on a brand-new note writes nothing; removing an
/// existing note goes through « Supprimer » and its confirmation. The returned
/// outcome lets the caller refresh its own marks.
Future<NoteEditorOutcome?> showNoteEditorSheet({
  required BuildContext context,
  required AppDatabase db,
  required String reference,
  String verseText = '',
  UserNote? note,
  required int bookIndex,
  required int chapter,
  required int verse,
}) {
  // A modal bottom sheet NEVER rises above the keyboard by itself (the
  // framework adds no viewInsets handling here): without this outer padding
  // the body field sits behind the keyboard and the reader types blind.
  return showModalBottomSheet<NoteEditorOutcome>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: premiumPalette(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      side: BorderSide(color: premiumCardBorder(context, opacity: .18)),
    ),
    builder: (sheetContext) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
      child: NoteEditorSheet(
        db: db,
        reference: reference,
        verseText: verseText,
        note: note,
        bookIndex: bookIndex,
        chapter: chapter,
        verse: verse,
      ),
    ),
  );
}

class NoteEditorSheet extends StatefulWidget {
  final AppDatabase db;
  final String reference;
  final String verseText;
  final UserNote? note;
  final int bookIndex;
  final int chapter;
  final int verse;

  const NoteEditorSheet({
    super.key,
    required this.db,
    required this.reference,
    this.verseText = '',
    required this.note,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
  });

  @override
  State<NoteEditorSheet> createState() => _NoteEditorSheetState();
}

class _NoteEditorSheetState extends State<NoteEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  bool _closed = false;

  bool get _isExisting => widget.note?.id != null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.note?.title ?? '');
    _body = TextEditingController(text: widget.note?.text ?? '');
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// Persists the draft, then pops with the matching outcome. Guarded against
  /// double-fire (✕ tap racing a drag-to-dismiss): the first close wins.
  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    final text = _body.text.trim();
    var outcome = NoteEditorOutcome.untouched;
    if (text.isNotEmpty) {
      await widget.db.upsertNote(
        (widget.note ?? _draft())
            .copyWith(title: _title.text.trim(), text: text),
      );
      outcome = NoteEditorOutcome.saved;
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  UserNote _draft() => UserNote(
        bookIndex: widget.bookIndex,
        chapter: widget.chapter,
        verse: widget.verse,
        title: '',
        text: '',
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _confirmDelete() async {
    final p = premiumPalette(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: premiumCardBorder(context, opacity: .18)),
        ),
        title: const Text('Supprimer cette note ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const ValueKey('note-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _closed) return;
    _closed = true;
    await widget.db.deleteNoteById(widget.note!.id!);
    if (mounted) Navigator.of(context).pop(NoteEditorOutcome.deleted);
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return PopScope(
      // Intercepts back gesture / barrier tap so [_close] persists first.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        // The modal route lifts the sheet above the keyboard and hands the
        // REMAINING height as constraints — sizing on MediaQuery.size would
        // overflow that space and leave the body field behind the keyboard.
        child: LayoutBuilder(
          builder: (context, space) {
            final maxHeight = space.maxHeight.isFinite
                ? space.maxHeight
                : MediaQuery.sizeOf(context).height * .9;
            return ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 4, 20, sheetBottomInset(context)),
                child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.reference,
                          style: premiumText(
                              context, 16, FontWeight.w800, p.textDark),
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('note-editor-close'),
                        tooltip: 'Fermer',
                        onPressed: _close,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  if (widget.verseText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: premiumCardBorder(context, opacity: .16)),
                      ),
                      child: Text(
                        '« ${widget.verseText} »',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(context, 12.5, FontWeight.w500,
                            p.textGrey,
                            height: 1.45,
                            italic: FontStyle.italic),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('note-editor-title'),
                    controller: _title,
                    textInputAction: TextInputAction.next,
                    style: premiumText(
                        context, 14.5, FontWeight.w700, p.textDark),
                    decoration: InputDecoration(
                      hintText: 'Titre (optionnel)',
                      hintStyle: premiumText(
                          context, 14, FontWeight.w600, p.textGrey),
                      isDense: true,
                      // Le thème global met `filled: true` + `panelColor` :
                      // sans ce drapeau un aplat **carré** de cette couleur
                      // se peindrait derrière le titre, sur la feuille
                      // `p.surface` — voir `notes_screen._buildSearchField`.
                      filled: false,
                      border: InputBorder.none,
                    ),
                  ),
                  const Divider(height: 20),
                  TextField(
                    key: const ValueKey('note-editor-body'),
                    controller: _body,
                    maxLines: null,
                    minLines: 6,
                    autofocus: !_isExisting,
                    style: premiumText(
                        context, 14, FontWeight.w500, p.textDark,
                        height: 1.55),
                    decoration: InputDecoration(
                      hintText: 'Écrire une note…',
                      hintStyle: premiumText(
                          context, 14, FontWeight.w500, p.textGrey),
                      // Même aplat carré hérité du thème que le champ titre.
                      filled: false,
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_isExisting)
                        TextButton.icon(
                          key: const ValueKey('note-editor-delete'),
                          onPressed: _confirmDelete,
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 18,
                              color: Theme.of(context).colorScheme.error),
                          label: Text('Supprimer',
                              style: premiumText(
                                  context,
                                  13,
                                  FontWeight.w700,
                                  Theme.of(context).colorScheme.error)),
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 10),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        'Enregistré à la fermeture',
                        style: premiumText(
                            context, 11.5, FontWeight.w600, p.textGrey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
          },
        ),
      ),
    );
  }
}
