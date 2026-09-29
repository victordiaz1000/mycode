import 'package:flutter/material.dart';

import '../data/tab_manager.dart';
import 'bible_theme_scope.dart';
import 'premium_style.dart';
import 'tab_context_menu.dart';

/// Compact Chrome-style tab strip (maquette v1.1):
/// scrollable open tabs + a "＋" (new home tab) + a gold counter that opens
/// the [shown switcher].
class TabStrip extends StatefulWidget {
  final TabManager manager;
  final VoidCallback onOpenSwitcher;

  const TabStrip({
    super.key,
    required this.manager,
    required this.onOpenSwitcher,
  });

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  /// Marks the active chip so the strip can reveal it when a link or the
  /// switcher activates a tab sitting outside the visible range.
  final GlobalKey _activeKey = GlobalKey();

  void _revealActiveTab() {
    final index = widget.manager.activeIndex;
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chipContext = _activeKey.currentContext;
      if (chipContext == null) return;
      final chipBox = chipContext.findRenderObject();
      final viewportBox =
          Scrollable.of(chipContext).context.findRenderObject();
      if (chipBox is! RenderBox || viewportBox is! RenderBox) return;
      final chipLeft = chipBox.localToGlobal(Offset.zero).dx;
      final chipRight = chipLeft + chipBox.size.width;
      final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
      final viewportRight = viewportLeft + viewportBox.size.width;
      // Already fully visible (tap on a shown tab) : no scroll, Chrome-like.
      if (chipLeft >= viewportLeft && chipRight <= viewportRight) return;
      Scrollable.ensureVisible(
        chipContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _revealActiveTab();
  }

  @override
  void didUpdateWidget(covariant TabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _revealActiveTab();
  }

  @override
  Widget build(BuildContext context) {
    final manager = widget.manager;
    final bibleTheme = BibleThemeScope.of(context);
    final p = premiumPalette(context);
    return SizedBox(
      height: 56,
      child: Container(
        // Bandeau dérivé de la palette premium : la teinte M3 `surface…` ne
        // suivait ni le thème biblique ni le fond crème des écrans.
        color: p.surface.withValues(alpha: .60),
        child: Row(
          children: [
            // Plus → new home tab
            IconButton(
              tooltip: 'Nouvel onglet',
              onPressed: () => manager.openHome(),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
            // Tabs — a plain Row (not a lazy ListView) so every chip is
            // built and the active one can always be scrolled into view.
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < manager.tabs.length; i++)
                      _TabChip(
                        manager: manager,
                        index: i,
                        activeKey:
                            i == manager.activeIndex ? _activeKey : null,
                      ),
                  ],
                ),
              ),
            ),
            // Gold counter → opens the switcher
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Material(
                color: bibleTheme.accentColor,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: widget.onOpenSwitcher,
                  borderRadius: BorderRadius.circular(9),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${manager.count}',
                      style: TextStyle(
                        color: bibleTheme.textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final TabManager manager;
  final int index;

  const _TabChip({
    required this.manager,
    required this.index,
    Key? activeKey,
  }) : super(key: activeKey);

  @override
  Widget build(BuildContext context) {
    final tab = manager.tabs[index];
    final active = manager.activeIndex == index;
    final p = premiumPalette(context);
    final bibleTheme = BibleThemeScope.of(context);
    final group = manager.groupById(tab.groupId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: Material(
        color: active
            ? bibleTheme.accentColor.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(11)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => manager.activate(index),
          onLongPress: () {
            hapticMenuPulse();
            showTabContextMenu(context, manager, index);
          },
          child: Container(
            // Width follows the title, capped at 116 like the original strip.
            constraints: const BoxConstraints(maxWidth: 116),
            decoration: active
                ? BoxDecoration(
                    color: bibleTheme.accentColor.withValues(alpha: .12),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                    // Marqueur d'état : le filet d'accent du dessus est doublé
                    // d'un halo discret pour que l'onglet courant se lise même
                    // sur les palettes où l'or se confond avec le crème.
                    boxShadow: [
                      BoxShadow(
                        color: bibleTheme.accentColor.withValues(alpha: .18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                    border: Border(
                      top: BorderSide(
                        color: bibleTheme.accentColor,
                        width: 2,
                      ),
                    ),
                  )
                : BoxDecoration(
                    // Inactive tabs stay visible as tabs: a soft fill,
                    // without a border — dérivée de la même palette que le
                    // bandeau, pour que l'onglet repose dessus.
                    color: p.surface.withValues(alpha: .95),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              // Hugs the content: a short title gives a narrow tab, the ✕
              // sits right after the text (maquette v1.1).
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.pinned)
                  Icon(Icons.push_pin,
                      size: 11, color: bibleTheme.accentColor),
                Flexible(
                  child: Text(
                    tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? bibleTheme.titleColor
                          : p.onSurfaceMuted,
                    ),
                  ),
                ),
                // Group membership dot (maquette v2 « gdot »).
                if (group != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: group.color.color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                InkWell(
                  onTap: () => manager.close(index),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Icon(Icons.close,
                        size: 14, color: p.textGrey),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}