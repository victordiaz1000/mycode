import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/work_store.dart';

/// Un ouvrage complet : les métadonnées de garde, un sommaire à deux niveaux
/// et deux chapitres. Assez petit pour être lu d'œil, assez complet pour que
/// `Work.parse` soit vraiment exercé par l'aller-retour disque.
Map<String, dynamic> fakeWork() => {
      'code': 'MINISTERE',
      'title': 'LE MINISTÈRE OU LE SEIGNEUR',
      'subtitle': 'QUE PRÉFÈRES-TU ?',
      'author': 'Trésor Koufounda',
      'publisher': 'Vases de Terre les Éditions',
      'isbn': '978-2-9578689-3-3',
      'rights': '© 2024 · diffusion gratuite autorisée',
      'toc': [
        {'title': 'INTRODUCTION', 'level': 0, 'chapter': 1},
        {'title': "I. D'ABORD L'ADORATION", 'level': 1, 'chapter': 2},
      ],
      'chapters': [
        {
          'number': 1,
          'title': 'INTRODUCTION',
          'blocks': [
            {
              'type': 'p',
              'text': "Le ministère est d'abord une conséquence de l'appel.",
            },
          ],
        },
        {
          'number': 2,
          'title': 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR',
          'blocks': [
            {'type': 'h2', 'text': "I. D'ABORD L'ADORATION"},
            {'type': 'quote', 'text': '« Oui, je serai avec toi. »'},
            {'type': 'li', 'text': 'La vie de prière.'},
            {'type': 'pair', 'text': 'Bereshit', 'gloss': 'Genèse'},
          ],
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late WorkStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_work_test');
    WorkStore.useRoot(temp);
    store = WorkStore();
  });

  tearDown(() async {
    WorkStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('WorkStore', () {
    test('a fresh device holds nothing', () async {
      expect(await store.installed(), isEmpty);
      expect(await store.load('MINISTERE'), isNull);
      expect(await store.sizeOnDisk('MINISTERE'), 0);
    });

    test('a saved work is written, recorded and read back', () async {
      await store.save('MINISTERE', fakeWork());

      final file = await store.workFile('MINISTERE');
      expect(await file.exists(), isTrue,
          reason: 'le fichier atterrit dans <documents>/works/<code>.json');
      expect(file.path.endsWith('works${Platform.pathSeparator}'
          'MINISTERE.json'), isTrue);

      expect(await store.installed(), contains('MINISTERE'));

      final loaded = await store.load('MINISTERE');
      expect(loaded, isNotNull);
      expect(loaded!['title'], 'LE MINISTÈRE OU LE SEIGNEUR');
      expect((loaded['chapters'] as List).length, 2);
      // L'aller-retour conserve les accents : un ouvrage sans eux serait
      // illisible, et c'est précisément là que l'encodage casse.
      expect(loaded['subtitle'], 'QUE PRÉFÈRES-TU ?');
    });

    test('two works are independent on the device', () async {
      await store.save('MINISTERE', fakeWork());
      await store.save('AUTRE', fakeWork());

      expect(await store.installed(), {'MINISTERE', 'AUTRE'});
      expect((await store.load('MINISTERE'))!['code'], 'MINISTERE');
    });

    test('remove deletes the file and drops the registry entry', () async {
      await store.save('MINISTERE', fakeWork());
      await store.save('AUTRE', fakeWork());

      await store.remove('MINISTERE');

      expect(await store.installed(), {'AUTRE'});
      expect(await store.sizeOnDisk('MINISTERE'), 0);
      expect(await store.load('MINISTERE'), isNull);
    });

    test('sizeOnDisk reflects the stored file', () async {
      await store.save('MINISTERE', fakeWork());
      final file = await store.workFile('MINISTERE');
      expect(await store.sizeOnDisk('MINISTERE'), await file.length());
    });

    test('a corrupt registry degrades to empty instead of throwing', () async {
      await store.save('MINISTERE', fakeWork());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(WorkStore.registryKey, 'not json');

      expect(await store.installed(), isEmpty);
      // Le fichier, lui, est toujours là : rien n'est perdu, on se
      // retélécharge, mais surtout l'écran ne plante pas.
      expect(await store.sizeOnDisk('MINISTERE'), greaterThan(0));
    });

    test('revision bumps on save and remove', () async {
      final before = WorkStore.revision.value;
      await store.save('MINISTERE', fakeWork());
      expect(WorkStore.revision.value, greaterThan(before));

      final mid = WorkStore.revision.value;
      await store.remove('MINISTERE');
      expect(WorkStore.revision.value, greaterThan(mid));
    });
  });
}
