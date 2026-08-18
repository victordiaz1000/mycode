import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'book_catalog.dart';
import 'book_mapping.dart';
import 'library_store.dart';
import 'version_catalog.dart';

/// Where an install stands, pushed to the Bibliothèque while it runs.
class DownloadProgress {
  final String code;

  /// Books already on the device, including those from a previous attempt.
  final int done;

  /// Books the canon holds — [bookCatalog] length.
  final int total;

  /// BYM index being fetched right now, null once finished.
  final int? currentBook;

  const DownloadProgress({
    required this.code,
    required this.done,
    required this.total,
    this.currentBook,
  });

  double get fraction => total == 0 ? 0 : done / total;

  /// "Genèse" — what the row prints under the bar.
  String? get currentBookName =>
      currentBook == null ? null : catalogEntry(currentBook!).shortName;
}

/// Why an install stopped.
enum DownloadStatus {
  /// Every book landed.
  complete,

  /// A book's payload was unusable (non-200 4xx, or a 200 carrying no chapter).
  /// Whatever arrived is kept and the next attempt resumes.
  failed,

  /// The request never reached the server — offline, DNS, airplane mode.
  noConnection,

  /// The server answered slowly or refused: timeout, 429, or 5xx. A retry in a
  /// few minutes is the honest answer.
  serverError,

  /// [DownloadService.cancel] was called mid-flight.
  cancelled,

  /// The version has no free source (copyright, décision 9).
  unavailable,
}

/// How one book fetch ended, before deciding whether to stop the install.
enum _BookFetchKind {
  ok,
  noConnection,
  serverError,
  invalidPayload;

  DownloadStatus get status => switch (this) {
        _BookFetchKind.ok => DownloadStatus.complete,
        _BookFetchKind.noConnection => DownloadStatus.noConnection,
        _BookFetchKind.serverError => DownloadStatus.serverError,
        _BookFetchKind.invalidPayload => DownloadStatus.failed,
      };
}

class _BookFetchResult {
  final _BookFetchKind kind;
  final Map<String, dynamic>? payload;

  const _BookFetchResult(this.kind, [this.payload]);
}

/// Outcome of one install attempt.
class DownloadOutcome {
  final String code;
  final DownloadStatus status;

  /// Books on the device when the attempt ended.
  final int done;
  final int total;

  /// BYM index that failed, when [status] is [DownloadStatus.failed].
  final int? failedBook;

  const DownloadOutcome({
    required this.code,
    required this.status,
    required this.done,
    required this.total,
    this.failedBook,
  });

  bool get isComplete => status == DownloadStatus.complete;

  /// One line for the snackbar.
  String get message => switch (status) {
        DownloadStatus.complete => 'Téléchargement terminé.',
        DownloadStatus.cancelled => 'Téléchargement interrompu — $done/$total '
            'livres conservés, la reprise repartira de là.',
        DownloadStatus.unavailable =>
          'Cette version n\'a pas de source libre.',
        DownloadStatus.noConnection => 'Échec du téléchargement — aucune '
            'connexion internet. Vérifiez votre réseau puis relancez, '
            '$done/$total livres conservés.',
        DownloadStatus.serverError => 'Échec du téléchargement — le serveur est '
            'momentanément indisponible. Patientez quelques minutes puis '
            'relancez, $done/$total livres conservés.',
        DownloadStatus.failed => failedBook == null
            ? 'Téléchargement interrompu — $done/$total livres conservés.'
            : 'Échec sur ${catalogEntry(failedBook!).shortName} — $done/$total '
                'livres conservés, relancer reprendra là où ça s\'est arrêté.',
      };
}

/// Downloads a version book by book into the [LibraryStore] (décision 6).
///
/// Never fetches `v2/<id>.json`: the whole Darby is 10 Mo in one response,
/// where a book is a few kilobytes (décision 9). So one install is 66 requests,
/// and on a phone network one of them failing partway is routine. Books already
/// recorded are skipped, so a failed attempt is not lost work — relaunching
/// resumes from the first missing book.
class DownloadService {
  DownloadService({http.Client? client, LibraryStore? store})
      : _client = client ?? http.Client(),
        _store = store ?? LibraryStore();

  final http.Client _client;
  final LibraryStore _store;

