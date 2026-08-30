import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/bym_update_store.dart';

/// Contenu de livre minimal : le magasin ne lit pas le JSON, il le transporte.
String book(String name) => jsonEncode({
      'book': name,
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {'verse': '1:1', 'text': 'Au commencement Élohîm créa.'},
          ],
        },
      ],
    });

/// Sha de commit et empreintes de blob : la forme compte (40 hexadécimaux), la
/// valeur non — le magasin transporte, c'est le service qui vérifie.
const String commitA = 'cb535d4a3c9f1e2b7d8a4c5e6f708192a3b4c5d6';
const String commitB = '0123456789abcdef0123456789abcdef01234567';
const String blobGenese = '6551d038aabbccddeeff00112233445566778899';
const String blobExode = 'f5817358aabbccddeeff00112233445566778899';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late BymUpdateStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_update_store_test');
    BymUpdateStore.useRoot(temp);
    // L'état est statique : sans remise à zéro, un test hériterait du registre
    // du précédent.
    BymUpdateStore.resetInMemory();
    store = BymUpdateStore();
  });

  tearDown(() async {
    BymUpdateStore.useAppDirectory();
    BymUpdateStore.resetInMemory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('BymUpdateStore.install', () {
    test('fait basculer le transit et enregistre le commit', () async {
      await store.stage('01-Genese.json', book('Bereshit (Genèse)'));

      // Rien n'est visible du lecteur avant la bascule : c'est ce qui garantit
      // que l'état affiché ne mente jamais.
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(await store.read('01-Genese.json'), isNull);

      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30, 12),
        notes: 'Correction Genèse 1:2',
        blobs: const {'01-Genese.json': blobGenese},
      );

      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isTrue);
      expect(BymUpdateStore.installedCommit, commitA);
      expect(BymUpdateStore.installedNotes, 'Correction Genèse 1:2');
      expect(BymUpdateStore.installedAt, DateTime.utc(2026, 8, 30, 12));
      expect(BymUpdateStore.updatedCount, 1);
      // L'empreinte est ce que le service comparera à l'arbre distant : la
      // perdre reproposerait le livre à chaque vérification.
      expect(BymUpdateStore.installedBlobs['01-Genese.json'], blobGenese);
      expect(await store.read('01-Genese.json'), contains('Bereshit'));
      // Le transit est vidé : il ne reste rien à confondre avec un livre servi.
      expect(await (await store.staging()).exists(), isFalse);
      expect(await store.sizeOnDisk(), greaterThan(0));
    });

    test('refuse un livre annoncé mais absent du transit', () async {
      await store.stage('01-Genese.json', book('Bereshit (Genèse)'));

      await expectLater(
        store.install(
          commit: commitA,
          committedAt: DateTime.utc(2026, 8, 30),
          notes: '',
          blobs: const {
            '01-Genese.json': blobGenese,
            '02-Exode.json': blobExode,
          },
        ),
        throwsA(isA<StateError>()),
      );

      // Aucun commit enregistré : l'échec laisse l'état précédent intact.
      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
    });

    test('cumule les livres de deux mises à jour successives', () async {
      await store.stage('01-Genese.json', book('Genèse'));
      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: 'Genèse',
        blobs: const {'01-Genese.json': blobGenese},
      );

      await store.stage('02-Exode.json', book('Exode'));
      await store.install(
        commit: commitB,
        committedAt: DateTime.utc(2026, 8, 31),
        notes: 'Exode',
        blobs: const {'02-Exode.json': blobExode},
      );

      // Une mise à jour ne porte que son delta : le livre corrigé la fois
      // précédente doit rester servi, avec son empreinte.
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isTrue);
      expect(BymUpdateStore.hasUpdate('02-Exode.json'), isTrue);
      expect(BymUpdateStore.updatedCount, 2);
      expect(BymUpdateStore.installedBlobs['01-Genese.json'], blobGenese);
      expect(BymUpdateStore.installedCommit, commitB);
    });

    test('incrémente la révision pour que les écrans se rafraîchissent',
        () async {
      final before = BymUpdateStore.revision.value;
      await store.stage('01-Genese.json', book('Genèse'));
      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: '',
        blobs: const {'01-Genese.json': blobGenese},
      );
      expect(BymUpdateStore.revision.value, greaterThan(before));
    });
  });

  group('BymUpdateStore.load', () {
    test('relit le registre après un redémarrage', () async {
      await store.stage('01-Genese.json', book('Genèse'));
      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: 'Correction',
        blobs: const {'01-Genese.json': blobGenese},
      );

      // Simule un processus neuf : les préférences et les fichiers survivent,
      // la mémoire non.
      BymUpdateStore.resetInMemory();
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);

      await BymUpdateStore.load();

      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isTrue);
      expect(BymUpdateStore.installedCommit, commitA);
      expect(BymUpdateStore.installedNotes, 'Correction');
      expect(BymUpdateStore.installedBlobs['01-Genese.json'], blobGenese);
    });

    test('un registre vide n\'annonce aucun commit, même si la clé traîne',
        () async {
      // Un `clear()` interrompu peut laisser le commit sans ses empreintes :
      // l'état afficherait alors un texte que personne ne lit.
      SharedPreferences.setMockInitialValues({
        BymUpdateStore.commitKey: commitA,
      });
      await BymUpdateStore.load();
      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.updatedCount, 0);
    });

    test('ne lève pas sur un registre illisible', () async {
      SharedPreferences.setMockInitialValues({
        BymUpdateStore.blobsKey: 'ceci n\'est pas du JSON',
        BymUpdateStore.commitKey: commitA,
      });
      await BymUpdateStore.load();
      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.updatedCount, 0);
    });

    test('purge une installation héritée du système à numéro de version',
        () async {
      // L'ancien système (GitHub + jsDelivr, semver) laissait des fichiers
      // rattachés à aucun commit amont, donc invérifiables. Ils doivent
      // disparaître au premier démarrage : un texte dont on ne sait plus rien
      // ne se sert pas, on repart de l'embarqué.
      final directory = await store.directory();
      await directory.create(recursive: true);
      await File(p.join(directory.path, '01-Genese.json'))
          .writeAsString(book('Genèse'));
      SharedPreferences.setMockInitialValues({
        BymUpdateStore.legacyVersionKey: '1.3.0',
        BymUpdateStore.legacyFilesKey: jsonEncode(['01-Genese.json']),
      });

      await BymUpdateStore.load();

      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.updatedCount, 0);
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(await directory.exists(), isFalse);

      // Les clés héritées sont effacées, donc la purge ne se rejoue pas.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(BymUpdateStore.legacyVersionKey), isFalse);
      expect(prefs.containsKey(BymUpdateStore.legacyFilesKey), isFalse);
    });

    test('garde une installation du nouveau système malgré une clé héritée',
        () async {
      // Cohabitation transitoire : une mise à jour GitLab déjà installée ne doit
      // pas être emportée par le nettoyage d'une clé de l'ancien monde.
      await store.stage('01-Genese.json', book('Genèse'));
      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: '',
        blobs: const {'01-Genese.json': blobGenese},
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BymUpdateStore.legacyVersionKey, '1.3.0');
      BymUpdateStore.resetInMemory();

      await BymUpdateStore.load();

      expect(BymUpdateStore.installedCommit, commitA);
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isTrue);
      expect(await store.read('01-Genese.json'), contains('Genèse'));
      expect(prefs.containsKey(BymUpdateStore.legacyVersionKey), isFalse);
    });
  });

  group('BymUpdateStore.clear', () {
    test('vide la mémoire avant même de toucher au disque', () async {
      await store.stage('01-Genese.json', book('Genèse'));
      await store.install(
        commit: commitA,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: '',
        blobs: const {'01-Genese.json': blobGenese},
      );

      final pending = store.clear();
      // Sans attendre : une lecture concurrente doit déjà repartir sur l'asset.
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(BymUpdateStore.installedCommit, isNull);

      await pending;
      expect(await (await store.directory()).exists(), isFalse);
      expect(await store.sizeOnDisk(), 0);

      // Et le registre ne ressuscite pas au redémarrage suivant.
      await BymUpdateStore.load();
      expect(BymUpdateStore.updatedCount, 0);
    });
  });

  group('BymUpdateStore.discardStaging', () {
    test('jette un transit interrompu', () async {
      await store.stage('01-Genese.json', book('Genèse'));
      final staging = await store.staging();
      expect(await File(p.join(staging.path, '01-Genese.json')).exists(), isTrue);

      await store.discardStaging();
      expect(await staging.exists(), isFalse);
      // Le dossier servi n'est pas emporté au passage.
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
    });
  });

  group('BymUpdateStore.read', () {
    test('renvoie null quand le registre est en avance sur les fichiers',
        () async {
      // Cas d'un `clear()` interrompu : la carte existe encore, le fichier non.
      SharedPreferences.setMockInitialValues({
        BymUpdateStore.blobsKey: jsonEncode({'01-Genese.json': blobGenese}),
        BymUpdateStore.commitKey: commitA,
      });
      await BymUpdateStore.load();
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isTrue);
      // Null, et non une exception : le lecteur retombe sur l'asset embarqué.
      expect(await store.read('01-Genese.json'), isNull);
    });
  });

  group('BymUpdateStore.lastCheck', () {
    test('mémorise l\'horodatage de la dernière vérification', () async {
      expect(await store.lastCheck(), isNull);
      final when = DateTime.utc(2026, 8, 30, 9, 15);
      await store.markChecked(when);
      expect(await store.lastCheck(), when);
    });
  });
}
