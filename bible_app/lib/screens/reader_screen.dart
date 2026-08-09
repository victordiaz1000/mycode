import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/library_store.dart';
import '../data/tab_manager.dart';
import '../data/version_repository.dart';
import '../models/study_tab.dart';
import '../widgets/chapter_reader.dart';
import '../widgets/reader_actions_bar.dart';
import '../widgets/tab_strip.dart';
import '../widgets/tab_switcher.dart';

/// The tabbed reading context at the heart of the app: a Chrome-style tab
/// strip on top, the active tab's content below, and a card switcher + home
/// page. Owns a [TabManager] whose state persists across launches.
class ReaderScreen extends StatefulWidget {
  /// Optional injected [TabManager] for tests; the screen creates its own
  /// (and owns it) when null.
  final TabManager? initialManager;

  /// Optional notifier driving "jump to verse" requests (from search).
  final ValueListenable<VerseTarget?>? jumpToVerse;

  /// Switches the shell to the Bibliothèque destination. Null when the screen
  /// is used on its own (tests): the reader then only names the Bibliothèque.
  final VoidCallback? onOpenLibrary;

  const ReaderScreen({
    super.key,
    this.initialManager,
    this.jumpToVerse,
    this.onOpenLibrary,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final TabManager _manager;
  late final bool _ownsManager;

  @override
  void initState() {
    super.initState();
    _manager = widget.initialManager ?? TabManager();
    _ownsManager = widget.initialManager == null;
    // An injected manager is owned (and already restored) by the caller;
    // reloading it here would race with its pending writes.
    if (_ownsManager) {
      _manager.load().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    if (_ownsManager) _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _manager,
      builder: (context, _) {
        if (!_manager.hasTabs) {
          return _NewTabHome(
            manager: _manager,
            onOpenLibrary: widget.onOpenLibrary,
          );
        }
        final activeIndex = _manager.activeIndex < 0 ? 0 : _manager.activeIndex;
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                TabStrip(
                  manager: _manager,
                  onOpenSwitcher: () => TabSwitcher.show(context, _manager),
                ),
                Expanded(
                  child: IndexedStack(
                    index: activeIndex,
                    children: [
                      for (final tab in _manager.tabs) _buildTabContent(tab),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabContent(StudyTab tab) {
    if (tab.isHome) {
      return _HomeTab(manager: _manager, onOpenLibrary: widget.onOpenLibrary);
    }
    return ChapterReader(
      key: ValueKey('reader-${tab.id}-${tab.bookIndex}-${tab.chapter}'),
      bookIndex: tab.bookIndex!,
      chapter: tab.chapter!,
      initialVersionCode: tab.versionCode,
      jumpToVerse: widget.jumpToVerse,
      onOpenLibrary: widget.onOpenLibrary,
      onVersionChanged: (code) => _manager.updateTabVersion(tab.id, code),
      // Navigating from inside a tab (« Livres » pill, ‹ › arrows) moves *this*
      // tab instead of spawning one — only the strip's ＋ adds a tab. Opening
      // from the Accueil screen or from search still uses openReading.
      onOpenChapter: (bookIndex, chapter) =>
          _manager.replaceActiveReading(bookIndex, chapter),
    );
  }
}

/// A home ("new tab") page: the reading action bar with a navigation hint.
///
/// Picking a book here fills *this* tab instead of opening another one — the
/// empty « Nouvel onglet » added by the ＋ is exactly the tab the reader means
/// to fill, like typing a URL in a blank Chrome tab.
class _HomeTab extends StatelessWidget {
  final TabManager manager;
  final VoidCallback? onOpenLibrary;
  const _HomeTab({required this.manager, this.onOpenLibrary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(title: const Text('BYM')),
      body: Column(
        children: [
          _HomeActionsBar(
            onOpenChapter: (bookIndex, chapter) =>
                manager.replaceActiveReading(bookIndex, chapter),
            onOpenLibrary: onOpenLibrary,
          ),
          const Expanded(child: _EmptyReadingHint()),
        ],
      ),
    );
  }
}

/// Empty state (no open tabs): the reading action bar alone on top (the
/// reference pill reads « Livres » and opens the books sheet; the verse
/// chevron stays disabled without a chapter) over a navigation hint.
///
/// No AppBar here: the bar *is* the navigation surface, and the ＋ button that
/// adds a « Nouvel onglet » lives in the [TabStrip], which appears as soon as
/// the first tab opens.
class _NewTabHome extends StatelessWidget {
  final TabManager manager;
  final VoidCallback? onOpenLibrary;
  const _NewTabHome({required this.manager, this.onOpenLibrary});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _HomeActionsBar(
              onOpenChapter: (bookIndex, chapter) =>
                  manager.openReading(bookIndex, chapter),
              onOpenLibrary: onOpenLibrary,
            ),
            const Expanded(child: _EmptyReadingHint()),
          ],
        ),
      ),
    );
  }
}

/// The reading bar of a tab that holds no chapter yet.
///
/// It exists because the plain [ReaderActionsBar] defaults `installedVersions`
/// to `const {}`, and the two home pages used to take that default: the sheet
/// read every downloaded translation as absent and answered « à télécharger
/// depuis la Bibliothèque » for versions sitting on the device.
///
/// Picking a version here **records it for the next chapter** rather than
/// refusing for lack of one to switch. `ChapterReader` reads the same
/// preference at `initState`, so choosing the version and then the book — the
/// order the pills are laid out in — opens straight into it.
class _HomeActionsBar extends StatefulWidget {
  final void Function(int bookIndex, int chapter) onOpenChapter;
  final VoidCallback? onOpenLibrary;

  const _HomeActionsBar({required this.onOpenChapter, this.onOpenLibrary});

  @override
  State<_HomeActionsBar> createState() => _HomeActionsBarState();
}

class _HomeActionsBarState extends State<_HomeActionsBar> {
  final LibraryStore _library = LibraryStore();
  AppPreferences? _prefs;
  Map<String, InstalledVersion> _installed = const {};

  /// BYM until the preferences answer — the same default the reader shows.
  String get _versionCode =>
      _prefs?.versionCode ?? VersionRepository.embeddedCode;

  @override
  void initState() {
    super.initState();
    _load();
    // A home tab also survives in the shell's IndexedStack: without this it
    // would keep the registry as it stood when the tab was created.
    LibraryStore.revision.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.load();
    final installed = await _installedVersions();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _installed = installed;
    });
  }

  Future<void> _onLibraryChanged() async {
    final installed = await _installedVersions();
    if (!mounted) return;
    setState(() => _installed = installed);

    // The recorded version just lost its files — the reader would fall back to
    // BYM on the next chapter anyway, so say so here rather than keep a pill
    // pointing at nothing.
    final code = _versionCode;
    if (code != VersionRepository.embeddedCode &&
        installed[code]?.isEmpty != false) {
      _selectVersion(VersionRepository.embeddedCode);
    }
  }

  Future<Map<String, InstalledVersion>> _installedVersions() async {
    try {
      return await _library.installed();
    } catch (_) {
      // No registry available → the bar offers the embedded BYM alone.
      return const {};
    }
  }

  void _selectVersion(String code) {
    final prefs = _prefs;
    if (prefs == null || prefs.versionCode == code) return;
    setState(() => prefs.versionCode = code);
    prefs.save();
  }

  @override
  Widget build(BuildContext context) {
    return ReaderActionsBar(
      versionCode: _versionCode,
      installedVersions: _installed,
      onSelectVersion: _selectVersion,
      onOpenChapter: widget.onOpenChapter,
      onOpenLibrary: widget.onOpenLibrary,
      onVerses: null,
    );
  }
}

/// Placeholder shown under the reading action bar when no chapter is open:
/// invites the reader to pick a book through the « Livres » pill above.
class _EmptyReadingHint extends StatelessWidget {
  const _EmptyReadingHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Ouvrez le sélecteur « Livres » ci-dessus pour commencer '
              'la lecture.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}