import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';

/// Un fond de livres dont le texte peut changer sous le lecteur, comme le fait
/// une mise à jour installée : le même livre, un verset corrigé.
class _MutableBibleBundle extends FakeBibleBundle {
  _MutableBibleBundle() : super(chapters: 3);

  /// Bascule sur le texte corrigé pour toute lecture suivante.
  bool corrected = false;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final json = await super.loadString(key, cache: cache);
    return corrected
        ? json.replaceAll('Verset de test', 'Verset corrigé')
        : json;
  }
}

/// L'écran de lecture doit appliquer la correction sans être refermé : le
/// lecteur vient d'accepter la mise à jour depuis Réglages, il revient à son
/// onglet, le verset corrigé doit y être.
void main() {
  late _MutableBibleBundle bundle;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    bundle = _MutableBibleBundle();
    LocalRepository.useBundle(bundle);
  });

  tearDown(LocalRepository.useRootBundle);

  Future<void> pumpReader(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChapterReader(bookIndex: 1, chapter: 2)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('le verset corrigé apparaît sans rouvrir l\'onglet', (
    tester,
  ) async {
    await pumpReader(tester);
    expect(find.text('Verset de test Ge. 2:1.'), findsOneWidget);

    // Ce que fait `BymUpdateService.apply()` une fois les livres basculés.
    bundle.corrected = true;
    BymUpdateService.invalidateCaches();
    await tester.pumpAndSettle();

    expect(find.text('Verset corrigé Ge. 2:1.'), findsOneWidget);
    expect(find.text('Verset de test Ge. 2:1.'), findsNothing);
  });

  testWidgets('l\'onglet n\'est pas remonté, donc la position tient', (
    tester,
  ) async {
    await pumpReader(tester);
    final before = tester.state(find.byType(ChapterReader));

    bundle.corrected = true;
    BymUpdateService.invalidateCaches();
    await tester.pumpAndSettle();

    // Même `State` : le lecteur relit son livre, il ne renaît pas. Un
    // remontage perdrait le défilement, la sélection et le verset visé — un
    // prix qu'une correction de typographie ne justifie pas.
    expect(tester.state(find.byType(ChapterReader)), same(before));
  });

  testWidgets('pas de squelette de chargement pendant la relecture', (
    tester,
  ) async {
    await pumpReader(tester);

    bundle.corrected = true;
    BymUpdateService.invalidateCaches();
    // Une seule frame : c'est l'instant où le nouveau `Future` est en attente.
    // `FutureBuilder` garde la donnée du snapshot précédent, donc le texte reste
    // à l'écran au lieu de laisser la place au squelette — sinon la page
    // clignoterait et le défilement repartirait du haut.
    await tester.pump();

    expect(find.text('Verset de test Ge. 2:1.'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Verset corrigé Ge. 2:1.'), findsOneWidget);
  });
}
