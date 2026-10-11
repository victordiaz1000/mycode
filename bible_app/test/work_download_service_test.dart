import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/work_catalog.dart';
import 'package:bible_app/data/work_download_service.dart';
import 'package:bible_app/data/work_store.dart';

const ministereConfigured = WorkEntry(
  code: 'MINISTERE',
  title: 'LE MINISTÈRE OU LE SEIGNEUR',
  author: 'Trésor Koufounda',
  rights: '© 2024 Vases de Terre les Éditions',
  description: '11 chapitres sur le service du Seigneur.',
  availability: WorkAvailability.downloadable,
  url: 'https://s3.filebase.example/works/ministere.json',
);

/// Le vrai catalogue du pilote : téléchargeable, mais sans URL publiée — la
/// tuile dit « URL à configurer » au lieu d'offrir un téléchargement voué à
/// l'échec.
const ministereUnconfigured = WorkEntry(
  code: 'MINISTERE',
  title: 'LE MINISTÈRE OU LE SEIGNEUR',
  author: 'Trésor Koufounda',
  rights: '© 2024 Vases de Terre les Éditions',
  description: '11 chapitres sur le service du Seigneur.',
  availability: WorkAvailability.downloadable,
);

/// Une URL pourtant écrite, mais une entrée déclarée sans source.
const sansSource = WorkEntry(
  code: 'MINISTERE',
  title: 'LE MINISTÈRE OU LE SEIGNEUR',
  author: 'Trésor Koufounda',
  rights: '© 2024 Vases de Terre les Éditions',
  description: '11 chapitres sur le service du Seigneur.',
  availability: WorkAvailability.unavailable,
  url: 'https://s3.filebase.example/works/ministere.json',
);

