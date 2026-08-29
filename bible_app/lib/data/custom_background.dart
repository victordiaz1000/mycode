import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'theme_catalog.dart';

/// The user's photo as a reading theme — one slot, replaced on every pick.
///
/// The palette is derived ONCE at pick time from the photo's mean luminosity
/// (light text on a dark photo, dark text on a bright one, gold accents — the
/// app's signature liseré) and persisted as JSON, so a cold start rebuilds
/// the theme without decoding the image again. The photo itself is COPIED out
/// of the picker cache into the app's documents directory: the cache is
/// purged by the system, the theme must outlive it.
class CustomBackgroundStore {
  CustomBackgroundStore._();

  static const _kId = customThemeId;
  static const _kName = 'Ma photo';

  static Directory? _root;

  /// Tests inject a temp directory: `path_provider` answers over a platform
  /// channel, and inside the fake-async zone of `testWidgets` it never does.
  static void useRoot(Directory dir) => _root = dir;

  static void useAppDirectory() => _root = null;

  static Future<Directory> _directory() async {
    final injected = _root;
    if (injected != null) return injected;
    return getApplicationDocumentsDirectory();
  }

  /// The live photo theme, if one is picked.
  static BibleTheme? get current => customBibleTheme;

  /// Rebuilds the slot from the persisted JSON (null clears it). Called at
  /// startup — BEFORE the theme id is resolved — and after every pick or
  /// delete. A corrupted JSON degrades to « no photo » (same contract as the
  /// library registry): the file may still be there and a new pick repairs
  /// everything, a broken string must not take the app down.
  static void restore(String? json) {
    if (json == null || json.isEmpty) {
      customBibleTheme = null;
      return;
    }
    try {
      customBibleTheme =
          themeFromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      customBibleTheme = null;
    }
  }

  /// Copies [pickedPath] into the app directory, derives the palette from the
  /// photo and installs it as the live photo theme. Returns the JSON to
  /// persist (the caller writes it via `AppPreferences.saveCustomTheme`).
  ///
  /// The destination name is UNIQUE per pick: `FileImage` caches by path, so
  /// overwriting a fixed file would leave the previous photo on screen — the
  /// cache never learns the bytes changed. A new pick = a new path = a fresh
  /// decode; the previous file is deleted right after the copy.
  static Future<String> install(String pickedPath) async {
    final dir = await _directory();
    final previous = customBibleTheme?.customFile;
    final dest = p.join(
      dir.path,
      'custom_background_${DateTime.now().microsecondsSinceEpoch}.img',
    );
    final copied = await File(pickedPath).copy(dest);
    if (previous != null && previous != dest) {
      try {
        File(previous).deleteSync();
      } catch (_) {
        // Already gone — the goal is reached either way.
      }
    }

    final bytes = await copied.readAsBytes();
    final tone = await _meanColor(bytes);
    final theme = _themeFor(copied.path, tone);
    customBibleTheme = theme;
    return jsonEncode(themeToJson(theme));
  }

  /// Removes the photo (file + slot). Returns true when a theme actually
  /// existed, so the caller can skip the confirmation-less no-op.
  ///
  /// The unlink is SYNCHRONOUS on purpose: awaiting real file I/O inside a
  /// widget test's fake-async zone never completes (the same trap as
  /// path_provider), which froze the whole delete flow mid-way. One unlink
  /// costs microseconds; blocking is irrelevant here.
  static Future<bool> delete() async {
    final theme = customBibleTheme;
    if (theme == null) return false;
    final file = theme.customFile;
    if (file != null) {
      try {
        File(file).deleteSync();
      } catch (_) {
        // Already gone — the goal is reached either way.
      }
    }
    customBibleTheme = null;
    return true;
  }

