import 'package:flutter/material.dart';

import '../data/tab_manager.dart';
import '../models/study_tab.dart';
import '../widgets/bible_theme_scope.dart';

/// Full-screen card switcher (maquette v1.1): a grid of tab previews, a
/// "Fermés récemment" queue, and bottom actions (Accueil / + / Tout fermer).
class TabSwitcher extends StatelessWidget {
  final TabManager manager;

  const TabSwitcher({super.key, required this.manager});

  /// Opens the switcher as a modal overlay and returns the index of the tab
  /// the caller should focus (or -1 / reused commands).
  static Future<void> show(BuildContext context, TabManager manager) {
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, animation, _) => TabSwitcher(manager: manager),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final pinned =
        manager.tabs.where((t) => t.pinned).toList();
    final unpinned =
        manager.tabs.where((t) => !t.pinned).toList();
    final ordered = [...pinned, ...unpinned];

    int originalIndexOf(StudyTab t) =>
        manager.tabs.indexWhere((x) => x.id == t.id);

    return Scaffold(
      backgroundColor: bibleTheme.backgroundAsset.isNotEmpty
          ? bibleTheme.textColor.withValues(alpha: 0.08)
          : Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: bibleTheme.backgroundAsset.isNotEmpty
            ? bibleTheme.textColor.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surface,
        foregroundColor: bibleTheme.titleColor,
        title: Column(
          children: [
            Text('${manager.count} onglet${manager.count > 1 ? 's' : ''}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: bibleTheme.titleColor)),
            Text('mémorisés en local',
                style: TextStyle(
                    fontSize: 9,
                    color: bibleTheme.textColor.withValues(alpha: 0.72),
                    letterSpacing: .14)),
          ],
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Terminé',
                style: TextStyle(color: bibleTheme.titleColor)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) {
                    final tab = ordered[i];
                    final idx = originalIndexOf(tab);
                    return _SwitcherCard(
                      manager: manager,
                      tab: tab,
                      index: idx,
                    );
                  },
                ),
                if (manager.recentlyClosed.isNotEmpty)
                  _Recently(manager: manager),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundAction(
                icon: Icons.home_outlined,
                tooltip: 'Accueil',
                onTap: () {
                  manager.openHome();
                  Navigator.of(context).pop();
                },
              ),
              FloatingActionButton(
                onPressed: () {
                  manager.openHome();
                  Navigator.of(context).pop();
                },
                tooltip: 'Nouvel onglet',
                child: const Icon(Icons.add),
              ),
              _RoundAction(
                icon: Icons.clear_all,
                tooltip: 'Tout fermer',
                onTap: () {
                  manager.closeAll();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitcherCard extends StatelessWidget {
  final TabManager manager;
  final StudyTab tab;
  final int index;

  const _SwitcherCard({
    required this.manager,
    required this.tab,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final active = manager.activeIndex == index;
    return GestureDetector(
      onTap: () {
        manager.activate(index);
        Navigator.of(context).pop();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? bibleTheme.highlightRef : Colors.transparent,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(color: bibleTheme.highlightRef, blurRadius: 8),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Text(tab.isReading ? '❧' : '⌂',
                      style: TextStyle(color: bibleTheme.accentColor)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: bibleTheme.textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  InkWell(
                    onTap: () => manager.togglePin(index),
                    child: Icon(
                      tab.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 14,
                      color: tab.pinned
                          ? bibleTheme.accentColor
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      // Duplicate via long-lived UI is revealed in the menu;
                      // simple ✕ close is kept here.
                      manager.close(index);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: tab.isHome
                      ? Theme.of(context).colorScheme.surfaceContainerHighest
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Center(
                  child: tab.isHome
                      ? Text('⌂',
                          style: TextStyle(
                              fontSize: 30, color: bibleTheme.accentColor))
                      : Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(tab.title,
                                  style: TextStyle(
                                      color: bibleTheme.textColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 6),
                              Container(
                                height: 3.5,
                                width: double.infinity,
                                color: bibleTheme.accentColor.withValues(alpha: 0.33),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: bibleTheme.textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w800)),
                  Text('mémorisé en local',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Recently extends StatelessWidget {
  final TabManager manager;

  const _Recently({required this.manager});

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface.withAlpha(36))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fermés récemment',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .22)),
              TextButton(
                onPressed: () => manager.clearRecentlyClosed(),
                child: Text('Vider',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10)),
              ),
            ],
          ),
          for (final tab in manager.recentlyClosed)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withAlpha(20),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(22)),
              ),
              child: Row(
                children: [
                  Text('❧', style: TextStyle(color: bibleTheme.accentColor)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFFC9D0DF), fontSize: 11)),
                  ),
                  InkWell(
                    onTap: () => manager.reopen(),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 4),
                      decoration: BoxDecoration(
                        color: bibleTheme.accentColor,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('Rouvrir',
                          style: TextStyle(
                              color: bibleTheme.textColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        foregroundColor: theme.colorScheme.onSurface,
      ),
    );
  }
}