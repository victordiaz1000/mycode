import 'package:flutter/material.dart';

import '../data/tab_manager.dart';
import '../models/study_tab.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/premium_style.dart';

/// Full-screen card switcher (maquette v1.1): a grid of tab previews, a
/// "Fermés récemment" queue, and bottom actions (Accueil / + / Tout fermer).
///
/// Restyled in the app's premium language (crème, cartes blanches, or) so the
/// selector matches the Accueil, Favoris, Historique and the reading chrome.
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
    final p = premiumPalette(context);
    final pinned =
        manager.tabs.where((t) => t.pinned).toList();
    final unpinned =
        manager.tabs.where((t) => !t.pinned).toList();
    final ordered = [...pinned, ...unpinned];

    int originalIndexOf(StudyTab t) =>
        manager.tabs.indexWhere((x) => x.id == t.id);

    return Scaffold(
      backgroundColor: kPremiumBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${manager.count} onglet${manager.count > 1 ? 's' : ''}',
                style:
                    premiumText(context, 15, FontWeight.w800, p.textDark)),
            Text('mémorisés en local',
                style: premiumText(context, 9.5, FontWeight.w600,
                    p.textGrey,
                    spacing: .14)),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Terminé',
                  style: premiumText(
                      context, 13, FontWeight.w800, p.primary)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.8,
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
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
              _GoldPlus(
                onTap: () {
                  manager.openHome();
                  Navigator.of(context).pop();
                },
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
    final p = premiumPalette(context);
    final active = manager.activeIndex == index;
    return GestureDetector(
      onTap: () {
        manager.activate(index);
        Navigator.of(context).pop();
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? bibleTheme.highlightRef : Colors.transparent,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                      color: bibleTheme.highlightRef.withValues(alpha: 0.38),
                      blurRadius: 14,
                      offset: const Offset(0, 6)),
                ]
              : premiumShadow(p.primaryDark,
                  opacity: 0.07, blur: 16, offset: const Offset(0, 6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 6),
              child: Row(
                children: [
                  Text(tab.isReading ? '❧' : '⌂',
                      style: TextStyle(color: p.primary, fontSize: 13)),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: premiumText(
                          context, 11.5, FontWeight.w800, p.textDark),
                    ),
                  ),
                  InkWell(
                    onTap: () => manager.togglePin(index),
                    child: Icon(
                      tab.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                      size: 14,
                      color: tab.pinned ? p.primary : p.textGrey,
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
                          size: 13, color: p.textGrey),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: tab.isHome
                      ? p.primarySoft
                      : const Color(0xFFF3F1EB),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: tab.isHome
                      ? Text('⌂',
                          style: TextStyle(
                              fontSize: 30, color: p.primary))
                      : Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(tab.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: premiumText(context, 14,
                                      FontWeight.w700, p.textDark)),
                              const SizedBox(height: 8),
                              Container(
                                height: 4,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: p.primary.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: premiumText(
                          context, 11, FontWeight.w800, p.textDark)),
                  const SizedBox(height: 2),
                  Text('mémorisé en local',
                      style: premiumText(
                          context, 9, FontWeight.w700, p.textGrey)),
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
    final p = premiumPalette(context);
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.black.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Fermés récemment',
                  style: premiumText(context, 11.5, FontWeight.w800,
                      p.textDark,
                      spacing: .22)),
              TextButton(
                onPressed: () => manager.clearRecentlyClosed(),
                child: Text('Vider',
                    style: premiumText(
                        context, 11, FontWeight.w700, p.textGrey)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final tab in manager.recentlyClosed)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: premiumShadow(p.primaryDark,
                    opacity: 0.05, blur: 10, offset: const Offset(0, 4)),
              ),
              child: Row(
                children: [
                  Text('❧',
                      style:
                          TextStyle(color: p.primary, fontSize: 13)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                            context, 11.5, FontWeight.w600, p.textDark)),
                  ),
                  InkWell(
                    onTap: () => manager.reopen(),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 5),
                      decoration: BoxDecoration(
                        color: p.primary,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text('Rouvrir',
                          style: TextStyle(
                              color: Colors.white,
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
    final p = premiumPalette(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: premiumShadow(p.primaryDark,
                opacity: 0.06, blur: 12, offset: const Offset(0, 5)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, size: 22, color: p.textDark),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldPlus extends StatelessWidget {
  final VoidCallback onTap;

  const _GoldPlus({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Tooltip(
      message: 'Nouvel onglet',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        elevation: 0,
        child: Ink(
          decoration: BoxDecoration(
            gradient: p.heroGradient,
            shape: BoxShape.circle,
            boxShadow: premiumShadow(p.primary,
                opacity: 0.35, blur: 14, offset: const Offset(0, 6)),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.add, color: Colors.white, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}