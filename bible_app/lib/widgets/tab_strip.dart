import 'package:flutter/material.dart';

import '../data/tab_manager.dart';

/// Compact Chrome-style tab strip (maquette v1.1):
/// scrollable open tabs + a "＋" (new home tab) + a gold counter that opens
/// the [shown switcher].
class TabStrip extends StatelessWidget {
  final TabManager manager;
  final VoidCallback onOpenSwitcher;

  const TabStrip({
    super.key,
    required this.manager,
    required this.onOpenSwitcher,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gold = const Color(0xFFD3A94F);
    return SizedBox(
      height: 56,
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        child: Row(
          children: [
            // Plus → new home tab
            IconButton(
              tooltip: 'Nouvel onglet',
              onPressed: () => manager.openHome(),
              icon: const Icon(Icons.add),
            ),
            const SizedBox(width: 4),
            // Tabs
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                children: [
                  for (var i = 0; i < manager.tabs.length; i++)
                    _TabChip(manager: manager, index: i),
                ],
              ),
            ),
            // Gold counter → opens the switcher
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: Material(
                color: gold,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  onTap: onOpenSwitcher,
                  borderRadius: BorderRadius.circular(9),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      '${manager.count}',
                      style: const TextStyle(
                        color: Color(0xFF241A04),
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

  const _TabChip({required this.manager, required this.index});

  @override
  Widget build(BuildContext context) {
    final tab = manager.tabs[index];
    final active = manager.activeIndex == index;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
      child: Material(
        color: active ? theme.colorScheme.surface : Colors.transparent,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(11)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => manager.activate(index),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 116),
            decoration: active
                ? const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: Color(0xFFD3A94F), width: 2),
                    ),
                  )
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tab.pinned)
                  const Icon(Icons.push_pin,
                      size: 11, color: Color(0xFFD3A94A)),
                Flexible(
                  child: Text(
                    tab.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: active
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => manager.close(index),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 13),
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