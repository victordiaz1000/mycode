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

import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// The LSGS reading contract: a Strong code in the verse is tappable and opens
/// the complete Strong detail screen; the words elsewhere keep opening the
/// study sheet, whose Lexique button is off — the reader already sees the
/// Strong text word by word.
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

  Future<void> pumpLsgsReader(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            initialVersionCode: VersionRepository.lsgsCode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The RichText that carries the LSGS corpus text (verse 1, « AA H7225 »).
  Finder strongVerseText() => find.byWidgetPredicate(
    (w) => w is RichText && w.text.toPlainText() == 'AA H7225',
  );

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

  testWidgets('tapping a Strong code opens the Strong detail screen', (
    tester,
  ) async {
    await pumpLsgsReader(tester);

    // The Strong span opens the same complete fiche as the Strong dictionary,
    // not the study sheet or the old quick modal.
    await tapStrongCode(tester);

    expect(find.byType(EtudeVersetScreen), findsNothing);
    expect(find.byType(StrongDetailScreen), findsOneWidget);
    // The fake lexicon serves a definition for H7225.
    expect(find.text('H7225'), findsWidgets);
    expect(
      find.text('Définition test de H7225.'),
      findsWidgets,
      reason: 'the Strong code opens the complete detail screen',
    );
  });

  testWidgets('an occurrence verse tapped in the fiche targets the reader', (
    tester,
  ) async {
    await pumpLsgsReader(tester);

    await tapStrongCode(tester);
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

  testWidgets(
    'the Lexique button of the study sheet is off in LSGS',
    (tester) async {
      await pumpLsgsReader(tester);

      // Verse 2 bears no Strong code — the study sheet opens on tap.
      await tester.tap(find.text('Au commencement'));
      await tester.pumpAndSettle();

      // LSGS already renders every Strong code word by word, so the Lexique
      // button stays off rather than open a screen the reader already sees.
      final lexiqueButton = find.widgetWithText(
        OutlinedButton,
        'Lexique & Dictionnaire — verset mot à mot',
      );
      await tester.ensureVisible(lexiqueButton);
      await tester.pumpAndSettle();
      final button = tester.widget<OutlinedButton>(lexiqueButton);
      expect(button.onPressed, isNull);
      expect(find.byType(EtudeVersetScreen), findsNothing);

      // Et il le *montre* : hors BYM le bouton n'est pas seulement sourd, il est
      // grisé et dit où le mot à mot s'ouvre. Vérifié depuis le lecteur, donc en
      // passant par le vrai garde-fou (`carriesNotes`) et pas par un drapeau
      // posé à la main comme dans `study_sheet_test.dart`.
      expect(find.text('Disponible depuis le texte BYM.'), findsOneWidget);
    },
  );

  testWidgets('the Lexique button is off on the LSGS verse', (tester) async {
    await pumpLsgsReader(tester);

    await tester.tap(find.text('Au commencement'));
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(
        OutlinedButton,
        'Lexique & Dictionnaire — verset mot à mot',
      ),
    );
    expect(button.onPressed, isNull,
        reason: 'LSGS is already the word-by-word Strong rendering');
  });
}