  /// Mean color of an image, downsampled to 32×32 before averaging: the mean
  /// of a full photo and of its thumbnail are the same for this purpose, and
  /// the thumbnail decode costs kilobytes instead of megabytes. Transparent
  /// pixels are skipped — a PNG's empty areas decode as black, and counting
  /// them would read a mostly-transparent motif as a dark photo.
  static Future<Color> _meanColor(List<int> bytes) async {
    final codec = await ui.instantiateImageCodec(
      Uint8List.fromList(bytes),
      targetWidth: 32,
      targetHeight: 32,
    );
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (data == null) return const Color(0xFF808080);
    final pixels = data.buffer.asUint8List();
    var r = 0, g = 0, b = 0, count = 0;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) continue;
      r += pixels[i];
      g += pixels[i + 1];
      b += pixels[i + 2];
      count++;
    }
    if (count == 0) return const Color(0xFF808080);
    return Color.fromARGB(255, r ~/ count, g ~/ count, b ~/ count);
  }

  /// Palette derived from the photo itself: the mean colour's HUE tints every
  /// role — deep dark text on a bright photo, frosted light text on a dark
  /// one, titles and accents carrying the picture's colour. The previous
  /// fixed brown/gold palettes ignored the photo entirely: a blue picture
  /// landed with brown titles, reading as the default theme's leftovers.
  static BibleTheme _themeFor(String filePath, Color tone) {
    final hsl = HSLColor.fromColor(tone);
    final hue = hsl.hue;
    // A photo's mean is often muddy: nudge the saturation up so the derived
    // accents carry some of the picture's colour, clamped where text derived
    // from it stays legible.
    final sat = (hsl.saturation * 1.25).clamp(.12, .55).toDouble();
    final luminous = tone.computeLuminance() > .45;
    final safeTone = luminous
        ? hsl.withLightness((hsl.lightness + .18).clamp(0.0, .92).toDouble())
              .toColor()
        : hsl.withLightness((hsl.lightness * .55).clamp(0.0, .35).toDouble())
              .toColor();
    if (luminous) {
      return BibleTheme(
        id: _kId,
        name: _kName,
        customFile: filePath,
        backgroundFit: BackgroundFit.cover,
        backgroundTone: safeTone,
        textColor: HSLColor.fromAHSL(
          1,
          hue,
          (sat * .75).clamp(0.0, .40),
          .16,
        ).toColor(),
        titleColor: HSLColor.fromAHSL(
          1,
          hue,
          (sat + .12).clamp(0.0, .60),
          .30,
        ).toColor(),
        verseNumColor: HSLColor.fromAHSL(
          1,
          hue,
          (sat + .08).clamp(0.0, .55),
          .38,
        ).toColor(),
        accentColor: HSLColor.fromAHSL(
          1,
          hue,
          (sat + .15).clamp(0.0, .60),
          .40,
        ).toColor(),
        highlightRef: HSLColor.fromAHSL(
          1,
          hue,
          (sat + .18).clamp(0.0, .65),
          .42,
        ).toColor(),
      );
    }
    return BibleTheme(
      id: _kId,
      name: _kName,
      customFile: filePath,
      backgroundFit: BackgroundFit.cover,
      backgroundTone: safeTone,
      textColor: HSLColor.fromAHSL(
        1,
        hue,
        (sat * .40).clamp(0.0, .30),
        .93,
      ).toColor(),
      titleColor: HSLColor.fromAHSL(
        1,
        hue,
        (sat + .15).clamp(0.0, .70),
        .68,
      ).toColor(),
      verseNumColor: HSLColor.fromAHSL(
        1,
        hue,
        (sat * .60).clamp(0.0, .45),
        .76,
      ).toColor(),
      accentColor: HSLColor.fromAHSL(
        1,
        hue,
        (sat + .10).clamp(0.0, .65),
        .60,
      ).toColor(),
      highlightRef: HSLColor.fromAHSL(
        1,
        hue,
        (sat + .12).clamp(0.0, .70),
        .62,
      ).toColor(),
    );
  }

  /// JSON of the colors only — the file path rides along so a restart finds
  /// the photo without re-deriving anything.
  static Map<String, dynamic> themeToJson(BibleTheme t) => {
    'file': t.customFile,
    'tone': t.backgroundTone.toARGB32(),
    'text': t.textColor.toARGB32(),
    'title': t.titleColor.toARGB32(),
    'verseNum': t.verseNumColor.toARGB32(),
    'accent': t.accentColor.toARGB32(),
    'highlight': t.highlightRef.toARGB32(),
  };

  static BibleTheme themeFromJson(Map<String, dynamic> json) => BibleTheme(
    id: _kId,
    name: _kName,
    customFile: json['file'] as String?,
    backgroundFit: BackgroundFit.cover,
    backgroundTone: Color(json['tone'] as int),
    textColor: Color(json['text'] as int),
    titleColor: Color(json['title'] as int),
    verseNumColor: Color(json['verseNum'] as int),
    accentColor: Color(json['accent'] as int),
    highlightRef: Color(json['highlight'] as int),
  );
}
