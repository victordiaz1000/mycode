import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/book_mapping.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/version_catalog.dart';

const darby = VersionEntry(
  code: 'DBY',
  name: 'Bible Darby',
  rights: '1890 · domaine public',
  availability: VersionAvailability.downloadable,
  getbibleId: 'darby',
);

const lsgs = VersionEntry(
  code: 'LSGS',
  name: 'Bible Segond 1910 + Strongs',
  rights: 'sans source libre',
);

/// A book payload shaped like the live getbible answer, mixed types included:
/// `chapter` is an int on the chapter but a String on the verse.
String bookBody(int standardNumber) => jsonEncode({
      'translation': 'Darby',
      'abbreviation': 'darby',
      'lang': 'fr',
      'nr': standardNumber,
      'name': 'Livre $standardNumber',
      'chapters': [
        {
          'chapter': 1,
          'name': 'Livre $standardNumber 1',
          'verses': [
            {
              'chapter': '1',
              'verse': '1',
              'name': 'Livre $standardNumber 1:1',
              'text': 'Texte accentué é à ù.',
            },
          ],
        },
      ],
    });

/// Client answering every book, recording the standard numbers asked for.
MockClient servingAll(List<int> asked) => MockClient((request) async {
      final number = int.parse(
          request.url.pathSegments.last.replaceAll('.json', ''));
      asked.add(number);
      return http.Response.bytes(utf8.encode(bookBody(number)), 200);
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_download_test');
    LibraryStore.useRoot(temp);
    store = LibraryStore();
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('DownloadService.bookUri', () {
    test('translates the BYM index into the standard number', () {
      // BYM 27 is Psaumes, standard 19 — the mapping the API expects.
      expect(bymToStandard(27), 19);
      expect(
        DownloadService.bookUri('darby', bymToStandard(27)).toString(),
        'https://api.getbible.net/v2/darby/19.json',
      );
    });
  });

  group('DownloadService.install', () {
    test('fetches the whole canon and reports complete', () async {
      final asked = <int>[];
      final service =
          DownloadService(client: servingAll(asked), store: store);

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.complete);
      expect(outcome.isComplete, isTrue);
      expect(outcome.done, bookCatalog.length);
      expect(asked, hasLength(bookCatalog.length));
      expect((await store.versionState('DBY')).isComplete, isTrue);
      // Stored bytes survive the accents: the body is decoded as UTF-8.
      final book = await store.loadBook('DBY', 1);
      expect(
        (book!['chapters'] as List).first['verses'].first['text'],
        contains('accentué é à ù'),
      );
    });

    test('skips the books already on the device', () async {
      await store.saveBook('DBY', 1, {'chapters': [1]});
      await store.saveBook('DBY', 2, {'chapters': [1]});

      final asked = <int>[];
      await DownloadService(client: servingAll(asked), store: store)
          .install(darby);

      expect(asked, hasLength(bookCatalog.length - 2));
      expect(asked, isNot(contains(bymToStandard(1))));
      expect(asked, isNot(contains(bymToStandard(2))));
    });

    test('a failure keeps what landed and names the failing book', () async {
      // Book 3 in reading order fails; the two before it must survive.
      final client = MockClient((request) async {
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        if (number == bymToStandard(3)) {
          return http.Response('nope', 503);
        }
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });

      final outcome =
          await DownloadService(client: client, store: store).install(darby);

      expect(outcome.status, DownloadStatus.failed);
      expect(outcome.failedBook, 3);
      expect(outcome.done, 2);
      expect(outcome.message, contains('Lévitique'));
      expect(outcome.message, contains('2/${bookCatalog.length}'));

      final state = await store.versionState('DBY');
      expect(state.books, {1, 2});
      expect(state.isPartial, isTrue);
    });

    test('relaunching after a failure resumes and finishes', () async {
      var failing = true;
      final asked = <int>[];
      final client = MockClient((request) async {
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        asked.add(number);
        if (failing && number == bymToStandard(3)) {
          return http.Response('nope', 503);
        }
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });
      final service = DownloadService(client: client, store: store);

      expect((await service.install(darby)).status, DownloadStatus.failed);
      failing = false;
      asked.clear();

      final second = await service.install(darby);
      expect(second.status, DownloadStatus.complete);
      // The two books of the first attempt are not fetched again.
      expect(asked, hasLength(bookCatalog.length - 2));
      expect(asked.first, bymToStandard(3), reason: 'resumes where it broke');
    });

    test('a 200 without chapters counts as a failure', () async {
      final client = MockClient((request) async =>
          http.Response.bytes(utf8.encode(jsonEncode({'chapters': []})), 200));

      final outcome =
          await DownloadService(client: client, store: store).install(darby);

      expect(outcome.status, DownloadStatus.failed);
      expect(outcome.done, 0);
      expect((await store.versionState('DBY')).isEmpty, isTrue);
    });

    test('cancel stops after the book in flight and keeps it', () async {
      late DownloadService service;
      var served = 0;
      final client = MockClient((request) async {
        served++;
        if (served == 2) service.cancel();
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });
      service = DownloadService(client: client, store: store);

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.cancelled);
      expect(outcome.done, 2);
      expect(outcome.message, contains('conservés'));
      expect((await store.versionState('DBY')).books, {1, 2});
    });

    test('a version without a free source is refused without a request',
        () async {
      final asked = <int>[];
      final outcome = await DownloadService(client: servingAll(asked), store: store)
          .install(lsgs);

      expect(outcome.status, DownloadStatus.unavailable);
      expect(asked, isEmpty);
    });

    test('progress reports the book being fetched, then the end', () async {
      final asked = <int>[];
      final seen = <String>[];

      await DownloadService(client: servingAll(asked), store: store).install(
        darby,
        onProgress: (p) => seen.add('${p.done}/${p.total}:'
            '${p.currentBookName ?? "fin"}'),
      );

      expect(seen.first, '0/${bookCatalog.length}:Genèse');
      expect(seen.last, '${bookCatalog.length}/${bookCatalog.length}:fin');
      expect(seen, hasLength(bookCatalog.length + 1));
    });
  });
}
