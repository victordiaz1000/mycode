import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/custom_background.dart';
import 'package:bible_app/data/theme_catalog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('custom_bg_test');
    CustomBackgroundStore.useRoot(temp);
  });

  tearDown(() async {
    CustomBackgroundStore.useAppDirectory();
    CustomBackgroundStore.restore(null);
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Writes [asset] into the temp dir as a picked photo would arrive.
  Future<String> stageAsset(String asset, String name) async {
    final bytes = await rootBundle.load(asset);
    final file = File('${temp.path}/$name');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    return file.path;
  }

  test('a bright photo derives a dark-text palette, a dark one a light text',
      () async {
    final bright = await CustomBackgroundStore.install(
      await stageAsset('assets/themes/blanc.png', 'bright.jpg'),
    );
    final brightTheme = CustomBackgroundStore.current!;
    expect(brightTheme.customFile, isNotNull);
    expect(File(brightTheme.customFile!).existsSync(), isTrue);
    expect(bright, jsonEncode(CustomBackgroundStore.themeToJson(brightTheme)));
    expect(
      brightTheme.usesLightText,
      isFalse,
      reason: 'blanc.png is almost white → the text must be dark',
    );

    await CustomBackgroundStore.install(
      await stageAsset('assets/themes/nuit.png', 'dark.png'),
    );
    final darkTheme = CustomBackgroundStore.current!;
    expect(
      darkTheme.usesLightText,
      isTrue,
      reason: 'nuit.png is near-black → the text must be light',
    );
    // Replacing the photo installs a NEW file (a unique name per pick —
    // FileImage caches by path, a fixed name would keep the old photo on
    // screen) and deletes the previous one.
    expect(darkTheme.customFile, isNot(brightTheme.customFile));
    expect(File(darkTheme.customFile!).existsSync(), isTrue);
    expect(File(brightTheme.customFile!).existsSync(), isFalse);
  });

  test('the JSON round-trips through restore without decoding the image',
      () async {
    await CustomBackgroundStore.install(
      await stageAsset('assets/themes/nuit.png', 'dark.png'),
    );
    final theme = CustomBackgroundStore.current!;
    final json = jsonEncode(CustomBackgroundStore.themeToJson(theme));

    CustomBackgroundStore.restore(null);
    expect(CustomBackgroundStore.current, isNull);

    CustomBackgroundStore.restore(json);
    final restored = CustomBackgroundStore.current!;
    expect(restored.id, customThemeId);
    expect(restored.customFile, theme.customFile);
    expect(restored.backgroundTone, theme.backgroundTone);
    expect(restored.textColor, theme.textColor);
    expect(restored.titleColor, theme.titleColor);
    expect(restored.accentColor, theme.accentColor);
    expect(restored.usesLightText, theme.usesLightText);
  });

  test('a corrupted JSON degrades to no custom theme, never a crash', () {
    CustomBackgroundStore.restore('{not json');
    expect(CustomBackgroundStore.current, isNull);
  });

  test('the palette carries the photo hue, not a fixed one', () async {
    await CustomBackgroundStore.install(
      await stageAsset('assets/themes/bleu.png', 'blue.png'),
    );
    final blue = HSLColor.fromColor(CustomBackgroundStore.current!.accentColor);

    await CustomBackgroundStore.install(
      await stageAsset('assets/themes/sinai.png', 'ocre.png'),
    );
    final ocre = HSLColor.fromColor(CustomBackgroundStore.current!.accentColor);

    expect(
      blue.hue,
      inInclusiveRange(150, 280),
      reason: 'bleu.png is blue → the accent must be blue, not the old gold',
    );
    expect(
      ocre.hue,
      inInclusiveRange(5, 80),
      reason: 'sinai.png is ocre → the accent must be warm',
    );
  });

  test('delete removes the file and clears the slot; a second call is a no-op',
      () async {
    await CustomBackgroundStore.install(
      await stageAsset('assets/themes/nuit.png', 'dark.png'),
    );
    final file = CustomBackgroundStore.current!.customFile!;

    expect(await CustomBackgroundStore.delete(), isTrue);
    expect(File(file).existsSync(), isFalse);
    expect(CustomBackgroundStore.current, isNull);
    expect(await CustomBackgroundStore.delete(), isFalse);
  });

  test('themeById resolves the custom slot, and falls back when empty', () {
    expect(themeById(customThemeId).id, bibleThemes.first.id,
        reason: 'no photo picked yet → the fallback theme');
    CustomBackgroundStore.restore(
      jsonEncode(
        CustomBackgroundStore.themeToJson(
          const BibleTheme(
            id: customThemeId,
            name: 'Ma photo',
            customFile: 'X:/nowhere/photo.jpg',
            backgroundTone: Color(0xFF202020),
            textColor: Color(0xFFEEEEEE),
            titleColor: Color(0xFFF0C75C),
            verseNumColor: Color(0xFFA8B4C8),
            accentColor: Color(0xFFD9B44A),
            highlightRef: Color(0xFFE6BE55),
          ),
        ),
      ),
    );
    expect(themeById(customThemeId).name, 'Ma photo');
    expect(themeById('vitrail').id, 'vitrail',
        reason: 'catalog ids still resolve normally');
  });
}
