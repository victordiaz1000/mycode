import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/data/version_repository.dart';

import 'support/fake_bible_bundle.dart';

/// A book exactly as getbible serves it, mixed types included: `chapter` is an
/// int on the chapter but a String on the verse.
Map<String, dynamic> getbibleBook(int standardNumber, {int chapters = 2}) => {
      'translation': 'Darby',
      'abbreviation': 'darby',
      'lang': 'fr',
      'nr': standardNumber,
      // English on purpose: the KJV answers in its own language.
      'name': 'Book $standardNumber',
      'chapters': [
        for (var c = chapters; c >= 1; c--)
          {
            'chapter': c,
            'name': 'Book $standardNumber $c',
            'verses': [
              for (var v = 1; v <= 3; v++)
                {
                  'chapter': '$c',
                  'verse': '$v',
                  'name': 'Book $standardNumber $c:$v',
                  'text': 'Texte téléchargé $c:$v.',
                },
            ],
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryStore store;
  late VersionRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_version_repo_test');
    LibraryStore.useRoot(temp);
    LocalRepository.useBundle(FakeBibleBundle());
    VersionRepository.clearCache();
    store = LibraryStore();
    repository = VersionRepository(store: store);
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    LocalRepository.useRootBundle();
    VersionRepository.clearCache();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('bookFromGetbible', () {
    test('keeps the French BYM name, not the translation\'s own', () {
      final book = bookFromGetbible(getbibleBook(19), bymIndex: 27);
      // BYM 27 is Psaumes; getbible answered « Book 19 ».
      expect(book.book, catalogEntry(27).shortName);
      expect(book.abbreviation, catalogEntry(27).abbreviation);
      expect(book.number, 27);
    });

    test('sorts the chapters and numbers the verses', () {
      final book = bookFromGetbible(getbibleBook(1, chapters: 3), bymIndex: 1);

      expect(book.chapters.map((c) => c.chapter), [1, 2, 3]);
      final verse = book.chapters[1].verses.last;
      expect(verse.verse, '2:3');
      expect(verse.number, 3);
      expect(verse.text, 'Texte téléchargé 2:3.');
      // No BYM notes in a downloaded translation — the plain text stands in.
      expect(verse.textWithNotes, verse.text);
      expect(verse.notes, isEmpty);
      expect(verse.section, isNull);
    });

    test('survives a malformed payload instead of throwing', () {
      final book = bookFromGetbible({
        'chapters': [
          'not a chapter',
          {
            'chapter': '4',
            'verses': [
              'not a verse',
              {'verse': 2, 'text': '  Espaces autour.  '},
              {'verse': 3, 'text': '   '},
            ],
          },
        ],
      }, bymIndex: 1);

      expect(book.chapters, hasLength(1));
      expect(book.chapters.single.chapter, 4, reason: 'String chapter number');
      // The blank verse is dropped; the other keeps its trimmed text.
      expect(book.chapters.single.verses, hasLength(1));
      expect(book.chapters.single.verses.single.verse, '4:2');
      expect(book.chapters.single.verses.single.text, 'Espaces autour.');
    });
  });

  group('VersionRepository', () {
    test('BYM comes from the embedded bundle', () async {
      final book = await repository.loadBook('BYM', 1);
      expect(book.chapters, hasLength(2));
      expect(book.chapters.first.verses.first.notes, isNotEmpty);
      expect(repository.isEmbedded('BYM'), isTrue);
    });

    test('LSGS is treated as an embedded Strong version', () async {
      final book = await repository.loadBook('LSGS', 1);
      expect(book.book, 'Genèse');
      expect(book.chapters, isNotEmpty);
      expect(repository.isEmbedded('LSGS'), isTrue);
      expect(book.chapters.first.verses.first.text, contains('H0430'));
      expect(book.chapters.first.verses.first.text, contains('Dieu H0430'));
      expect(book.chapters.first.verses.first.text, contains('H0430 créa'));
    });

    test('a downloaded version comes from the device', () async {
      await store.saveBook('DBY', 1, getbibleBook(1));

      final book = await repository.loadBook('DBY', 1);
      expect(book.chapters.first.verses.first.text, 'Texte téléchargé 1:1.');

      final chapter = await repository.loadChapter('DBY', 1, 2);
      expect(chapter.verses, hasLength(3));
      expect(await repository.chapterCount('DBY', 1), 2);
    });

    test('a book that was never downloaded is refused, not faked', () async {
      // Falling back to the BYM text under a « DBY » label would be a silent
      // lie: the reader has no way to notice.
      expect(
        () => repository.loadBook('DBY', 5),
        throwsA(isA<BookNotDownloaded>()
            .having((e) => e.bymIndex, 'bymIndex', 5)
            .having((e) => e.message, 'message', contains('DBY'))),
      );
    });

    test('an unknown version code is treated as not downloaded', () async {
      expect(() => repository.loadBook('ZZZ', 1),
          throwsA(isA<BookNotDownloaded>()));
    });

    test('the parsed book is cached, and forgotten on demand', () async {
      await store.saveBook('DBY', 1, getbibleBook(1));
      final first = await repository.loadBook('DBY', 1);
      expect(identical(await repository.loadBook('DBY', 1), first), isTrue);

      // The Bibliothèque deleting a version must not leave it readable.
      await store.remove('DBY');
      VersionRepository.forget('DBY');
      expect(() => repository.loadBook('DBY', 1),
          throwsA(isA<BookNotDownloaded>()));
    });

    test('neighbouring chapters follow the BYM order whatever the version',
        () async {
      // Nothing is downloaded for DBY, yet the arrows must still resolve:
      // chapter counts are a property of the canon, not of the translation.
      expect(await repository.previousChapter(1, 1), isNull);
      expect(await repository.nextChapter(1, 1), (1, 2));
      expect(await repository.nextChapter(1, 2), (2, 1));
      expect(await repository.previousChapter(2, 1), (1, 2));
    });
  });

  group('the format of a version', () {
    test('only the BYM schema is said to carry notes', () {
      expect(versionByCode('BYM')!.carriesNotes, isTrue);
      // What the reader keys « Texte + notes » and the book header on. getbible
      // serves text alone, so claiming notes here would show an empty toggle.
      expect(versionByCode('DBY')!.carriesNotes, isFalse);
      expect(versionByCode('LSG')!.carriesNotes, isFalse);
      expect(versionByCode('LSGS')!.carriesNotes, isFalse,
          reason: 'LSGS gives Strong tokens but no BYM metadata or introduction');
    });

    test('everything downloadable today is getbible', () {
      // The flag is not free-standing: `loadBook` chooses its parser from it, so
      // a downloadable entry left on the wrong format would parse to an empty
      // book at the first download rather than fail loudly.
      final downloadable = [
        for (final group in versionCatalog)
          for (final version in group.versions)
            if (version.downloadable) version,
      ];
      expect(downloadable, isNotEmpty);
      for (final version in downloadable) {
        expect(version.format, VersionFormat.getbible,
            reason: '${version.code} is served by getbible');
        expect(version.getbibleId, isNotNull, reason: version.code);
      }
    });

    test('an unknown code falls on the poorer schema', () {
      // The default matters: a code absent from the catalogue must not be read
      // as BYM-format, which would look for metadata that is not there.
      expect(versionByCode('ZZZ'), isNull);
      expect(const VersionEntry(code: 'ZZZ', name: 'z', rights: 'z').format,
          VersionFormat.getbible);
    });
  });
}
