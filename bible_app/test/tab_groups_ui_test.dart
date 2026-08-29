import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/models/tab_group.dart';
import 'package:bible_app/widgets/tab_strip.dart';
import 'package:bible_app/widgets/tab_switcher.dart';

void main() {
  testWidgets('grouped tabs render as named sections, ungrouped last',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(27, 23);
    final g =
        m.createGroup(name: 'Lecture du soir', color: TabGroupColor.violet);
    m.assignTabToGroup(0, g.id);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));

    expect(find.text('Lecture du soir'), findsOneWidget);
    // Only the grouped tab is on screen: Ps. 23 lives in the ungrouped
    // section, under the fold of the lazy list.
    expect(find.text('Ge. 1'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Sans groupe'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('Ps. 23'), findsWidgets);
  });

  testWidgets('the chevron folds a group away', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    expect(find.text('Ge. 1'), findsWidgets);
    expect(m.groups.single.collapsed, isFalse);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(m.groups.single.collapsed, isTrue);
    // Folded: no member cards in the section anymore.
    expect(find.text('Ge. 1'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(m.groups.single.collapsed, isFalse);
    expect(find.text('Ge. 1'), findsWidgets);
  });

  testWidgets('✕ on the group header closes every member at once',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    m.openReading(27, 23);
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);
    m.assignTabToGroup(1, g.id);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.tap(find.byIcon(Icons.close).first); // group header ✕
    await tester.pump();

    expect(m.count, 0);
    expect(m.recentlyClosed.length, 2);
    expect(
        m.recentlyClosed.every((t) => t.groupId == g.id), isTrue);
  });

  testWidgets('long-pressing a card opens the context menu', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.longPress(find.text('Ge. 1').first);
    await tester.pumpAndSettle();

    expect(find.text("Épingler l'onglet"), findsOneWidget);
    expect(find.text('Dupliquer'), findsOneWidget);
    expect(find.text('Ajouter au groupe…'), findsOneWidget);
    expect(find.text("Fermer l'onglet"), findsOneWidget);
  });

  testWidgets('the context menu pins the tab', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.longPress(find.text('Ge. 1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text("Épingler l'onglet"));
    await tester.pumpAndSettle();

    expect(m.tabs.single.pinned, isTrue);
  });

  testWidgets('the context menu duplicates the tab', (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.longPress(find.text('Ge. 1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dupliquer'));
    await tester.pumpAndSettle();

    expect(m.count, 2);
    expect(m.active!.bookIndex, 1);
  });

  testWidgets('the context menu creates a group and assigns the tab',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.longPress(find.text('Ge. 1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter au groupe…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau groupe…'));
    await tester.pumpAndSettle();

    // Group editor dialog.
    await tester.enterText(find.byType(TextField), 'Le berger');
    await tester.tap(find.text('Créer'));
    await tester.pumpAndSettle();

    expect(m.groups.single.name, 'Le berger');
    expect(m.tabs.single.groupId, m.groups.single.id);
  });

  testWidgets('tapping a group name opens the rename editor',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);
    final g = m.createGroup(name: 'Soir', color: TabGroupColor.or);
    m.assignTabToGroup(0, g.id);

    await tester.pumpWidget(MaterialApp(home: TabSwitcher(manager: m)));
    await tester.tap(find.text('Soir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Lecture du soir');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(m.groups.single.name, 'Lecture du soir');
  });

  testWidgets('long-pressing a strip chip opens the same context menu',
      (tester) async {
    final m = TabManager();
    m.openReading(1, 1);

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TabStrip(manager: m, onOpenSwitcher: () {}))));
    await tester.longPress(find.text('Ge. 1'));
    await tester.pumpAndSettle();

    expect(find.text("Épingler l'onglet"), findsOneWidget);
    expect(find.text("Fermer l'onglet"), findsOneWidget);
  });
}
