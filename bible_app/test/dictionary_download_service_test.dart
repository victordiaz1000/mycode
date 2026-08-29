import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_download_service.dart';
import 'package:bible_app/data/dictionary_store.dart';

const baillyConfigured = DictionaryEntry(
  code: 'BAILLY',
  name: 'Bailly — Grec-français',
  rights: 'libre',
  description: 'Dictionnaire grec-français.',
  availability: DictionaryAvailability.downloadable,
  url: 'https://s3.filebase.example/dictionaries/bailly.json',
);

const baillyUnconfigured = DictionaryEntry(
  code: 'BAILLY',
  name: 'Bailly — Grec-français',
  rights: 'libre',
  description: 'Dictionnaire grec-français.',
  availability: DictionaryAvailability.downloadable,
);

const nave = DictionaryEntry(
  code: 'NAVE',
  name: 'Nave',
  rights: 'catégorie thématique',
  description: 'Sans source.',
  availability: DictionaryAvailability.unavailable,
);

String validBody() => jsonEncode({
      'entries': {
        'ALPHA': {'term': 'ALPHA', 'definition': 'Première lettre.'},
        'BETA': 'Deuxième lettre.',
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late DictionaryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_dict_dl_test');
    DictionaryStore.useRoot(temp);
    store = DictionaryStore();
  });

  tearDown(() async {
    DictionaryStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('DictionaryDownloadService.install', () {
    test('an entry without an URL is unavailable, no request is made', () async {
      var requested = false;
      final client = MockClient((_) async {
        requested = true;
        return http.Response(validBody(), 200);
      });
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(baillyUnconfigured);

      expect(outcome.status, DictionaryDownloadStatus.unavailable);
      expect(requested, isFalse);
      expect(await store.installed(), isEmpty);
    });

    test('an unavailable entry is refused the same way', () async {
      var requested = false;
      final client = MockClient((_) async {
        requested = true;
        return http.Response(validBody(), 200);
      });
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(nave);

      expect(outcome.status, DictionaryDownloadStatus.unavailable);
      expect(requested, isFalse);
    });

    test('a 200 with entries is saved and reported complete', () async {
      String? requestedUrl;
      final client = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(baillyConfigured);

      expect(outcome.isComplete, isTrue);
      expect(requestedUrl, baillyConfigured.url);
      expect(await store.installed(), {'BAILLY'});
      final loaded = await store.load('BAILLY');
      expect(loaded, isNotNull);
      expect((loaded!['entries'] as Map).containsKey('ALPHA'), isTrue);
    });

    test('an accent-bearing body survives the round trip', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'entries': {
              'ÉGLISE': {
                'term': 'ÉGLISE',
                'definition': 'Assemblée des croyants éàù.',
              },
            },
          })),
          200));
      final service = DictionaryDownloadService(client: client, store: store);

      await service.install(baillyConfigured);

      final loaded = await store.load('BAILLY');
      final entry = (loaded!['entries'] as Map)['ÉGLISE'] as Map;
      expect(entry['definition'], 'Assemblée des croyants éàù.');
    });

    test('a non-200 4xx is a broken-link failure and nothing is stored',
        () async {
      final client = MockClient((_) async => http.Response('', 404));
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a 5xx is a server failure, not a broken link', () async {
      final client = MockClient((_) async => http.Response('', 503));
      final service = DictionaryDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.serverError);
      expect(await store.installed(), isEmpty);
    });

    test('a busy server is retried automatically, then succeeds', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        if (attempts <= 2) return http.Response('', 503);
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = DictionaryDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(baillyConfigured);

      expect(outcome.isComplete, isTrue, reason: 'deux relances suffisent');
      expect(attempts, 3);
      expect(await store.installed(), {'BAILLY'});
    });

    test('progress flows with the bytes and the announced size', () async {
      final body = utf8.encode(validBody());
      final client =
          MockClient((_) async => http.Response.bytes(body, 200));
      final service = DictionaryDownloadService(client: client, store: store);
      final seen = <DictionaryDownloadProgress>[];

      final outcome =
          await service.install(baillyConfigured, onProgress: seen.add);

      expect(outcome.isComplete, isTrue);
      expect(seen, isNotEmpty);
      expect(seen.last.received, body.length);
      expect(seen.last.total, body.length);
      expect(seen.last.fraction, 1.0);
    });

    test('a 429 asks for patience, not a broken link', () async {
      final client = MockClient((_) async => http.Response('', 429));
      final service = DictionaryDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.serverError);
      expect(await store.installed(), isEmpty);
    });

    test('a 200 without entries is a failure, not an installed hole', () async {
      final client = MockClient((_) async =>
          http.Response(jsonEncode({'translation': 'Bailly'}), 200));
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('garbage is a failure, not a crash', () async {
      final client = MockClient((_) async => http.Response('{broken', 200));
      final service = DictionaryDownloadService(client: client, store: store);

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a SocketException means no connection, nothing is stored', () async {
      final client = MockClient((_) async => throw const SocketException('off'));
      final service = DictionaryDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(baillyConfigured);

      expect(outcome.status, DictionaryDownloadStatus.noConnection);
      expect(await store.installed(), isEmpty);
    });

    test('cancel mid-request prevents the save', () async {
      final gate = Completer<void>();
      final client = MockClient((_) async {
        await gate.future;
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = DictionaryDownloadService(client: client, store: store);

      final future = service.install(baillyConfigured);
      service.cancel();
      gate.complete();
      final outcome = await future;

      expect(outcome.status, DictionaryDownloadStatus.cancelled);
      expect(await store.installed(), isEmpty);
    });

    test('messages are French and distinct', () {
      expect(
        DictionaryDownloadOutcome(
          code: 'B',
          status: DictionaryDownloadStatus.complete,
        ).message,
        'Dictionnaire téléchargé.',
      );
      expect(
        DictionaryDownloadOutcome(
          code: 'B',
          status: DictionaryDownloadStatus.unavailable,
        ).message,
        'Ce dictionnaire n\'a pas encore d\'URL configurée.',
      );
      expect(
        DictionaryDownloadOutcome(
          code: 'B',
          status: DictionaryDownloadStatus.invalidPayload,
        ).message,
        contains('n\'est pas un dictionnaire valide'),
      );
      expect(
        DictionaryDownloadOutcome(
          code: 'B',
          status: DictionaryDownloadStatus.noConnection,
        ).message,
        contains('aucune connexion internet'),
      );
      expect(
        DictionaryDownloadOutcome(
          code: 'B',
          status: DictionaryDownloadStatus.serverError,
        ).message,
        contains('Patientez quelques minutes'),
      );
    });
  });
}