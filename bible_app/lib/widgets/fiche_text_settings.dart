import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import 'bible_theme_scope.dart';
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
    // Fond crème du langage premium, comme les feuilles du lecteur : la
    // feuille prenait par défaut le blanc du thème, seule surface étrangère
    // au reste de l'application.
    backgroundColor: premiumBackground(context),
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
          // Les fiches partent de 16 pt : c'est leur 100 %, pas celui de la
          // lecture — le pourcentage se lit rapporté à la famille en cours.
          base: ReadingTextSize.medium.fontSize,
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
        // Panneau « premium affirmé » : voile vertical `surface → surfaceAlt`,
        // liseré net et deux ombres, sous la poignée de traction des feuilles
        // qui en portent une. Les cartes de section gardent leur propre fond
        // et leur liseré : elles restent lisibles sur toute la hauteur du
        // voile. Marge horizontale seule — la hauteur disponible, elle, ne
        // bouge pas.
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: premiumSurface(context, radius: 24, depth: 1.3),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contrôles sans cadre
//
// Un contrôle ne sait pas dans quoi il vit. La feuille d'affichage l'habille d'un
// [DisplayCard] ; l'écran Réglages l'habille d'une rangée à icône. C'est ce qui
// permet aux deux surfaces d'afficher la même préférence **sans jamais pouvoir
// en diverger** : il n'y a qu'une mise en page des pastilles, donc la modifier ici
// la change partout, et un réglage ne peut pas avoir deux implémentations.
//
// Ce découpage n'a de sens que parce que les cadres sont réellement différents —
// un libellé en capitales dans une carte teintée, ou une rangée d'icône dans une
// liste. Partager le cadre aurait imposé à l'un des deux écrans la langue visuelle
// de l'autre.
// ─────────────────────────────────────────────────────────────────────────────

/// Une préférence, un contrôle : ses valeurs tiennent dans **une** barre, à
/// segments égaux, posée dans une même gouttière.
///
/// Choisir entre deux ou trois options est une décision, pas une collection de
/// boutons indépendants — la gouttière le dit, et la valeur courante prend
/// l'accent. Les segments égaux sont aussi ce qui rend la barre valable à toute
/// largeur : un téléphone de 320 px et une tablette montrent la même rangée,
/// seulement plus longue, là où des pastilles libres s'emballaient en 4 + 2 et
/// des boutons pleine largeur s'empilaient sur trois écrans.
///
/// Le piège que ce widget évite : un [Container] avec un `alignment` posé dans
/// un `Wrap` reçoit la largeur **maximale** du wrap — chaque pastille devient
/// large comme la carte et le `Wrap` les empile. Ici la largeur est partagée par
/// `Expanded`, jamais laissée au hasard.
///
/// [segmentOf] dessine le contenu lorsqu'un libellé n'est pas un mot —
/// l'échelle de tailles y dessine un « A » à la taille qu'il choisit.
/// [tooltipOf] parle pour un segment quand la rangée affiche une forme
/// raccourcie de son libellé. [enabledOf] garde une option qui ne s'applique
/// pas **visible et inerte**, jamais masquée.
class ReadingChoiceBar<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Ce que le segment annonce quand il est raccourci à l'écran.
  final String Function(T)? tooltipOf;

  /// False pour une option qui existe mais ne s'applique pas maintenant.
  final bool Function(T)? enabledOf;

  /// Contenu du segment, à la place du libellé.
  final Widget Function(BuildContext, T, bool selected)? segmentOf;

  /// Une barre qui traverse toute la carte d'une tablette cesse de se lire
  /// comme un contrôle pour se lire comme un curseur : le plafond lui garde la
  /// taille d'un contrôle, quelle que soit la surface.
  final double maxWidth;

  const ReadingChoiceBar({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.tooltipOf,
    this.enabledOf,
    this.segmentOf,
    this.maxWidth = 460,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: p.textGrey.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.textGrey.withValues(alpha: .16)),
        ),
        child: Row(
          children: [
            for (final option in options)
              Expanded(child: _segment(context, option, p)),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, T option, PremiumPalette p) {
    final enabled = enabledOf?.call(option) ?? true;
    final current = option == selected && enabled;
    final Widget content = segmentOf?.call(context, option, current) ??
        Text(
          labelOf(option),
          maxLines: 1,
          style: premiumText(
            context,
            13,
            current ? FontWeight.w700 : FontWeight.w500,
            current ? p.onPrimary : p.textDark,
          ),
        );
    final Widget plate = Container(
      height: 36,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: current ? p.primary : null,
        borderRadius: BorderRadius.circular(9),
      ),
      // L'échelle système est plafonnée à 1.18, mais elle est à 1.18 : « Versets
      // séparés » dans la moitié d'une barre doit rétrécir, pas saigner dans le
      // segment voisin.
      child: FittedBox(fit: BoxFit.scaleDown, child: content),
    );
    final Widget segment = InkWell(
      onTap: enabled ? () => onChanged(option) : null,
      borderRadius: BorderRadius.circular(9),
      // Une option qui ne se prend pas tout de suite lit délavée plutôt que
      // disparue : il faut voir qu'elle existe et ce qui bloque.
      child: enabled ? plate : Opacity(opacity: .45, child: plate),
    );
    final tooltip = tooltipOf?.call(option);
    return tooltip == null
        ? segment
        : Tooltip(message: tooltip, child: segment);
  }
}

