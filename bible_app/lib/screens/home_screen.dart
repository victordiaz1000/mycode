import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../data/reading_history.dart';
import '../data/tab_manager.dart';
import '../models/chapter.dart';
import 'themes_screen.dart';

/// Destinations of the bottom navigation bar (maquette § 01).
enum BymDestination { accueil, lecture, recherche, bibliotheque, reglages }

const Color bymGold = Color(0xFFD3A94F);

/// "il y a 5 min", "hier, 21:14", "lundi", "12/03".
String formatRelativeDate(DateTime when, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final delta = ref.difference(when);
  if (delta.inMinutes < 1) return 'à l’instant';
  if (delta.inMinutes < 60) return 'il y a ${delta.inMinutes} min';

  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(ref.year, ref.month, ref.day);
  final days = today.difference(day).inDays;
  final hhmm = '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
  if (days <= 0) return 'aujourd’hui, $hhmm';
  if (days == 1) return 'hier, $hhmm';
  if (days < 7) return _weekdays[when.weekday - 1];
  return '${when.day.toString().padLeft(2, '0')}/'
      '${when.month.toString().padLeft(2, '0')}';
}

const List<String> _weekdays = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
];

/// The Chrome-like home page (maquette § 01) : universal search bar, tool
/// shortcuts, a « Reprendre la lecture » card and the recent studies.
///
/// It shares the app's [TabManager], so the gold counter matches the reading
/// tabs and opening anything from here lands in the Lecture destination.
class HomeScreen extends StatefulWidget {
  final TabManager manager;

  /// Switches the bottom navigation to another destination.
  final void Function(BymDestination destination) onSelectDestination;

