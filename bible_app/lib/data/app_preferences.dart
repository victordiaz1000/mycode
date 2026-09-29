import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'theme_catalog.dart';
import 'custom_background.dart';
import 'version_repository.dart';

/// Persisted user preferences for the reading screen (maquette v3/v4):
/// notes on/off, note disposition, text size, active version, reading theme.
class AppPreferences {
  static const _kNotesMode = 'reading.notesMode';
  static const _kNoteDisposition = 'reading.noteDisposition';
  static const _kFontSize = 'reading.fontSize';
  static const _kVersionCode = 'reading.versionCode';
  static const _kThemeId = 'reading.themeId';
  static const _kTextAlign = 'reading.textAlign';
  static const _kFontFamily = 'reading.fontFamily';
  static const _kSpacing = 'reading.spacing';
  static const _kImmersion = 'reading.immersion';
  static const _kLayout = 'reading.layout';
  static const _kFontWeight = 'reading.fontWeight';
  static const _kPanelOpacity = 'reading.panelOpacity';
  static const _kTextColor = 'reading.textColor';
  static const _kCustomTheme = 'reading.customTheme';

  bool notesMode;
  NoteDisposition disposition;

  /// Immersion mode: the reading hides its own bars (actions, find) and the
  /// shells above it hide theirs (tab strip, bottom navigation) so only the
  /// text remains. A floating pill exits.
  bool immersion;

  /// Point size of the verse body text; see [ReadingTextSize].
  double fontSize;

  /// Horizontal alignment of the reading/dictionary text.
  ReadingTextAlign textAlign;

  /// Typeface used by verse bodies and their notes.
  ReadingFont readingFont;

  /// Vertical airiness of the reading area (« Aération » du menu ⋯).
  ReadingSpacing spacing;

  /// How the chapter lays verses out: one tile per verse, or a continuous
  /// flow of paragraphs (verse numbers in exposant) cut by section titles.
  ReadingLayout layout;

  /// Stroke weight of the verse body. Some fonts / screens render the same
  /// w400 visibly darker than others — this lets the reader dial it.
  ReadingFontWeight fontWeight;

  /// Opacity of the semi-transparent panel the verses sit on (0.0–1.0).
  /// 0 = the background shows through completely, 1 = an opaque panel; the
  /// default .80 reproduces the historical rendering.
  double panelOpacity;

  /// Optional override of the reading body text colour, stored as the decimal
  /// ARGB integer (e.g. '4278190080'). Null = follow the theme's own colour.
  String? textColorOverride;

  /// Version being read — BYM by default, or a code downloaded through the
  /// Bibliothèque. Persisted so the choice survives a restart.
  String versionCode;

  /// Reading theme selected by the user.
  String themeId;

  /// Thème de lecture par défaut : Bois doré. Une seule source de vérité pour
  /// le constructeur, le notifier initial et la relecture des préférences.
  static const String defaultThemeId = 'forest';

  AppPreferences({
    this.notesMode = false,
    this.disposition = NoteDisposition.below,
    this.immersion = false,
    double? fontSize,
    this.textAlign = ReadingTextAlign.left,
    this.readingFont = ReadingFont.crimson,
    this.spacing = ReadingSpacing.normal,
    this.layout = ReadingLayout.tiles,
    this.fontWeight = ReadingFontWeight.normal,
    double? panelOpacity,
    this.textColorOverride,
    this.versionCode = VersionRepository.embeddedCode,
    this.themeId = defaultThemeId,
  }) : fontSize = fontSize ?? ReadingTextSize.extraLarge.fontSize,
       panelOpacity = panelOpacity ?? .80;

