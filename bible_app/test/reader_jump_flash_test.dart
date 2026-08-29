import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/chapter_reader.dart';
import 'package:bible_app/widgets/verse_tile.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';

/// The wash that marks the verse a link landed on.
///
/// The bug this file guards: every verse link outside the reader — occurrence
/// Strong, référence d'une feuille d'étude, fiche de dictionnaire, note BYM,
/// résultat de recherche — goes through the shell's `_openReading`, which sets
/// BOTH the tab's `verse` (so the position survives in the tab) and the jump
/// target. On the tab that link opens, the reader therefore ran two jumps at
/// once: the flashing one from the notifier, then the silent position restore
/// on the very same verse — and the silent one, arriving a frame later, wiped
/// the flash. The link landed on the right verse with nothing to show for it.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
    LsgsRepository.useBundle(FakeLsgsBundle());
    AppPreferences.themeNotifier.value = AppPreferences.defaultThemeId;
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    AppPreferences.themeNotifier.value = AppPreferences.defaultThemeId;
  });

  Finder tileOf(int verseNumber) => find.byWidgetPredicate(
    (w) => w is VerseTile && w.verseNumber == verseNumber,
    description: 'VerseTile of verse $verseNumber',
  );

  bool isFlashing(WidgetTester tester, int verseNumber) =>
      tester.widget<VerseTile>(tileOf(verseNumber)).isFlashing;

  /// The colour actually painted behind the verse right now.
  ///
  /// Read off the [Container] that [AnimatedContainer] builds: it holds the
  /// *interpolated* decoration, so this sees the fade mid-flight and not just
  /// the target the tile asked for.
  Color? paintedBehind(WidgetTester tester, int verseNumber) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.descendant(
              of: tileOf(verseNumber),
              matching: find.byType(AnimatedContainer),
            ),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration;
    return decoration is BoxDecoration ? decoration.color : container.color;
  }

  /// Frame-by-frame, because the reader's reveal awaits `endOfFrame` until the
  /// verse list has clients: one big `pump(600ms)` advances the clock but draws
  /// a single frame, so the jump never gets off the ground. Stays well short of
  /// [kVerseFlashHold].
  Future<void> pumpFrames(WidgetTester tester, [int frames = 40]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Runs the clock past every pending reveal/flash timer so the teardown does
  /// not trip on one.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  /// Opens Genèse 2:3 exactly the way the shell does for a tapped reference:
  /// the tab carries the verse *and* the jump notifier names it.
  Future<TabManager> openByLink(WidgetTester tester) async {
    final manager = TabManager();
    final jump = ValueNotifier<VerseTarget?>(null);
    addTearDown(jump.dispose);
    manager.openReading(1, 2, verse: 3);
    jump.value = const VerseTarget(bookIndex: 1, chapter: 2, verse: 3);
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(
          child: ReaderScreen(initialManager: manager, jumpToVerse: jump),
        ),
      ),
    );
    await pumpFrames(tester);
    return manager;
  }

  testWidgets('a verse link from another screen flashes where it lands', (
    tester,
  ) async {
    final manager = await openByLink(tester);

    expect(isFlashing(tester, 3), isTrue);
    expect(manager.tabs.single.verse, 3, reason: 'and it still lands there');
    expect(isFlashing(tester, 1), isFalse);
    expect(isFlashing(tester, 2), isFalse);
    await drain(tester);
  });

  testWidgets('the wash follows the theme accent, not a fixed gold', (
    tester,
  ) async {
    // « Oliveraie » is deliberately far from the old hard-coded gold
    // (0x66D3A94F): its accent is a green, so a stale constant cannot pass.
    // Set through the store, not the notifier: `AppPreferences.load()`
    // rebroadcasts the persisted id and would undo a bare notifier write.
    SharedPreferences.setMockInitialValues({'reading.themeId': 'oliveraie'});
    await openByLink(tester);

    final expected = themeById('oliveraie').jumpFlashColor;
    expect(expected.a, closeTo(.40, .001));
    expect(paintedBehind(tester, 3), expected);
    expect(
      themeById('oliveraie').accentColor,
      isNot(const Color(0xFFD3A94F)),
      reason: 'the theme this test relies on must not be gold',
    );
    await drain(tester);
  });

  testWidgets('the wash fades out instead of popping off', (tester) async {
    await openByLink(tester);
    final full = paintedBehind(tester, 3)!;

    // Frame by frame to the end of the hold. One big `pump(kVerseFlashHold)`
    // would elapse the fade's own timer inside the same slice and the single
    // frame drawn at the end would only ever show the finished state.
    for (var i = 0; i < 200 && isFlashing(tester, 3); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(isFlashing(tester, 3), isFalse, reason: 'the hold has to expire');

    // Halfway into the fade: mid-flight, so strictly between the full wash and
    // nothing. A flat on/off snaps to transparent here — which is what the
    // flash used to do.
    await tester.pump(kVerseFlashFadeOut ~/ 2);
    final mid = paintedBehind(tester, 3)!;
    expect(mid.a, lessThan(full.a));
    expect(mid.a, greaterThan(0));

    await drain(tester);
    expect(paintedBehind(tester, 3)?.a ?? 0, 0, reason: 'and then nothing');
  });

  testWidgets('a position merely restored stays silent', (tester) async {
    // A cold restart resumes where the reader stopped — that is a place to
    // resume, not a fresh jump, and it must not flash. Same tab state as the
    // link case, minus the jump target: this is what the guard must not swallow.
    final manager = TabManager();
    manager.openReading(1, 2, verse: 3);
    await tester.pumpWidget(
      MaterialApp(
        home: BibleThemeScope(child: ReaderScreen(initialManager: manager)),
      ),
    );
    await pumpFrames(tester);

    expect(isFlashing(tester, 3), isFalse);
    expect(paintedBehind(tester, 3)?.a ?? 0, 0);
    expect(manager.tabs.single.verse, 3, reason: 'restored all the same');
    await drain(tester);
  });

  testWidgets('the flowing layout washes the verse too', (tester) async {
    // « Texte continu » paints the wash as a `background` Paint on the verse's
    // spans rather than behind a tile — the same accent has to reach it.
    SharedPreferences.setMockInitialValues({
      'reading.layout': 'paragraph',
      'reading.themeId': 'oliveraie',
    });
    await openByLink(tester);

    expect(
      tester.any(find.byType(VerseTile)),
      isFalse,
      reason: 'the flowing layout builds no tiles',
    );
    // Compared as packed ARGB: the colour makes a round trip through a `Paint`
    // here, which quantises the channels, so `==` on the doubles misses by a
    // hair.
    final wash = themeById('oliveraie').jumpFlashColor.toARGB32();
    expect(
      _spanBackgrounds(tester).where((c) => c.toARGB32() == wash),
      isNotEmpty,
      reason: 'no span carries the jump wash',
    );
    await drain(tester);
  });
}

/// Every background colour carried by a rendered span of the reading area.
///
/// Walked by hand rather than with `visitChildren`: that one skips any span
/// whose `text` is null, and the flow wraps each verse in exactly such a
/// text-less span — the one carrying the wash.
Iterable<Color> _spanBackgrounds(WidgetTester tester) {
  final colors = <Color>[];
  void walk(InlineSpan span) {
    final paint = span.style?.background;
    if (paint != null) colors.add(paint.color);
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    walk(rich.text);
  }
  return colors;
}
