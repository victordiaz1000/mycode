import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/bym_markdown_converter.dart';
import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/data/bym_update_store.dart';

/// Shas de commit : la forme (40 hexadécimaux) est ce que le service valide, la
/// valeur ne sert qu'à distinguer les trois provenances possibles.
const String shaEmbedded = '1111111111111111111111111111111111111111';
const String shaHead = '2222222222222222222222222222222222222222';
const String shaInstalled = '3333333333333333333333333333333333333333';

/// Markdown d'un livre, au format attendu par [BymMarkdownConverter].
///
/// Les mises à jour transportent désormais du Markdown et non du JSON : c'est le
/// convertisseur embarqué qui fabrique le livre servi. Les tests doivent donc
/// partir d'une source réaliste, tabulation de verset comprise.
String markdown(String title, {int chapters = 1, String text = 'Au commencement'}) {
  final buffer = StringBuffer('# $title\n\n');
  for (var c = 1; c <= chapters; c++) {
    buffer.writeln('## Chapitre $c');
    buffer.writeln('$c:1\t$text ($c:1).');
    buffer.writeln();
  }
  return buffer.toString();
}

/// Empreinte de blob git du Markdown, telle que GitLab la publierait.
String blobOf(String source) =>
    gitBlobId(Uint8List.fromList(utf8.encode(source)));

/// Sert `_source.json` comme le fait l'APK, ou rien du tout pour reproduire un
/// build incomplet.
class _SourceBundle extends AssetBundle {
  _SourceBundle(this.source);

  /// Contenu de `_source.json`, null pour un build sans références.
  final String? source;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == bymSourceAsset && source != null) return source!;
    // Le vrai `rootBundle` lève sur un asset absent : le service doit traiter ce
    // cas, pas recevoir une chaîne vide.
    throw StateError('Asset absent des tests : $key');
  }

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(await loadString(key))));
}

String sourceJson({
  required String commit,
  required Map<String, String> blobs,
  String committedAt = '2026-08-01T00:00:00Z',
}) =>
    jsonEncode({
      'commit': commit,
      'committedAt': committedAt,
      'blobs': blobs,
    });

/// Réponse de `/repository/commits`, réduite aux champs que le service lit.
String commitsJson(List<(String, String, String)> commits) => jsonEncode([
      for (final (id, date, title) in commits)
        {'id': id, 'short_id': id.substring(0, 8), 'committed_date': date,
          'title': title},
    ]);

/// Réponse de `/repository/tree` : `01-Genese.md` → empreinte de blob.
String treeJson(
  Map<String, String> blobs, {
  List<Map<String, Object?>> extra = const [],
}) =>
    jsonEncode([
      for (final entry in blobs.entries)
        {
          'id': entry.value,
          'name': entry.key,
          'type': 'blob',
          'path': entry.key,
          'mode': '100644',
        },
      ...extra,
    ]);