/// Le curseur à pourcentage — la grammaire commune des feuilles de réglages,
/// reprise telle quelle du panneau d'Opacité : l'affichage en haut à droite,
/// le curseur à crans dont l'étiquette suit le pouce. Un seul widget pour
/// l'opacité et la taille : les deux ne peuvent pas dériver l'un de l'autre.
class ReadingPercentSlider extends StatelessWidget {
  /// La valeur affichée, en pourcentage. Hors bornes possible : l'affichage
  /// dit la vérité, le pouce reste aux butoirs.
  final double percent;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onPercent;

  /// Sépare, comme pour l'opacité, le vivant de l'écriture : on pendant le
  /// glissement, ce appelé au relâcher pour ne pas marteler les préférences.
  final ValueChanged<double>? onPercentEnd;

  const ReadingPercentSlider({
    super.key,
    required this.percent,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onPercent,
    this.onPercentEnd,
  });

  @override
  Widget build(BuildContext context) {
    final label = '${percent.round()} %';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Slider(
          value: percent.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onPercent,
          onChangeEnd: onPercentEnd,
        ),
      ],
    );
  }
}

/// La taille du texte en pourcentage, sur le modèle exact du curseur
/// d'Opacité de la même feuille : 100 % est la valeur par défaut de la
/// famille en cours — 22 pt pour la lecture, 16 pt pour les fiches — et le
/// curseur va de 50 % à 200 %.
///
/// Les six crans (« petit »…« géant ») disaient un adjectif : il fallait le
/// connaître pour s'y retrouver. Le pourcentage dit le saut exact, et la
/// barre donne la taille à la mesure où on la veut.
///
/// [divisions] est calé sur celui de l'Opacité : 20 crans, les mêmes
/// pointillés sur la piste, le même nombre de détentes à parcourir. Les deux
/// dials se lisent du regard, côte à côte dans la même feuille — ils doivent
/// se ressembler au trait, et 150 crans fusionnaient en une piste lisse,
/// sans pointillés, à côté d'une opacité pointillée.
class ReadingSizeSlider extends StatelessWidget {
  final double fontSize;

