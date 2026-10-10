import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/etude_verset_screen.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// The Strong reading contract, on the two embedded Segond corpora: a Strong
/// code in the verse opens the extract sheet — what the entry is, with a button
/// to the complete fiche — while a tap on the verse itself opens nothing: the
/// study sheet (Note, Comparer, Partager…) belongs to versions read as a
/// continuous text, and a Strong-tagged corpus reads word by word. The long
/// press still selects the verse. The LSS is the LSGS's denser twin (it also
/// numbers the particles French does not render) and follows the same rules —
/// it is read as a version like any other, not only as the lexicon's corpus.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    VersionRepository.clearCache();
  });

  Future<void> pumpReader(WidgetTester tester, String code) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            initialVersionCode: code,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpLsgsReader(WidgetTester tester) =>
      pumpReader(tester, VersionRepository.lsgsCode);

  /// The RichText that carries the corpus text of verse 1 — `full` names which
  /// corpus: the LSGS renders « AA H7225 », the LSS adds the waw it numbers
  /// (« AA H7225 H8804 »).
  Finder strongVerseText([String full = 'AA H7225']) => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == full,
  );

  /// Taps inside the recognised span of the Strong code, not the centre of the
  /// whole RichText (which fills the reading line).
  Future<void> tapStrongCode(WidgetTester tester,
      [String full = 'AA H7225']) async {
    const code = 'H7225';
    final paragraph =
        tester.renderObject<RenderParagraph>(strongVerseText(full));
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

  testWidgets('tapping a Strong code opens the extract sheet', (tester) async {
    await pumpLsgsReader(tester);

    // The Strong span opens the extract sheet — the entry read at a glance —
    // not the study sheet, and not the complete fiche either: a first look is
    // not a study.
    await tapStrongCode(tester);

    expect(find.byType(EtudeVersetScreen), findsNothing);
    expect(find.byType(StrongDetailScreen), findsNothing,
        reason: 'the extract comes first, the fiche comes after');
    // The extract names the entry: the code, and the short definition the
    // fake lexicon serves for H7225.
    expect(find.text('Voir la fiche complète'), findsOneWidget);
    expect(
      find.text('Définition test de H7225.'),
      findsOneWidget,
      reason: 'the extract carries the brief definition',
    );

    // The button closes the sheet and pushes the complete fiche behind it.
    await tester.tap(find.text('Voir la fiche complète'));
    await tester.pumpAndSettle();

    expect(find.byType(StrongDetailScreen), findsOneWidget);
    expect(
      find.text('Définition test de H7225.'),
      findsWidgets,
      reason: 'the fiche shows the same definition, complete',
    );
  });

  testWidgets('an occurrence verse tapped in the fiche targets the reader', (
    tester,
  ) async {
    await pumpLsgsReader(tester);

    await tapStrongCode(tester);
    await tester.tap(find.text('Voir la fiche complète'));
    await tester.pumpAndSettle();
    expect(find.byType(StrongDetailScreen), findsOneWidget);

    // The fake corpus indexes H7225 at Genèse 1:1 — the very verse the reader
    // is on. Tap it: the fiche clears and the reference machinery opens the
    // chapter (standalone fallback pushes a ChapterScreen).
    await tester.scrollUntilVisible(find.text('Genèse 1:1'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Genèse 1:1'));
    await tester.pumpAndSettle();

    expect(find.byType(StrongDetailScreen), findsNothing,
        reason: 'the fiche is cleared before the reader takes over');
    expect(find.byType(ChapterScreen), findsOneWidget,
        reason: 'the standalone fallback opens the referenced chapter');
  });

  testWidgets('the study sheet never opens on an LSGS verse', (tester) async {
    await pumpLsgsReader(tester);

    // Verse 2 bears no Strong code: the tap reaches the tile and finds
    // nothing to open — Note, Comparer, Partager & co. belong to versions
    // read as a continuous text, and this one is already word by word.
    await tester.tap(find.text('Au commencement'));
    await tester.pumpAndSettle();

    expect(find.text('ACTIONS'), findsNothing);
    expect(find.text('Références'), findsNothing);
    expect(find.byType(EtudeVersetScreen), findsNothing);

    // The tile is alive all the same — the gesture machinery is there, only
    // the sheet is gone: a long press still selects the verse.
    await tester.longPress(find.text('Au commencement'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('selection-bar')),
      findsOneWidget,
      reason: 'la sélection multiple reste la voie du verset',
    );
  });

  testWidgets('the LSS reads as a version of its own, code for code', (
    tester,
  ) async {
    await pumpReader(tester, VersionRepository.lssCode);

    // The reading bar names the corpus actually read — no silent fallback to
    // the BYM, which the reader would have no way to notice.
    expect(
      find.descendant(
          of: find.byType(ReaderActionsBar), matching: find.text('LSS')),
      findsOneWidget,
    );

    // Its own text, not the LSGS one: the fake numbers the waw consecutive of
    // Genèse 1:1 only under `bible/lss/`, as the real corpus does. A reader
    // (or a `loadBook` serving the wrong folder) would show the plain verse.
    expect(strongVerseText('AA H7225 H8804'), findsOneWidget,
        reason: 'le jeton sans mot français prend la place de son code');

    // Same contract as the LSGS: the code opens the extract, the verse itself
    // opens nothing — the study sheet belongs to continuous texts.
    await tapStrongCode(tester, 'AA H7225 H8804');
    expect(find.byType(EtudeVersetScreen), findsNothing);
    expect(find.byType(StrongDetailScreen), findsNothing,
        reason: 'l\'extrait d\'abord, la fiche ensuite');
    expect(find.text('Voir la fiche complète'), findsOneWidget);
  });
}
