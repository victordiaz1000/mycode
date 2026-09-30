import 'package:flutter/material.dart';

import '../data/tab_manager.dart';
import '../models/study_tab.dart';
import '../models/tab_group.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/premium_style.dart';
import '../widgets/tab_context_menu.dart';

/// Full-screen card switcher (maquette v2): grouped sections (named, colored,
/// collapsible), a "Fermés récemment" queue, and bottom actions
/// (Accueil / + / Tout fermer). Long-press or ⋯ on a card opens the shared
/// context menu.
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
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        // Velours d'accent : le même voile qui ancre les AppBars de Favoris,
        // Notes et Historique. L'écran passe de « page nue » à surface
        // habillée sans que rien ne bouge.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                p.primary.withValues(alpha: .12),
                p.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${manager.count} onglet${manager.count > 1 ? 's' : ''}',
              style: premiumText(context, 15, FontWeight.w800, p.textDark),
            ),
            Text(
              'mémorisés en local',
              style: premiumText(
                context,
                9.5,
                FontWeight.w600,
                p.textGrey,
                spacing: .14,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                backgroundColor: p.primarySoft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              child: Text(
                'Terminé',
                style: premiumText(context, 13, FontWeight.w800, p.primary),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final liveSections = <_Section>[
            for (final group in manager.groups)
              if (manager.tabs.any((t) => t.groupId == group.id))
                _Section(group: group, tabs: _pinnedFirst(manager.tabs.where((t) => t.groupId == group.id))),
            if (manager.tabs.any((t) => t.groupId == null))
              _Section(
                  group: null,
                  tabs:
                      _pinnedFirst(manager.tabs.where((t) => t.groupId == null))),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            children: [
              for (final section in liveSections)
                _GroupSection(manager: manager, section: section),
              if (manager.recentlyClosed.isNotEmpty) _Recently(manager: manager),
            ],
          );
        },
      ),
      // Barre d'action en « dock » : la rangée flottait à nu sur le crème,
      // elle prend une coque premium et son filet d'accroche — le même
      // registre que le panneau de la feuille d'étude.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
          child: DecoratedBox(
            // `DecoratedBox` et non `Container` : la coque n'est pas une
            // carte, elle ne doit pas entrer dans le repérage « gold border ».
            decoration: premiumSurface(context, radius: 24, depth: 1.0),
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 34,
                  right: 34,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          p.primary.withValues(alpha: 0),
                          p.primary.withValues(alpha: 0.6),
                          p.primary.withValues(alpha: 0),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  static List<StudyTab> _pinnedFirst(Iterable<StudyTab> tabs) {
    final list = tabs.toList();
    list.sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0));
    return list;
  }
}

class _Section {
  final TabGroup? group;
  final List<StudyTab> tabs;

  const _Section({required this.group, required this.tabs});
}

/// A collapsible group section (maquette v2 « g-head »): color dot, editable
/// name, member count, ✕ to close the whole group, chevron to fold.
class _GroupSection extends StatelessWidget {
  final TabManager manager;
  final _Section section;

  const _GroupSection({required this.manager, required this.section});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final group = section.group;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: group == null ? 8 : 14, bottom: 2),
          child: group == null
              // Intertitre de section : le filet d'accent des autres écrans,
              // puis le libellé exact tel quel (« Sans groupe »).
              ? Row(
                  children: [
                    Container(
                      width: 4,
                      height: 13,
                      decoration: BoxDecoration(
                        color: p.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sans groupe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                          context,
                          9.5,
                          FontWeight.w800,
                          p.textGrey,
                          spacing: .22,
                        ),
                      ),
                    ),
                  ],
                )
              : _GroupHeader(manager: manager, group: group),
        ),
        if (group?.collapsed ?? false)
          const SizedBox.shrink()
        else
          _CardGrid(manager: manager, tabs: section.tabs),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final TabManager manager;
  final TabGroup group;

  const _GroupHeader({required this.manager, required this.group});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final memberCount =
        manager.tabs.where((t) => t.groupId == group.id).length;
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration:
              BoxDecoration(color: group.color.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => showGroupEditor(context, manager, group: group),
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: premiumText(context, 12, FontWeight.w800, p.textDark),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          // Pastille d'accent (et non un gris de texte) : le compteur devient
          // un repère de section, comme les puces de l'Accueil.
          decoration: BoxDecoration(
            color: p.primarySoft,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text('$memberCount',
              style: premiumText(context, 10, FontWeight.w800, p.primary)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Fermer le groupe',
          onPressed: () => manager.closeGroup(group.id),
          icon: Icon(Icons.close, size: 15, color: p.textGrey),
        ),
        InkWell(
          onTap: () => manager.toggleGroupCollapsed(group.id),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AnimatedRotation(
              turns: group.collapsed ? -.25 : 0,
              duration: const Duration(milliseconds: 220),
              child: Icon(Icons.expand_more,
                  size: 15, color: p.textGrey),
            ),
          ),
        ),
      ],
    );
  }
}

class _CardGrid extends StatelessWidget {
  final TabManager manager;
  final List<StudyTab> tabs;

  const _CardGrid({required this.manager, required this.tabs});