/// La charge qu'un lien valide servirait : c'est le JSON de
/// `appCodebar/pdf_book_to_json.py`, réduit à l'essentiel.
String validBody() => jsonEncode({
      'code': 'MINISTERE',
      'title': 'LE MINISTÈRE OU LE SEIGNEUR',
      'subtitle': 'QUE PRÉFÈRES-TU ?',
      'author': 'Trésor Koufounda',
      'toc': [
        {'title': 'INTRODUCTION', 'level': 0, 'chapter': 1},
      ],
      'chapters': [
        {
          'number': 1,
          'title': 'INTRODUCTION',
          'blocks': [
            {'type': 'p', 'text': "Le ministère est une conséquence de l'appel."},
          ],
        },
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late WorkStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_work_dl_test');
    WorkStore.useRoot(temp);
    store = WorkStore();
  });

  tearDown(() async {
    WorkStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('WorkDownloadService.install', () {
    test('an entry without an URL is unavailable, no request is made',
        () async {
      var requested = false;
      final client = MockClient((_) async {
        requested = true;
        return http.Response(validBody(), 200);
      });
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereUnconfigured);

      expect(outcome.status, WorkDownloadStatus.unavailable);
      expect(requested, isFalse);
      expect(await store.installed(), isEmpty);
    });

    test('an unavailable entry is refused the same way', () async {
      var requested = false;
      final client = MockClient((_) async {
        requested = true;
        return http.Response(validBody(), 200);
      });
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(sansSource);

      expect(outcome.status, WorkDownloadStatus.unavailable);
      expect(requested, isFalse);
    });

    test('a 200 with chapters is saved and reported complete', () async {
      String? requestedUrl;
      final client = MockClient((request) async {
        requestedUrl = request.url.toString();
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.isComplete, isTrue);
      expect(requestedUrl, ministereConfigured.url);
      expect(await store.installed(), {'MINISTERE'});
      final loaded = await store.load('MINISTERE');
      expect(loaded, isNotNull);
      expect(loaded!['title'], 'LE MINISTÈRE OU LE SEIGNEUR');
    });

    test('an accent-bearing body survives the round trip', () async {
      final client = MockClient((_) async => http.Response.bytes(
          utf8.encode(jsonEncode({
            'title': 'LE MINISTÈRE OU LE SEIGNEUR',
            'subtitle': 'QUE PRÉFÈRES-TU ?',
            'chapters': [
              {
                'number': 1,
                'title': 'INTRODUCTION',
                'blocks': [
                  {'type': 'p', 'text': 'Éloge à la grâce, éàù ô.'},
                ],
              },
            ],
          })),
          200));
      final service = WorkDownloadService(client: client, store: store);

      await service.install(ministereConfigured);

      final loaded = await store.load('MINISTERE');
      expect(loaded!['title'], 'LE MINISTÈRE OU LE SEIGNEUR');
      final blocks = (loaded['chapters'] as List).first['blocks'] as List;
      expect(blocks.first['text'], 'Éloge à la grâce, éàù ô.');
    });

    test('a non-200 4xx is a broken-link failure and nothing is stored',
        () async {
      final client = MockClient((_) async => http.Response('', 404));
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a 5xx is a server failure, not a broken link', () async {
      final client = MockClient((_) async => http.Response('', 503));
      final service = WorkDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.serverError);
      expect(await store.installed(), isEmpty);
    });

    test('a 429 asks for patience, not a broken link', () async {
      final client = MockClient((_) async => http.Response('', 429));
      final service = WorkDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.serverError);
      expect(await store.installed(), isEmpty);
    });

    test('a busy server is retried automatically, then succeeds', () async {
      var attempts = 0;
      final client = MockClient((_) async {
        attempts++;
        if (attempts <= 2) return http.Response('', 503);
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = WorkDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(ministereConfigured);

      expect(outcome.isComplete, isTrue, reason: 'deux relances suffisent');
      expect(attempts, 3);
      expect(await store.installed(), {'MINISTERE'});
    });

    test('progress flows with the bytes and the announced size', () async {
      final body = utf8.encode(validBody());
      final client = MockClient((_) async => http.Response.bytes(body, 200));
      final service = WorkDownloadService(client: client, store: store);
      final seen = <WorkDownloadProgress>[];

      final outcome =
          await service.install(ministereConfigured, onProgress: seen.add);

      expect(outcome.isComplete, isTrue);
      expect(seen, isNotEmpty);
      expect(seen.last.received, body.length);
      expect(seen.last.total, body.length,
          reason: 'un serveur qui annonce sa taille permet une barre '
              'déterminée');
      expect(seen.last.fraction, 1.0);
    });

    test('a stream without Content-Length leaves the fraction null', () async {
      // Encodage chunked : le serveur ne dit pas où s'arrête le fichier. Le
      // service doit alors refuser de deviner — une barre qui monte jusqu'à
      // 100 % sur un flux tronqué mentirait — tout en recevant les octets.
      final client = MockClient.streaming((_, _) async => http.StreamedResponse(
        Stream.fromIterable([utf8.encode(validBody())]),
        200,
      ));
      final service = WorkDownloadService(client: client, store: store);
      final seen = <WorkDownloadProgress>[];

      final outcome =
          await service.install(ministereConfigured, onProgress: seen.add);

      expect(outcome.isComplete, isTrue);
      expect(seen, isNotEmpty);
      expect(seen.last.total, isNull);
      expect(seen.last.fraction, isNull);
      expect(seen.last.received, greaterThan(0),
          reason: 'les octets sont bien comptés, seule la borne manque');
    });

    test('a gzipped body is counted as it travels, then opened', () async {
      // raw.githubusercontent.com sert tout en gzip : sur le pilote,
      // 67 Ko annoncés pour 241 Ko de JSON une fois ouvert. Le service doit
      // compter les octets **tels qu'ils circulent** — sinon la barre bondit
      // à 100 % après un quart du fichier, et l'étiquette lit
      // « 241 Ko / 67 Ko » — puis ouvrir le gzip, une fois la réception finie.
      final raw = gzip.encode(utf8.encode(validBody()));
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([raw]),
          200,
          contentLength: raw.length,
          headers: const {'content-encoding': 'gzip'},
        ),
      );
      final service = WorkDownloadService(client: client, store: store);
      final seen = <WorkDownloadProgress>[];

      final outcome =
          await service.install(ministereConfigured, onProgress: seen.add);

      expect(outcome.isComplete, isTrue,
          reason: 'le gzip décompressé doit redevenir le livre');
      expect(seen.last.total, raw.length,
          reason: 'l\'en-tête mesure les octets compressés, comme le flux');
      expect(seen.last.received, raw.length,
          reason: 'reçu et total décrivent la même chose : la barre est juste');
      expect(seen.last.fraction, 1.0);
      final loaded = await store.load('MINISTERE');
      expect(loaded!['title'], 'LE MINISTÈRE OU LE SEIGNEUR');
    });

    test('a truncated gzip is a broken payload, not a crash', () async {
      // Le fichier a été tronqué en route : décompresser lève, et le service
      // doit le rendre en « charge invalide » — pas en livre corrompu posé
      // sur l'appareil.
      final raw = gzip.encode(utf8.encode(validBody()));
      final client = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          Stream.fromIterable([raw.sublist(0, raw.length ~/ 2)]),
          200,
          contentLength: raw.length ~/ 2,
          headers: const {'Content-Encoding': 'gzip'},
        ),
      );
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a 200 without chapters is a failure, not an installed hole',
        () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'title': 'Le Ministère'}), 200),
      );
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty,
          reason: 'un lien cassé sert souvent une page HTML en 200');
    });

    test('a 200 with empty chapters is refused too', () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'title': 'Le Ministère',
            'chapters': <dynamic>[],
          }),
          200));
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a 200 without a title is refused — the pill would read blank',
        () async {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'chapters': [
              {
                'number': 1,
                'title': 'INTRODUCTION',
                'blocks': [
                  {'type': 'p', 'text': 'Texte.'},
                ],
              },
            ],
          }),
          200));
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('garbage is a failure, not a crash', () async {
      final client = MockClient((_) async => http.Response('{broken', 200));
      final service = WorkDownloadService(client: client, store: store);

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.invalidPayload);
      expect(await store.installed(), isEmpty);
    });

    test('a SocketException means no connection, nothing is stored', () async {
      final client = MockClient((_) async => throw const SocketException('off'));
      final service = WorkDownloadService(
        client: client,
        store: store,
        retryBackoff: Duration.zero,
      );

      final outcome = await service.install(ministereConfigured);

      expect(outcome.status, WorkDownloadStatus.noConnection);
      expect(await store.installed(), isEmpty);
    });

    test('cancel mid-request prevents the save', () async {
      final gate = Completer<void>();
      final client = MockClient((_) async {
        await gate.future;
        return http.Response.bytes(utf8.encode(validBody()), 200);
      });
      final service = WorkDownloadService(client: client, store: store);

      final future = service.install(ministereConfigured);
      service.cancel();
      gate.complete();
      final outcome = await future;

      expect(outcome.status, WorkDownloadStatus.cancelled);
      expect(await store.installed(), isEmpty);
    });

    test('messages are French and distinct', () {
      String messageOf(WorkDownloadStatus status) =>
          WorkDownloadOutcome(code: 'MINISTERE', status: status).message;

      expect(messageOf(WorkDownloadStatus.complete), 'Livre téléchargé.');
      expect(
        messageOf(WorkDownloadStatus.unavailable),
        'Ce livre n\'a pas encore d\'URL configurée.',
      );
      expect(messageOf(WorkDownloadStatus.invalidPayload),
          contains('n\'est pas un livre valide'));
      expect(messageOf(WorkDownloadStatus.noConnection),
          contains('aucune connexion internet'));
      expect(messageOf(WorkDownloadStatus.serverError),
          contains('Patientez quelques minutes'));
      expect(messageOf(WorkDownloadStatus.cancelled),
          contains('Téléchargement interrompu'));

      final messages = WorkDownloadStatus.values.map(messageOf).toSet();
      expect(messages.length, WorkDownloadStatus.values.length,
          reason: 'deux arrêts différents ne doivent pas se confondre dans '
              'le snackbar');
    });
  });
}
