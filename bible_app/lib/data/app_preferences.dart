import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'theme_catalog.dart';
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

  bool notesMode;
  NoteDisposition disposition;

  /// Point size of the verse body text; see [ReadingTextSize].
  double fontSize;

  /// Horizontal alignment of the reading/dictionary text.
  ReadingTextAlign textAlign;

  /// Version being read — BYM by default, or a code downloaded through the
  /// Bibliothèque. Persisted so the choice survives a restart.
  String versionCode;

  /// Reading theme selected by the user.
  String themeId;

  AppPreferences({
    this.notesMode = false,
    this.disposition = NoteDisposition.below,
    double? fontSize,
    this.textAlign = ReadingTextAlign.justify,
    this.versionCode = VersionRepository.embeddedCode,
    this.themeId = 'vitrail',
  }) : fontSize = fontSize ?? ReadingTextSize.extraLarge.fontSize;

  /// Notifier for the current theme id so the app can rebuild when it changes.
  static final ValueNotifier<String> themeNotifier =
      ValueNotifier<String>(bibleThemes.first.id);

  static Future<AppPreferences> load() async {
    final sp = await SharedPreferences.getInstance();
    final prefs = AppPreferences(
      notesMode: sp.getBool(_kNotesMode) ?? false,
      disposition: sp.getString(_kNoteDisposition) == 'inline'
          ? NoteDisposition.inline
          : NoteDisposition.below,
      fontSize: sp.getDouble(_kFontSize),
      textAlign: ReadingTextAlign.nearest(sp.getString(_kTextAlign)),
      versionCode:
          sp.getString(_kVersionCode) ?? VersionRepository.embeddedCode,
      themeId: sp.getString(_kThemeId) ?? bibleThemes.first.id,
    );
    // Broadcast initial value
    try {
      themeNotifier.value = prefs.themeId;
    } catch (_) {}
    return prefs;
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kNotesMode, notesMode);
    await sp.setString(_kNoteDisposition,
        disposition == NoteDisposition.inline ? 'inline' : 'below');
    await sp.setDouble(_kFontSize, fontSize);
    await sp.setString(_kTextAlign, textAlign.name);
    await sp.setString(_kVersionCode, versionCode);
    await sp.setString(_kThemeId, themeId);
    // Broadcast the change so the app can update its Material theme.
    try {
      themeNotifier.value = themeId;
    } catch (_) {}
  }
}

enum NoteDisposition { inline, below }

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
  final double fontSize;

  /// The step closest to [value] — the stored size is a raw double, so a value
  /// written by an older build still checks the nearest entry.
  static ReadingTextSize nearest(double value) => values.reduce(
        (a, b) =>
            (a.fontSize - value).abs() <= (b.fontSize - value).abs() ? a : b,
      );
}

/// The horizontal text alignments offered by the ⋯ menu of a reading surface
/// (reading and dictionary tabs).
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

  static ReadingTextAlign nearest(String? name) => values.asNameMap()[name] ??
      values.asNameMap()['justify']!;
}