  /// La taille lue à 100 % : le défaut de la famille de préférences
  /// desservie. Un pourcentage ne dit rien sans sa référence.
  final double base;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const ReadingSizeSlider({
    super.key,
    required this.fontSize,
    required this.base,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ReadingPercentSlider(
      percent: (fontSize / base) * 100,
      min: 50.0,
      max: 200.0,
      divisions: 20,
      onPercent: (percent) => onChanged(base * percent / 100),
      onPercentEnd: onChangeEnd == null
          ? null
          : (percent) => onChangeEnd!(base * percent / 100),
    );
  }
}

/// The four alignments as a bar of icon segments: they share whatever width
/// the row gives them, four equal cells rather than four loose buttons that
/// wrapped on a 320-px phone.
class ReadingAlignChips extends StatelessWidget {
  final ReadingTextAlign align;
  final ValueChanged<ReadingTextAlign> onChanged;

  const ReadingAlignChips({
    super.key,
    required this.align,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return ReadingChoiceBar<ReadingTextAlign>(
      options: ReadingTextAlign.values,
      labelOf: (option) => option.label,
      selected: align,
      onChanged: onChanged,
      tooltipOf: (option) => 'Aligner ${option.label}',
      segmentOf: (context, option, selected) => Icon(
        _alignIcon(option),
        size: 18,
        // L'`IconButton` teintait l'icône au bleu du `colorScheme`, qui n'est
        // pas celui de la palette : la rangée sortait du thème chaud.
        color: selected ? p.onPrimary : p.textDark,
      ),
    );
  }
}

IconData _alignIcon(ReadingTextAlign option) => switch (option) {
      ReadingTextAlign.left => Icons.format_align_left,
      ReadingTextAlign.center => Icons.format_align_center,
      ReadingTextAlign.right => Icons.format_align_right,
      ReadingTextAlign.justify => Icons.format_align_justify,
    };

/// The typefaces as bare choice chips, each previewed in its own family.
class ReadingFontChips extends StatelessWidget {
  final ReadingFont font;
  final ValueChanged<ReadingFont> onChanged;

  const ReadingFontChips({
    super.key,
    required this.font,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
    );
  }
}

/// The three chip-shaped preferences (disposition, graisse, aération) as one
/// [ReadingChoiceBar] — the frameless control, dressed by the caller's surface.
class ReadingOptionBar<T> extends StatelessWidget {
  final List<T> options;
  final String Function(T) labelOf;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T)? tooltipOf;
  final bool Function(T)? enabledOf;

  const ReadingOptionBar({
    super.key,
    required this.options,
    required this.labelOf,
    required this.selected,
    required this.onChanged,
    this.tooltipOf,
    this.enabledOf,
  });

  @override
  Widget build(BuildContext context) {
    return ReadingChoiceBar<T>(
      options: options,
      labelOf: labelOf,
      selected: selected,
      onChanged: onChanged,
      tooltipOf: tooltipOf,
      enabledOf: enabledOf,
    );
  }
}

/// How much of the theme's background shows through behind the verses.
class ReadingOpacitySlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  /// Fired on release: dragging rebuilds the reader on every tick, which would
  /// write the preferences a dozen times per gesture.
  final ValueChanged<double>? onChangeEnd;

  const ReadingOpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return ReadingPercentSlider(
      percent: value * 100,
      min: 0,
      max: 100,
      divisions: 20,
      onPercent: (percent) => onChanged(percent / 100),
      onPercentEnd: onChangeEnd == null
          ? null
          : (percent) => onChangeEnd!(percent / 100),
    );
  }
}

/// The « Couleur du texte » presets: null first (follow the theme), then a
/// handful of deep hues plus one light — on a light theme the light choice
/// flips the reading panels dark instead of becoming invisible.
const List<int?> readingTextColorChoices = [
  null,
  0xFF1B1B1F, // noir doux
  0xFF3B2312, // brun profond
  0xFF1E2A44, // bleu nuit
  0xFF24331F, // vert olive
  0xFF4A1F24, // bordeaux
  0xFFEDF3FC, // blanc glacé
];

/// The bare colour swatches. [selected] holds the stored ARGB **as a string**,
/// because that is how the preference keeps it (`reading.textColor`).
class ReadingTextColorSwatches extends StatelessWidget {
  final String? selectedArgb;
  final ValueChanged<int?> onChanged;

