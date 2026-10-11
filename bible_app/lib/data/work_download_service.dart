import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' as io;

import 'work_catalog.dart';
import 'work_store.dart';

/// Why a work install stopped.
enum WorkDownloadStatus {
  /// The file landed and is readable.
  complete,

  /// No network: the request never reached the server (offline, DNS, airplane).
  noConnection,

  /// The server answered but refused: rate-limit (429), timeout, or 5xx.
  serverError,

  /// A 200 arrived but the payload is not a work (`chapters` / `title`).
  invalidPayload,

  /// [WorkDownloadService.cancel] was called mid-flight.
  cancelled,

  /// The entry has no source URL configured yet.
  unavailable,
}

/// Where a work download stands while bytes flow in.
///
/// Un ouvrage est **un** fichier — 240 Ko pour le pilote, davantage pour un
/// livre plus long — donc la barre peut être **déterminée** quand le serveur
/// annonce sa taille (`Content-Length`), indéterminée sinon ([fraction] null).
class WorkDownloadProgress {
  final String code;

  /// Bytes received so far.
  final int received;

  /// Total announced by the server, null (or ≤ 0) when it streams without
  /// declaring its length (chunked encoding).
  final int? total;

  const WorkDownloadProgress({
    required this.code,
    required this.received,
    required this.total,
  });

  /// 0.0 .. 1.0, or null when the server did not announce a size.
  double? get fraction {
    if (total == null || total! <= 0) return null;
    return (received / total!).clamp(0.0, 1.0);
  }
}

/// Outcome of one work install attempt.
class WorkDownloadOutcome {
  final String code;
  final WorkDownloadStatus status;

  const WorkDownloadOutcome({required this.code, required this.status});

  bool get isComplete => status == WorkDownloadStatus.complete;

  /// One line for the snackbar, French.
  String get message => switch (status) {
        WorkDownloadStatus.complete => 'Livre téléchargé.',
        WorkDownloadStatus.cancelled =>
          'Téléchargement interrompu — rien à reprendre, relancez.',
        WorkDownloadStatus.unavailable =>
          'Ce livre n\'a pas encore d\'URL configurée.',
        WorkDownloadStatus.noConnection =>
          'Échec du téléchargement — aucune connexion internet. '
              'Vérifiez votre réseau puis relancez le téléchargement.',
        WorkDownloadStatus.serverError =>
          'Échec du téléchargement — le serveur est momentanément indisponible '
              '(limite de requêtes atteinte ou lenteur réseau). '
              'Patientez quelques minutes puis réessayez.',
        WorkDownloadStatus.invalidPayload =>
          'Échec du téléchargement — le fichier reçu n\'est pas un livre '
              'valide. Le lien est peut-être cassé : signalez-le.',
      };
}

/// How one fetch ended, before deciding what to store.
enum _FetchKind {
  ok,
  noConnection,
  serverError,
  invalidPayload,
  cancelled;

  /// Transitoire : une relance automatique a du sens avant d'abandonner.
  bool get transient => this == noConnection || this == serverError;

  WorkDownloadStatus get status => switch (this) {
        _FetchKind.ok => WorkDownloadStatus.complete,
        _FetchKind.noConnection => WorkDownloadStatus.noConnection,
        _FetchKind.serverError => WorkDownloadStatus.serverError,
        _FetchKind.invalidPayload => WorkDownloadStatus.invalidPayload,
        _FetchKind.cancelled => WorkDownloadStatus.cancelled,
      };
}

/// One fetch outcome: the kind and, on success, the parsed payload.
class _FetchResult {
  final _FetchKind kind;
  final Map<String, dynamic>? payload;

  const _FetchResult(this.kind, [this.payload]);

  const _FetchResult.cancelled() : this(_FetchKind.cancelled);
}

/// Downloads one work JSON file into the [WorkStore].
///
/// Le calque du service des dictionnaires, avec ses deux parades : **relance
/// automatique** d'un échec transitoire ([attemptsPerWork] fois, backoff
/// croissant) et **annulation en vol**, chaque bloc reçu étant un point de
/// contrôle du drapeau.
///
/// Ce qui est validé avant d'écrire : un HTTP 200 **et** une charge portant une
/// liste `chapters` non vide **et** un `title`. Un dictionnaire se contente de
/// ses `entries` ; un ouvrage sans titre n'aurait rien à mettre dans la
/// pastille gauche de l'écran Lecture, et un 200 sur un lien cassé
/// s'installerait comme un livre vide.
class WorkDownloadService {
  WorkDownloadService({
    http.Client? client,
    WorkStore? store,
    this.attemptsPerWork = 3,
    this.retryBackoff = const Duration(milliseconds: 400),
  })  : _injectedClient = client,
        _store = store ?? WorkStore();

  final int attemptsPerWork;

  /// Attente avant la n-ième relance : [retryBackoff], puis ×2, ×4…
  final Duration retryBackoff;

  final http.Client? _injectedClient;
  final WorkStore _store;

  http.Client? _ownedClient;