http.Response _ok(String body) => http.Response.bytes(utf8.encode(body), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  final requested = <String>[];

  // Trois livres du catalogue, dans leur version embarquée puis corrigée.
  final geneseOld = markdown('Bereshit (Genèse) (Ge.)');
  final geneseNew = markdown('Bereshit (Genèse) (Ge.)', text: 'Au commencement Élohîm créa');
  final exodeOld = markdown('Shemot (Exode) (Ex.)');
  final exodeNew = markdown('Shemot (Exode) (Ex.)', text: 'Voici les noms');
  final levitiqueOld = markdown('Vayiqra (Lévitique) (Lé.)');
  final levitiqueNew = markdown('Vayiqra (Lévitique) (Lé.)', text: 'YHWH appela');

  /// `_source.json` de l'APK : les trois livres dans leur version d'origine.
  final embeddedBlobs = <String, String>{
    '01-Genese.md': blobOf(geneseOld),
    '02-Exode.md': blobOf(exodeOld),
    '03-Levitique.md': blobOf(levitiqueOld),
  };

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_update_service_test');
    BymUpdateStore.useRoot(temp);
    BymUpdateStore.resetInMemory();
    requested.clear();
    BymUpdateChecker.clear();
  });

  tearDown(() async {
    BymUpdateStore.useAppDirectory();
    BymUpdateStore.resetInMemory();
    BymUpdateChecker.clear();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Client qui journalise chaque URL et répond selon [routes], la clé étant un
  /// fragment de l'URL. Les routes sont essayées dans l'ordre d'insertion : c'est
  /// ce qui permet de distinguer la requête de notes (`since=`) de celle du
  /// dernier commit, toutes deux sur `/repository/commits`.
  MockClient client(
    Map<String, http.Response Function()> routes, {
    Object? Function(String url)? onRequest,
  }) =>
      MockClient((request) async {
        final url = request.url.toString();
        requested.add(url);
        final thrown = onRequest?.call(url);
        if (thrown is Exception) throw thrown;
        for (final route in routes.entries) {
          if (url.contains(route.key)) return route.value();
        }
        return http.Response('not found', 404);
      });

  BymUpdateService service({
    required http.Client httpClient,
    bool withSource = true,
    int maxInFlight = 4,
  }) =>
      BymUpdateService(
        client: httpClient,
        bundle: _SourceBundle(withSource
            ? sourceJson(commit: shaEmbedded, blobs: embeddedBlobs)
            : null),
        retryBackoff: Duration.zero,
        maxInFlight: maxInFlight,
      );

  /// URLs de livres demandées : c'est ce compte qui prouve qu'aucun octet de
  /// texte n'est descendu sans accord.
  Iterable<String> rawRequests() =>
      requested.where((u) => u.contains('/-/raw/'));

  /// Le plan que `checkForUpdate` produirait, écrit à la main pour les tests
  /// d'`apply`.
  BymUpdateCheck plan(Map<String, String> blobs) => BymUpdateCheck(
        BymUpdateStatus.available,
        commit: shaHead,
        committedAt: DateTime.utc(2026, 8, 30, 12),
        books: blobs.keys.toList(),
        blobs: blobs,
        notes: 'Pr. 6:16 qu\'Elohîm -> que YHWH',
      );

  group('BymSourceIndex.parse', () {
    test('lit commit, date et empreintes', () {
      final index = BymSourceIndex.parse(jsonDecode(sourceJson(
        commit: shaEmbedded,
        blobs: embeddedBlobs,
      )))!;
      expect(index.commit, shaEmbedded);
      expect(index.committedAt, DateTime.utc(2026, 8, 1));
      expect(index.blobs['01-Genese.md'], blobOf(geneseOld));
    });

    test('refuse un index dont on ne pourrait rien conclure', () {
      // Chaque cas ferait proposer des livres au hasard : mieux vaut aucun index.
      expect(BymSourceIndex.parse(null), isNull);
      expect(BymSourceIndex.parse('<html>429</html>'), isNull);
      // Sha hors forme, donc inutilisable dans une URL.
      expect(
        BymSourceIndex.parse(jsonDecode(
            sourceJson(commit: 'master', blobs: embeddedBlobs))),
        isNull,
      );
      // Empreintes vides ou toutes hors forme.
      expect(
        BymSourceIndex.parse(jsonDecode(
            sourceJson(commit: shaEmbedded, blobs: const {}))),
        isNull,
      );
      expect(
        BymSourceIndex.parse(jsonDecode(sourceJson(
            commit: shaEmbedded, blobs: const {'01-Genese.md': 'zzz'}))),
        isNull,
      );
      // Sans date, le texte ne serait pas datable dans Réglages.
      expect(
        BymSourceIndex.parse(jsonDecode(jsonEncode(
            {'commit': shaEmbedded, 'blobs': embeddedBlobs}))),
        isNull,
      );
    });
  });

  group('checkForUpdate', () {
    test('annonce les livres qui ont changé sans télécharger un octet de texte',
        () async {
      final svc = service(
        httpClient: client({
          // Avant la route générale : les deux URLs portent `/repository/commits`.
          'since=': () => _ok(commitsJson([
                (shaHead, '2026-08-29T23:49:15.000+02:00',
                    'Pr. 6:16 qu\'Elohîm -> que YHWH'),
                (shaEmbedded, '2026-08-01T00:00:00Z', 'Version embarquée'),
              ])),
          'repository/commits': () => _ok(commitsJson([
                (shaHead, '2026-08-29T23:49:15.000+02:00',
                    'Pr. 6:16 qu\'Elohîm -> que YHWH'),
              ])),
          'repository/tree': () => _ok(treeJson({
                ...embeddedBlobs,
                '01-Genese.md': blobOf(geneseNew),
                '02-Exode.md': blobOf(exodeNew),
              })),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.available);
      expect(check.hasUpdate, isTrue);
      expect(check.commit, shaHead);
      // Ordre du catalogue, pas celui de la réponse.
      expect(check.books, ['01-Genese.md', '02-Exode.md']);
      expect(check.bookCount, 2);
      expect(check.bookLabel, '2 livres');
      expect(check.blobs['01-Genese.md'], blobOf(geneseNew));
      // Les notes viennent des titres de commits amont, et le commit du texte en
      // place en est exclu (`since` est inclusif).
      expect(check.notes, 'Pr. 6:16 qu\'Elohîm -> que YHWH');
      // Un commit, un arbre, des notes : 10 Ko, et aucun livre.
      expect(requested.length, 3);
      expect(rawRequests(), isEmpty);
      // La vérification est horodatée pour ne pas se répéter avant 24 h.
      expect(await BymUpdateStore().lastCheck(), isNotNull);
    });

    test('un commit identique à celui du texte en place ne demande pas l\'arbre',
        () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaEmbedded, '2026-08-01T00:00:00Z', 'idem')])),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.upToDate);
      expect(check.hasUpdate, isFalse);
      // Le raccourci qui rend la vérification quotidienne quasi gratuite.
      expect(requested.length, 1);
      expect(await BymUpdateStore().lastCheck(), isNotNull);
    });

    test('un arbre identique à l\'index de référence conclut « à jour »',
        () async {
      // Le dépôt a bougé (README, CI) mais aucun de nos livres.
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'CI')])),
          'repository/tree': () => _ok(treeJson(embeddedBlobs)),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.upToDate);
      expect(rawRequests(), isEmpty);
      // Pas même la requête de notes : rien à raconter.
      expect(requested.length, 2);
    });

    test('une mise à jour déjà installée recouvre l\'index embarqué', () async {
      // Genèse a déjà été corrigé : comparer l'arbre au seul texte embarqué le
      // reproposerait indéfiniment.
      final store = BymUpdateStore();
      await store.stage('01-Genese.json', BymMarkdownConverter.convertToJson(geneseNew));
      await store.install(
        commit: shaInstalled,
        committedAt: DateTime.utc(2026, 8, 15),
        notes: 'Genèse',
        blobs: {'01-Genese.json': blobOf(geneseNew)},
      );

      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'CI')])),
          'repository/tree': () => _ok(treeJson({
                ...embeddedBlobs,
                '01-Genese.md': blobOf(geneseNew),
              })),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.upToDate);
      expect(rawRequests(), isEmpty);
    });

    test('un sha de commit hors forme est refusé avant toute autre requête',
        () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () => _ok(jsonEncode([
                {'id': 'master', 'committed_date': '2026-08-29T00:00:00Z'},
              ])),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.invalidPayload);
      // Le sha est le seul champ distant qui entre dans une URL : ni arbre ni
      // livre n'est demandé avec une valeur non conforme.
      expect(requested.length, 1);
      // Rien d'horodaté : la vérification n'a pas abouti.
      expect(await BymUpdateStore().lastCheck(), isNull);
    });

    test('une empreinte de blob hors forme fait refuser tout l\'arbre',
        () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'Corrections')])),
          'repository/tree': () => _ok(treeJson({
                ...embeddedBlobs,
                '01-Genese.md': 'pas-un-sha',
              })),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.invalidPayload);
      expect(rawRequests(), isEmpty);
      expect(await BymUpdateStore().lastCheck(), isNull);
    });

    test('un fichier inconnu du catalogue est ignoré, pas téléchargé', () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'README')])),
          'repository/tree': () => _ok(treeJson(
                {...embeddedBlobs, '01-Genese.md': blobOf(geneseNew)},
                extra: [
                  // Existe en amont, n'est pas un livre : jamais demandé.
                  {'id': 'f' * 40, 'name': 'README.md', 'type': 'blob'},
                  {'id': 'e' * 40, 'name': 'Dockerfile', 'type': 'blob'},
                  // Un dossier : le filtre de type passe avant la validation du
                  // sha, sinon un `id` de sous-arbre ferait tout refuser.
                  {'id': 'pas-un-sha', 'name': 'traductions', 'type': 'tree'},
                ],
              )),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.available);
      expect(check.books, ['01-Genese.md']);
      expect(check.bookLabel, '1 livre');
    });

    test('un livre local absent de l\'arbre est ignoré, jamais supprimé',
        () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'Ménage')])),
          // Exode et Lévitique ont disparu de l'arbre : ils restent embarqués.
          'repository/tree': () =>
              _ok(treeJson({'01-Genese.md': blobOf(geneseNew)})),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.available);
      expect(check.books, ['01-Genese.md']);
    });

    test('un arbre où aucun livre n\'est reconnu est refusé', () async {
      // Dépôt réorganisé, redirection, page d'erreur bien formée : conclure « à
      // jour » masquerait le problème pour toujours.
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'Refonte')])),
          'repository/tree': () => _ok(jsonEncode([
                {'id': 'f' * 40, 'name': 'README.md', 'type': 'blob'},
              ])),
        }),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.invalidPayload);
      expect(rawRequests(), isEmpty);
    });

    test('hors ligne : noConnection, transitoire, aucune écriture', () async {
      final svc = service(
        httpClient:
            client(const {}, onRequest: (_) => const SocketException('offline')),
      );

      final check = await svc.checkForUpdate();

      expect(check.status, BymUpdateStatus.noConnection);
      expect(check.status.transient, isTrue);
      expect(check.hasUpdate, isFalse);
      expect(BymUpdateStore.installedCommit, isNull);
      // Sans horodatage, la prochaine vérification aura lieu tout de suite.
      expect(await BymUpdateStore().lastCheck(), isNull);
    });

    test('un 503 est un serverError, pas une charge invalide', () async {
      final svc = service(
        httpClient:
            client({'repository/commits': () => http.Response('busy', 503)}),
      );
      final check = await svc.checkForUpdate();
      expect(check.status, BymUpdateStatus.serverError);
      expect(check.status.transient, isTrue);
    });

    test('un 200 illisible est une charge invalide, non transitoire', () async {
      final svc = service(
        httpClient:
            client({'repository/commits': () => _ok('<html>oops</html>')}),
      );
      final check = await svc.checkForUpdate();
      expect(check.status, BymUpdateStatus.invalidPayload);
      expect(check.status.transient, isFalse);
    });

    test('`_source.json` absent : unconfigured, et rien n\'est demandé',
        () async {
      final svc = service(httpClient: client(const {}), withSource: false);
      final check = await svc.checkForUpdate();
      expect(check.status, BymUpdateStatus.unconfigured);
      // Échec fermé : pas de comparaison contre une valeur inventée, donc pas
      // même une requête.
      expect(requested, isEmpty);
    });
  });

  group('apply', () {
    test('installe les livres vérifiés, convertis, et enregistre le commit',
        () async {
      final svc = service(
        httpClient: client({
          '01-Genese.md': () => _ok(geneseNew),
          '02-Exode.md': () => _ok(exodeNew),
        }),
      );

      final progress = <BymUpdateProgress>[];
      final outcome = await svc.apply(
        plan({
          '01-Genese.md': blobOf(geneseNew),
          '02-Exode.md': blobOf(exodeNew),
        }),
        onProgress: progress.add,
      );

      expect(outcome.applied, isTrue);
      expect(outcome.bookCount, 2);
      expect(outcome.message, contains('2 livres'));
      expect(BymUpdateStore.installedCommit, shaHead);
      expect(BymUpdateStore.installedAt, DateTime.utc(2026, 8, 30, 12));
      expect(BymUpdateStore.installedNotes, contains('Pr. 6:16'));
      expect(BymUpdateStore.updatedCount, 2);
      // Le registre est indexé en `.json` (ce que lit le lecteur) et porte
      // l'empreinte du `.md` (ce que compare la vérification suivante).
      expect(BymUpdateStore.installedBlobs['01-Genese.json'], blobOf(geneseNew));
      // Ce qui est servi est la sortie du convertisseur embarqué, pas le `.md`.
      expect(await BymUpdateStore().read('01-Genese.json'),
          BymMarkdownConverter.convertToJson(geneseNew));
      expect(await BymUpdateStore().read('02-Exode.json'),
          BymMarkdownConverter.convertToJson(exodeNew));
      // Le transit ne survit pas à la bascule.
      expect(await (await BymUpdateStore().staging()).exists(), isFalse);
      expect(progress.last.done, 2);
      expect(progress.last.fraction, 1.0);
    });

    test('les livres sont lus épinglés au sha, jamais sur la branche', () async {
      final svc = service(
        httpClient: client({'01-Genese.md': () => _ok(geneseNew)}),
      );

      await svc.apply(plan({'01-Genese.md': blobOf(geneseNew)}));

      expect(requested.single,
          'https://gitlab.com/anjc/bjc-source/-/raw/$shaHead/01-Genese.md');
      // Une URL épinglée est immuable : aucun texte périmé ne peut arriver, quelle
      // que soit la durée du cache de bord.
      expect(requested.single, isNot(contains('/master/')));
    });

    test('une empreinte de blob fausse fait tout refuser', () async {
      final svc = service(
        // Contenu altéré ou tronqué en transit : l'empreinte ne colle plus.
        httpClient: client({'01-Genese.md': () => _ok(geneseOld)}),
      );

      final outcome = await svc.apply(plan({'01-Genese.md': blobOf(geneseNew)}));

      expect(outcome.status, BymUpdateStatus.invalidPayload);
      expect(outcome.applied, isFalse);
      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(await (await BymUpdateStore().staging()).exists(), isFalse);
    });

    test('une page d\'erreur servie en 200 échoue sur l\'empreinte', () async {
      final page = '<html><body>Sign in to GitLab</body></html>';
      final svc = service(
        httpClient: client({'01-Genese.md': () => _ok(page)}),
      );

      final outcome = await svc.apply(plan({'01-Genese.md': blobOf(geneseNew)}));

      expect(outcome.status, BymUpdateStatus.invalidPayload);
      expect(BymUpdateStore.installedCommit, isNull);
    });

    test('un Markdown sans titre est refusé malgré la bonne empreinte',
        () async {
      // L'empreinte prouve l'authenticité, pas la lisibilité : un fichier vidé en
      // amont est authentique.
      const truncated = '## Chapitre 1\n1:1\tTexte.\n';
      final svc = service(
        httpClient: client({'01-Genese.md': () => _ok(truncated)}),
      );

      final outcome = await svc.apply(plan({'01-Genese.md': blobOf(truncated)}));

      expect(outcome.status, BymUpdateStatus.invalidPayload);
      expect(BymUpdateStore.installedCommit, isNull);
    });

    test('un livre sans chapitre est refusé malgré la bonne empreinte',
        () async {
      // Se convertit sans erreur, et donnerait un livre que personne ne peut
      // lire : la structure est vérifiée en plus de la conversion.
      final empty = markdown('Bereshit (Genèse) (Ge.)', chapters: 0);
      final svc = service(
        httpClient: client({'01-Genese.md': () => _ok(empty)}),
      );

      final outcome = await svc.apply(plan({'01-Genese.md': blobOf(empty)}));

      expect(outcome.status, BymUpdateStatus.invalidPayload);
      expect(BymUpdateStore.installedCommit, isNull);
    });

    test('un échec sur le 2ᵉ livre de 3 n\'installe rien et n\'appelle pas le 3ᵉ',
        () async {
      final svc = service(
        httpClient: client({
          '01-Genese.md': () => _ok(geneseNew),
          '02-Exode.md': () => http.Response('disparu', 404),
          '03-Levitique.md': () => _ok(levitiqueNew),
        }),
        // Un livre à la fois : c'est ce qui rend l'abandon observable.
        maxInFlight: 1,
      );

      final outcome = await svc.apply(plan({
        '01-Genese.md': blobOf(geneseNew),
        '02-Exode.md': blobOf(exodeNew),
        '03-Levitique.md': blobOf(levitiqueNew),
      }));

      expect(outcome.status, BymUpdateStatus.invalidPayload);
      expect(BymUpdateStore.installedCommit, isNull);
      // Le premier livre était bon : il disparaît pourtant avec le transit,
      // sinon le texte servi serait panaché et la date affichée mentirait.
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(await BymUpdateStore().read('01-Genese.json'), isNull);
      expect(requested.where((u) => u.contains('03-Levitique')), isEmpty);
    });

    test('un plan incomplet est refusé avant toute requête', () async {
      final svc = service(httpClient: client(const {}));

      // Livre inconnu du catalogue : le nom d'un fichier ne vient jamais du
      // dépôt sans être intersecté avec le catalogue local.
      expect(
        (await svc.apply(plan({'99-Inconnu.md': blobOf(geneseNew)}))).status,
        BymUpdateStatus.invalidPayload,
      );
      // Empreinte hors forme : rien ne serait vérifiable.
      expect(
        (await svc.apply(plan({'01-Genese.md': 'pas-un-sha'}))).status,
        BymUpdateStatus.invalidPayload,
      );
      // Plan vide.
      expect(
        (await svc.apply(plan(const {}))).status,
        BymUpdateStatus.invalidPayload,
      );
      // Sha de commit hors forme.
      expect(
        (await svc.apply(BymUpdateCheck(
          BymUpdateStatus.available,
          commit: 'master',
          committedAt: DateTime.utc(2026, 8, 30),
          books: const ['01-Genese.md'],
          blobs: {'01-Genese.md': blobOf(geneseNew)},
        )))
            .status,
        BymUpdateStatus.invalidPayload,
      );
      // Aucun octet n'est descendu pour être refusé ensuite.
      expect(requested, isEmpty);
    });

    test('une annulation en cours de route conserve le texte précédent',
        () async {
      late BymUpdateService svc;
      svc = service(
        httpClient: client({'01-Genese.md': () => _ok(geneseNew)},
            onRequest: (_) {
          svc.cancel();
          return null;
        }),
        maxInFlight: 1,
      );

      final outcome = await svc.apply(plan({
        '01-Genese.md': blobOf(geneseNew),
        '02-Exode.md': blobOf(exodeNew),
      }));

      expect(outcome.status, BymUpdateStatus.cancelled);
      expect(BymUpdateStore.installedCommit, isNull);
      expect(await (await BymUpdateStore().staging()).exists(), isFalse);
    });

    test('relance un échec transitoire, puis abandonne proprement', () async {
      var calls = 0;
      final svc = service(
        httpClient: client({
          '01-Genese.md': () {
            calls++;
            return http.Response('busy', 503);
          },
        }),
      );

      final outcome = await svc.apply(plan({'01-Genese.md': blobOf(geneseNew)}));

      expect(outcome.status, BymUpdateStatus.serverError);
      // Trois tentatives, comme `DownloadService`, et pas une de plus.
      expect(calls, 3);
      expect(BymUpdateStore.installedCommit, isNull);
    });

    test('un 404 n\'est pas relancé', () async {
      var calls = 0;
      final svc = service(
        httpClient: client({
          '01-Genese.md': () {
            calls++;
            return http.Response('absent', 404);
          },
        }),
      );

      await svc.apply(plan({'01-Genese.md': blobOf(geneseNew)}));

      // Un livre absent du commit épinglé le restera : relancer ne ferait que
      // perdre du temps devant l'utilisateur.
      expect(calls, 1);
    });
  });

  group('effectiveDate / effectiveCommit', () {
    test('sans mise à jour, le texte est celui de l\'asset embarqué', () async {
      final svc = service(httpClient: client(const {}));
      expect(await svc.effectiveCommit(), shaEmbedded);
      expect(await svc.effectiveDate(), DateTime.utc(2026, 8, 1));
    });

    test('une mise à jour installée l\'emporte', () async {
      final store = BymUpdateStore();
      await store.stage('01-Genese.json', BymMarkdownConverter.convertToJson(geneseNew));
      await store.install(
        commit: shaInstalled,
        committedAt: DateTime.utc(2026, 8, 15),
        notes: '',
        blobs: {'01-Genese.json': blobOf(geneseNew)},
      );

      final svc = service(httpClient: client(const {}));
      expect(await svc.effectiveCommit(), shaInstalled);
      expect(await svc.effectiveDate(), DateTime.utc(2026, 8, 15));
    });

    test('sans `_source.json`, aucune date n\'est inventée', () async {
      final svc = service(httpClient: client(const {}), withSource: false);
      expect(await svc.effectiveCommit(), isNull);
      expect(await svc.effectiveDate(), isNull);
    });
  });

  group('revertToEmbedded', () {
    test('efface la mise à jour installée', () async {
      final store = BymUpdateStore();
      await store.stage('01-Genese.json', BymMarkdownConverter.convertToJson(geneseNew));
      await store.install(
        commit: shaInstalled,
        committedAt: DateTime.utc(2026, 8, 30),
        notes: '',
        blobs: {'01-Genese.json': blobOf(geneseNew)},
      );

      await service(httpClient: client(const {})).revertToEmbedded();

      expect(BymUpdateStore.installedCommit, isNull);
      expect(BymUpdateStore.hasUpdate('01-Genese.json'), isFalse);
      expect(await store.sizeOnDisk(), 0);
    });
  });

  group('BymUpdateChecker.maybeCheck', () {
    test('publie la mise à jour repérée', () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaHead, '2026-08-29T00:00:00Z', 'Corrections')])),
          'repository/tree': () => _ok(treeJson({
                ...embeddedBlobs,
                '01-Genese.md': blobOf(geneseNew),
              })),
        }),
      );

      await BymUpdateChecker.maybeCheck(service: svc);

      expect(BymUpdateChecker.available.value?.bookLabel, '1 livre');
      expect(BymUpdateChecker.available.value?.commit, shaHead);
    });

    test('ne redemande rien avant 24 h', () async {
      final store = BymUpdateStore();
      await store.markChecked(DateTime.now());
      final svc = service(httpClient: client(const {}));

      await BymUpdateChecker.maybeCheck(service: svc, store: store);

      expect(requested, isEmpty);
      expect(BymUpdateChecker.available.value, isNull);

      // `force` passe outre : c'est le bouton de Réglages.
      await BymUpdateChecker.maybeCheck(service: svc, store: store, force: true);
      expect(requested, isNotEmpty);
    });

    test('reste silencieux hors ligne', () async {
      final svc = service(
        httpClient:
            client(const {}, onRequest: (_) => const SocketException('offline')),
      );

      await BymUpdateChecker.maybeCheck(service: svc);

      // Aucune exception, et rien d'annoncé : le démarrage ne doit rien coûter.
      expect(BymUpdateChecker.available.value, isNull);
    });

    test('n\'annonce rien quand le texte est déjà à jour', () async {
      final svc = service(
        httpClient: client({
          'repository/commits': () =>
              _ok(commitsJson([(shaEmbedded, '2026-08-01T00:00:00Z', 'idem')])),
        }),
      );

      await BymUpdateChecker.maybeCheck(service: svc);

      expect(BymUpdateChecker.available.value, isNull);
    });
  });
}
