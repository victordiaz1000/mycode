import 'package:shared_preferences/shared_preferences.dart';

import 'version_repository.dart';

/// Persisted user preferences for the reading screen (maquette v3/v4):
/// notes on/off, note disposition, text size, active version.
class AppPreferences {
  static const _kNotesMode = 'reading.notesMode';
  static const _kNoteDisposition = 'reading.noteDisposition';
  static const _kFontSize = 'reading.fontSize';
  static const _kVersionCode = 'reading.versionCode';

  bool notesMode;
  NoteDisposition disposition;

  /// Point size of the verse body text; see [ReadingTextSize].
  double fontSize;

  /// Version being read — BYM by default, or a code downloaded through the
  /// Bibliothèque. Persisted so the choice survives a restart.
  String versionCode;

  AppPreferences({
    this.notesMode = false,
    this.disposition = NoteDisposition.below,
    double? fontSize,
    this.versionCode = VersionRepository.embeddedCode,
  }) : fontSize = fontSize ?? ReadingTextSize.medium.fontSize;

  static Future<AppPreferences> load() async {
    final sp = await SharedPreferences.getInstance();
    return AppPreferences(
      notesMode: sp.getBool(_kNotesMode) ?? false,
      disposition: sp.getString(_kNoteDisposition) == 'inline'
          ? NoteDisposition.inline
          : NoteDisposition.below,
      fontSize: sp.getDouble(_kFontSize),
      versionCode:
          sp.getString(_kVersionCode) ?? VersionRepository.embeddedCode,
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kNotesMode, notesMode);
    await sp.setString(_kNoteDisposition,
        disposition == NoteDisposition.inline ? 'inline' : 'below');
    await sp.setDouble(_kFontSize, fontSize);
    await sp.setString(_kVersionCode, versionCode);
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
