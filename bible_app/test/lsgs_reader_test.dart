import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/strong_lexique_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// The LSGS reading contract: a Strong code in the verse is tappable and opens
/// the quick French definition in a bottom sheet; the words elsewhere keep
/// opening the study sheet, whose Lexique button leads to the word-by-word
/// clickable rendering.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpLsgsReader(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChapterReader(
          bookIndex: 1,
          chapter: 1,
          initialVersionCode: VersionRepository.lsgsCode,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// The RichText that carries the LSGS corpus text (verse 1, « AA H7225 »).
  Finder strongVerseText() => find.byWidgetPredicate((w) =>
      w is RichText && w.text.toPlainText() == 'AA H7225');

  /// Taps inside the recognised span of the Strong code, not the centre of the
  /// whole RichText (which fills the reading line).
  Future<void> tapStrongCode(WidgetTester tester) async {
    const code = 'H7225';
    const full = 'AA H7225';
    final paragraph = tester.renderObject<RenderParagraph>(strongVerseText());
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(
        baseOffset: full.indexOf(code),
        extentOffset: full.indexOf(code) + code.length,
      ),
    );
    expect(boxes, isNotEmpty);
    final box = boxes.first;
    await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a Strong code opens its French definition',
      (tester) async {
    await pumpLsgsReader(tester);

    // The Strong span now carries a recogniser: the tap answers with the
    // definition sheet, not the study sheet.
    await tapStrongCode(tester);

    expect(find.byType(StrongLexiqueScreen), findsNothing);
    // The fake lexicon serves a definition for H7225.
    expect(find.text('H7225'), findsWidgets);
    expect(find.text('Définition test de H7225.'), findsOneWidget,
        reason: 'the Strong code opens the definition sheet');
  });

  testWidgets('the Lexique button of the study sheet opens the Strong lexicon',
      (tester) async {
    await pumpLsgsReader(tester);

    // Verse 2 bears no Strong code — same path: tap, sheet, Lexique button.
    await tester.tap(find.text('Au commencement'));
    await tester.pumpAndSettle();

    final lexiqueButton = find.widgetWithText(
        OutlinedButton, 'Lexique Strong — verset mot à mot');
    await tester.ensureVisible(lexiqueButton);
    await tester.pumpAndSettle();
    await tester.tap(lexiqueButton);
    await tester.pumpAndSettle();

    expect(find.byType(StrongLexiqueScreen), findsOneWidget);
  });

  testWidgets('the Lexique button is enabled by the LSGS verse',
      (tester) async {
    await pumpLsgsReader(tester);

    await tester.tap(find.text('Au commencement'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(find.widgetWithText(
        OutlinedButton, 'Lexique Strong — verset mot à mot'));
    expect(button.onPressed, isNotNull);
  });
}