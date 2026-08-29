import 'reference_parser.dart';

/// One entry of a downloaded dictionary: a term and its definition.
class DictionaryArticle {
  final String term;
  final String definition;

  const DictionaryArticle({required this.term, required this.definition});

  /// Accepts both shapes the embedded lexicons use: a bare string value
  /// (« BAILLY » → string) or an object with a `definition` field.
  factory DictionaryArticle.fromJson(String key, dynamic value) {
    final term = key.trim();
    if (value is Map) {
      final raw = value['definition'];
      return DictionaryArticle(
        term: term,
        definition: raw?.toString().trim() ?? '',
      );
    }
    return DictionaryArticle(term: term, definition: value?.toString().trim() ?? '');
  }
}

/// In-memory view of a downloaded dictionary (`{entries: {...}}`), with the
/// same search shape as the embedded lexicons.
class DictionaryReader {
  final Map<String, DictionaryArticle> _byKey = {};
  final Map<String, String> _normalized = {};
  List<String> _keys = const [];

  int get size => _keys.length;

  /// Builds the reader from a decoded dictionary payload. Returns null when the
  /// payload is not a dictionary at all (missing or empty `entries`).
  factory DictionaryReader.fromJson(Map<String, dynamic> json) {
    final reader = DictionaryReader._();
    final rawEntries = json['entries'];
    if (rawEntries is! Map || rawEntries.isEmpty) return reader;
    for (final item in rawEntries.entries) {
      final key = item.key.toString().trim();
      if (key.isEmpty) continue;
      final article = DictionaryArticle.fromJson(key, item.value);
      if (article.definition.isEmpty) continue;
      reader._byKey[key] = article;
      reader._normalized[key] = normalizeForSearch(article.term);
    }
    reader._keys = reader._byKey.keys.toList()..sort();
    return reader;
  }

  DictionaryReader._();

  List<DictionaryArticle> all() => [for (final key in _keys) _byKey[key]!];

  /// Exact lookup by term (case-insensitive), or null when absent.
  DictionaryArticle? lookup(String term) => _byKey[term.trim().toUpperCase()];

  /// The characters that make up a dictionary word, used to bound the
  /// cross-links: letters (accents folded in), digits, underscore and hyphen
  /// — but not the apostrophe, so that « l'ABBA » links its « ABBA ».
  static const String _wordChars = r'A-Za-z0-9À-ÖØ-öø-ÿ_\-';

  /// A term is linkable when it is a single word: letters, hyphens and
  /// apostrophes only. Multi-word titles (« ABDIAS OU OBADIA ») or parenthesised
  /// ones (« ABEL (LIEU) ») cannot be matched in running text.
  static final RegExp _linkableTerm = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ'’\-]{2,}$");

  RegExp? _linkPattern;

  /// A single case-insensitive regex that finds, anywhere in a text, every
  /// word that is itself a dictionary entry. Longest terms first (so
  /// « ABEL-BETH-MAACA » wins over « ABEL » at the same position) and word
  /// boundaries so that « ABEL » inside « ABELARD » or « ABEL-BETH » is not a
  /// link. Null when no term is linkable.
  RegExp? linkPattern() {
    if (_linkPattern != null) return _linkPattern;
    final terms = _keys.where(_linkableTerm.hasMatch).toList()
      ..sort((a, b) => b.length - a.length);
    if (terms.isEmpty) return null;
    _linkPattern = RegExp(
      '(?<![$_wordChars])(?:${terms.map(RegExp.escape).join('|')})'
      '(?![$_wordChars])',
      caseSensitive: false,
    );
    return _linkPattern;
  }

  List<DictionaryArticle> search(String query, {int limit = 50}) {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final exact = _byKey[trimmed.toUpperCase()];
    if (exact != null) return [exact];

    final needle = normalizeForSearch(trimmed);
    if (needle.isEmpty) return const [];

    final ranked = <({int score, int rank, String key})>[];
    for (var i = 0; i < _keys.length; i++) {
      final key = _keys[i];
      final normalizedKey = _normalized[key]!;
      final score = normalizedKey == needle
          ? 0
          : normalizedKey.startsWith(needle)
              ? 1
              : normalizedKey.contains(needle)
                  ? 2
                  : null;
      if (score != null) {
        ranked.add((score: score, rank: i, key: key));
      }
    }
    ranked.sort((a, b) {
      if (a.score != b.score) return a.score - b.score;
      return a.rank - b.rank;
    });
    return [for (final result in ranked.take(limit)) _byKey[result.key]!];
  }
}