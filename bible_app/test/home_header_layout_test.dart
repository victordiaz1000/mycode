import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/main.dart';

import 'support/fake_bible_bundle.dart';

/// The two buttons of the Accueil header (thèmes, compteur d'onglets) sit flush
/// against the right edge of the header, whatever the width.
///
/// This is not decoration: the title beside them must stay elastic so it cannot
/// overflow on a narrow phone, and the obvious way to write that — a `Flexible`
/// around the title — silently breaks the alignment. `Flexible` is *loose*: it
/// claims only the width the text actually needs, and the leftover space lands
/// AFTER the last child, so both buttons drift inward as the screen widens (up
/// to 390 px from the edge on a 1024 px tablet). Only `Expanded` (tight) hands
/// the whole remainder to the title box and keeps the buttons pinned.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 2, verses: 8));
  });
  tearDown(LocalRepository.useRootBundle);

  /// Distance between the right edge of the thèmes button and the right edge of
  /// the screen. Flush right means this is the header's own padding plus the
  /// counter beside it — a constant, whatever room the title left over.
  Future<double> rightInset(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();

    final button = find.byIcon(Icons.palette_outlined);
    expect(button, findsOneWidget);
    return width - tester.getRect(button).right;
  }

  /// Widths are split on the 400 px « compact » breakpoint, which changes the
  /// gap between the two buttons (6 px vs 12 px) and so the inset itself. Within
  /// one regime the inset must not move at all.
  ///
  /// The wide group is what actually catches a loose title: with `Flexible` the
  /// insets there read 78 / 101.5 / 255.5 / 389.5 px instead of a flat 78.
  for (final group in const [
    ('compact', <double>[320, 360]),
    ('large', <double>[412, 480, 600, 800, 1024]),
  ]) {
    final (regime, widths) = group;
    testWidgets('the header buttons stay pinned to the right edge ($regime)', (
      tester,
    ) async {
      final insets = <double, double>{};
      for (final width in widths) {
        insets[width] = await rightInset(tester, width);
      }
      final reference = insets[widths.first]!;
      for (final entry in insets.entries) {
        expect(
          entry.value,
          moreOrLessEquals(reference, epsilon: 0.5),
          reason: 'les boutons se décollent du bord : '
              '${entry.value.toStringAsFixed(1)} px à ${entry.key.toInt()} '
              'contre ${reference.toStringAsFixed(1)} px à '
              '${widths.first.toInt()} — le titre doit être dans un `Expanded`, '
              'pas un `Flexible`',
        );
      }
    });
  }
}
