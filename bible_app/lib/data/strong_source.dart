import '../models/translation.dart';
import 'read_repository.dart';

/// Source of the "FR + Strong" version used by the Lexique tab (decision 10).
///
/// The final French-with-Strong source is not yet validated (see AGENTS.md).
/// Today this proxies an installed getbible translation via [readRepository];
/// words are not yet Strong-tagged. Swap [implementedTranslation] for the real
/// FR+Strong source (or a Filebase `url:`) when it is available.
class StrongSource {
  final ReadRepository readRepository;
  final Translation implementedTranslation;

  StrongSource({
    required this.readRepository,
    Translation? implementedTranslation,
  }) : implementedTranslation =
            implementedTranslation ??
            const Translation(
              id: 'ls1910',
              name: 'FR (Louis Segond 1910)',
              language: 'fr',
              source: 'getbible',
            );

  /// Fetches the FR+Strong verse texts for [chapter] of the book at [bymIndex].
  Future<List<String>> fetchChapter({required int bymIndex, required int chapter}) {
    return readRepository.fetchChapter(
      translation: implementedTranslation,
      bymIndex: bymIndex,
      chapter: chapter,
    );
  }
}
