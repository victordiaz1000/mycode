import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../data/share_text.dart';
import '../models/user_data.dart';
import '../utils/date_format.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/note_editor_sheet.dart';
import '../widgets/premium_style.dart';

enum _NoteSort { recent, book }

/// Écran « Mes notes » : toutes les notes utilisateur, triées (récent / livre),
/// cherchables, exportables en fichier texte partagé. Plusieurs notes peuvent
/// porter sur un même verset — chacune a sa carte.
///
/// [db] et [repository] sont injectables (même couture que [FavorisScreen])
/// pour les tests.
class NotesScreen extends StatefulWidget {
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;
  final AppDatabase? db;
  final LocalRepository? repository;

  const NotesScreen({super.key, this.onOpenVerse, this.db, this.repository});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late final AppDatabase _db = widget.db ?? AppDatabase.instance;
  late final LocalRepository _repository = widget.repository ?? LocalRepository();

  List<_NoteEntry> _notes = const [];
  bool _loading = true;
  Object? _error;
  String _query = '';
  _NoteSort _sort = _NoteSort.recent;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final raw = await _db.allNotes();
      final enriched = await _enrich(raw);
      if (!mounted) return;
      setState(() {
        _notes = enriched;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<List<_NoteEntry>> _enrich(List<UserNote> notes) async {
    if (notes.isEmpty) return const [];
    // Group by book to avoid loading the same book N times.
    final byBook = <int, List<UserNote>>{};
    for (final n in notes) {
      byBook.putIfAbsent(n.bookIndex, () => []).add(n);
    }
    final texts = <(int, int, int), String>{};
    for (final entry in byBook.entries) {
      try {
        final book = await _repository.loadBook(entry.key);
        for (final c in book.chapters) {
          for (final v in c.verses) {
            texts[(entry.key, c.chapter, v.number)] = v.text;
          }
        }
      } catch (_) {
        // leave empty
      }
    }
    return [
      for (final n in notes)
        _NoteEntry(
          note: n,
          reference:
              '${catalogEntry(n.bookIndex).shortName} ${n.chapter}:${n.verse}',
          verseText: texts[(n.bookIndex, n.chapter, n.verse)] ?? '',
        ),
    ];
  }

  List<_NoteEntry> get _filtered {
    final q = _query.trim().toLowerCase();
    final base = q.isEmpty
        ? _notes
        : _notes.where((e) {
            final ref = e.reference.toLowerCase();
            final title = e.note.title.toLowerCase();
            final verse = e.verseText.toLowerCase();
            final note = e.note.text.toLowerCase();
            return ref.contains(q) ||
                verse.contains(q) ||
                note.contains(q) ||
                title.contains(q);
          }).toList();
    if (_sort == _NoteSort.recent) return base;
    // Ordre de lecture : livre (index BYM), puis chapitre et verset ; au sein
    // d'un même verset, la note la plus récente d'abord.
    final sorted = [...base]..sort((a, b) {
        final byBook = a.note.bookIndex.compareTo(b.note.bookIndex);
        if (byBook != 0) return byBook;
        final byChapter = a.note.chapter.compareTo(b.note.chapter);
        if (byChapter != 0) return byChapter;
        final byVerse = a.note.verse.compareTo(b.note.verse);
        if (byVerse != 0) return byVerse;
        return b.note.updatedAt.compareTo(a.note.updatedAt);
      });
    return sorted;
  }

  Future<void> _edit(_NoteEntry entry) async {
    final outcome = await showNoteEditorSheet(
      context: context,
      db: _db,
      reference: entry.reference,
      verseText: entry.verseText,
      note: entry.note,
      bookIndex: entry.note.bookIndex,
      chapter: entry.note.chapter,
      verse: entry.note.verse,
    );
    if (outcome == null || !mounted) return;
    // Reload to reorder by updated_at and refresh verse text if needed.
    setState(() => _loading = true);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == NoteEditorOutcome.deleted
              ? 'Note supprimée'
              : 'Note enregistrée',
        ),
      ),
    );
  }

  void _open(_NoteEntry e) {
    widget.onOpenVerse?.call(e.note.bookIndex, e.note.chapter, e.note.verse);
  }

  /// Le texte d'export complet — extrait en fonction pure pour être testable
  /// sans toucher au disque ni au canal de partage.
  @visibleForTesting
  static String buildExport(List<_NoteEntry> entries) {
    final buffer = StringBuffer('Mes notes — BYM\n\n');
    for (final e in entries) {
      buffer.writeln('${e.reference}${e.note.title.isEmpty ? '' : ' — ${e.note.title}'}');
      if (e.verseText.isNotEmpty) buffer.writeln('« ${e.verseText} »');
      buffer.writeln(e.note.text);
      buffer.writeln(
        '(modifiée le ${formatFullDate(DateTime.fromMillisecondsSinceEpoch(e.note.updatedAt))})',
      );
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<void> _export() async {
    if (_notes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune note à exporter')),
      );
      return;
    }
    try {
      final content = buildExport(_notes);
      final dir = await getTemporaryDirectory();
      final file = File(p.join(dir.path, 'bym-notes.txt'));
      await file.writeAsString(
        '$content\n\n—\nExporté depuis $appName',
        flush: true,
      );
      await shareTextFile(file.path, subject: 'Mes notes BYM');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'exporter les notes")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Mes notes',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
        actions: [
          IconButton(
            key: const ValueKey('notes-export'),
            tooltip: 'Exporter les notes',
            onPressed: _notes.isEmpty ? null : _export,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: _loading
              ? const ListLoadingSkeleton(padding: EdgeInsets.zero)
              : _error != null
                  ? _buildError(context)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSearchField(context),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SegmentedButton<_NoteSort>(
                                key: const ValueKey('notes-sort'),
                                segments: const [
                                  ButtonSegment(
                                    value: _NoteSort.recent,
                                    icon: Icon(Icons.schedule_rounded, size: 16),
                                    label: Text('Récent'),
                                  ),
                                  ButtonSegment(
                                    value: _NoteSort.book,
                                    icon: Icon(Icons.menu_book_outlined, size: 16),
                                    label: Text('Livre'),
                                  ),
                                ],
                                selected: {_sort},
                                onSelectionChanged: (selection) =>
                                    setState(() => _sort = selection.first),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${filtered.length} note${filtered.length > 1 ? 's' : ''}',
                          style: premiumText(
                              context, 13, FontWeight.w500, p.textGrey),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filtered.isEmpty
                              ? _buildEmpty(context)
                              : ListView.separated(
                                  key: const ValueKey('notes-list'),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) =>
                                      _buildCard(context, filtered[i]),
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text('Impossible de charger vos notes.',
              style: premiumText(context, 15, FontWeight.w800, p.textDark)),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: premiumShadow(p.primaryDark),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        style: premiumText(context, 14, FontWeight.w500, p.textDark),
        decoration: InputDecoration(
          hintText: 'Rechercher dans vos notes…',
          hintStyle: premiumText(context, 14, FontWeight.w500, p.textGrey),
          prefixIcon: Icon(Icons.search_rounded, color: p.textGrey),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final p = premiumPalette(context);
    final hasNotes = _notes.isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.note_alt_outlined,
              size: 56, color: p.textGrey.withValues(alpha: .4)),
          const SizedBox(height: 12),
          Text(
            hasNotes ? 'Aucun résultat' : 'Aucune note pour l’instant',
            style: premiumText(context, 16, FontWeight.w800, p.textDark),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              hasNotes
                  ? 'Aucune note ne correspond à cette recherche.'
                  : 'Appuyez sur un verset puis sur « Note » pour en créer une. Vos notes apparaîtront ici.',
              style: premiumText(context, 13, FontWeight.w500, p.textGrey,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, _NoteEntry e) {
    final p = premiumPalette(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(p.primaryDark,
              opacity: 0.07, blur: 16, offset: const Offset(0, 6)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onOpenVerse == null ? null : () => _open(e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: p.primarySoft, shape: BoxShape.circle),
                      child: Icon(Icons.sticky_note_2_outlined,
                          size: 16, color: p.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(e.reference,
                          style: premiumText(
                              context, 14, FontWeight.w800, p.textDark)),
                    ),
                    Text(
                      formatRelativeDate(DateTime.fromMillisecondsSinceEpoch(
                          e.note.updatedAt)),
                      style:
                          premiumText(context, 11, FontWeight.w600, p.textGrey),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: p.textGrey.withValues(alpha: .6)),
                  ],
                ),
                if (e.note.title.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    e.note.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        premiumText(context, 14.5, FontWeight.w800, p.textDark),
                  ),
                ],
                if (e.verseText.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '« ${e.verseText} »',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: premiumText(context, 12.5, FontWeight.w500, p.textGrey,
                        height: 1.45,
                        italic: FontStyle.italic),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: p.primary.withValues(alpha: .10)),
                  ),
                  child: Text(
                    e.note.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: premiumText(
                        context, 13.5, FontWeight.w600, p.textDark, height: 1.5),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () => _edit(e),
                      icon:
                          Icon(Icons.edit_outlined, size: 16, color: p.primary),
                      label: Text('Modifier',
                          style: premiumText(
                              context, 12.5, FontWeight.w700, p.primary)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        minimumSize: Size.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteEntry {
  final UserNote note;
  final String reference;
  final String verseText;
  const _NoteEntry(
      {required this.note, required this.reference, required this.verseText});
}
