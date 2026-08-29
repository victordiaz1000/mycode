import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

/// A bundle that keeps every book in flight until [release] — the cold first
/// open, where the reader still shows its loading spinner when the jump is
/// asked for.
class GatedBibleBundle extends AssetBundle {
  GatedBibleBundle({int verses = 40}) : _inner = FakeBibleBundle(verses: verses);

  final FakeBibleBundle _inner;
  final Completer<void> _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    await _gate.future;
    return _inner.loadString(key);
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

/// Tapping a note reference opens a brand-new reading tab: the shell sets the
/// [VerseTarget] *before* that tab's [ChapterReader] is built, so the target
/// is consumed from `initState` while the chapter is still loading. The jump
/// must survive that cold start instead of leaving the reader on verse 1 —
/// which only worked from the second attempt, once the book sat in cache.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('a reference jump lands on the verse on the FIRST open',
      (tester) async {
    final bundle = GatedBibleBundle();
    LocalRepository.useBundle(bundle);
    addTearDown(LocalRepository.useRootBundle);

    final target = ValueNotifier<VerseTarget?>(
      const VerseTarget(bookIndex: 1, chapter: 1, verse: 30),
    );
    addTearDown(target.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChapterReader(bookIndex: 1, chapter: 1, jumpToVerse: target),
        ),
      ),
    );
    // First frame: the reader consumed the preset target while showing the
    // loading spinner — no list, no scroll client yet.
    await tester.pump();

    // Give the old failure window time to run out BEFORE the book arrives:
    // the pre-fix jump gave up here and left the reader on verse 1.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    bundle.release();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pumpAndSettle();

    final tile = find.text('Verset de test Ge. 1:30.');
    expect(tile, findsOneWidget);
    // Built is not enough — it must be inside the viewport, not in the cache
    // extent above or below it.
    final viewport = tester.getRect(find.byType(ChapterReader));
    final rect = tester.getRect(tile);
    expect(rect.top, greaterThanOrEqualTo(viewport.top));
    expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));

    // Let the 900 ms flash timer finish so no timer is left pending.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}