  const HomeScreen({
    super.key,
    required this.manager,
    required this.onSelectDestination,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocalRepository _repository = LocalRepository();
  List<ReadingEntry> _recent = const [];

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.manager.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final recent = await widget.manager.history.load();
    if (!mounted) return;
    setState(() => _recent = recent);
  }

  void _openReading(int bookIndex, int chapter) {
    widget.manager.openReading(bookIndex, chapter);
    widget.onSelectDestination(BymDestination.lecture);
  }

  void _soon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — bientôt disponible.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resume = _recent.isEmpty ? null : _recent.first;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _TopBar(
              tabCount: widget.manager.count,
              onOpenThemes: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ThemesScreen()),
              ),
              onOpenTabs: () {
                if (!widget.manager.hasTabs) widget.manager.openHome();
                widget.onSelectDestination(BymDestination.lecture);
              },
            ),
            const SizedBox(height: 14),
            _SearchBar(
              onTap: () =>
                  widget.onSelectDestination(BymDestination.recherche),
            ),
            const SizedBox(height: 16),
            _Shortcuts(
              canResume: resume != null,
              onResume: resume == null
                  ? null
                  : () => _openReading(resume.bookIndex, resume.chapter),
              onFavorites: () => _soon('Favoris'),
              onAudio: () => _soon('Audio'),
              onCompare: () => _soon('Comparaison'),
              onDictionary: () =>
                  widget.onSelectDestination(BymDestination.bibliotheque),
            ),
            const SizedBox(height: 18),
            if (resume == null)
              const _EmptyResume()
            else
              _ResumeCard(
                entry: resume,
                repository: _repository,
                onResume: () => _openReading(resume.bookIndex, resume.chapter),
              ),
            const SizedBox(height: 22),
            _RecentStudies(
              entries: _recent.length > 1 ? _recent.sublist(1) : const [],
              onOpen: _openReading,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final int tabCount;
  final VoidCallback onOpenThemes;
  final VoidCallback onOpenTabs;

  const _TopBar({
    required this.tabCount,
    required this.onOpenThemes,
    required this.onOpenTabs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Image.asset(
          'assets/brand/logo.png',
          height: 32,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(
            Icons.auto_stories,
            color: theme.colorScheme.primary,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Thèmes',
          onPressed: onOpenThemes,
          icon: const Icon(Icons.palette_outlined),
        ),
        Material(
          color: bymGold,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: onOpenTabs,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                '$tabCount',
                style: const TextStyle(
                  color: Color(0xFF241A04),
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rechercher un verset, un livre, un thème…',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: bymGold.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Jean 3.16',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shortcuts extends StatelessWidget {
  final bool canResume;
  final VoidCallback? onResume;
  final VoidCallback onFavorites;
  final VoidCallback onAudio;
  final VoidCallback onCompare;
  final VoidCallback onDictionary;

  const _Shortcuts({
    required this.canResume,
    required this.onResume,
    required this.onFavorites,
    required this.onAudio,
    required this.onCompare,
    required this.onDictionary,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _ShortcutChip(
            icon: Icons.menu_book,
            label: 'Reprendre',
            enabled: canResume,
            onTap: onResume,
          ),
          _ShortcutChip(
              icon: Icons.star_outline, label: 'Favoris', onTap: onFavorites),
          _ShortcutChip(
              icon: Icons.headphones_outlined, label: 'Audio', onTap: onAudio),
          _ShortcutChip(
              icon: Icons.compare_arrows, label: 'Comparer', onTap: onCompare),
          _ShortcutChip(
              icon: Icons.library_books_outlined,
              label: 'Dico',
              onTap: onDictionary),
        ],
      ),
    );
  }
}

class _ShortcutChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  const _ShortcutChip({
    required this.icon,
    required this.label,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurface.withValues(alpha: .35);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 78,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color:
                theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyResume extends StatelessWidget {
  const _EmptyResume();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Text(
          'Aucune lecture pour l’instant — ouvrez un chapitre depuis '
          'l’onglet Lecture ou la recherche.',
        ),
      ),
    );
  }
}

/// « Reprendre la lecture » : last visited chapter, first-verse excerpt and
/// progress within the book.
class _ResumeCard extends StatelessWidget {
  final ReadingEntry entry;
  final LocalRepository repository;
  final VoidCallback onResume;

  const _ResumeCard({
    required this.entry,
    required this.repository,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: bymGold.withValues(alpha: .14),
      child: InkWell(
        onTap: onResume,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: FutureBuilder<Chapter>(
            future: repository.loadChapter(entry.bookIndex, entry.chapter),
            builder: (context, snapshot) {
              final excerpt = snapshot.hasData && snapshot.data!.verses.isNotEmpty
                  ? snapshot.data!.verses.first.text
                  : '';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${catalogEntry(entry.bookIndex).name} — '
                    'chapitre ${entry.chapter}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (excerpt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '« $excerpt »',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FutureBuilder<int>(
                    future: repository.chapterCount(entry.bookIndex),
                    builder: (context, count) => _progress(
                      context,
                      total: count.data ?? 0,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _progress(BuildContext context, {required int total}) {
    final theme = Theme.of(context);
    final ratio = total <= 0 ? 0.0 : (entry.chapter / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: bymGold.withValues(alpha: .25),
            valueColor: const AlwaysStoppedAnimation<Color>(bymGold),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Reprendre la lecture', style: theme.textTheme.labelMedium),
            if (total > 0)
              Text('ch. ${entry.chapter} / $total',
                  style: theme.textTheme.labelMedium),
          ],
        ),
      ],
    );
  }
}

class _RecentStudies extends StatelessWidget {
  final List<ReadingEntry> entries;
  final void Function(int bookIndex, int chapter) onOpen;

  const _RecentStudies({required this.entries, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Études récentes',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Vos derniers chapitres ouverts apparaîtront ici.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final entry in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: bymGold.withValues(alpha: .2),
                child: const Text('✦', style: TextStyle(fontSize: 13)),
              ),
              title: Text('${entry.bookName} ${entry.chapter}'),
              subtitle: Text(
                  'Lecture · ${formatRelativeDate(entry.dateTime)}'),
              onTap: () => onOpen(entry.bookIndex, entry.chapter),
            ),
      ],
    );
  }
}