  static const Duration requestTimeout = Duration(seconds: 20);

  bool _cancelled = false;

  /// Asks the running install to stop after the book in flight. What already
  /// landed stays on the device.
  void cancel() => _cancelled = true;

  /// The endpoint serving one whole book for [entry].
  ///
  /// A direct host wins when the entry carries a [VersionEntry.urlTemplate]
  /// (GitHub raw, décision 7) : its `{book}` token is replaced by the
  /// **standard** 1..66 number. Otherwise the getbible.net v2 endpoint is used.
  /// [standardBook] is the standard 1..66 number, not the BYM index — see
  /// [bymToStandard].
  static Uri bookUri(VersionEntry entry, int standardBook) {
    final template = entry.urlTemplate;
    if (template != null && template.isNotEmpty) {
      return Uri.parse(template.replaceAll('{book}', '$standardBook'));
    }
    return Uri.parse(
        'https://api.getbible.net/v2/${entry.getbibleId}/$standardBook.json');
  }

  /// Installs [entry], skipping the books already on the device.
  ///
  /// [onProgress] fires before each book is fetched and once at the end.
  Future<DownloadOutcome> install(
    VersionEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    _cancelled = false;
    final total = bookCatalog.length;

    if (!entry.fetchable) {
      return DownloadOutcome(
        code: entry.code,
        status: DownloadStatus.unavailable,
        done: 0,
        total: total,
      );
    }

    var done = (await _store.versionState(entry.code)).bookCount;
    final missing = await _store.missingBooks(entry.code);

    for (final bookIndex in missing) {
      if (_cancelled) {
        return DownloadOutcome(
          code: entry.code,
          status: DownloadStatus.cancelled,
          done: done,
          total: total,
        );
      }
      onProgress?.call(DownloadProgress(
        code: entry.code,
        done: done,
        total: total,
        currentBook: bookIndex,
      ));

      final book = await _fetchBook(entry, bookIndex);
      if (book.kind != _BookFetchKind.ok) {
        return DownloadOutcome(
          code: entry.code,
          status: book.kind.status,
          done: done,
          total: total,
          failedBook: bookIndex,
        );
      }

      await _store.saveBook(entry.code, bookIndex, book.payload!);
      done++;
    }

    onProgress?.call(
        DownloadProgress(code: entry.code, done: done, total: total));
    return DownloadOutcome(
      code: entry.code,
      status: DownloadStatus.complete,
      done: done,
      total: total,
    );
  }

  /// One book as getbible serves it, classified instead of swallowed.
  ///
  /// Returning a [._BookFetchResult] rather than throwing keeps the caller's
  /// resume logic in one place: every failure means « stop here, keep what
  /// landed » — and the kind tells the user *why* (offline, busy server,
  /// unusable payload) so the message can be precise.
  Future<_BookFetchResult> _fetchBook(VersionEntry entry, int bymIndex) async {
    try {
      final uri = bookUri(entry, bymToStandard(bymIndex));
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) {
        return _BookFetchResult(_kindOfStatus(response.statusCode));
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const _BookFetchResult(_BookFetchKind.invalidPayload);
      }
      // A 200 carrying no chapter is a failure too — an empty book stored as
      // installed would read as a hole in the version.
      final chapters = decoded['chapters'];
      if (chapters is! List || chapters.isEmpty) {
        return const _BookFetchResult(_BookFetchKind.invalidPayload);
      }
      return _BookFetchResult(_BookFetchKind.ok, decoded);
    } on TimeoutException {
      // The server did not answer in time: busy or the network is slow.
      return const _BookFetchResult(_BookFetchKind.serverError);
    } on SocketException {
      // The request never left the device (offline, DNS, airplane).
      return const _BookFetchResult(_BookFetchKind.noConnection);
    } on http.ClientException {
      return const _BookFetchResult(_BookFetchKind.noConnection);
    } catch (_) {
      return const _BookFetchResult(_BookFetchKind.invalidPayload);
    }
  }

  /// What a non-200 status says: a busy/limited server asks for patience, a
  /// broken link reads as a payload problem.
  static _BookFetchKind _kindOfStatus(int status) {
    if (status == 429 || status >= 500) return _BookFetchKind.serverError;
    return _BookFetchKind.invalidPayload;
  }
}
