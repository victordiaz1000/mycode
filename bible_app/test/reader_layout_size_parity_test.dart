import 'package:flutter/material.dart';
// `RenderParagraph` : la mesure se fait sur l'arbre de rendu, pas sur le style
// déclaré — c'est tout l'objet du test d'échelle plus bas.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

/// Both layouts must render the verse body at exactly the same point size:
/// « Versets séparés » is the reference look, « Texte continu » follows it.
/// (The paragraph blocks receive an explicitly resolved style — a regression
/// here means someone re-read the size from the unscoped Theme.)
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3, verses: 40));
  });
  tearDown(LocalRepository.useRootBundle);

  Future<double> measure(
    WidgetTester tester,
    ReadingLayout layout,
    double fontSize, {
    String fontWeight = 'normal',
  }) async {
    SharedPreferences.setMockInitialValues({
      'reading.layout': layout.name,
      'reading.fontSize': fontSize,
      'reading.fontWeight': fontWeight,
    });
    await tester.pumpWidget(
      // A fresh key per configuration: without it pumpWidget would REUSE the
      // previous ChapterReader state and its already-loaded preferences.
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            key: ValueKey('$layout-$fontSize-$fontWeight'),
            bookIndex: 1,
            chapter: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (layout == ReadingLayout.tiles) {
      return tester
              .widget<Text>(find.text('Verset de test Ge. 2:1.'))
              .style
              ?.fontSize ??
          -1;
    }
    return tester
            .widget<RichText>(find.byType(RichText).last)
            .text
            .style
            ?.fontSize ??
        -1;
  }

  testWidgets('every text size renders identically in both layouts', (
    tester,
  ) async {
    // Phone-width viewport: the responsive ladder branches apply (<400px).
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    for (final size in ReadingTextSize.values) {
      final tiles = await measure(tester, ReadingLayout.tiles, size.fontSize);
      final para =
          await measure(tester, ReadingLayout.paragraph, size.fontSize);
      expect(
        para,
        tiles,
        reason:
            '« ${size.label} » : continu=${para}pt vs séparés=${tiles}pt',
      );
    }
  });

  /// The declared `fontSize` above is only half the story: what the reader SEES
  /// is `textScaler × fontSize`. `Text` / `Text.rich` resolve the scaler from
  /// the ambient `MediaQuery` — a bare `RichText` defaults to
  /// `TextScaler.noScaling` and silently drops it. Since `main.dart` folds the
  /// device factor and the bounded system scale into that `MediaQuery`, the
  /// continuous flow used to paint ~14 % smaller than the tiles AND than the
  /// book introduction (which is a `Text`), reading tighter and darker at the
  /// same nominal point size. This measures the EFFECTIVE size on both paths.
  testWidgets('the ambient text scaler reaches both layouts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    /// Effective painted size of the verse body, straight off the render tree.
    Future<double> effective(ReadingLayout layout, TextScaler scaler) async {
      SharedPreferences.setMockInitialValues({'reading.layout': layout.name});
      await tester.pumpWidget(
        MaterialApp(
          // Same shape as `main.dart`'s builder: the reader must inherit the
          // scaler, not the raw view one.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: child!,
          ),
          home: Scaffold(
            body: ChapterReader(
              key: ValueKey('scaled-$layout-${scaler.scale(1)}'),
              bookIndex: 1,
              chapter: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final paragraph = tester.renderObject<RenderParagraph>(
        layout == ReadingLayout.tiles
            ? find.text('Verset de test Ge. 2:1.')
            : find.byType(RichText).last,
      );
      final declared = paragraph.text.style?.fontSize ?? -1;
      return paragraph.textScaler.scale(declared);
    }

    // 1.18 is the ceiling `main.dart` clamps the system scale to; .9 is the
    // narrow-screen device factor. Both directions must hold.
    for (final scale in [0.9, 1.0, 1.18]) {
      final scaler = TextScaler.linear(scale);
      final tiles = await effective(ReadingLayout.tiles, scaler);
      final para = await effective(ReadingLayout.paragraph, scaler);
      expect(
        para,
        tiles,
        reason: 'échelle $scale : continu=${para}px vs séparés=${tiles}px',
      );
    }
  });

  testWidgets('the chosen font weight applies to both layouts', (tester) async {
    FontWeight measureWeight(WidgetTester tester, ReadingLayout layout) {
      if (layout == ReadingLayout.tiles) {
        return tester
                .widget<Text>(find.text('Verset de test Ge. 2:1.'))
                .style
                ?.fontWeight ??
            FontWeight.w400;
      }
      return tester
              .widget<RichText>(find.byType(RichText).last)
              .text
              .style
              ?.fontWeight ??
          FontWeight.w400;
    }

    Future<void> dump(ReadingFontWeight weight) async {
      SharedPreferences.setMockInitialValues({
        'reading.fontWeight': weight.name,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChapterReader(
              key: ValueKey('weight-${weight.name}'),
              bookIndex: 1,
              chapter: 2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final weight in ReadingFontWeight.values) {
      await dump(weight);
      final tiles = measureWeight(tester, ReadingLayout.tiles);
      final para = measureWeight(tester, ReadingLayout.paragraph);
      expect(tiles, weight.weight,
          reason: '${weight.label} : tuiles en ${tiles.value}');
      expect(para, weight.weight,
          reason: '${weight.label} : continu en ${para.value}');
    }
  });
}
