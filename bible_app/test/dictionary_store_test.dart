import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/dictionary_store.dart';

Map<String, dynamic> fakeDictionary() => {
      'entries': {
        'ALPHA': {'term': 'ALPHA', 'definition': 'Première lettre.'},
        'BETA': 'Deuxième lettre.',
      },
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late DictionaryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_dict_test');
    DictionaryStore.useRoot(temp);
    store = DictionaryStore();
  });

  tearDown(() async {
    DictionaryStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('DictionaryStore', () {
    test('a fresh device holds nothing', () async {
      expect(await store.installed(), isEmpty);
      expect(await store.load('BAILLY'), isNull);
      expect(await store.sizeOnDisk('BAILLY'), 0);
    });

    test('a saved dictionary is written, recorded and read back', () async {
      await store.save('BAILLY', fakeDictionary());

      final file = await store.dictionaryFile('BAILLY');
      expect(await file.exists(), isTrue);

      expect(await store.installed(), contains('BAILLY'));

      final loaded = await store.load('BAILLY');
      expect(loaded, isNotNull);
      expect((loaded!['entries'] as Map).containsKey('ALPHA'), isTrue);
    });

    test('remove deletes the file and drops the registry entry', () async {
      await store.save('BAILLY', fakeDictionary());
      await store.save('GBM', fakeDictionary());

      await store.remove('BAILLY');

      expect(await store.installed(), {'GBM'});
      expect(await store.sizeOnDisk('BAILLY'), 0);
      expect(await store.load('BAILLY'), isNull);
    });

    test('sizeOnDisk reflects the stored file', () async {
      await store.save('BAILLY', fakeDictionary());
      final file = await store.dictionaryFile('BAILLY');
      expect(await store.sizeOnDisk('BAILLY'), await file.length());
    });

    test('a corrupt registry degrades to empty instead of throwing', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(DictionaryStore.registryKey, 'not json');

      expect(await store.installed(), isEmpty);
    });

    test('revision bumps on save and remove', () async {
      final before = DictionaryStore.revision.value;
      await store.save('BAILLY', fakeDictionary());
      expect(DictionaryStore.revision.value, greaterThan(before));

      final mid = DictionaryStore.revision.value;
      await store.remove('BAILLY');
      expect(DictionaryStore.revision.value, greaterThan(mid));
    });
  });
}