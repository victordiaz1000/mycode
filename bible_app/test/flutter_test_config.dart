import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Amorce partagée des suites : exécutée avant chaque fichier de test.
///
/// Elle charge les polices embarquées dans la collection de polices du test.
/// Sans cela, `flutter test` rend TOUT le texte avec sa police de test interne,
/// où chaque glyphe est un carré de 1 em quelle que soit la famille demandée —
/// des métriques qui ne ressemblent à aucun appareil, et qui rendent muet tout
/// test de débordement horizontal.
///
/// Ce chargement était auparavant un effet de bord de `google_fonts` : il
/// appelait `FontLoader` sur les fichiers trouvés dans le manifest d'assets. La
/// dépendance a été retirée (l'application nomme sa famille embarquée
/// directement), donc le chargement devient explicite ici — au bon endroit, et
/// pour toutes les familles déclarées, non plus seulement celles dont le nom de
/// fichier suivait la convention de ce paquet.
Future<void> testExecutable(Future<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await _chargerPolicesEmbarquees();
  await testMain();
}

/// Familles chargées, et seulement elles : le dossier complet pèse ~15 Mo, ce
/// qui se paierait à chaque fichier de test. Celles-ci sont les seules dont la
/// mise en page de l'interface dépend — la typographie du chrome et la police de
/// lecture par défaut.
const Set<String> _famillesUtiles = {'Plus Jakarta Sans', 'Lora'};

Future<void> _chargerPolicesEmbarquees() async {
  final manifest = json.decode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;

  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final family = entry['family'] as String;
    if (!_famillesUtiles.contains(family)) continue;
    final loader = FontLoader(family);
    for (final font in (entry['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}
