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

/// A downloadable version served from GitHub raw (un JSON par livre), the
/// direct-host path the [urlTemplate] field enables.
const githubVersion = VersionEntry(
  code: 'GITHUB',
  name: 'Version GitHub',
  rights: 'libre de droit',
  availability: VersionAvailability.downloadable,
  urlTemplate:
      'https://raw.githubusercontent.com/user/repo/main/books/{book}.json',
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
        DownloadService.bookUri(darby, bymToStandard(27)).toString(),
        'https://api.getbible.net/v2/darby/19.json',
      );
    });

    test('a direct URL template replaces the getbible endpoint', () {
      expect(
        DownloadService.bookUri(githubVersion, bymToStandard(27)).toString(),
        'https://raw.githubusercontent.com/user/repo/main/books/19.json',
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

    test('fetches from a GitHub URL template book by book', () async {
      final asked = <String>[];
      final client = MockClient((request) async {
        asked.add(request.url.toString());
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });
      final service = DownloadService(client: client, store: store);

      final outcome = await service.install(githubVersion);

      expect(outcome.status, DownloadStatus.complete);
      expect(asked, hasLength(bookCatalog.length));
      // Le token {book} est devenu le numéro standard du premier livre.
      expect(asked.first, contains('raw.githubusercontent.com'));
      expect(asked.first, endsWith('/books/1.json'));
      expect((await store.versionState('GITHUB')).isComplete, isTrue);
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
      // Book 3 in reading order fails; whatever landed around it must survive.
      final client = MockClient((request) async {
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        if (number == bymToStandard(3)) {
          return http.Response('nope', 503);
        }
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });

      final outcome = await DownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      ).install(darby);

      expect(outcome.status, DownloadStatus.serverError);
      expect(outcome.failedBook, 3);
      // Les quatre ouvriers initiaux partent ensemble : les livres 1, 2 et 4
      // arrivent bons avant l'arrêt du tir — seul le 3 manque.
      expect(outcome.done, 3);
      expect(outcome.message, contains('Patientez quelques minutes'));
      expect(outcome.message, contains('3/${bookCatalog.length}'));

      final state = await store.versionState('DBY');
      expect(state.books, {1, 2, 4});
      expect(state.isPartial, isTrue);
    });

    test('no connection names the cause, not the book', () async {
      final client = MockClient(
          (request) async => throw const SocketException('offline'));
      final service = DownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.noConnection);
      expect(outcome.failedBook, 1);
      expect(outcome.message, contains('aucune connexion internet'));
      expect((await store.versionState('DBY')).isEmpty, isTrue);
    });

    test('a broken link is a payload failure, not a patience message',
        () async {
      final client = MockClient(
          (request) async => http.Response('', 404));
      final service = DownloadService(client: client, store: store);

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.failed);
      expect(outcome.message, contains('relancer reprendra'));
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
      final service = DownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      expect((await service.install(darby)).status, DownloadStatus.serverError);
      failing = false;
      asked.clear();

      final second = await service.install(darby);
      expect(second.status, DownloadStatus.complete);
      // Les trois livres de la première tentative ne sont pas refetchés.
      expect(asked, hasLength(bookCatalog.length - 3));
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

    test('cancel stops the batch in flight and keeps what landed', () async {
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
      // L'annulation sonne pendant le dispatch du lot initial : les quatre
      // ouvriers ont déjà tiré leur livre et leurs réponses arrivent bonnes —
      // tout le lot atterrit, mais aucun ouvrier ne repart ensuite.
      expect(outcome.done, DownloadService.maxInFlight);
      expect(outcome.message, contains('conservés'));
      expect((await store.versionState('DBY')).bookCount, outcome.done);
    });

    test('a flaky book succeeds without a manual resume', () async {
      final attempts = <int, int>{};
      final client = MockClient((request) async {
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        attempts.update(number, (n) => n + 1, ifAbsent: () => 1);
        // Le 5ᵉ livre échoue deux fois côté serveur, puis passe.
        if (number == bymToStandard(5) && attempts[number]! <= 2) {
          return http.Response('busy', 503);
        }
        return http.Response.bytes(utf8.encode(bookBody(number)), 200);
      });
      final service = DownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.complete);
      expect(attempts[bymToStandard(5)], 3, reason: 'two retries, then ok');
      expect((await store.versionState('DBY')).isComplete, isTrue);
    });

    test('a broken payload is not retried — a dead link stays dead', () async {
      final attempts = <int, int>{};
      final client = MockClient((request) async {
        final number = int.parse(
            request.url.pathSegments.last.replaceAll('.json', ''));
        attempts.update(number, (n) => n + 1, ifAbsent: () => 1);
        return http.Response('', 404);
      });
      final service =
          DownloadService(client: client, store: store);

      final outcome = await service.install(darby);

      expect(outcome.status, DownloadStatus.failed);
      expect(attempts.values.every((n) => n == 1), isTrue);
    });

    test('a version without a free source is refused without a request',
        () async {
      final asked = <int>[];
      final outcome = await DownloadService(client: servingAll(asked), store: store)
          .install(lsgs);

      expect(outcome.status, DownloadStatus.unavailable);
      expect(asked, isEmpty);
    });

    test('progress reports starts, completions, then the end', () async {
      final asked = <int>[];
      final seen = <DownloadProgress>[];

      await DownloadService(client: servingAll(asked), store: store).install(
        darby,
        onProgress: seen.add,
      );

      // Premier départ : rien d'arrivé, Genèse en vol.
      expect(seen.first.done, 0);
      expect(seen.first.currentBookName, 'Genèse');
      // Fin : tout le canon, plus aucun livre en vol.
      expect(seen.last.done, bookCatalog.length);
      expect(seen.last.currentBookName, isNull);
      // Un départ + une arrivée par livre, et l'appel final.
      expect(seen, hasLength(bookCatalog.length * 2 + 1));
      // La fraction complétée ne recule jamais, où qu'ils atterrissent.
      var previous = -1;
      for (final p in seen) {
        expect(p.done, greaterThanOrEqualTo(previous));
        previous = p.done;
      }
    });
  });
}