  /// Notifier for the current theme id so the app can rebuild when it changes.
  /// Emitted after any reading preference is persisted.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static final ValueNotifier<String> themeNotifier = ValueNotifier<String>(
    defaultThemeId,
  );

  /// Broadcast whenever the immersion preference changes, so the shells above
  /// the reader (tab strip, bottom navigation) can hide themselves without a
  /// callback chain through every widget in between.
  static final ValueNotifier<bool> immersionNotifier = ValueNotifier<bool>(
    false,
  );

  static Future<AppPreferences> load() async {
    final sp = await SharedPreferences.getInstance();
    // The photo theme must sit in its runtime slot BEFORE the theme id is
    // resolved below — otherwise a persisted 'custom' would silently fall
    // back to the first catalog theme for this session.
    CustomBackgroundStore.restore(
      sp.getString(_kCustomTheme),
    );
    final prefs = AppPreferences(
      notesMode: sp.getBool(_kNotesMode) ?? false,
      disposition: sp.getString(_kNoteDisposition) == 'inline'
          ? NoteDisposition.inline
          : NoteDisposition.below,
      fontSize: sp.getDouble(_kFontSize),
      textAlign: ReadingTextAlign.nearest(sp.getString(_kTextAlign)),
      // Crimson Pro : police par défaut de l'écran lecture — la valeur stockée
      // gagne dès que le lecteur a choisi autre chose.
      readingFont: ReadingFont.nearest(
        sp.getString(_kFontFamily),
        fallback: ReadingFont.crimson,
      ),
      spacing: ReadingSpacing.nearest(sp.getString(_kSpacing)),
      layout: ReadingLayout.nearest(sp.getString(_kLayout)),
      fontWeight: ReadingFontWeight.nearest(sp.getString(_kFontWeight)),
      panelOpacity: (sp.getDouble(_kPanelOpacity) ?? .80).clamp(0.0, 1.0),
      textColorOverride: sp.getString(_kTextColor),
      versionCode:
          sp.getString(_kVersionCode) ?? VersionRepository.embeddedCode,
      themeId: themeById(sp.getString(_kThemeId) ?? defaultThemeId).id,
    );
    prefs.immersion = sp.getBool(_kImmersion) ?? false;
    // Broadcast initial value
    try {
      themeNotifier.value = prefs.themeId;
      immersionNotifier.value = prefs.immersion;
    } catch (_) {}
    return prefs;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kNotesMode, notesMode);
    await sp.setString(
      _kNoteDisposition,
      disposition == NoteDisposition.inline ? 'inline' : 'below',
    );
    await sp.setDouble(_kFontSize, fontSize);
    await sp.setString(_kTextAlign, textAlign.name);
    await sp.setString(_kFontFamily, readingFont.name);
    await sp.setString(_kSpacing, spacing.name);
    await sp.setString(_kLayout, layout.name);
    await sp.setString(_kFontWeight, fontWeight.name);
    await sp.setDouble(_kPanelOpacity, panelOpacity);
    if (textColorOverride == null) {
      await sp.remove(_kTextColor);
    } else {
      await sp.setString(_kTextColor, textColorOverride!);
    }
    await sp.setString(_kVersionCode, versionCode);
    await sp.setString(_kThemeId, themeId);
    await sp.setBool(_kImmersion, immersion);
    // Broadcast the change so the app can update its Material theme.
    try {
      themeNotifier.value = themeId;
      immersionNotifier.value = immersion;
      revision.value++;
    } catch (_) {}
  }

  /// Persists (or clears with null) the photo theme's JSON and refreshes the
  /// runtime slot. Called by the themes screen after a pick or a delete —
  /// separate from [save] because the photo theme outlives any single
  /// preference write.
  Future<void> saveCustomTheme(String? json) async {
    final sp = await SharedPreferences.getInstance();
    if (json == null) {
      await sp.remove(_kCustomTheme);
    } else {
      await sp.setString(_kCustomTheme, json);
    }
    CustomBackgroundStore.restore(json);
  }
}

enum NoteDisposition { inline, below }

/// How a chapter lays its verses out (the ⋯ menu of the reading bar).
enum ReadingLayout {
  /// One tile per verse, the historical layout: number in the margin, text on
  /// the right, notes and markers attached to their tile.
  tiles('Versets séparés'),

  /// A continuous flow of paragraphs: verse numbers shrink into exposants,
  /// verses follow one another inside the same paragraph, section titles cut
  /// the flow. Reads like a printed Bible.
  paragraph('Texte continu');

  const ReadingLayout(this.label);

  final String label;

  static ReadingLayout nearest(String? name) =>
      values.asNameMap()[name] ?? ReadingLayout.tiles;
}

