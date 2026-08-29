import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import 'premium_style.dart';

/// The text display — size, typeface, alignment — of the fiche screens
/// (dictionaries, Strong, Notes BYM Lexique…).
///
/// It is deliberately separate from the reader's preferences: « la taille du
/// texte » des fiches vit sous les clés `fiche.*`, la lecture garde les siennes.
/// [FichePreferences.revision] carries each change to the scopes already on
/// screen.
class FicheTextStyle {
  final double fontSize;

  /// Typeface family from [ReadingFont]; never null, and always a family
  /// embedded in `pubspec.yaml` — the reading fonts no longer offer the
  /// platform `sans-serif`, whose rendering varied from device to device.
  final String? fontFamily;
  final TextAlign align;

  const FicheTextStyle(this.fontSize, this.fontFamily, this.align);
}

/// Which preference family a scope reads and writes — each screen family
/// keeps its own size / alignment / typeface.
enum DisplayGroup {
  /// Dictionaries, Westphal, Notes BYM Lexique (`fiche.*`).
  fiches,

  /// Strong fiche and verse study (`etude.*`).
  etude,
}

Future<FicheTextStyle> _read(DisplayGroup group) async {
  switch (group) {
    case DisplayGroup.fiches:
      final p = await FichePreferences.load();
      return FicheTextStyle(p.fontSize, p.readingFont.fontFamily, p.textAlign.align);
    case DisplayGroup.etude:
      final p = await EtudePreferences.load();
      return FicheTextStyle(p.fontSize, p.readingFont.fontFamily, p.textAlign.align);
  }
}

Future<void> _write(
  DisplayGroup group,
  FicheTextStyle style,
  ReadingFont font,
) async {
  switch (group) {
    case DisplayGroup.fiches:
      final p = await FichePreferences.load();
      p.fontSize = style.fontSize;
      p.textAlign = _alignOf(style);
      p.readingFont = font;
      await p.save();
      return;
    case DisplayGroup.etude:
      final p = await EtudePreferences.load();
      p.fontSize = style.fontSize;
      p.textAlign = _alignOf(style);
      p.readingFont = font;
      await p.save();
      return;
  }
}

ReadingTextAlign _alignOf(FicheTextStyle style) => ReadingTextAlign.values
    .firstWhere((a) => a.align == style.align, orElse: () => ReadingTextAlign.left);

ValueNotifier<int> _revisionOf(DisplayGroup group) => switch (group) {
      DisplayGroup.fiches => FichePreferences.revision,
      DisplayGroup.etude => EtudePreferences.revision,
    };

typedef FicheTextBuilder = Widget Function(
  BuildContext context,
  FicheTextStyle style,
);

/// Loads the display preferences once and rebuilds its [builder] whenever
/// they change — through this screen's own menu or any other surface.
///
/// Wrap the whole [Scaffold]: the builder styles both the article body and
/// the AppBar's [FicheDisplayMenuButton].
class FicheTextScope extends StatefulWidget {
  final FicheTextBuilder builder;

  /// Which settings family this screen owns.
  final DisplayGroup group;

  const FicheTextScope({
    super.key,
    required this.builder,
    this.group = DisplayGroup.fiches,
  });

  @override
  State<FicheTextScope> createState() => _FicheTextScopeState();
}

class _FicheTextScopeState extends State<FicheTextScope> {
  FicheTextStyle? _style;

  @override
  void initState() {
    super.initState();
    _load();
    _revisionOf(widget.group).addListener(_load);
  }

  @override
  void dispose() {
    _revisionOf(widget.group).removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final style = await _read(widget.group);
    if (!mounted) return;
    setState(() => _style = style);
  }

  @override
  Widget build(BuildContext context) {
    // Defaults until the preferences answer — one frame, and the same values
    // as a fresh install. La famille suit le défaut de [FichePreferences] :
    // codée en dur, elle rendait cette frame dans la police système.
    return widget.builder(
      context,
      _style ??
          FicheTextStyle(
            ReadingTextSize.medium.fontSize,
            ReadingFont.jakarta.fontFamily,
            TextAlign.left,
          ),
    );
  }
}

/// The ⋮ AppBar action opening the display sheet of a fiche.
class FicheDisplayMenuButton extends StatelessWidget {
  /// Which settings family this button drives.
  final DisplayGroup group;

