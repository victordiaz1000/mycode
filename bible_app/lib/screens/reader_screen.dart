import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/library_store.dart';
import '../data/reading_history.dart';
import '../data/tab_manager.dart';
import '../data/version_repository.dart';
import '../models/study_tab.dart';
import '../widgets/bym_update_banner.dart';
import '../widgets/chapter_reader.dart';
import '../widgets/premium_style.dart';
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

  /// Opens a Bible reference tapped inside a reading note (book, chapter,
  /// verse) — the shell jumps the reading to it. Null keeps the reader's own
  /// fallback (open the chapter, verse lost) for standalone use.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  /// Où conduit le bandeau « Mettre à jour le texte BYM » : la section de
  /// Réglages, seul endroit qui décide d'un téléchargement. Null en usage isolé
  /// (tests) — le bandeau reste alors une annonce à lire.
  final VoidCallback? onOpenSettings;

  const ReaderScreen({
    super.key,
    this.initialManager,
    this.jumpToVerse,
    this.onOpenLibrary,
    this.onOpenVerse,
    this.onOpenSettings,
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
      builder: (context, _) => ListenableBuilder(
        listenable: AppPreferences.immersionNotifier,
        builder: (context, _) {
          if (!_manager.hasTabs) {
            return _NewTabHome(
              manager: _manager,
              onOpenLibrary: widget.onOpenLibrary,
              onOpenSettings: widget.onOpenSettings,
            );
          }
          final activeIndex = _manager.activeIndex < 0
              ? 0
              : _manager.activeIndex;
          // Immersion hides the strip too — the reader's exit pill brings it
          // back. Without this the tabs stayed as a golden crown over a text
          // that asked to be alone.
          final immersive = AppPreferences.immersionNotifier.value;
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  if (!immersive)
                    TabStrip(
                      manager: _manager,
                      onOpenSwitcher: () => TabSwitcher.show(context, _manager),
                    ),
                  // Sous les onglets, au-dessus du texte : le bandeau annonce la
                  // correction disponible là où le lecteur se trouve. Il ne
                  // s'affiche que si une mise à jour attend, et l'immersion
                  // l'emporte sur lui comme sur le reste du décor.
                  if (!immersive)
                    BymUpdateBanner(onOpenSettings: widget.onOpenSettings),
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
      ),
    );
  }

  Widget _buildTabContent(StudyTab tab) {
    if (tab.isHome) {
      return _HomeTab(
        manager: _manager,
        tab: tab,
        onOpenLibrary: widget.onOpenLibrary,
      );
    }
    return ChapterReader(
      key: ValueKey('reader-${tab.id}-${tab.bookIndex}-${tab.chapter}'),
      bookIndex: tab.bookIndex!,
      chapter: tab.chapter!,
      initialVersionCode: tab.versionCode,
      initialVerse: tab.verse,
      onVerseChanged: (verse) => _manager.updateTabVerse(tab.id, verse),
      jumpToVerse: widget.jumpToVerse,
      onOpenLibrary: widget.onOpenLibrary,
      // The ⋯ sheet's « Tous les réglages » row. Same destination switch as the
      // update banner's: the reading tab stays alive in the shell's IndexedStack,
      // so leaving for Réglages costs no position.
      onOpenSettings: widget.onOpenSettings,
      onVersionChanged: (code) => _manager.updateTabVersion(tab.id, code),
      // Navigating from inside a tab (« Livres » pill, ‹ › arrows) moves *this*
      // tab instead of spawning one — only the strip's ＋ adds a tab. Opening
      // from the Accueil screen or from search still uses openReading.
      onOpenChapter: (bookIndex, chapter) =>
          _manager.replaceActiveReading(bookIndex, chapter),
      // A Bible reference inside a note opens the referenced passage, keeping
      // the verse, through the shell's jump machinery.
      onReferenceTap: widget.onOpenVerse == null
          ? null
          : (ref) => widget.onOpenVerse!(
              ref.bookIndex,
              ref.chapter ?? 1,
              ref.verse ?? 1,
            ),
    );
  }
}