/// Stroke weight of the reading text (the ⋯ menu's « Graisse » row).
enum ReadingFontWeight {
  light('Léger', FontWeight.w300),
  normal('Normal', FontWeight.w400),
  fonce('Foncé', FontWeight.w600);

  const ReadingFontWeight(this.label, this.weight);

  final String label;
  final FontWeight weight;

  static ReadingFontWeight nearest(String? name) {
    if (name == null) return normal;
    return values.asNameMap()[name] ?? normal;
  }
}

/// The reading text sizes offered by the ⋯ menu of the reading bar.
///
/// [medium] is the Material `bodyLarge` default, i.e. exactly what the reader
/// rendered before the control existed — picking it restores that layout. The
/// upper half of the ladder ([huge], [giant]) exists for readers with failing
/// eyesight: 30 pt is roughly double the default body.
enum ReadingTextSize {
  small('petit', 14),
  medium('moyen', 16),
  large('grand', 19),
  extraLarge('très grand', 22),
  huge('énorme', 26),
  giant('géant', 30);

  const ReadingTextSize(this.label, this.fontSize);

  /// Lower-case adjective, shown as « Texte <label> » in the menu.
  final String label;

  /// Nominal point size. It is NOT reduced here for narrow screens: `main.dart`
  /// already folds a width-keyed `deviceFactor` (.90 / .95 / .98 below 360 /
  /// 400 / 480 px) into the ambient `textScaler`, which every `Text` — reading
  /// body included — resolves. A second ladder on this enum used the very same
  /// breakpoints and the very same factors, so the two compounded: « petit »
  /// landed at 11.3 pt instead of 12.6 pt on a 320 px phone, a 19 % cut where
  /// 10 % was intended. One reduction, in one place.
  final double fontSize;

  /// The step closest to [value] — the stored size is a raw double, so a value
  /// written by an older build still checks the nearest entry.
  static ReadingTextSize nearest(double value) => values.reduce(
    (a, b) => (a.fontSize - value).abs() <= (b.fontSize - value).abs() ? a : b,
  );
}

/// The horizontal text alignments offered by the ⋯ menu of a reading surface
/// (reading and dictionary tabs).

/// The vertical airiness of the reading area (« Aération » du menu ⋯).
///
/// The reader derives its whole vertical rhythm from the body font size so
/// large type keeps the breathing room of small type; [gapFactor] and
/// [leadingFactor] let the reader dial that rhythm tighter or looser on top
/// of it.
enum ReadingSpacing {
  compact('Serré', 0.72, 0.94),
  normal('Normal', 1.0, 1.0),
  airy('Aéré', 1.45, 1.09);

  const ReadingSpacing(this.label, this.gapFactor, this.leadingFactor);

  final String label;

  /// Multiplier applied to every vertical gap (between verses, around section
  /// titles, in the number gutter). 1.0 reproduces the historical layout at
  /// the default 16 pt body.
  final double gapFactor;

  /// Multiplier applied to the body's line height.
  final double leadingFactor;

  static ReadingSpacing nearest(String? name) =>
      values.asNameMap()[name] ?? ReadingSpacing.normal;
}

enum ReadingFont {
  classic('Classique · Lora', 'Lora'),
  elegant('Élégante', 'Lato'),
  jakarta('Plus Jakarta Sans', 'Plus Jakarta Sans'),
  garamond('EB Garamond', 'EB Garamond'),
  crimson('Crimson Pro', 'Crimson Pro'),
  notoSerif('Noto Serif', 'Noto Serif'),
  literata('Literata', 'Literata'),
  spectral('Spectral', 'Spectral'),
  alegreya('Alegreya', 'Alegreya'),
  gentium('Gentium Plus', 'Gentium Plus'),
  // Les noms de l'énumération sont **persistés** (`values.asNameMap()` dans
  // [nearest]) : les renommer ferait retomber le choix du lecteur sur le repli.
  cardo('Cardo · hébreu & grec', 'Cardo'),
  newsreader('Newsreader', 'Newsreader');

  const ReadingFont(this.label, this.fontFamily);

  final String label;
  final String fontFamily;

  /// Nom stocké par l'ancienne option « Moderne », dont la famille était
  /// `sans-serif` — donc la police système de l'appareil, la seule de la liste
  /// que l'archive n'embarquait pas. L'application étant hors-ligne et voulant
  /// un rendu identique partout, elle a été retirée : le choix migre vers Plus
  /// Jakarta Sans, la sans serif embarquée la plus proche.
  static const String _ancienNomModerne = 'modern';

