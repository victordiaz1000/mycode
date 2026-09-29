import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/share_text.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

/// The study sheet's « Partager » and « Copier » carry the full reference
/// (book + chapter + verse), not a bare verse number.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
  });

  testWidgets('Partager hands the reference and text to the system share',
      (tester) async {
    final previous = shareText;
    var shared = '';
    Rect? anchor;
    shareText = (message, {Rect? origin}) async {
      shared = message;
      anchor = origin;
    };
    addTearDown(() => shareText = previous);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
    ));
    await tester.pumpAndSettle();


    await tester.dragUntilVisible(
      find.text('Verset de test Ge. 1:1.'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verset de test Ge. 1:1.'));
    await tester.pumpAndSettle();

    // The action grid sits under the fold of the sheet's own list on the
    // small test surface — bring « Partager » into view before tapping.
    await tester.dragUntilVisible(
      find.text('Partager'),
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Partager'));
    await tester.pumpAndSettle();

    expect(shared, contains('Verset de test Ge. 1:1.'));
    expect(shared, contains('Bereshit 1:1'));
    expect(
      shared.split('\n').first,
      appName,
      reason: 'le partage s\'ouvre sur le nom de l\'app',
    );
    // The sheet is given an anchor: without one `share_plus` has nothing to
    // position against, which is the classic tablet misplacement.
    expect(anchor, isNotNull, reason: 'la feuille doit avoir une origine');
  });

  testWidgets('Copier carries the reference too', (tester) async {
    // Clipboard.setData goes through a platform channel: without a handler it
    // never answers inside fake-async and the test hangs forever. Capture the
    // payload at the channel boundary instead.
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          copied = (message.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 1)),
    ));
    await tester.pumpAndSettle();


    await tester.dragUntilVisible(
      find.text('Verset de test Ge. 1:1.'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verset de test Ge. 1:1.'));
    await tester.pumpAndSettle();

    // Same fold as « Partager » : scroll the sheet before tapping.
    await tester.dragUntilVisible(
      find.text('Copier'),
      find.byType(ListView).last,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copier'));
    await tester.pumpAndSettle();

    // Exact, not `contains`: the shape *is* the contract, and a loose matcher
    // let the inline format drift back in unnoticed.
    expect(copied, '$appName\nBereshit 1:1 Verset de test Ge. 1:1.',
        reason: 'le nom de l\'app ouvre la copie, puis la référence en tête');
  });
}