/// A home ("new tab") page: the reading action bar with a navigation hint.
///
/// Picking a book here fills *this* tab instead of opening another one — the
/// empty « Nouvel onglet » added by the ＋ is exactly the tab the reader means
/// to fill, like typing a URL in a blank Chrome tab.
///
/// The version picked here is recorded on the tab, not in the shared
/// preferences: a blank tab is a tab like any other, and its choice must not
/// move the tabs already open (nor be overwritten by them).
class _HomeTab extends StatelessWidget {
  final TabManager manager;
  final StudyTab tab;
  final VoidCallback? onOpenLibrary;
  const _HomeTab({
    required this.manager,
    required this.tab,
    this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBackground(context),
      body: Column(
        children: [
          _HomeActionsBar(
            versionCode: tab.versionCode,
            onSelectVersion: (code) => manager.updateTabVersion(tab.id, code),
            // `replaceActiveReading` keeps the tab's own version, so the order
            // the pills read in — version, then book — opens straight into it.
            onOpenChapter: (bookIndex, chapter) =>
                manager.replaceActiveReading(bookIndex, chapter),
            onOpenLibrary: onOpenLibrary,
          ),
          Expanded(
            child: _EmptyReadingBody(
              onOpenChapter: (bookIndex, chapter) =>
                  manager.replaceActiveReading(bookIndex, chapter),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state (no open tabs): the strip stays put — ＋ and the counter
/// reading « 0 » remain the anchor that opens tabs and the card switcher —
/// over the reading action bar and a navigation hint.
///
/// No AppBar here: the bars *are* the navigation surface.
///
/// The one page with no tab to record a version on, so here — and only here —
/// the « Version de lecture par défaut » preference is the store: it is both
/// what the pill shows and what seeds the tab this page is about to open.
class _NewTabHome extends StatefulWidget {
  final TabManager manager;
  final VoidCallback? onOpenLibrary;
  final VoidCallback? onOpenSettings;
  const _NewTabHome({
    required this.manager,
    this.onOpenLibrary,
    this.onOpenSettings,
  });

  @override
  State<_NewTabHome> createState() => _NewTabHomeState();
}

class _NewTabHomeState extends State<_NewTabHome> {
  AppPreferences? _prefs;

  /// BYM until the preferences answer — the same default the reader shows.
  String _versionCode = VersionRepository.embeddedCode;

  @override
  void initState() {
    super.initState();
    _load();
    // The Réglages screen can move the default while this page sits open.
    AppPreferences.revision.addListener(_load);
  }

  @override
  void dispose() {
    AppPreferences.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _versionCode = prefs.versionCode;
    });
  }

  /// Records the pick as the new default. `save()` bumps the revision, which
  /// calls [_load] back — it reads the very value just written, so the two
  /// paths cannot disagree.
  void _selectVersion(String code) {
    final prefs = _prefs;
    if (prefs == null || code == _versionCode) return;
    setState(() => _versionCode = code);
    prefs.versionCode = code;
    prefs.save();
  }

  /// Opens the first tab in the version the pill names — [TabManager] has no
  /// active tab to inherit from here, and would otherwise fall back to BYM.
  void _openChapter(int bookIndex, int chapter) =>
      widget.manager.openReading(bookIndex, chapter, versionCode: _versionCode);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: premiumBackground(context),
      body: SafeArea(
        child: Column(
          children: [
            // The strip never disappears, even with zero tabs: hiding it made
            // the ＋ / counter vanish without warning after closing the last
            // tab. The switcher opens from here too.
            TabStrip(
              manager: widget.manager,
              onOpenSwitcher: () =>
                  TabSwitcher.show(context, widget.manager),
            ),
            // Même annonce que dans un onglet ouvert : la page sans onglet est
            // aussi la page de lecture, et c'est souvent la première vue au
            // lancement — donc celle qui doit le dire.
            BymUpdateBanner(onOpenSettings: widget.onOpenSettings),
            _HomeActionsBar(
              versionCode: _versionCode,
              onSelectVersion: _selectVersion,
              onOpenChapter: _openChapter,
              onOpenLibrary: widget.onOpenLibrary,
            ),
            Expanded(child: _EmptyReadingBody(onOpenChapter: _openChapter)),
          ],
        ),
      ),
    );
  }
}

/// The reading bar of a tab that holds no chapter yet.
///
/// It exists because the plain [ReaderActionsBar] defaults `installedVersions`
/// to `const {}`, and the two home pages took that default: the sheet read
/// every downloaded translation as absent and answered « à télécharger depuis
/// la Bibliothèque » for versions sitting on the device.
///
/// Where the pick is *recorded* is the caller's business ([versionCode] /
/// [onSelectVersion]): a hosted home tab writes on its tab, the zero-tab home
/// on the default preference. This bar only reads the registry and reports the
/// choice.
class _HomeActionsBar extends StatefulWidget {
  /// Version the pill names — the code the hosting page holds.
  final String versionCode;

  /// Records a version picked in the sheet.
  final ValueChanged<String> onSelectVersion;

  final void Function(int bookIndex, int chapter) onOpenChapter;
  final VoidCallback? onOpenLibrary;

  const _HomeActionsBar({
    required this.versionCode,
    required this.onSelectVersion,
    required this.onOpenChapter,
    this.onOpenLibrary,
  });

  @override
  State<_HomeActionsBar> createState() => _HomeActionsBarState();
}

class _HomeActionsBarState extends State<_HomeActionsBar> {
  final LibraryStore _library = LibraryStore();
  Map<String, InstalledVersion> _installed = const {};

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
    final installed = await _installedVersions();
    if (!mounted) return;
    setState(() => _installed = installed);
  }

  Future<void> _onLibraryChanged() async {
    final installed = await _installedVersions();
    if (!mounted) return;
    setState(() => _installed = installed);

    // The recorded version just lost its files — the reader would fall back to
    // BYM on the next chapter anyway, so say so here rather than keep a pill
    // pointing at nothing.
    final code = widget.versionCode;
    if (code != VersionRepository.embeddedCode &&
        installed[code]?.isEmpty != false) {
      widget.onSelectVersion(VersionRepository.embeddedCode);
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

  @override
  Widget build(BuildContext context) {
    return ReaderActionsBar(
      versionCode: widget.versionCode,
      installedVersions: _installed,
      onSelectVersion: widget.onSelectVersion,
      onOpenChapter: widget.onOpenChapter,
      onOpenLibrary: widget.onOpenLibrary,
      onVerses: null,
    );
  }
}

/// What an empty reading tab shows: the resume banner (last position from the
/// history, if any) above the navigation hint.
class _EmptyReadingBody extends StatelessWidget {
  /// Where resuming goes — fills *this* tab (the same routing the « Livres »
  /// pill above uses).
  final void Function(int bookIndex, int chapter) onOpenChapter;

  const _EmptyReadingBody({required this.onOpenChapter});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ReadingEntry?>(
      future: ReadingHistory().last(),
      builder: (context, snapshot) {
        final entry = snapshot.data;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (entry != null)
              _ResumeCard(entry: entry, onTap: () => onOpenChapter(entry.bookIndex, entry.chapter))
            else
              const _EmptyReadingHint(),
          ],
        );
      },
    );
  }
}

/// « Reprendre Ge. 1 » : the last visited chapter, one tap back into it. The
/// verse-level position is restored by the reader itself (tab persistence).
class _ResumeCard extends StatelessWidget {
  final ReadingEntry entry;
  final VoidCallback onTap;
  const _ResumeCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        // « Premium affirmé » : le liseré **neutre** de la carte, jamais
        // l'accent — un contour doré posé sur le crème tournait au cerne
        // coloré (voir [premiumCardBorder]). Deux ombres : l'ambiante qui
        // décolle la carte, la serrée qui la pose. `surfaceTintColor` = la
        // surface elle-même : le voile Material 3 se fond dans le fond au
        // lieu de le teinter.
        elevation: 1,
        shadowColor: p.primaryDark.withValues(alpha: .14),
        surfaceTintColor: p.surface,
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: premiumCardBorder(context, opacity: .25)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.history_edu, color: p.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reprendre ${entry.label}',
                        style: premiumText(
                          context,
                          15,
                          FontWeight.w800,
                          p.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.bookName,
                        style: premiumText(context, 12, FontWeight.w500, p.textGrey),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: p.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder shown under the reading action bar when no chapter is open:
/// invites the reader to pick a book through the « Livres » pill above.
class _EmptyReadingHint extends StatelessWidget {
  const _EmptyReadingHint();

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: p.primarySoft,
                shape: BoxShape.circle,
                // Le disque teinté garde son aplat d'accent ; on lui ajoute un
                // liseré net et un halo d'accent pour qu'il se détache du fond
                // crème au lieu de fondre dedans.
                border: Border.all(
                  color: premiumCardBorder(context, opacity: .28),
                ),
                boxShadow: premiumShadow(
                  p.primary,
                  opacity: .18,
                  blur: 20,
                  offset: const Offset(0, 8),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.menu_book_outlined, size: 40, color: p.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Ouvrez le sélecteur « Livres » ci-dessus pour commencer '
              'la lecture.',
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                15,
                FontWeight.w600,
                p.textGrey,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