  @override
  Widget build(BuildContext context) {
    int originalIndexOf(StudyTab t) =>
        manager.tabs.indexWhere((x) => x.id == t.id);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 7),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.8,
      ),
      itemCount: tabs.length,
      itemBuilder: (context, i) {
        final tab = tabs[i];
        return _SwitcherCard(
            manager: manager, tab: tab, index: originalIndexOf(tab));
      },
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

  void _openMenu(BuildContext context) {
    hapticMenuPulse();
    showTabContextMenu(context, manager, index);
  }

  @override
  Widget build(BuildContext context) {
    final bibleTheme = BibleThemeScope.of(context);
    final p = premiumPalette(context);
    final active = manager.activeIndex == index;
    final groupName = manager.groupById(tab.groupId)?.name;
    return GestureDetector(
      onLongPress: () => _openMenu(context),
      onTap: () {
        manager.activate(index);
        Navigator.of(context).pop();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: active
                // Onglet courant : le bord d'accent est assumé — c'est un
                // marqueur d'état, verrouillé par le test « gold border » —
                // doublé d'un halo. Le fond passe de l'aplat `p.surface` au
                // voile `premiumSurface` + une ombre large : l'onglet courant
                // se détache comme une carte surélevée, pas comme un cadre.
                ? premiumSurface(context, radius: 20, depth: 1.1).copyWith(
                    border: Border.all(color: bibleTheme.highlightRef, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color:
                            bibleTheme.highlightRef.withValues(alpha: 0.38),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                      ...premiumShadow(
                        p.primaryDark,
                        opacity: 0.12,
                        blur: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  )
                // Les autres onglets : surface premium, liseré neutre, deux
                // ombres (la grande ambiante, la serrée du contact).
                : premiumSurface(context, radius: 20, depth: 0.9),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 4, 6),
                  child: Row(
                    children: [
                      Text(
                        tab.isReading ? '❧' : '⌂',
                        style: TextStyle(color: p.primary, fontSize: 13),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          tab.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: premiumText(
                            context,
                            11.5,
                            FontWeight.w800,
                            p.textDark,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _openMenu(context),
                        borderRadius: BorderRadius.circular(7),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(Icons.more_horiz,
                              size: 14, color: p.textGrey),
                        ),
                      ),
                      InkWell(
                        onTap: () => manager.close(index),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child:
                              Icon(Icons.close, size: 13, color: p.textGrey),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      // Vignette « page » : lavage d'accent sur l'accueil,
                      // ton creusé sur les lectures, le tout pris dans un
                      // liseré net — l'applat devient une surface habillée.
                      gradient: tab.isHome
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                p.primarySoft,
                                p.primary.withValues(alpha: .05),
                              ],
                            )
                          : null,
                      color: tab.isHome ? null : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: premiumCardBorder(context, opacity: .14),
                      ),
                    ),
                    child: Center(
                      child: tab.isHome
                          ? Text(
                              '⌂',
                              style:
                                  TextStyle(fontSize: 30, color: p.primary),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    tab.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: premiumText(
                                      context,
                                      14,
                                      FontWeight.w700,
                                      p.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (tab.verse != null)
                                    Text('v. ${tab.verse}',
                                        style: premiumText(context, 10,
                                            FontWeight.w700, p.textGrey))
                                  else
                                    Container(
                                      height: 4,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        // Filet d'accent en dégradé, comme la
                                        // règle de section des écrans d'étude.
                                        gradient: p.heroGradient,
                                        borderRadius:
                                            BorderRadius.circular(2),
                                        boxShadow: premiumShadow(
                                          p.primary,
                                          opacity: 0.25,
                                          blur: 6,
                                          offset: const Offset(0, 2),
                                        ),
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
                      Text(
                        tab.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                          context,
                          11,
                          FontWeight.w800,
                          p.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        groupName == null
                            ? 'mémorisé en local'
                            : 'groupe « $groupName »',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                            context, 9, FontWeight.w700, p.textGrey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Pinned marker (maquette « .pin », top-left of the card).
          if (tab.pinned)
            Positioned(
              top: 5,
              left: 5,
              child: Icon(
                Icons.push_pin,
                size: 12,
                color: p.primary,
                // Halo de lisibilité tiré de la palette (plus de blanc codé
                // en dur) : la punaise reste lisible sur le dégradé de carte.
                shadows: [
                  Shadow(color: p.surface, blurRadius: 4),
                ],
              ),
            ),
        ],
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
          top: BorderSide(color: premiumCardBorder(context, opacity: .35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 4,
                    height: 13,
                    decoration: BoxDecoration(
                      color: p.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Fermés récemment',
                    style: premiumText(
                      context,
                      11.5,
                      FontWeight.w800,
                      p.textDark,
                      spacing: .22,
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => manager.clearRecentlyClosed(),
                child: Text(
                  'Vider',
                  style: premiumText(context, 11, FontWeight.w700, p.textGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final tab in manager.recentlyClosed)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: premiumSurface(context, radius: 14, depth: 0.6),
              child: Row(
                children: [
                  Text('❧', style: TextStyle(color: p.primary, fontSize: 13)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: premiumText(
                        context,
                        11.5,
                        FontWeight.w600,
                        p.textDark,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => manager.reopen(),
                    borderRadius: BorderRadius.circular(9),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 5,
                      ),
                      // Pastille en dégradé + halo : « Rouvrir » rejoint la
                      // même famille que le « + » doré du bas.
                      decoration: BoxDecoration(
                        gradient: p.heroGradient,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: premiumShadow(
                          p.primary,
                          opacity: 0.30,
                          blur: 10,
                          offset: const Offset(0, 4),
                        ),
                      ),
                      child: Text(
                        'Rouvrir',
                        style: TextStyle(
                          color: p.onPrimary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
        color: Colors.transparent,
        elevation: 0,
        child: Ink(
          decoration: premiumSurface(context, radius: 16, depth: 0.6),
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
            boxShadow: premiumShadow(
              p.primary,
              opacity: 0.35,
              blur: 14,
              offset: const Offset(0, 6),
            ),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(Icons.add, color: p.onPrimary, size: 28),
            ),
          ),
        ),
      ),
    );
  }
}
