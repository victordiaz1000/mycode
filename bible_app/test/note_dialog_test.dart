import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/widgets/note_dialog.dart';

/// The note editor of the study sheet. It used to keep its
/// [TextEditingController] in the reader and dispose it right after
/// `showDialog` returned — but a route pops *before* its exit fade ends, and
/// the fade's re-subscription touched the disposed controller:
/// `A TextEditingController was used after being disposed` (the red error
/// screen). These tests hold the contract that the dialog owns its controller
/// and never crashes while closing.
void main() {
  /// Opens the dialog over a bare screen; `result` receives its outcome.
  Future<void> pumpDialog(
    WidgetTester tester, {
    String initialText = '',
    bool showDelete = false,
    required void Function(NoteDialogResult?) onResult,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final r = await showDialog<NoteDialogResult>(
                context: context,
                builder: (context) => NoteDialog(
                  title: 'Note — 1:1',
                  initialText: initialText,
                  showDelete: showDelete,
                ),
              );
              onResult(r);
            },
            child: const Text('ouvrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('annuler closes the dialog without crashing', (tester) async {
    NoteDialogResult? result;
    await pumpDialog(tester, onResult: (r) => result = r);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the disposed-controller crash on cancel');
    expect(result?.kind, NoteDialogResultKind.cancelled);
  });

  testWidgets('the keyboard escape closes the dialog without crashing',
      (tester) async {
    await pumpDialog(tester, onResult: (_) {});

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('enregistrer reports the trimmed text', (tester) async {
    NoteDialogResult? result;
    await pumpDialog(tester, onResult: (r) => result = r);

    await tester.enterText(find.byType(TextField), '  ma note  ');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.kind, NoteDialogResultKind.saved);
    expect(result?.text, 'ma note');
  });

  testWidgets('enregistrer with an empty text acts as a cancel',
      (tester) async {
    NoteDialogResult? result;
    await pumpDialog(tester, onResult: (r) => result = r);

    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(result?.kind, NoteDialogResultKind.cancelled);
  });

  testWidgets('supprimer appears only for an existing note and reports it',
      (tester) async {
    NoteDialogResult? result;
    await pumpDialog(tester, showDelete: true, onResult: (r) => result = r);

    expect(find.text('Supprimer'), findsOneWidget);
    await tester.tap(find.text('Supprimer'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.kind, NoteDialogResultKind.deleted);
  });

  testWidgets('supprimer is absent for a brand-new note', (tester) async {
    await pumpDialog(tester, onResult: (_) {});

    expect(find.text('Supprimer'), findsNothing);
  });
}