  const ReadingTextColorSwatches({
    super.key,
    required this.selectedArgb,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final choice in readingTextColorChoices)
          _TextColorSwatch(
            argb: choice,
            selected: selectedArgb == choice?.toString(),
            onTap: () => onChanged(choice),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sections cadrées — la langue des feuilles
// ─────────────────────────────────────────────────────────────────────────────

/// The size as one slider that reports itself in percent, in a
/// [DisplayCard] — the same control and the same grammar as the opacity
/// dial. [base] is the size read at 100 %: each preference family's own
/// default, so the percentage starts where the reader starts. [onChangeEnd]
/// separates the live value from the write, as on the opacity dial.
class DisplaySizeSection extends StatelessWidget {
  final double fontSize;

  /// La taille lue à 100 % : le défaut de la famille desservie (22 pt en
  /// lecture, 16 pt sur les fiches).
  final double base;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const DisplaySizeSection({
    super.key,
    required this.fontSize,
    required this.base,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Taille du texte',
      icon: Icons.format_size,
      child: ReadingSizeSlider(
        fontSize: fontSize,
        base: base,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// The four alignments as icon chips, in a [DisplayCard].
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
      child: ReadingAlignChips(align: align, onChanged: onChanged),
    );
  }
}

/// The typefaces as choice chips, in a [DisplayCard].
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
      child: ReadingFontChips(font: font, onChanged: onChanged),
    );
  }
}

/// « Versets séparés » or a continuous printed-Bible flow.
class DisplayLayoutSection extends StatelessWidget {
  final ReadingLayout layout;
  final ValueChanged<ReadingLayout> onChanged;

  const DisplayLayoutSection({
    super.key,
    required this.layout,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Disposition du texte',
      icon: Icons.segment,
      child: ReadingOptionBar<ReadingLayout>(
        options: ReadingLayout.values,
        labelOf: (option) => option.label,
        selected: layout,
        onChanged: onChanged,
      ),
    );
  }
}

/// Léger / Normal / Foncé. Some screens render w400 visibly darker than others
/// — this lets the reader dial the stroke to taste, identically in both layouts.
class DisplayWeightSection extends StatelessWidget {
  final ReadingFontWeight weight;
  final ValueChanged<ReadingFontWeight> onChanged;

  const DisplayWeightSection({
    super.key,
    required this.weight,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Graisse du texte',
      icon: Icons.format_bold,
      child: ReadingOptionBar<ReadingFontWeight>(
        options: ReadingFontWeight.values,
        labelOf: (option) => option.label,
        selected: weight,
        onChanged: onChanged,
      ),
    );
  }
}

/// Serré / Normal / Aéré. The vertical rhythm already scales with the font size
/// (see `ReadingRhythm`) so big type keeps its breathing room; this tightens or
/// loosens it to taste.
class DisplaySpacingSection extends StatelessWidget {
  final ReadingSpacing spacing;
  final ValueChanged<ReadingSpacing> onChanged;

  const DisplaySpacingSection({
    super.key,
    required this.spacing,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Aération du texte',
      icon: Icons.format_line_spacing,
      child: ReadingOptionBar<ReadingSpacing>(
        options: ReadingSpacing.values,
        labelOf: (option) => option.label,
        selected: spacing,
        onChanged: onChanged,
      ),
    );
  }
}

/// The body text colour: « suivre le thème » by default, then a handful of
/// presets. A light colour flips the panels dark via `withTextColor`, so every
/// swatch stays readable.
class DisplayTextColorSection extends StatelessWidget {
  final String? selectedArgb;
  final ValueChanged<int?> onChanged;

