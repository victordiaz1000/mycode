import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'dictionary_catalog.dart';
import 'dictionary_store.dart';

/// Why a dictionary install stopped.
enum DictionaryDownloadStatus {
  /// The file landed and is readable.
  complete,

  /// No network: the request never reached the server (offline, DNS, airplane).
  noConnection,

  /// The server answered but refused: rate-limit (429), timeout, or 5xx.
  serverError,

  /// A 200 arrived but the payload is not a `{entries: {...}}` dictionary.
  invalidPayload,

  /// [DictionaryDownloadService.cancel] was called mid-flight.
  cancelled,

  /// The entry has no source URL configured yet.
  unavailable,
}

/// Where a dictionary download stands while bytes flow in.
///
/// Un dictionnaire est **un** fichier — parfois lourd (Bailly ≈ 11 Mo) — donc
/// la barre peut être **déterminée** quand le serveur annonce sa taille
/// (`Content-Length`), indéterminée sinon ([fraction] null).
class DictionaryDownloadProgress {
  final String code;

  /// Bytes received so far.
  final int received;

  /// Total announced by the server, null (or ≤ 0) when it streams without
  /// declaring its length (chunked encoding).
  final int? total;

  const DictionaryDownloadProgress({
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

/// Outcome of one dictionary install attempt.
class DictionaryDownloadOutcome {
  final String code;
  final DictionaryDownloadStatus status;

  const DictionaryDownloadOutcome({required this.code, required this.status});

  bool get isComplete => status == DictionaryDownloadStatus.complete;

  /// One line for the snackbar, French.
  String get message => switch (status) {
        DictionaryDownloadStatus.complete => 'Dictionnaire téléchargé.',
        DictionaryDownloadStatus.cancelled =>
          'Téléchargement interrompu — rien à reprendre, relancez.',
        DictionaryDownloadStatus.unavailable =>
          'Ce dictionnaire n\'a pas encore d\'URL configurée.',
        DictionaryDownloadStatus.noConnection =>
          'Échec du téléchargement — aucune connexion internet. '
              'Vérifiez votre réseau puis relancez le téléchargement.',
        DictionaryDownloadStatus.serverError =>
          'Échec du téléchargement — le serveur est momentanément indisponible '
              '(limite de requêtes atteinte ou lenteur réseau). '
              'Patientez quelques minutes puis réessayez.',
        DictionaryDownloadStatus.invalidPayload =>
          'Échec du téléchargement — le fichier reçu n\'est pas un dictionnaire '
              'valide. Le lien est peut-être cassé : signalez-le.',
      };
}

/// How one fetch ended, before deciding what to store.
///
/// The statuses mirror the user-facing [DictionaryDownloadStatus] so that the
/// snackbar can name the real cause: no network at all, a busy/slow server,
/// or a payload that is not a dictionary. Everything is distinct French text.
enum _FetchKind {
  ok,
  noConnection,
  serverError,
  invalidPayload,
  cancelled;

  /// Transitoire : une relance automatique a du sens avant d'abandonner.
  bool get transient => this == noConnection || this == serverError;

  DictionaryDownloadStatus get status => switch (this) {
        _FetchKind.ok => DictionaryDownloadStatus.complete,
        _FetchKind.noConnection => DictionaryDownloadStatus.noConnection,
        _FetchKind.serverError => DictionaryDownloadStatus.serverError,
        _FetchKind.invalidPayload => DictionaryDownloadStatus.invalidPayload,
        _FetchKind.cancelled => DictionaryDownloadStatus.cancelled,
      };
}

/// One fetch outcome: the kind and, on success, the parsed payload.
class _FetchResult {
  final _FetchKind kind;
  final Map<String, dynamic>? payload;

  const _FetchResult(this.kind, [this.payload]);

  const _FetchResult.cancelled() : this(_FetchKind.cancelled);
}

/// Downloads one dictionary JSON file into the [DictionaryStore].
///
/// A dictionary is a single request — nothing like a Bible version's 66 books —
/// but the file can be heavy (Bailly ≈ 11 Mo), so the body is read **en flux** :
/// chaque bloc reçu pousse une [DictionaryDownloadProgress], ce qui donne une
/// barre déterminée dès que le serveur annonce sa taille. Deux parades de plus :
///
/// - **Relance automatique** — un échec transitoire (réseau, serveur occupé)
///   est retenté [attemptsPerBook] fois avec backoff croissant ; un lien cassé
///   ne deviendra pas bon.
/// - **Annulation en vol** — [cancel] ferme le client possédé et coupe la
///   requête ; chaque bloc reçu est aussi un point de contrôle du drapeau.
///
/// What is validated before saving: an HTTP 200 *and* a payload carrying a
/// non-empty `entries` map. A 200 with garbage would store a file that reads as
/// installed but opens empty.
class DictionaryDownloadService {
  DictionaryDownloadService({
    http.Client? client,
    DictionaryStore? store,
    this.attemptsPerBook = 3,
    this.retryBackoff = const Duration(milliseconds: 400),
  })  : _injectedClient = client,
        _store = store ?? DictionaryStore();

  final int attemptsPerBook;

  /// Attente avant la n-ième relance : [retryBackoff], puis ×2, ×4…
  final Duration retryBackoff;

  final http.Client? _injectedClient;
  final DictionaryStore _store;

  http.Client? _ownedClient;

  /// Le client possédé est recréé à la demande après un [cancel]/[close].
  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

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
  Future<DictionaryDownloadOutcome> install(
    DictionaryEntry entry, {
    void Function(DictionaryDownloadProgress)? onProgress,
  }) async {
    _cancelled = false;
    if (!entry.downloadable || !entry.configured) {
      return DictionaryDownloadOutcome(
        code: entry.code,
        status: DictionaryDownloadStatus.unavailable,
      );
    }

    for (var attempt = 1;; attempt++) {
      final result =
          await _fetchStreamed(entry.url!, entry.code, onProgress);
      if (result.kind == _FetchKind.ok) {
        await _store.save(entry.code, result.payload!);
        return _outcome(entry.code, result);
      }
      if (!result.kind.transient) return _outcome(entry.code, result);
      if (_cancelled) return _outcome(entry.code, result);
      if (attempt >= attemptsPerBook) return _outcome(entry.code, result);
      await Future<void>.delayed(retryBackoff * (1 << (attempt - 1)));
    }
  }

  DictionaryDownloadOutcome _outcome(String code, _FetchResult result) =>
      DictionaryDownloadOutcome(code: code, status: result.kind.status);

  /// One fetch, classified instead of swallowed: the caller decides what to
  /// store, this method decides *why* nothing came back.
  ///
  /// Le corps est lu bloc par bloc : annulation vérifiée à chaque bloc, et
  /// progression poussée au fur et à mesure.
  Future<_FetchResult> _fetchStreamed(
    String url,
    String code,
    void Function(DictionaryDownloadProgress)? onProgress,
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
        onProgress?.call(DictionaryDownloadProgress(
          code: code,
          received: received,
          total: totalKnown ? total : null,
        ));
      }
      if (_cancelled) return const _FetchResult.cancelled();

      final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
      if (decoded is! Map<String, dynamic>) {
        return const _FetchResult(_FetchKind.invalidPayload);
      }
      final entries = decoded['entries'];
      if (entries is! Map || entries.isEmpty) {
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
}
