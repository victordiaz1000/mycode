import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/widgets/tab_strip.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('TabStrip renders tabs and the gold counter', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(40, 5);

    await tester.pumpWidget(wrap(TabStrip(manager: m, onOpenSwitcher: () {})));

    expect(find.text('Ge. 1'), findsOneWidget);
    expect(find.text('Mt. 5'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // gold counter
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('tapping a tab activates it', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(40, 40);
    expect(m.activeIndex, 1);

    await tester.pumpWidget(wrap(TabStrip(manager: m, onOpenSwitcher: () {})));
    await tester.tap(find.text('Ge. 1'));
    await tester.pump();

    expect(m.activeIndex, 0);
  });

  testWidgets('closing a tab via its ✕ removes it', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(40, 40);

    await tester.pumpWidget(wrap(TabStrip(manager: m, onOpenSwitcher: () {})));

    // Two close icons exist; close the active one (Mt. 40) → goes to recent.
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();

    expect(m.count, 1);
    expect(m.tabs.single.title, 'Ge. 1');
    expect(m.recentlyClosed.single.title, 'Mt. 40');
  });

  testWidgets('➕ opens a home tab', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(wrap(TabStrip(manager: m, onOpenSwitcher: () {})));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(m.count, 2);
    expect(m.active!.isHome, isTrue);
  });

  testWidgets('counter opens the switcher callback', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    var opened = false;

    await tester.pumpWidget(wrap(
        TabStrip(manager: m, onOpenSwitcher: () => opened = true)));
    await tester.tap(find.text('1'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('pinned tab shows a pin icon', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.togglePin(0);

    await tester.pumpWidget(wrap(TabStrip(manager: m, onOpenSwitcher: () {})));

    expect(find.byIcon(Icons.push_pin), findsOneWidget);
  });
}