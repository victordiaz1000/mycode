import 'book_catalog.dart';

/// A parsed scripture reference: a book, and optionally a chapter and a verse.
class BibleReference {
  /// BYM book index (1..66).
  final int bookIndex;
  final int? chapter;
  final int? verse;

  const BibleReference({required this.bookIndex, this.chapter, this.verse});

  /// "Ge. 1:1", "Ge. 1", "Ge."
  String get label {
    final abbr = catalogEntry(bookIndex).abbreviation;
    if (chapter == null) return abbr;
    if (verse == null) return '$abbr $chapter';
    return '$abbr $chapter:$verse';
  }

  @override
  String toString() => 'BibleReference($bookIndex, $chapter, $verse)';

  @override
  bool operator ==(Object other) =>
      other is BibleReference &&
      other.bookIndex == bookIndex &&
      other.chapter == chapter &&
      other.verse == verse;

  @override
  int get hashCode => Object.hash(bookIndex, chapter, verse);
}

const Map<String, String> _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae', '’': "'",
};

/// Lowercases, strips accents and punctuation, collapses whitespace.
/// "Yeshayahu (Ésaïe)" → "yeshayahu esaie".
String normalizeForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final ch = String.fromCharCode(rune);
    final plain = _accents[ch] ?? ch;
    // Single ASCII letter/digit/space — a code check is far cheaper than a
    // RegExp per character (this runs over every verse and every 14k Strong
    // definition on each search).
    if (plain.length == 1) {
      final code = plain.codeUnitAt(0);
      if ((code >= 97 && code <= 122) ||
          (code >= 48 && code <= 57) ||
          code == 32) {
        buffer.write(plain);
        continue;
      }
    }
    buffer.write(' ');
  }
  return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Where [needle] occurs in [haystack], ignoring case and accents, or null.
///
/// The returned bounds are indices into the **original** [haystack], so the
/// search screen can paint a highlight over accented text ("grace" finds
/// « grâce »). Unlike [normalizeForSearch], nothing is collapsed or dropped:
/// each source character keeps its own offset.
({int start, int end})? findIgnoringAccents(String haystack, String needle) {
  if (needle.isEmpty || haystack.isEmpty) return null;

  // Folded text, plus the original index each folded character came from.
  final folded = StringBuffer();
  final origin = <int>[];
  var cursor = 0;
  for (final rune in haystack.runes) {
    final ch = String.fromCharCode(rune);
    final plain = _accents[ch.toLowerCase()] ?? ch.toLowerCase();
    for (var i = 0; i < plain.length; i++) {
      origin.add(cursor);
    }
    folded.write(plain);
    cursor += ch.length;
  }

  final foldedNeedle = StringBuffer();
  for (final rune in needle.runes) {
    final ch = String.fromCharCode(rune);
    foldedNeedle.write(_accents[ch.toLowerCase()] ?? ch.toLowerCase());
  }

  final start = folded.toString().indexOf(foldedNeedle.toString());
  if (start < 0) return null;
  final endFolded = start + foldedNeedle.length;
  return (
    start: origin[start],
    end: endFolded < origin.length ? origin[endFolded] : haystack.length,
  );
}

/// Book indices matching [query] by name or abbreviation, best match first.
///
/// Ranking: exact abbreviation > name prefix > word prefix > substring.
/// An empty query returns nothing (the caller shows its own default list).
List<int> searchBooks(String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];

  final scored = <({int book, int score})>[];
  for (var i = 1; i <= bookCatalog.length; i++) {
    final entry = bookCatalog[i - 1];
    final name = normalizeForSearch(entry.name);
    final abbr = normalizeForSearch(entry.abbreviation);

    int? score;
    if (abbr == q) {
      score = 0;
    } else if (name.startsWith(q)) {
      score = 1;
    } else if (name.split(' ').any((w) => w.startsWith(q))) {
      score = 2;
    } else if (name.contains(q)) {
      score = 3;
    } else if (abbr.startsWith(q)) {
      score = 4;
    }
    if (score != null) scored.add((book: i, score: score));
  }
  scored.sort((a, b) =>
      a.score != b.score ? a.score - b.score : a.book - b.book);
  return [for (final s in scored) s.book];
}

/// Trailing "3:16", "3.16", "3 16" or "3" — chapter and optional verse.
final RegExp _trailingNumbers =
    RegExp(r'\s+(\d{1,3})(?:\s*[:.,v]\s*(\d{1,3}))?\s*$');

/// Splits "Jean 3:16" into its book part ("Jean") and trailing chapter/verse.
///
/// Only *trailing* numbers count, so book names that start with a digit
/// ("1 Samuel") keep working. When the trailing numbers do not follow a known
/// book they stay part of [bookQuery] (e.g. "1 Samuel").
({String bookQuery, int? chapter, int? verse}) splitReference(String query) {
  final trimmed = query.trim();
  final match = _trailingNumbers.firstMatch(trimmed);
  if (match == null) return (bookQuery: trimmed, chapter: null, verse: null);

  final bookPart = trimmed.substring(0, match.start);
  if (searchBooks(bookPart).isEmpty) {
    return (bookQuery: trimmed, chapter: null, verse: null);
  }
  return (
    bookQuery: bookPart,
    chapter: int.tryParse(match.group(1)!),
    verse: match.group(2) == null ? null : int.tryParse(match.group(2)!),
  );
}

/// Parses a free-text reference such as "Jean 3:16", "Ge 1", "1 Samuel 3.4"
/// or just "Psaumes". Returns null when no book can be identified.
BibleReference? parseReference(String query) {
  final parts = splitReference(query);
  final books = searchBooks(parts.bookQuery);
  if (books.isEmpty) return null;
  return BibleReference(
    bookIndex: books.first,
    chapter: parts.chapter,
    verse: parts.verse,
  );
}
