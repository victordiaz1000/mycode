import 'dictionary_catalog.dart';
import 'dictionary_reader.dart';
import 'dictionary_store.dart';
import 'fredaw_lexicon.dart';

/// A dictionary that can be consulted word by word inside the verse study.
///
/// Two families, one face: [WestphalVerseDictionary] reads the asset bundled
/// with the app, [DownloadedVerseDictionary] the file a download landed in
/// [DictionaryStore]. The study sheet needs three things of it — the name on
/// the picker, the pattern that finds its terms in the verse, the article of
/// one term — and never has to know where the text comes from.
abstract class VerseDictionary {
  const VerseDictionary();

  /// Catalogue code (`dictionaryCatalog`) — « FREDAW », « GBM »…
  String get code;

  /// Name shown on the picker (Westphal 1932, Glossaire Martin 1744…).
  String get name;

  /// Embedded on the device: readable without the Bibliothèque ever having
  /// been opened.
  bool get embedded;

  /// The words of the verse that are entries of this dictionary, as a single
  /// case-insensitive regex — null when no term is linkable.
  Future<RegExp?> linkPattern();

  /// The article of [term], or null when this dictionary does not know it.
  Future<DictionaryArticle?> lookup(String term);
}

/// Westphal 1932, read from `assets/lexicon/fredaw.json`.
class WestphalVerseDictionary extends VerseDictionary {
  const WestphalVerseDictionary();

  /// The dictionary the study sheet has always used — and the one it falls
  /// back to when a downloaded dictionary is no longer on the device.
  static const String defaultCode = 'FREDAW';

  @override
  String get code => defaultCode;

  @override
  String get name => 'Westphal 1932';

  @override
  bool get embedded => true;

  @override
  Future<RegExp?> linkPattern() => FreDawLexicon.instance.linkPattern();

  @override
  Future<DictionaryArticle?> lookup(String term) async {
    final entry = await FreDawLexicon.instance.lookup(term);
    // FreDawLexicon never answers null: a word it does not know comes back as
    // « Entrée FreDAW non disponible », which is the card the study sheet has
    // always shown for it. Terms reach it through [linkPattern], so in
    // practice the placeholder is never seen.
    return DictionaryArticle(term: entry.term, definition: entry.definition);
  }
}

/// A dictionary downloaded from the Bibliothèque, read in [store].
class DownloadedVerseDictionary extends VerseDictionary {
  DownloadedVerseDictionary({required this.entry, required this.reader});

  /// Its catalogue line — name, rights, description.
  final DictionaryEntry entry;

  /// The parsed file, kept so the fiche can cross-link its own terms.
  final DictionaryReader reader;

  @override
  String get code => entry.code;

  @override
  String get name => entry.name;

  @override
  bool get embedded => false;

  @override
  Future<RegExp?> linkPattern() async => reader.linkPattern();

  @override
  Future<DictionaryArticle?> lookup(String term) async => reader.lookup(term);
}

/// Opens [code]: the Westphal asset, or the file a download landed — null
/// when neither can serve it (a code the catalogue dropped, a file deleted
/// from the Bibliothèque, a payload that parses to nothing).
Future<VerseDictionary?> verseDictionaryFor(
  String code, {
  DictionaryStore? store,
}) async {
  if (code == WestphalVerseDictionary.defaultCode) {
    return const WestphalVerseDictionary();
  }
  final entry = dictionaryByCode(code);
  if (entry == null || !entry.embedded && !entry.downloadable) return null;
  final payload = await (store ?? DictionaryStore()).load(code);
  if (payload == null) return null;
  final reader = DictionaryReader.fromJson(payload);
  if (reader.size == 0) return null;
  return DownloadedVerseDictionary(entry: entry, reader: reader);
}

/// Every dictionary the study sheet can be consulted on: the embedded
/// Westphal first, then the downloads present on the device, in catalogue
/// order.
///
/// Neither the whole catalogue nor the whole registry is offered — the same
/// rule as the version picker in the reader: only what has text to serve. A
/// download that is not on the device would open on the empty state, Nave has
/// no source at all, and the Strong français is indexed by code rather than
/// by word, so it could not find a single term in a verse (its place is the
/// Lexique tab).
Future<List<VerseDictionary>> availableVerseDictionaries({
  DictionaryStore? store,
}) async {
  final available = <VerseDictionary>[const WestphalVerseDictionary()];
  Set<String> installed;
  try {
    installed = await (store ?? DictionaryStore()).installed();
  } catch (_) {
    return available;
  }
  for (final entry in dictionaryCatalog) {
    if (!entry.downloadable || !installed.contains(entry.code)) continue;
    final dictionary = await verseDictionaryFor(entry.code, store: store);
    if (dictionary != null) available.add(dictionary);
  }
  return available;
}
