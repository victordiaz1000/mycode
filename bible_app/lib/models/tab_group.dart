import 'package:flutter/material.dart';

/// The six group colors offered by the maquette v2 (bleu · rouge · or · vert ·
/// violet · rose), stored as an index so the palette can evolve without
/// rewriting persisted JSON.
enum TabGroupColor {
  bleu(0xFF4A7FD4),
  rouge(0xFFD4574A),
  or(0xFFD9A441),
  vert(0xFF5C9A68),
  violet(0xFF8A6BC9),
  rose(0xFFCF6A9F);

  const TabGroupColor(this.value);
  final int value;

  Color get color => Color(value);

  /// French label, shown next to the color dots of the group dialog.
  String get label => switch (this) {
        TabGroupColor.bleu => 'bleu',
        TabGroupColor.rouge => 'rouge',
        TabGroupColor.or => 'or',
        TabGroupColor.vert => 'vert',
        TabGroupColor.violet => 'violet',
        TabGroupColor.rose => 'rose',
      };

  static TabGroupColor fromIndex(int? index) =>
      (index != null && index >= 0 && index < TabGroupColor.values.length)
          ? TabGroupColor.values[index]
          : TabGroupColor.bleu;

  int get index0 => TabGroupColor.values.indexOf(this);
}

/// A named, colored group of study tabs (maquette v2 — gestion d'onglets).
///
/// A group only exists while its members do: closing every tab sends them to
/// the recently-closed queue, whose entries keep their group id, so the group
/// is recreated on restore and dissolved otherwise.
class TabGroup {
  final String id;
  String name;
  TabGroupColor color;

  /// Whether the section is folded in the switcher.
  bool collapsed;

  TabGroup({
    required this.id,
    required this.name,
    this.color = TabGroupColor.bleu,
    this.collapsed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.index0,
        'collapsed': collapsed,
      };

  factory TabGroup.fromJson(Map<String, dynamic> json) => TabGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        color: TabGroupColor.fromIndex(json['color'] as int?),
        collapsed: json['collapsed'] as bool? ?? false,
      );
}