  const FicheDisplayMenuButton({super.key, this.group = DisplayGroup.fiches});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Affichage',
      icon: const Icon(Icons.more_vert),
      onPressed: () => showFicheDisplaySheet(context, group: group),
    );
  }
}

/// Opens the display sheet of [group]: size / alignment / typeface over its
/// own keys (`fiche.*`, or `etude.*` for the study screens).
Future<void> showFicheDisplaySheet(
  BuildContext context, {
  DisplayGroup group = DisplayGroup.fiches,
}) async {
  final initial = await _read(group);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _FicheDisplaySheet(initial: initial, group: group),
  );
}

class _FicheDisplaySheet extends StatefulWidget {
  final FicheTextStyle initial;
  final DisplayGroup group;

  const _FicheDisplaySheet({required this.initial, required this.group});

  @override
  State<_FicheDisplaySheet> createState() => _FicheDisplaySheetState();
}

class _FicheDisplaySheetState extends State<_FicheDisplaySheet> {
  late double _fontSize = widget.initial.fontSize;
  late ReadingTextAlign _align = ReadingTextAlign.values.firstWhere(
    (a) => a.align == widget.initial.align,
    orElse: () => ReadingTextAlign.left,
  );
  late ReadingFont _font;

  @override
  void initState() {
    super.initState();
    _font = ReadingFont.values.firstWhere(
      (f) => f.fontFamily == widget.initial.fontFamily,
      orElse: () => ReadingFont.jakarta,
    );
  }

  Future<void> _apply() async {
    await _write(
      widget.group,
      FicheTextStyle(_fontSize, _font.fontFamily, _align.align),
      _font,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DisplaySettingsSheetLayout(
      children: [
        DisplaySizeSection(
          fontSize: _fontSize,
          onChanged: (value) {
            setState(() => _fontSize = value);
            _apply();
          },
        ),
        const SizedBox(height: 16),
        DisplayAlignSection(
          align: _align,
          onChanged: (value) {
            setState(() => _align = value);
            _apply();
          },
        ),
        const SizedBox(height: 16),
        DisplayFontSection(
          font: _font,
          onChanged: (value) {
            setState(() => _font = value);
            _apply();
          },
        ),
      ],
    );
  }
}

/// The common chrome of every display sheet: title, scroll-safe bottom inset,
/// and the section column. Shared by the fiche sheet and the reader's ⋯ sheet.
class DisplaySettingsSheetLayout extends StatelessWidget {
  final List<Widget> children;

  /// When provided, a ✕ button rides the « Affichage » title line — the exit
  /// stays visible at the top of the sheet without stealing its own row from
  /// the content.
  final VoidCallback? onClose;

  const DisplaySettingsSheetLayout({
    super.key,
    required this.children,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final titleStyle = premiumText(context, 17, FontWeight.w800, p.textDark);
    final Widget header = onClose == null
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text('Affichage', style: titleStyle),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('Affichage', style: titleStyle)),
                IconButton(
                  key: const ValueKey('display-sheet-close'),
                  tooltip: 'Fermer',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        // Scrollable rather than a bare Column: on a small phone (or the
        // reader's sheet, which also carries the notes rows) the sections
        // together can outgrow the surface.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              ...children,
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// The size ladder as one row of preview chips — an « A » drawn at the size it
/// selects (capped so « géant » fits). [sizes] lets the reader offer only its
/// large-print steps while the fiches list them all.
class DisplaySizeSection extends StatelessWidget {
  final double fontSize;

  /// Which steps to offer; defaults to every one of them.
  final List<ReadingTextSize> sizes;
  final ValueChanged<double> onChanged;

  const DisplaySizeSection({
    super.key,
    required this.fontSize,
    required this.onChanged,
    this.sizes = ReadingTextSize.values,
  });

  @override
  Widget build(BuildContext context) {
    final current = ReadingTextSize.nearest(fontSize);
    return DisplayCard(
      label: 'Taille du texte',
      icon: Icons.format_size,
      child: Row(
        mainAxisAlignment:
            sizes.length > 4 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
        children: [
          for (final size in sizes) ...[
            if (sizes.length <= 4) const SizedBox(width: 6),
            _SizeChip(
              size: size,
              selected: current == size,
              onTap: () => onChanged(size.fontSize),
            ),
          ],
        ],
      ),
    );
  }
}

/// The four alignments as icon chips.
class DisplayAlignSection extends StatelessWidget {
  final ReadingTextAlign align;
  final ValueChanged<ReadingTextAlign> onChanged;

  const DisplayAlignSection({
    super.key,
    required this.align,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Alignement',
      icon: Icons.format_align_left,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final option in ReadingTextAlign.values)
            _AlignChip(
              option: option,
              selected: option == align,
              onTap: () => onChanged(option),
            ),
        ],
      ),
    );
  }
}

/// The typefaces as choice chips, each previewed in its own family.
class DisplayFontSection extends StatelessWidget {
  final ReadingFont font;
  final ValueChanged<ReadingFont> onChanged;

