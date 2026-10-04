import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/library_store.dart';

/// A downloaded book as [LibraryStore] stores it.
Map<String, dynamic> fakeBook(int index) => {
      'nr': index,
      'name': 'Livre $index',
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {'chapter': '1', 'verse': '1', 'text': 'Verset $index:1:1'},
          ],
        },
      ],
    };

void main() {
  // Real `test()`, not `testWidgets`: the filesystem is genuinely reachable
  // here, unlike inside the fake-async zone of a widget test.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_library_test');
    LibraryStore.useRoot(temp);
    store = LibraryStore();
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('LibraryStore', () {
    test('a fresh device holds nothing', () async {
      expect(await store.installed(), isEmpty);
      final state = await store.versionState('DBY');
      expect(state.isEmpty, isTrue);
      expect(state.isComplete, isFalse);
      expect(state.progress, 0);
      expect(await store.missingBooks('DBY'), hasLength(bookCatalog.length));
    });

    test('a saved book is written, recorded and read back', () async {
      await store.saveBook('DBY', 1, fakeBook(1));

      final file = await store.bookFile('DBY', 1);
      expect(await file.exists(), isTrue);

      final state = await store.versionState('DBY');
      expect(state.has(1), isTrue);
      expect(state.bookCount, 1);
      expect(state.isPartial, isTrue);

      final loaded = await store.loadBook('DBY', 1);
      expect(loaded, isNotNull);
      expect(loaded!['name'], 'Livre 1');
    });

    test('missingBooks skips what already landed — the resume', () async {
      await store.saveBook('DBY', 1, fakeBook(1));
      await store.saveBook('DBY', 3, fakeBook(3));

      final missing = await store.missingBooks('DBY');
      expect(missing, isNot(contains(1)));
      expect(missing, isNot(contains(3)));
      expect(missing.first, 2, reason: 'reading order is kept');
      expect(missing, hasLength(bookCatalog.length - 2));
    });

    test('the whole canon reads as complete', () async {
      for (var i = 1; i <= bookCatalog.length; i++) {
        await store.saveBook('DBY', i, fakeBook(i));
      }
      final state = await store.versionState('DBY');
      expect(state.isComplete, isTrue);
      expect(state.isPartial, isFalse);
      expect(state.progress, 1.0);
      expect(await store.missingBooks('DBY'), isEmpty);
    });

    test('versions are kept apart', () async {
      await store.saveBook('DBY', 1, fakeBook(1));
      await store.saveBook('MAR', 2, fakeBook(2));

      expect((await store.versionState('DBY')).books, {1});
      expect((await store.versionState('MAR')).books, {2});
      expect((await store.installed()).keys, containsAll(['DBY', 'MAR']));
    });

    test('remove deletes the files and the registry entry', () async {
      await store.saveBook('DBY', 1, fakeBook(1));
      await store.saveBook('DBY', 2, fakeBook(2));
      final dir = await store.versionDirectory('DBY');
      expect(await dir.exists(), isTrue);

      await store.remove('DBY');

      expect(await dir.exists(), isFalse);
      expect((await store.versionState('DBY')).isEmpty, isTrue);
      expect(await store.loadBook('DBY', 1), isNull);
      expect(await store.installed(), isEmpty);
    });

    test('removing one version leaves the others alone', () async {
      await store.saveBook('DBY', 1, fakeBook(1));
      await store.saveBook('MAR', 1, fakeBook(1));

      await store.remove('DBY');

      expect((await store.versionState('MAR')).books, {1});
      expect(await store.loadBook('MAR', 1), isNotNull);
    });

    test('sizeOnDisk counts the stored books', () async {
      expect(await store.sizeOnDisk('DBY'), 0);
      await store.saveBook('DBY', 1, fakeBook(1));
      final size = await store.sizeOnDisk('DBY');
      expect(size, greaterThan(0));
      // Le poids du fichier tel qu'il est stocké, et non celui du JSON en
      // clair : les livres sont écrits en gzip (cf. `library_store_gzip_test`),
      // et la carte de la Bibliothèque annonce ce que la version occupe
      // vraiment.
      expect(size, await (await store.bookFile('DBY', 1)).length());
    });

    test('a corrupt registry degrades to empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        LibraryStore.registryKey: 'not json at all',
      });
      expect(await store.installed(), isEmpty);
      expect((await store.versionState('DBY')).isEmpty, isTrue);
    });

    test('an unknown book reads as absent', () async {
      expect(await store.loadBook('DBY', 42), isNull);
    });

    test('writes bump the revision so open screens can refresh', () async {
      // The reader and the search screen each hold their own LibraryStore and
      // cached their answer once. Without this signal a version downloaded
      // while the reader was alive stayed invisible to it, and the « Version »
      // sheet sent the user back to the Bibliothèque that had just installed it.
      final seen = <int>[];
      void listener() => seen.add(LibraryStore.revision.value);
      LibraryStore.revision.addListener(listener);
      addTearDown(() => LibraryStore.revision.removeListener(listener));

      await store.saveBook('DBY', 1, fakeBook(1));
      expect(seen, hasLength(1), reason: 'a book landing is a change');

      await store.saveBook('DBY', 2, fakeBook(2));
      expect(seen, hasLength(2));

      await store.remove('DBY');
      expect(seen, hasLength(3), reason: 'a deletion is a change too');
    });
  });
}