  static ReadingFont nearest(
    String? name, {
    ReadingFont fallback = ReadingFont.jakarta,
  }) {
    // La migration passe avant le repli du caller : celui de la lecture est
    // Crimson Pro, une serif — un lecteur qui avait choisi « Moderne » y perdrait
    // le sans serif qu'il voulait.
    if (name == _ancienNomModerne) return ReadingFont.jakarta;
    return values.asNameMap()[name] ?? fallback;
  }
}

enum ReadingTextAlign {
  left('gauche'),
  center('centré'),
  right('droite'),
  justify('justifié');

  const ReadingTextAlign(this.label);

  /// Lower-case adjective, shown as « Aligner <label> » in the menu.
  final String label;

  /// The Flutter [TextAlign] this option maps to.
  TextAlign get align => switch (this) {
    ReadingTextAlign.left => TextAlign.left,
    ReadingTextAlign.center => TextAlign.center,
    ReadingTextAlign.right => TextAlign.right,
    ReadingTextAlign.justify => TextAlign.justify,
  };

  static ReadingTextAlign nearest(String? name) =>
      values.asNameMap()[name] ?? ReadingTextAlign.left;
}

/// Display of the fiche screens (dictionaries, Notes BYM Lexique…),
/// deliberately separate from [AppPreferences]: the reading keeps its own size,
/// alignment and typeface.
class FichePreferences {
  static const _kFontSize = 'fiche.fontSize';
  static const _kTextAlign = 'fiche.textAlign';
  static const _kFontFamily = 'fiche.fontFamily';

  /// Emitted after every save so the open fiche scopes rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  double fontSize;
  ReadingTextAlign textAlign;
  ReadingFont readingFont;

  FichePreferences({
    double? fontSize,
    this.textAlign = ReadingTextAlign.left,
    this.readingFont = ReadingFont.jakarta,
  }) : fontSize = fontSize ?? ReadingTextSize.medium.fontSize;

  static Future<FichePreferences> load() async {
    final sp = await SharedPreferences.getInstance();
    return FichePreferences(
      fontSize: sp.getDouble(_kFontSize),
      textAlign: ReadingTextAlign.nearest(sp.getString(_kTextAlign)),
      readingFont: ReadingFont.nearest(sp.getString(_kFontFamily)),
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kFontSize, fontSize);
    await sp.setString(_kTextAlign, textAlign.name);
    await sp.setString(_kFontFamily, readingFont.name);
    revision.value++;
  }
}


/// Display of the study screens — the Strong fiche and the verse study —
/// separate from both the reader (`reading.*`) and the dictionaries
/// (`fiche.*`): the biblical-language study keeps its own display.
class EtudePreferences {
  static const _kFontSize = 'etude.fontSize';
  static const _kTextAlign = 'etude.textAlign';
  static const _kFontFamily = 'etude.fontFamily';

  /// Emitted after every save so the open scopes rebuild.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  double fontSize;
  ReadingTextAlign textAlign;
  ReadingFont readingFont;

  EtudePreferences({
    double? fontSize,
    this.textAlign = ReadingTextAlign.left,
    this.readingFont = ReadingFont.jakarta,
  }) : fontSize = fontSize ?? ReadingTextSize.medium.fontSize;

  static Future<EtudePreferences> load() async {
    final sp = await SharedPreferences.getInstance();
    return EtudePreferences(
      fontSize: sp.getDouble(_kFontSize),
      textAlign: ReadingTextAlign.nearest(sp.getString(_kTextAlign)),
      // Plus Jakarta Sans tant qu'aucun choix n'a été enregistré : c'est la
      // police par défaut des écrans d'étude (fiche Strong, étude de verset).
      readingFont: ReadingFont.nearest(
        sp.getString(_kFontFamily),
        fallback: ReadingFont.jakarta,
      ),
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(_kFontSize, fontSize);
    await sp.setString(_kTextAlign, textAlign.name);
    await sp.setString(_kFontFamily, readingFont.name);
    revision.value++;
  }
}