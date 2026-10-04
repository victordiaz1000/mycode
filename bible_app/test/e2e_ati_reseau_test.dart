// Bout en bout de l'ATI contre le dépôt publié, réseau réel.
//
//   Bibliothèque → ATI → Télécharger → 39/39 → Genèse 1
//
// Passe par les URL de `urlTemplate` telles que `DownloadService` les
// construit, le stockage gzip de `LibraryStore`, puis `VersionRepository` et
// `bookFromAti`. Ni bundle d'assets non plus — `loadBook('ATI', …)` ne passe
// pas par la BYM.
//
// `flutter_test_config.dart` pose pour toute la suite un `HttpClient`
// fantôme qui répond 400 : le setUp rend le réseau réel. La suite par défaut
// ne doit rien devoir à GitHub, donc le test est sauté sauf demande
// explicite —
//
//   BYM_E2E=1 flutter test test/e2e_ati_reseau_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';

void main() {
  // Sauté par défaut : la suite ne doit rien devoir à un réseau.
  final optIn = Platform.environment['BYM_E2E'] == '1';

  late Directory temp;
  late LibraryStore store;

  setUp(() async {
    // `flutter_test_config.dart` pose un HttpClient fantôme (400 partout) pour
    // toute la suite : ici on va chercher GitHub, on le remet donc réel.
    HttpOverrides.global = null;
    // L'état des versions vit dans les préférences : sans boutique mockée,
    // `getInstance` répond MissingPluginException même avec le binding.
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_e2e_ati');
    LibraryStore.useRoot(temp);
    VersionRepository.clearCache();
    store = LibraryStore();
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    VersionRepository.clearCache();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'ATI : 39/39 téléchargés puis Genèse 1 lue, réseau réel',
    () async {
    // ignore: avoid_print
    print('HttpOverrides.current = ${HttpOverrides.current}');
    final probe = await HttpClient()
        .getUrl(Uri.parse(
            'https://raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/ati/39.json'))
        .then((r) => r.close());
    // ignore: avoid_print
    print('sonde GET ati/39.json -> ${probe.statusCode}');
    await probe.drain<void>();

    final entry = versionByCode('ATI')!;
    expect(entry.format, VersionFormat.ati);
    expect(entry.otOnly, isTrue);
    expect(entry.bookCount, 39);

    final service = DownloadService(store: store);
    final seen = <DownloadProgress>[];
    final outcome = await service
        .install(entry, onProgress: seen.add)
        .timeout(const Duration(minutes: 5));
    service.close();

    // La barre de la Bibliothèque atteint 39/39.
    expect(outcome.status, DownloadStatus.complete, reason: outcome.message);
    expect(outcome.done, 39);
    expect(outcome.total, 39);
    expect(seen.last.done, 39);
    expect(seen.last.total, 39);
    expect((await store.versionState('ATI')).isComplete, isTrue);

    // La carte annonce le poids réel sur disque : ~8 Mo en gzip, pas 35.
    final octets = await store.sizeOnDisk('ATI');
    final mo = octets / 1048576;
    // ignore: avoid_print
    print('ATI sur disque : ${mo.toStringAsFixed(1)} Mo');
    expect(mo, greaterThan(4), reason: 'les 39 livres sont bien là');
    expect(mo, lessThan(15), reason: 'stockés compressés');

    // Genèse 1, via le dépôt qui sert le lecteur.
    final repository = VersionRepository(store: store);
    final chapitre = await repository.loadChapter('ATI', 1, 1);
    expect(chapitre.verses, hasLength(31));

    final premier = chapitre.verses.first;
    expect(premier.verse, '1:1');
    // Ligne de gloses jointes par `joinAtiGlosses` — pas un interlinéaire.
    // ignore: avoid_print
    print('Genèse 1:1 — ${premier.text}');
    expect(premier.text, contains('commencement'));
    expect(premier.text, contains('Dieu'));
    expect(premier.text, contains('la terre'));
    expect(premier.textWithNotes, premier.text);

    // Aucun verset blanc. Le dernier verset de chaque chapitre perdait ses
    // gloses tant que `CELLULE_RE` n'acceptait que `<td>` littéral — 929 versets
    // sortaient vides dans le lecteur. Le convertisseur refuse désormais d'en
    // publier un seul ; ici, contre le dépôt réel, on le vérifie à l'endroit où
    // cela se voit.
    final vides = chapitre.verses
        .where((v) => v.text.trim().isEmpty)
        .map((v) => v.verse)
        .toList();
    expect(vides, isEmpty, reason: 'versets sans glose : $vides');

    final dernier = chapitre.verses.last;
    expect(dernier.verse, '1:31');
    // ignore: avoid_print
    print('Genèse 1:31 — ${dernier.text}');
    expect(dernier.text, contains('sixième'));
    expect(dernier.text, contains('Dieu'));

    // Le livre reprend le vocabulaire BYM, pas celui du corpus.
    final livre = await repository.loadBook('ATI', 1);
    expect(livre.book, 'Genèse');

    // Table standard ↔ BYM : Ésaïe est BYM 12 mais standard 23.
    final esaie = await repository.loadBook('ATI', 12);
    expect(esaie.chapters, hasLength(66));
    },
    timeout: const Timeout(Duration(minutes: 6)),
    skip: optIn ? false : 'réseau réel — BYM_E2E=1 pour lancer ce test',
  );
}