  const DisplayFontSection({
    super.key,
    required this.font,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Police',
      icon: Icons.font_download,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final candidate in ReadingFont.values)
            _FontChip(
              font: candidate,
              selected: candidate == font,
              onTap: () => onChanged(candidate),
            ),
        ],
      ),
    );
  }
}

/// The card every display section lives in: rounded, tinted one step denser
/// than the sheet, hairline border and a soft shadow — the premium language
/// of the settings cards, applied to the display sheets. The label rides the
/// card with its own small icon.
class DisplayCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;

  const DisplayCard({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.primary.withValues(alpha: .14)),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: .05,
          blur: 10,
          offset: const Offset(0, 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: p.primary),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: premiumText(
                  context,
                  11,
                  FontWeight.w700,
                  p.textGrey,
                  spacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// A whole-card toggle row — icon tile, title + subtitle, switch — used for
/// modes rather than styling dials (the reader's immersion).
class DisplayToggleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const DisplayToggleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.primary.withValues(alpha: .14)),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: .05,
          blur: 10,
          offset: const Offset(0, 4),
        ),
      ),
      child: Row(
        children: [
          // The icon + texts toggle too — a bare switch is a small target,
          // and the historical SwitchListTile made the whole row tappable.
          Expanded(
            child: InkWell(
              onTap: () => onChanged(!value),
              borderRadius: BorderRadius.circular(11),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, size: 20, color: p.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: premiumText(
                            context,
                            14,
                            FontWeight.w700,
                            p.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: premiumText(context, 11.5, FontWeight.w500,
                              p.textGrey, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SizeChip extends StatelessWidget {
  final ReadingTextSize size;
  final bool selected;
  final VoidCallback onTap;

  const _SizeChip({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Drawn at the size it selects, capped so « géant » fits the row.
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 44,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.primary.withValues(alpha: .14) : null,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? p.primary : p.textGrey.withValues(alpha: .35),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Tooltip(
          message: 'Taille du texte ${size.label}',
          child: Text(
            'A',
            style: TextStyle(
              fontSize: size.fontSize > 24 ? 24 : size.fontSize,
              fontWeight: FontWeight.w700,
              color: selected ? p.primary : p.textDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _AlignChip extends StatelessWidget {
  final ReadingTextAlign option;
  final bool selected;
  final VoidCallback onTap;

  const _AlignChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon => switch (option) {
        ReadingTextAlign.left => Icons.format_align_left,
        ReadingTextAlign.center => Icons.format_align_center,
        ReadingTextAlign.right => Icons.format_align_right,
        ReadingTextAlign.justify => Icons.format_align_justify,
      };

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return IconButton(
      tooltip: 'Aligner ${option.label}',
      isSelected: selected,
      icon: Icon(_icon),
      selectedIcon: Icon(_icon),
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor:
            selected ? p.primary.withValues(alpha: .14) : Colors.transparent,
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  final ReadingFont font;
  final bool selected;
  final VoidCallback onTap;

  const _FontChip({
    required this.font,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return FilterChip(
      label: Text(
        font.label,
        style: TextStyle(
          fontFamily: font.fontFamily,
          color: selected ? p.primary : p.textDark,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      side: BorderSide(
        color: selected ? p.primary : p.textGrey.withValues(alpha: .35),
      ),
      backgroundColor: Colors.transparent,
      selectedColor: p.primary.withValues(alpha: .14),
    );
  }
}
