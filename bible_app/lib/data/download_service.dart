import 'dart:convert';

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

  /// A book failed. Whatever arrived is kept and the next attempt resumes.
  failed,

  /// [DownloadService.cancel] was called mid-flight.
  cancelled,

  /// The version has no free source (copyright, décision 9).
  unavailable,
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

  /// The getbible endpoint serving one whole book.
  ///
  /// [standardBook] is the standard 1..66 number, not the BYM index — see
  /// [bymToStandard].
  static Uri bookUri(String getbibleId, int standardBook) =>
      Uri.parse('https://api.getbible.net/v2/$getbibleId/$standardBook.json');

  /// Installs [entry], skipping the books already on the device.
  ///
  /// [onProgress] fires before each book is fetched and once at the end.
  Future<DownloadOutcome> install(
    VersionEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    _cancelled = false;
    final total = bookCatalog.length;
    final id = entry.getbibleId;

    if (!entry.downloadable || id == null) {
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

      final book = await _fetchBook(id, bookIndex);
      if (book == null) {
        return DownloadOutcome(
          code: entry.code,
          status: DownloadStatus.failed,
          done: done,
          total: total,
          failedBook: bookIndex,
        );
      }

      await _store.saveBook(entry.code, bookIndex, book);
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

  /// One book as getbible serves it, or null on any failure.
  ///
  /// Returning null rather than throwing keeps the caller's resume logic in one
  /// place: every failure means « stop here, keep what landed ».
  Future<Map<String, dynamic>?> _fetchBook(String id, int bymIndex) async {
    try {
      final uri = bookUri(id, bymToStandard(bymIndex));
      final response = await _client.get(uri).timeout(requestTimeout);
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      // A 200 carrying no chapter is a failure too — an empty book stored as
      // installed would read as a hole in the version.
      final chapters = decoded['chapters'];
      if (chapters is! List || chapters.isEmpty) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}
