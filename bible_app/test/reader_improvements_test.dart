import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/reference_parser.dart';
import 'package:bible_app/data/share_text.dart';
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

    testWidgets('la sélection se partage comme le verset, et ne se ferme pas', (
      tester,
    ) async {
      final previous = shareText;
      var shared = '';
      shareText = (message, {origin}) async => shared = message;
      addTearDown(() => shareText = previous);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
            copied =
                (message.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpReader(tester);
      // A long press opens the selection; a second verse joins it.
      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();
      await tester.tap(verseText('Verset de test Ge. 1:2.'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Partager les versets'));
      await tester.pumpAndSettle();

      expect(shared, contains('« Verset de test Ge. 1:1.'));
      expect(shared, contains('« Verset de test Ge. 1:2.'));
      // A contiguous selection is attributed as a range.
      expect(shared.trim(), endsWith('— Bereshit 1:1-2'));
      expect(shared.split('\n').first, appName,
          reason: 'la sélection partagée s\'ouvre sur le nom de l\'app');
      // Sharing is not terminal: the sheet is its own visible feedback, and the
      // reader may have more to do with these verses.
      expect(find.byTooltip('Partager les versets'), findsOneWidget);

      // Copy says the same thing: the app's name first, then one
      // reference-first line per verse.
      await tester.tap(find.byTooltip('Copier les versets'));
      await tester.pumpAndSettle();
      expect(copied, contains('Bereshit 1:1 Verset de test Ge. 1:1.'));
      expect(copied, contains('Bereshit 1:2 Verset de test Ge. 1:2.'));
      expect(copied!.split('\n').first, appName,
          reason: 'le nom de l\'app n\'apparaît qu\'une fois, en tête');
    });

    testWidgets('the bar stays inside a 320 px screen with five actions', (
      tester,
    ) async {
      await pumpReader(tester);
      // Narrowed *after* pumping: [pumpReader] installs its own tall surface.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.longPress(verseText('Verset de test Ge. 1:1.'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'the selection bar must not overflow the narrowest phone');
      for (final tooltip in [
        'Surligner la sélection',
        'Favoris sur la sélection',
        'Copier les versets',
        'Partager les versets',
        'Terminer la sélection',
      ]) {
        final bouton = find.byTooltip(tooltip);
        expect(bouton, findsOneWidget, reason: '« $tooltip » doit être là');
        expect(
          tester.getRect(bouton).right,
          lessThanOrEqualTo(320),
          reason: '« $tooltip » déborde de l\'écran',
        );
      }
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

      expect(clipboardText, contains('Bereshit 1:1 Verset de test Ge. 1:1.'));
      expect(clipboardText, contains('Bereshit 1:2 Verset de test Ge. 1:2.'));
      expect(
        clipboardText!.indexOf('Bereshit 1:1'),
        lessThan(clipboardText!.indexOf('Bereshit 1:2')),
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

    testWidgets('sur petit écran l\'icône quitte la barre pour la feuille ⋯', (
      tester,
    ) async {
      // Pas `pumpReader` : ce helper impose 800 de large, qui est justement
      // la largeur où l'icône DOIT être là. Téléphone en portrait.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
        ),
      );
      await tester.pumpAndSettle();

      // 390 de large : l'icône de recherche ne tient plus dans la barre.
      expect(find.byIcon(Icons.search), findsNothing);

      // La fonction, elle, ne part pas : elle rejoint la feuille ⋯.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      final entry = find.widgetWithText(
        OutlinedButton,
        'Trouver dans le chapitre',
      );
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();

      // La feuille s'est refermée : le champ de recherche s'est ouvert —
      // même libellé, cette fois en indice de champ.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Trouver dans le chapitre'), findsOneWidget);
    });
  });

  group('continue to the next chapter', () {
    testWidgets('the end-of-chapter footer opens the next chapter', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpReader(tester, onOpenChapter: (b, c) => opened.add('$b:$c'));

      // Same book, next chapter — and the BYM's own name for it, like the pill
      // above.
      expect(find.text('Continuer — Bereshit 2'), findsOneWidget);
      await tester.tap(find.text('Continuer — Bereshit 2'));
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
