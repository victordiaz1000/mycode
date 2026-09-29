import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/data/bym_update_store.dart';
import 'package:bible_app/main.dart';

/// Quand la vérification quotidienne a réellement lieu.
///
/// `initState` ne s'exécute qu'au démarrage à froid du processus. Android garde
/// volontiers une application en mémoire pendant des jours : sans crochet sur le
/// retour au premier plan, l'intervalle de 24 h serait un plafond sans plancher —
/// « au plus une fois par jour », jamais « au moins ». Ces deux tests tiennent
/// les deux bouts : le retour redonne sa chance à la vérification, et le verrou
/// des 24 h la retient quand même.
void main() {
  /// Requêtes sorties du service, dans l'ordre. C'est le seul signal fiable :
  /// compter les appels à `maybeCheck` ne distinguerait pas une vérification
  /// menée d'une vérification retenue par le verrou, qui est justement ce qu'on
  /// veut séparer ici.
  late List<String> requested;

  setUp(() {
    requested = <String>[];
    SharedPreferences.setMockInitialValues({});
    BymUpdateStore.resetInMemory();
    // Une panne serveur suffit : on mesure qu'une requête part, pas ce qu'elle
    // rapporte. Aucun octet ne quitte la machine de test.
    BymUpdateChecker.debugServiceFactory = () => BymUpdateService(
      client: MockClient((request) async {
        requested.add(request.url.path);
        return http.Response('', 500);
      }),
    );
  });

  tearDown(() {
    BymUpdateChecker.debugServiceFactory = null;
    BymUpdateChecker.clear();
    BymUpdateStore.resetInMemory();
  });

  /// Un aller-retour en arrière-plan, tel que le système le signale.
  ///
  /// `paused` avant `resumed` : la liaison ignore un état identique au courant,
  /// donc un `resumed` seul, sur une application déjà au premier plan, ne
  /// réveillerait personne — et le test passerait pour de mauvaises raisons.
  Future<void> retourAuPremierPlan(WidgetTester tester) async {
    for (final state in const [
      'AppLifecycleState.paused',
      'AppLifecycleState.resumed',
    ]) {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state),
        (_) {},
      );
    }
    await tester.pumpAndSettle();
  }

  testWidgets('un retour au premier plan redonne sa chance à la vérification', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();
    // Le démarrage à froid a déjà vérifié : c'est le comportement d'avant, et il
    // doit rester. On repart de zéro pour ne mesurer que le retour.
    expect(requested, isNotEmpty, reason: 'le démarrage à froid vérifie');
    requested.clear();

    await retourAuPremierPlan(tester);

    expect(
      requested,
      isNotEmpty,
      reason: 'sans ce crochet, une application jamais fermée ne vérifie jamais',
    );
  });

  testWidgets('le verrou des 24 h tient malgré les allers-retours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;

    await tester.pumpWidget(const BymApp());
    await tester.pumpAndSettle();

    // Ce qu'une vérification réussie aurait laissé.
    await BymUpdateStore().markChecked(DateTime.now());
    requested.clear();

    await retourAuPremierPlan(tester);
    await retourAuPremierPlan(tester);
    await retourAuPremierPlan(tester);

    expect(
      requested,
      isEmpty,
      reason: 'le crochet ajoute des occasions de vérifier, pas des requêtes',
    );
  });
}
