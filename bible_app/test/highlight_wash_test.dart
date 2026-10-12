import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/user_data.dart';

void main() {
  BibleTheme theme(String id) =>
      bibleThemes.firstWhere((t) => t.id == id);

  group('highlightWash', () {
    test('a light theme keeps the pastel translucent', () {
      final light = theme('parchemin');
      expect(light.usesLightText, isFalse);

      final wash = light.highlightWash('#fff3b0');
      expect(wash.a, moreOrLessEquals(0x8C / 0xFF, epsilon: 0.01));
    });

    test('a dark theme deepens the hue instead of muddying it', () {
      final dark = theme('nuit');
      expect(dark.usesLightText, isTrue,
          reason: 'nuit est le thème noir du lot');

      for (final hex in highlightColors) {
        final wash = dark.highlightWash(hex);
        final hsl = HSLColor.fromColor(wash);
        // Assez sombre pour porter un texte clair, assez coloré pour rester
        // un surlignage — pas le gris flou du pastel à 55 % sur fond noir.
        expect(hsl.lightness, inInclusiveRange(0.10, 0.50), reason: hex);
        expect(wash.a, 1.0, reason: hex);
      }
    });

    test('every dark theme of the catalogue stays readable', () {
      for (final t in bibleThemes.where((t) => t.usesLightText)) {
        for (final hex in highlightColors) {
          final wash = t.highlightWash(hex);
          final hsl = HSLColor.fromColor(wash);
          expect(hsl.lightness, inInclusiveRange(0.10, 0.55),
              reason: '${t.id} $hex');
        }
      }
    });

    test('the dot previews the wash, opaque', () {
      final dark = theme('nuit');
      for (final hex in highlightColors) {
        final dot = dark.highlightDot(hex);
        expect(dot.a, 1.0, reason: hex);
        expect(dot.value & 0xFFFFFF,
            dark.highlightWash(hex).value & 0xFFFFFF,
            reason: hex);
      }
      final light = theme('parchemin');
      expect(light.highlightDot('#fff3b0'), const Color(0xFFFFF3B0));
    });
  });
}