  /// Le client possédé est recréé à la demande après un [cancel]/[close].
  ///
  /// `autoUncompress` est désactivé **exprès**. dart:io annonce toujours
  /// `Accept-Encoding: gzip` ; avec l'auto-décompression il livre alors les
  /// octets *décompressés* tout en rapportant le `Content-Length` *compressé*
  /// — 67 Ko annoncés pour 241 Ko reçus sur le pilote. La barre bondirait à
  /// 100 % après un quart du fichier, et l'étiquette afficherait
  /// « 241 Ko / 67 Ko ». Sans auto-décompression le flux et l'en-tête décrivent
  /// les mêmes octets : la progression est juste, et [gzip] est décompressé une
  /// fois la réception complète — on garde ainsi le gain de bande passante.
  http.Client get _client => _injectedClient ??
      (_ownedClient ??= io.IOClient(HttpClient()..autoUncompress = false));

  static const Duration requestTimeout = Duration(seconds: 20);

  bool _cancelled = false;

  /// Asks the running install to stop. Le client possédé est fermé pour couper
  /// réellement la requête en cours plutôt que d'attendre son timeout.
  void cancel() {
    _cancelled = true;
    if (_injectedClient == null) {
      _ownedClient?.close();
      _ownedClient = null;
    }
  }

  /// Libère le client possédé (écran détruit). Un client injecté appartient à
  /// son appelant : jamais fermé ici.
  void close() {
    _ownedClient?.close();
    _ownedClient = null;
  }

  /// Installs [entry] — one request, one file, streamed with progress.
  Future<WorkDownloadOutcome> install(
    WorkEntry entry, {
    void Function(WorkDownloadProgress)? onProgress,
  }) async {
    _cancelled = false;
    if (!entry.downloadable || !entry.configured) {
      return WorkDownloadOutcome(
        code: entry.code,
        status: WorkDownloadStatus.unavailable,
      );
    }

    for (var attempt = 1;; attempt++) {
      final result = await _fetchStreamed(entry.url!, entry.code, onProgress);
      if (result.kind == _FetchKind.ok) {
        await _store.save(entry.code, result.payload!);
        return _outcome(entry.code, result);
      }
      if (!result.kind.transient) return _outcome(entry.code, result);
      if (_cancelled) return _outcome(entry.code, result);
      if (attempt >= attemptsPerWork) return _outcome(entry.code, result);
      await Future<void>.delayed(retryBackoff * (1 << (attempt - 1)));
    }
  }

  WorkDownloadOutcome _outcome(String code, _FetchResult result) =>
      WorkDownloadOutcome(code: code, status: result.kind.status);

  /// One fetch, classified instead of swallowed: the caller decides what to
  /// store, this method decides *why* nothing came back.
  Future<_FetchResult> _fetchStreamed(
    String url,
    String code,
    void Function(WorkDownloadProgress)? onProgress,
  ) async {
    try {
      final response = await _client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(requestTimeout)
          .catchError((_) {
        throw http.ClientException('client closed');
      });

      if (response.statusCode != 200) {
        // Le corps d'une erreur ne sert à rien mais il faut le drainer pour
        // rendre la connexion réutilisable.
        await response.stream.drain<void>();
        return _FetchResult(_kindOfStatus(response.statusCode));
      }

      final total = response.contentLength;
      final totalKnown = total != null && total > 0;
      final BytesBuilder builder = BytesBuilder(copy: false);
      var received = 0;

      await for (final chunk in response.stream) {
        if (_cancelled) return const _FetchResult.cancelled();
        builder.add(chunk);
        received += chunk.length;
        onProgress?.call(WorkDownloadProgress(
          code: code,
          received: received,
          total: totalKnown ? total : null,
        ));
      }
      if (_cancelled) return const _FetchResult.cancelled();

      List<int> bytes = builder.takeBytes();
      // Le serveur a comprimé (raw.githubusercontent.com le fait) : le client
      // n'a pas touché aux octets, c'est ici qu'on les ouvre. Un gzip tronqué
      // ou absent lève `FormatException`, rattrapé plus bas en charge invalide.
      if (_isGzip(response.headers)) {
        bytes = gzip.decode(bytes);
      }

      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        return const _FetchResult(_FetchKind.invalidPayload);
      }
      final chapters = decoded['chapters'];
      final title = decoded['title'];
      if (chapters is! List ||
          chapters.isEmpty ||
          title is! String ||
          title.trim().isEmpty) {
        return const _FetchResult(_FetchKind.invalidPayload);
      }
      return _FetchResult(_FetchKind.ok, decoded);
    } on TimeoutException {
      // The server did not answer in time: busy or the network is slow.
      return const _FetchResult(_FetchKind.serverError);
    } on SocketException {
      // The request never left the device (offline, DNS, airplane).
      return const _FetchResult(_FetchKind.noConnection);
    } on http.ClientException {
      return const _FetchResult(_FetchKind.noConnection);
    } catch (_) {
      return const _FetchResult(_FetchKind.invalidPayload);
    }
  }

  /// What a non-200 status says: a busy/limited server asks for patience, a
  /// broken link reads as a payload problem.
  static _FetchKind _kindOfStatus(int status) {
    if (status == 429 || status >= 500) return _FetchKind.serverError;
    return _FetchKind.invalidPayload;
  }

  /// Whether the body is still compressed. Les clés ne sont pas normalisées
  /// partout (dart:io les livre en minuscules, d'autres implémentations non),
  /// d'où une comparaison insensible à la casse ; la valeur peut porter
  /// plusieurs items (`gzip, deflate`), d'où la recherche du mot.
  static bool _isGzip(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-encoding' &&
          entry.value.contains('gzip')) {
        return true;
      }
    }
    return false;
  }
}