  const DisplayTextColorSection({
    super.key,
    required this.selectedArgb,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Couleur du texte',
      icon: Icons.format_color_text,
      child: ReadingTextColorSwatches(
        selectedArgb: selectedArgb,
        onChanged: onChanged,
      ),
    );
  }
}

/// How much of the theme's background shows through behind the verses.
class DisplayOpacitySection extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  const DisplayOpacitySection({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Opacité du panneau',
      icon: Icons.texture,
      child: ReadingOpacitySlider(
        value: value,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}

/// Texte seul / texte + notes, then how the notes sit — two bars, the second
/// one appearing only once there are notes to place. The mode and the
/// disposition stay two separate rows rather than one: « sans notes » must
/// remain reachable, and hiding a chosen disposition is what made readers
/// think it had been forgotten.
class DisplayNotesSection extends StatelessWidget {
  final bool notesMode;
  final NoteDisposition disposition;

  /// Whether « sous le verset » is renderable. False in the continuous layout,
  /// where note cards would chop the printed-text feel: the bar then offers the
  /// single disposition that applies, and the stored one falls back to
  /// « à la suite ».
  final bool belowAvailable;
  final ValueChanged<bool> onNotesMode;
  final ValueChanged<NoteDisposition> onDisposition;

  const DisplayNotesSection({
    super.key,
    required this.notesMode,
    required this.disposition,
    required this.belowAvailable,
    required this.onNotesMode,
    required this.onDisposition,
  });

  @override
  Widget build(BuildContext context) {
    return DisplayCard(
      label: 'Notes',
      icon: Icons.note_alt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReadingChoiceBar<bool>(
            options: const [false, true],
            labelOf: (on) => on ? 'Texte + notes' : 'Texte seul',
            selected: notesMode,
            onChanged: onNotesMode,
          ),
          if (notesMode) ...[
            const SizedBox(height: 8),
            ReadingChoiceBar<NoteDisposition>(
              options: belowAvailable
                  ? const [NoteDisposition.inline, NoteDisposition.below]
                  : const [NoteDisposition.inline],
              labelOf: (option) => option == NoteDisposition.below
                  ? 'Notes sous le verset'
                  : 'Notes à la suite',
              selected: disposition == NoteDisposition.below && belowAvailable
                  ? NoteDisposition.below
                  : NoteDisposition.inline,
              onChanged: onDisposition,
            ),
          ],
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
        // Liseré neutre : l'accent ne borde jamais une carte (voir
        // [premiumCardBorder]), il reste aux icônes et aux marqueurs d'état.
        border: Border.all(color: premiumCardBorder(context, opacity: .20)),
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
        // Même liseré neutre que la carte de réglage : pas de contour d'accent
        // autour d'une carte (voir [premiumCardBorder]).
        border: Border.all(color: premiumCardBorder(context, opacity: .20)),
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

/// A round swatch of [readingTextColorChoices]; the first (null) draws the
/// « suivre le thème » marker instead of a flat colour.
class _TextColorSwatch extends StatelessWidget {
  final int? argb;
  final bool selected;
  final VoidCallback onTap;

  const _TextColorSwatch({
    required this.argb,
    required this.selected,
    required this.onTap,
  });

  String get _tooltip => switch (argb) {
        null => 'Suivre le thème',
        0xFF1B1B1F => 'Noir',
        0xFF3B2312 => 'Brun',
        0xFF1E2A44 => 'Bleu nuit',
        0xFF24331F => 'Vert',
        0xFF4A1F24 => 'Bordeaux',
        _ => 'Blanc',
      };

  @override
  Widget build(BuildContext context) {
    final theme = BibleThemeScope.of(context);
    final fill = argb == null ? null : Color(argb!);
    return Tooltip(
      message: _tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // « Suivre le thème » : la couleur courante du corps de texte.
            color: fill ?? theme.textColor,
            border: Border.all(
              color: selected ? theme.accentColor : theme.panelBorderColor,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: fill == null
              ? Icon(
                  Icons.palette_outlined,
                  size: 16,
                  // Contrasté sur la couleur du thème elle-même.
                  color: theme.usesLightText ? Colors.black54 : Colors.white70,
                )
              : selected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      color: fill.computeLuminance() > .5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {  final ReadingFont font;
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
