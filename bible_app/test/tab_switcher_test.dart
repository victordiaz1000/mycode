import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/widgets/tab_switcher.dart';

void main() {
  testWidgets('switcher shows cards + recently closed + actions',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.close(0); // → recently closed (Genèse 1)
    m.openReading(12, 40); // active Ésaïe 40

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));

    expect(find.text('1 onglet'), findsOneWidget);
    expect(find.text('És. 40'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Rouvrir'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Fermés récemment'), findsOneWidget);
    expect(find.text('Rouvrir'), findsOneWidget);
  });

  testWidgets('tapping a card activates and closes the switcher',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(40, 40);
    m.activate(0);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.tap(find.text('Mt. 40').last);
    await tester.pumpAndSettle();

    expect(m.activeIndex, 1);
  });

  testWidgets('active card is highlighted with a gold border',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));

    final container = tester.widget<Container>(find
        .byWidgetPredicate((w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border is Border)
        .first);
    final border =
        ((container.decoration as BoxDecoration).border! as Border);
    expect(border.top.color, const Color(0xFFB8860B));
  });

  testWidgets('Rouvrir restores a closed tab', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.close(0);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.tap(find.text('Rouvrir'));
    await tester.pump();

    expect(m.count, 1);
    expect(m.active!.title, 'Ge. 1');
    expect(m.recentlyClosed, isEmpty);
  });

  testWidgets('Tout fermer clears open tabs', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(2, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.tap(find.byTooltip('Tout fermer'));
    await tester.pump();

    expect(m.count, 0);
    expect(m.activeIndex, -1);
  });
}