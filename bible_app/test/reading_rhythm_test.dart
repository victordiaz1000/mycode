import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/widgets/verse_tile.dart';

void main() {
  group('ReadingRhythm', () {
    test('at the historical default it reproduces the fixed-pixel layout', () {
      const r = ReadingRhythm(); // 16 pt, Normal
      expect(r.fontSize, 16);
      expect(r.s, 1.0);
      expect(r.tilePadV, 2);
      expect(r.textPadV, 4);
      expect(r.gutterRightPad, 8);
      expect(r.gutterTopPad, 2);
      expect(r.sectionTopPad, 14);
      expect(r.sectionBottomPad, 4);
      expect(r.letterSpacing, closeTo(0.5, 1e-9));
    });

    test('the gaps grow with the font size so big type keeps its air', () {
      const small = ReadingRhythm(fontSize: 16);
      const giant = ReadingRhythm(fontSize: 30);

      // The gap between two verses: 2·(tile bottom) + 4 + 4 + 2·(tile top).
      double interVerse(ReadingRhythm r) => 2 * r.tilePadV + 4 * r.textPadV;
      expect(interVerse(giant) / interVerse(small), closeTo(30 / 16, 1e-9));
      expect(giant.sectionTopPad, greaterThan(small.sectionTopPad));
      expect(giant.gutterRightPad, greaterThan(small.gutterRightPad));
    });

    test('the line height loosens as the glyphs grow', () {
      const small = ReadingRhythm(fontSize: 16);
      const giant = ReadingRhythm(fontSize: 30);

      // Base 1.6 : la mesure de la maquette de lecture (1.62 à 19 pt).
      expect(small.lineHeight, closeTo(1.6, 1e-9));
      expect(giant.lineHeight, closeTo(1.6 + 0.12, 1e-9));
      expect(
        ReadingRhythm(fontSize: 22).lineHeight,
        inInclusiveRange(small.lineHeight, giant.lineHeight),
      );
    });
  });

  group('ReadingSpacing', () {
    test('aéré > normal > serré on both gaps and leading', () {
      double gaps(ReadingSpacing s) =>
          ReadingRhythm(fontSize: 22, spacing: s).textPadV;
      double leading(ReadingSpacing s) =>
          ReadingRhythm(fontSize: 22, spacing: s).lineHeight;

      expect(gaps(ReadingSpacing.airy), greaterThan(gaps(ReadingSpacing.normal)));
      expect(
        gaps(ReadingSpacing.normal),
        greaterThan(gaps(ReadingSpacing.compact)),
      );
      expect(
        leading(ReadingSpacing.airy),
        greaterThan(leading(ReadingSpacing.normal)),
      );
      expect(
        leading(ReadingSpacing.normal),
        greaterThan(leading(ReadingSpacing.compact)),
      );
    });

    test('normal is the fallback for unknown or missing stored values', () {
      expect(ReadingSpacing.nearest(null), ReadingSpacing.normal);
      expect(ReadingSpacing.nearest('nimporte-quoi'), ReadingSpacing.normal);
      expect(
        ReadingSpacing.nearest(ReadingSpacing.airy.name),
        ReadingSpacing.airy,
      );
    });

    test('normal leaves the size-derived rhythm untouched', () {
      const sized = ReadingRhythm(fontSize: 26, spacing: ReadingSpacing.normal);
      expect(sized.lineHeight, closeTo(1.6 + 0.12 * (10 / 14), 1e-9));
    });
  });
}
