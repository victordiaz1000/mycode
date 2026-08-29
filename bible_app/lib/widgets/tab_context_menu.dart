import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/tab_manager.dart';
import '../models/tab_group.dart';
import 'premium_style.dart';

/// Opens the ⋯ / long-press context menu of the tab at [tabIndex]
/// (maquette v2): épingler · dupliquer · ajouter au groupe… · fermer.
///
/// Shared by the switcher cards and the strip chips so both surfaces offer
/// exactly the same actions.
Future<void> showTabContextMenu(
  BuildContext context,
  TabManager manager,
  int tabIndex,
) {
  final tab = manager.tabs[tabIndex];
  final p = premiumPalette(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: p.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Text(tab.isReading ? '❧' : '⌂',
                    style: TextStyle(color: p.primary, fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        premiumText(sheetContext, 13, FontWeight.w800, p.textDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _MenuItem(
            icon: tab.pinned ? Icons.push_pin_outlined : Icons.push_pin,
            label: tab.pinned ? "Désépingler l'onglet" : "Épingler l'onglet",
            onTap: () {
              manager.togglePin(tabIndex);
              Navigator.of(sheetContext).pop();
            },
          ),
          _MenuItem(
            icon: Icons.copy_rounded,
            label: 'Dupliquer',
            onTap: () {
              manager.duplicate(tabIndex);
              Navigator.of(sheetContext).pop();
            },
          ),
          _MenuItem(
            icon: Icons.folder_copy_outlined,
            label: 'Ajouter au groupe…',
            onTap: () {
              Navigator.of(sheetContext).pop();
              showGroupPicker(context, manager, tabIndex);
            },
          ),
          Divider(height: 10, thickness: 1, color: p.textGrey.withValues(alpha: .18)),
          _MenuItem(
            icon: Icons.close,
            label: "Fermer l'onglet",
            destructive: true,
            onTap: () {
              manager.close(tabIndex);
              Navigator.of(sheetContext).pop();
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Second level of the context menu (maquette v2 « cmGroups »): pick an
/// existing group, create one, or leave the current group.
Future<void> showGroupPicker(
  BuildContext context,
  TabManager manager,
  int tabIndex,
) {
  final tab = manager.tabs[tabIndex];
  return showModalBottomSheet(
    context: context,
    backgroundColor: premiumPalette(context).surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => ListenableBuilder(
      listenable: manager,
      builder: (listened, _) {
        final p = premiumPalette(listened);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('AJOUTER AU GROUPE',
                      style: premiumText(
                          listened, 10.5, FontWeight.w800, p.textGrey,
                          spacing: .2)),
                ),
              ),
              for (final group in manager.groups.where((g) =>
                  manager.tabs.any((t) => t.groupId == g.id)))
                _MenuItem(
                  leading: _ColorDot(color: group.color.color),
                  icon: null,
                  label: group.name,
                  trailing: tab.groupId == group.id ? Icons.check : null,
                  onTap: () {
                    manager.assignTabToGroup(tabIndex, group.id);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              if (!manager.groups.any(
                  (g) => manager.tabs.any((t) => t.groupId == g.id)))
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Aucun groupe pour l\'instant',
                      style: premiumText(listened, 12, FontWeight.w600, p.textGrey),
                    ),
                  ),
                ),
              Divider(
                  height: 10, thickness: 1, color: p.textGrey.withValues(alpha: .18)),
              if (tab.groupId != null)
                _MenuItem(
                  icon: Icons.folder_off_outlined,
                  label: 'Retirer du groupe',
                  onTap: () {
                    manager.assignTabToGroup(tabIndex, null);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              _MenuItem(
                icon: Icons.add,
                label: 'Nouveau groupe…',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  showGroupEditor(context, manager,
                      onCreate: (name, color) {
                    final group = manager.createGroup(name: name, color: color);
                    manager.assignTabToGroup(tabIndex, group.id);
                  });
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// Name + color dialog (maquette v2 « gdialog »). Used to create a new group
/// ([onCreate]) or to rename/recolor an existing one ([group]).
Future<void> showGroupEditor(
  BuildContext context,
  TabManager manager, {
  void Function(String name, TabGroupColor color)? onCreate,
  TabGroup? group,
}) {
  final p = premiumPalette(context);
  final nameController = TextEditingController(text: group?.name ?? '');
  var selected = group?.color ?? TabGroupColor.bleu;

  return showDialog(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        backgroundColor: p.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(group == null ? 'NOUVEAU GROUPE' : 'MODIFIER LE GROUPE',
            style: premiumText(dialogContext, 11.5, FontWeight.w800, p.primary,
                spacing: .2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              maxLength: 26,
              decoration: InputDecoration(
                hintText: 'Nom du groupe',
                counterText: '',
                filled: true,
                fillColor: p.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              style: premiumText(dialogContext, 13.5, FontWeight.w600, p.textDark),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final c in TabGroupColor.values)
                  Tooltip(
                    message: c.label,
                    child: GestureDetector(
                      onTap: () => setDialogState(() => selected = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: c.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected == c
                                ? p.textDark
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Annuler',
                style: premiumText(dialogContext, 13, FontWeight.w700, p.textGrey)),
          ),
          TextButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              HapticFeedback.selectionClick();
              if (group != null) {
                manager.renameGroup(group.id, name);
                manager.setGroupColor(group.id, selected);
              } else {
                onCreate?.call(name, selected);
              }
              Navigator.of(dialogContext).pop();
            },
            child: Text(group == null ? 'Créer' : 'Enregistrer',
                style: premiumText(dialogContext, 13, FontWeight.w800, p.primary)),
          ),
        ],
      ),
    ),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  final Widget? leading;
  final IconData? trailing;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final tint = destructive ? TabGroupColor.rouge.color : p.textDark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            leading ??
                Icon(icon, size: 19, color: destructive ? tint : p.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: premiumText(context, 12.5, FontWeight.w700, tint)),
            ),
            if (trailing != null) Icon(trailing, size: 17, color: p.primary),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Vibration + visual acknowledgement before a context menu opens
/// (maquette v2: appui long ≈ 0,48 s). Call from every long-press handler.
void hapticMenuPulse() {
  HapticFeedback.mediumImpact();
}
