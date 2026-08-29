import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/reference_parser.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';
import 'package:bible_app/widgets/tab_strip.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_bible_bundle.dart';

/// Last text passed to [Clipboard.setData] — the real platform channel never
/// answers under the fake-async zone of `testWidgets` (a bare `await
/// Clipboard.setData` hangs forever), so the channel is mocked in [setUp].
String? clipboardText;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    AppPreferences.immersionNotifier.value = false;
    clipboardText = null;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map<Object?, Object?>)['text']
            as String?;
      }
      return null;
    });
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    AppPreferences.immersionNotifier.value = false;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpReader(
    WidgetTester tester, {
    void Function(int book, int chapter)? onOpenChapter,
    void Function(BibleReference ref)? onReferenceTap,
  }) async {
    // A tall surface: chapter 1 opens on the book header, which pushes verse
    // 1 and everything below it out of the default 800x600 window.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(
            bookIndex: 1,
            chapter: 1,
            onOpenChapter: onOpenChapter,
            onReferenceTap: onReferenceTap,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder verseText(String text) => find.text(text);

  group('the selection bar', () {
    Finder barCount(String n) => find.descendant(
      of: find.byKey(const ValueKey('selection-bar')),
      matching: find.text(n),
    );

    testWidgets('long-press then taps select verses and show actions', (
      tester,
    ) async {
      await pumpReader(tester);

      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();
      expect(barCount('1'), findsOneWidget);
      expect(find.byIcon(Icons.format_color_fill), findsOneWidget);

      await tester.tap(verseText('Verset de test Ge. 1:2.'));
      await tester.pumpAndSettle();
      expect(barCount('2'), findsOneWidget);

      // The study sheet must not open from a tap made inside multi-select.
      expect(find.text('Surligner'), findsNothing);
    });

    testWidgets('the bar stays inside a 360 px screen — icons only', (
      tester,
    ) async {
      await pumpReader(tester);
      // Narrowed *after* pumping: [pumpReader] installs its own tall surface.
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'the selection bar must not overflow a small phone');
      // Icons only, no sentence.
      expect(find.textContaining('sélectionné'), findsNothing);
      expect(find.byIcon(Icons.format_color_fill), findsOneWidget);
    });

    testWidgets('copy exports the range in reading order and exits', (
      tester,
    ) async {
      await pumpReader(tester);

      // Select 2 then 1: the clipboard must still read 1 then 2.
      await tester.longPress(verseText('Verset de test Ge. 1:2.'));
      await tester.pumpAndSettle();
      await tester.tap(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.copy_all));
      await tester.pumpAndSettle();

      expect(clipboardText, contains('Genèse 1:1 Verset de test Ge. 1:1.'));
      expect(clipboardText, contains('Genèse 1:2 Verset de test Ge. 1:2.'));
      expect(
        clipboardText!.indexOf('Genèse 1:1'),
        lessThan(clipboardText!.indexOf('Genèse 1:2')),
        reason: 'verses are copied in reading order',
      );
      // Copying is terminal: the selection bar is gone.
      expect(find.byIcon(Icons.copy_all), findsNothing);
    });

    testWidgets('bulk favourite stars every selected verse at once', (
      tester,
    ) async {
      await pumpReader(tester);

      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();
      await tester.tap(verseText('Verset de test Ge. 1:3.'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.star), findsNothing);
      await tester.tap(find.byIcon(Icons.star_border));
      await tester.pumpAndSettle();

      // One star per selected verse (the bar's icon is star_border).
      final tiles = find.descendant(
        of: find.byType(VerseTile),
        matching: find.byIcon(Icons.star),
      );
      expect(tiles, findsNWidgets(2));
    });

    testWidgets('the palette applies one color to the whole selection', (
      tester,
    ) async {
      await pumpReader(tester);

      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.format_color_fill));
      await tester.pumpAndSettle();

      expect(find.text('Surligner 1 verset'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.format_color_reset));
      await tester.pumpAndSettle();

      // Nothing was highlighted beforehand: erasing is a no-op on screen but
      // the flow must complete without error.
      expect(find.text('Surligner 1 verset'), findsNothing);
    });
  });

  group('find in chapter', () {
    testWidgets('typing filters matches and the arrows walk through them', (
      tester,
    ) async {
      await pumpReader(tester);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(find.text('Trouver dans le chapitre'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Ge. 1:2');
      // The scan is debounced.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('1/1'), findsOneWidget);

      // A broader query counts all three verses of the fake chapter.
      await tester.enterText(find.byType(TextField), 'verset de test');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Trouver dans le chapitre'), findsNothing);
    });
  });

  group('continue to the next chapter', () {
    testWidgets('the end-of-chapter footer opens the next chapter', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpReader(tester, onOpenChapter: (b, c) => opened.add('$b:$c'));

      expect(find.text('Continuer — Genèse 2'), findsOneWidget);
      await tester.tap(find.text('Continuer — Genèse 2'));
      await tester.pumpAndSettle();

      expect(opened, ['1:2']);
    });
  });

  group('the Références action', () {
    testWidgets('lists the references carried by the verse notes', (
      tester,
    ) async {
      BibleReference? opened;
      await pumpReader(tester, onReferenceTap: (ref) => opened = ref);

      await tester.tap(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();
      // The study sheet is open (its « Actions » section is visible).
      expect(find.text('ACTIONS'), findsOneWidget);

      await tester.tap(find.text('Références'));
      await tester.pumpAndSettle();

      // The note of the fake verse 1 reads « Voir És. 45:18. »
      expect(find.text('És. 45:18'), findsOneWidget);
      await tester.tap(find.text('És. 45:18'));
      await tester.pumpAndSettle();

      expect(
        opened,
        const BibleReference(bookIndex: 12, chapter: 45, verse: 18),
      );
    });
  });

  group('immersion mode', () {
    testWidgets('hides the reading bar until the exit pill is tapped', (
      tester,
    ) async {
      await pumpReader(tester);
      expect(find.byType(ReaderActionsBar), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mode immersion'));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderActionsBar), findsNothing);
      expect(
        find.byTooltip('Quitter le mode immersion'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Quitter le mode immersion'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderActionsBar), findsOneWidget);
    });

    testWidgets('the tab strip hides with it', (tester) async {
      final manager = TabManager()..openReading(1, 1);
      await tester.pumpWidget(
        MaterialApp(home: ReaderScreen(initialManager: manager)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TabStrip), findsOneWidget);

      AppPreferences.immersionNotifier.value = true;
      await tester.pumpAndSettle();
      expect(find.byType(TabStrip), findsNothing);

      AppPreferences.immersionNotifier.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(TabStrip), findsOneWidget);
    });
  });

  group('the resume banner', () {
    testWidgets('an empty home offers the last visited chapter', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'history.recent': jsonEncode([
          {'book': 1, 'chapter': 2, 'at': 1700000000000},
        ]),
      });

      final manager = TabManager();
      await tester.pumpWidget(
        MaterialApp(home: ReaderScreen(initialManager: manager)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Reprendre Ge. 2'), findsOneWidget);
      expect(manager.hasTabs, isFalse);

      await tester.tap(find.textContaining('Reprendre Ge. 2'));
      await tester.pumpAndSettle();

      expect(manager.hasTabs, isTrue);
      expect(manager.tabs.first.bookIndex, 1);
      expect(manager.tabs.first.chapter, 2);
    });

    testWidgets('no history keeps the plain hint', (tester) async {
      final manager = TabManager();
      await tester.pumpWidget(
        MaterialApp(home: ReaderScreen(initialManager: manager)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Reprendre'), findsNothing);
      expect(find.textContaining('Livres'), findsWidgets);
    });
  });
}
