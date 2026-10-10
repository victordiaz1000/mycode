import '../models/lsgs.dart';
import 'book_catalog.dart';
import 'lsgs_repository.dart';

/// A single verse in the Strong corpus where a code appears.
class StrongOccurrence {
  final int bookIndex;
  final int chapter;
  final int verse;

  /// Human reference label, e.g. « Jean 3:16 » (`BookEntry.shortName`).
  final String reference;

  const StrongOccurrence({
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.reference,
  });
}

/// In-memory, lazily-built index of every Strong code over the embedded LSS
/// corpus: `strong code → verses where it appears`.
///
/// The LSS and not the LSGS, because that is what the study reads
/// (`EtudePreferences.versionCode`) and because its anchors number 446 codes
/// the LSGS does not have — the particles of the extended numbering, whose
/// most frequent (H8799, ×19 883 verses) would answer « 0 occurrence » here.
///
/// The 66 books are scanned once on first access and kept as a map of packed
/// references (nothing heavier — the verse text itself is read on demand by
/// the caller through [LsgsRepository.verseText]). This mirrors the build cost
/// of [FulltextIndex]; the result pays for itself across every fiche opened.
class StrongOccurrenceIndex {
  StrongOccurrenceIndex._();

  static final StrongOccurrenceIndex instance = StrongOccurrenceIndex._();

  static LsgsRepository? _repositoryOverride;

  static const int _books = 66;

  Map<String, List<StrongOccurrence>>? _byCode;
  bool _building = false;
  Future<void>? _buildingFuture;

  /// Serves the index from [repository] instead of the ambient one — the same
  /// seam as [LocalRepository.useBundle]: reading assets through the real
  /// `rootBundle` never completes inside the fake-async zone of `testWidgets`.
  static void useRepository(LsgsRepository repository) {
    _repositoryOverride = repository;
    clear();
  }

  static void useAmbientRepository() {
    _repositoryOverride = null;
    clear();
  }

  static void clear() {
    instance._byCode = null;
    instance._building = false;
    instance._buildingFuture = null;
  }

  bool get isBuilt => _byCode != null;

  Future<void> _ensureBuilt() {
    if (_byCode != null) return Future.value();
    return _buildingFuture ??= _build();
  }

  Future<void> _build() async {
    if (_building) return;
    _building = true;
    final repository = _repositoryOverride ?? LsgsRepository.strong();
    final byCode = <String, List<StrongOccurrence>>{};
    try {
      for (var book = 1; book <= _books; book++) {
        final LsgsBook loaded;
        try {
          loaded = await repository.loadBook(book);
        } catch (_) {
          continue; // a half-served corpus must not break the whole index
        }
        final shortName = catalogEntry(book).shortName;
        for (final chapter in loaded.chapters) {
          for (final verse in chapter.verses) {
            final seen = <String>{};
            for (final token in verse.tokens) {
              final strong = token.strong;
              if (strong == null || strong.isEmpty) continue;
              if (!seen.add(strong)) continue; // one occurrence per verse
              byCode
                  .putIfAbsent(strong, () => [])
                  .add(StrongOccurrence(
                    bookIndex: book,
                    chapter: chapter.chapter,
                    verse: verse.verse,
                    reference: '$shortName ${chapter.chapter}:${verse.verse}',
                  ));
            }
          }
        }
      }
    } finally {
      _building = false;
    }
    _byCode = byCode;
  }

  /// Verses where [strong] appears, in biblical order. Empty when the code is
  /// absent from the corpus or the index is being built (callers await
  /// [isBuilt] through [ensureBuilt] first via [occurrences]).
  Future<List<StrongOccurrence>> occurrences(String strong) async {
    await _ensureBuilt();
    return List.unmodifiable(_byCode?[strong] ?? const []);
  }

  /// Number of verses where [strong] appears.
  Future<int> count(String strong) async {
    await _ensureBuilt();
    return _byCode?[strong]?.length ?? 0;
  }
}