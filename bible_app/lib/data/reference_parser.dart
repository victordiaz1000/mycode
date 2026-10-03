import 'book_catalog.dart';

/// A parsed scripture reference: a book, and optionally a chapter and a verse.
///
/// [verseEnd] carries a verse RANGE read from the query (« Exode 4:5-10 »):
/// navigation opens the first verse, the label keeps the whole range. Null
/// outside a range. A bare « Mt 5-7 » stays a chapter-only reference — without
/// a colon the second number reads as a chapter, not a verse.
class BibleReference {
  /// BYM book index (1..66).
  final int bookIndex;
  final int? chapter;
  final int? verse;
  final int? verseEnd;

  const BibleReference({
    required this.bookIndex,
    this.chapter,
    this.verse,
    this.verseEnd,
  });

  /// "Ge. 1:1", "Ge. 1:1-3", "Ge. 1", "Ge."
  String get label {
    final abbr = catalogEntry(bookIndex).abbreviation;
    if (chapter == null) return abbr;
    if (verse == null) return '$abbr $chapter';
    if (verseEnd != null) return '$abbr $chapter:$verse-$verseEnd';
    return '$abbr $chapter:$verse';
  }

  @override
  String toString() => 'BibleReference($bookIndex, $chapter, $verse, $verseEnd)';

  @override
  bool operator ==(Object other) =>
      other is BibleReference &&
      other.bookIndex == bookIndex &&
      other.chapter == chapter &&
      other.verse == verse &&
      other.verseEnd == verseEnd;

  @override
  int get hashCode => Object.hash(bookIndex, chapter, verse, verseEnd);
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

/// The catalogue folded once. [searchBooks] runs per keystroke and once per
/// reference found in a page of text; these three spellings of 66 books never
/// change at runtime, so they are not paid for on every call.
final List<({String abbr, List<String> names})> _bookKeys = [
  for (final entry in bookCatalog)
    (
      // Spaces and periods dropped: « 1 Co. » must answer to « 1Co ».
      abbr: normalizeForSearch(entry.abbreviation).replaceAll(' ', ''),
      names: <String>{
        // The catalogue name, bilingual where the BYM heads it —
        // « Bereshit (Genèse) », « Bereshit ».
        normalizeForSearch(entry.name),
        // The French name alone, so an exact « Genèse » outranks a book that
        // merely starts with the same letters.
        normalizeForSearch(entry.shortName),
        // The name the BYM gives the book — the only spelling that reaches the
        // twenty-odd books whose BYM name is carried apart from [name]
        // (Mattithyah, Roma, Ivriyim, Diakonos).
        normalizeForSearch(entry.hebrewName),
      }.toList(),
    ),
];

/// One book's strict score against [query], or null when it does not match:
/// exact name > name prefix > word prefix > substring.
int? _matchName(String name, String query) {
  if (name == query) return 1;
  if (name.startsWith(query)) return 2;
  if (name.split(' ').any((w) => w.startsWith(query))) return 3;
  if (name.contains(query)) return 4;
  return null;
}

/// Book indices matching [query] by name or abbreviation, best match first.
///
/// Every spelling the app itself prints is accepted: the catalogue
/// abbreviation (« Mt », « 1Co », « Ps »), the full catalogue name
/// (« Bereshit (Genèse) »), the French name (« Genèse ») and the name the BYM
/// gives the book (« Mattithyah », « Roma », « Ivriyim » — Hebrew for the Old
/// Testament, Greek for the Gospels and the Epistles).
///
/// Ranking: exact abbreviation > exact name > name prefix > word prefix >
/// substring > abbreviation prefix.
///
/// When *nothing* matches, a second pass compares by edit distance, because a
/// transliteration is not a word a French reader spells from memory
/// (« Berchit », « Mattityah », « Psames »). It only ever runs on an empty
/// first pass: a typo must never outrank a real name.
///
/// An empty query returns nothing (the caller shows its own default list).
List<int> searchBooks(String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  // The query without its spaces, for keys the app prints with some: an
  // abbreviation (« 1Co ») and a BYM name (« Shir Hashirim ») are both typed
  // in one breath.
  final tight = q.replaceAll(' ', '');

  final scored = <({int book, int score})>[];
  final close = <({int book, int distance})>[];

  for (var i = 1; i <= bookCatalog.length; i++) {
    final keys = _bookKeys[i - 1];
    int? score;
    if (keys.abbr == tight) {
      score = 0;
    } else {
      for (final name in keys.names) {
        final s = _matchName(name, q);
        if (s != null && (score == null || s < score)) score = s;
      }
      if (score == null && keys.abbr.startsWith(tight)) score = 5;
    }
    if (score != null) {
      scored.add((book: i, score: score));
      continue;
    }

    // A typo needs letters to hide in: under four, tolerance would match half
    // the catalogue and the first pass would have been pointless.
    if (tight.length < 4) continue;
    final budget = _typoBudget(tight.length);
    int? best;
    for (final name in keys.names) {
      final d = _distanceWithin(name, tight, budget);
      if (d != null && (best == null || d < best)) best = d;
    }
    if (best != null) close.add((book: i, distance: best));
  }

  if (scored.isNotEmpty) {
    scored.sort(
        (a, b) => a.score != b.score ? a.score - b.score : a.book - b.book);
    return [for (final s in scored) s.book];
  }
  close.sort((a, b) =>
      a.distance != b.distance ? a.distance - b.distance : a.book - b.book);
  return [for (final c in close) c.book];
}

/// Misspelling slack, by query length: one slip up to four letters, two up to
/// seven, three beyond.
int _typoBudget(int length) => length <= 4 ? 1 : length <= 7 ? 2 : 3;

/// Levenshtein distance between [a] and [b], abandoned as soon as it passes
/// [max]: a row whose cheapest cell is already above [max] can never come back
/// down, so the rest of the table is not worth computing. Null when the
/// distance exceeds [max].
int? _distanceWithin(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return null;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    var rowMin = curr[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final deletion = prev[j] + 1;
      final insertion = curr[j - 1] + 1;
      final substitution = prev[j - 1] + cost;
      final cell = deletion < insertion
          ? (deletion < substitution ? deletion : substitution)
          : (insertion < substitution ? insertion : substitution);
      curr[j] = cell;
      if (cell < rowMin) rowMin = cell;
    }
    if (rowMin > max) return null;
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length] <= max ? prev[b.length] : null;
}

/// Trailing "3:16", "3.16", "3 16", "3:16-18" or "3" — chapter and optional
/// verse, itself optionally ranged. The range end is only meaningful behind a
/// verse (« 4:5-10 »): a bare « 5-7 » tail keeps [splitReference] from reading
/// its second number as a verse.
final RegExp _trailingNumbers =
    RegExp(r'\s+(\d{1,3})(?:\s*[:.,v]\s*(\d{1,3}))?(?:\s*-\s*(\d{1,3}))?\s*$');

/// Splits "Jean 3:16" into its book part ("Jean") and trailing chapter/verse.
///
/// Only *trailing* numbers count, so book names that start with a digit
/// ("1 Samuel") keep working. When the trailing numbers do not follow a known
/// book they stay part of [bookQuery] (e.g. "1 Samuel").
({String bookQuery, int? chapter, int? verse, int? verseEnd})
    splitReference(String query) {
  final trimmed = query.trim();
  final match = _trailingNumbers.firstMatch(trimmed);
  if (match == null) {
    return (bookQuery: trimmed, chapter: null, verse: null, verseEnd: null);
  }

  final bookPart = trimmed.substring(0, match.start);
  if (searchBooks(bookPart).isEmpty) {
    return (bookQuery: trimmed, chapter: null, verse: null, verseEnd: null);
  }
  final verse = match.group(2) == null ? null : int.tryParse(match.group(2)!);
  final verseEnd = verse == null || match.group(3) == null
      ? null
      : int.tryParse(match.group(3)!);
  return (
    bookQuery: bookPart,
    chapter: int.tryParse(match.group(1)!),
    verse: verse,
    verseEnd: verseEnd,
  );
}

/// Parses a free-text reference such as "Jean 3:16", "Ge 1", "1 Samuel 3.4",
/// "Exode 4:5-10" or just "Psaumes" — and the same references under the BYM's
/// own names ("Mattithyah 5", "Roma 8:1", "Bereshit"), a misspelling of them
/// included ("Psames 23"). Returns null when no book can be identified.
BibleReference? parseReference(String query) {
  final parts = splitReference(query);
  final books = searchBooks(parts.bookQuery);
  if (books.isEmpty) return null;
  return BibleReference(
    bookIndex: books.first,
    chapter: parts.chapter,
    verse: parts.verse,
    verseEnd: parts.verseEnd,
  );
}

/// A Bible reference found inside running text: the bounds of the span (into
/// the original text) and the parsed target.
class TextReference {
  final int start;
  final int end;
  final BibleReference reference;

  const TextReference({required this.start, required this.end, required this.reference});
}

/// French Bible abbreviations as found in Westphal 1932 (« Lu », « 1Co »,
/// « Ps »), folded by [normalizeForSearch] (lowercase, no punctuation, no
/// accents). The article writes them without the catalogue's periods and
/// sometimes without a space (« 1Ch »), so the catalogue abbreviations do not
/// resolve them. Keys are distinct enough that « Es » (Ésaïe) never meets
/// « Est » (Esther) nor « Esd » (Esdras).
const Map<String, int> _bibleAbbreviations = {
  'ge': 1, 'ex': 2, 'le': 3, 'no': 4, 'de': 5, 'jos': 6, 'jg': 7,
  'ru': 31,
  '1s': 8, '2s': 9, '1r': 10, '2r': 11,
  '1ch': 38, '2ch': 39, 'esd': 36, 'ne': 37,
  'es': 12, 'est': 34, 'je': 13, 'la': 32, 'ez': 14, 'da': 35,
  'os': 15, 'jo': 16, 'jl': 16, 'am': 17, 'ab': 18, 'jon': 19,
  'mi': 20, 'na': 21, 'ha': 22, 'so': 23, 'ag': 24, 'za': 25,
  'mal': 26, 'ps': 27, 'pr': 28, 'jb': 29, 'ct': 30, 'ec': 33,
  'mt': 40, 'mc': 41, 'lu': 42, 'lc': 42, 'jn': 43, 'ac': 44,
  'ro': 51, '1co': 49, '2co': 50, 'ga': 46, 'ep': 52, 'ph': 53,
  'col': 54, '1th': 47, '2th': 48, '1ti': 56, '2ti': 60,
  'tit': 57, 'phm': 55, 'he': 62, 'ja': 45, '1p': 58, '2p': 59,
  'jd': 61, '1jn': 63, '2jn': 64, '3jn': 65, 'ap': 66,
};

/// A letter or digit continuing a word — blocks a reference whose number
/// flows into a bigger number (« 1948 ») or into an affix.
final RegExp _refWordChar = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿ0-9_]');

/// Same as [_refWordChar] plus the hyphen and the apostrophe — a reference
/// book must not start inside a compound (« saint-Jean », « parJean »).
final RegExp _refBookPrefixChar = RegExp(r"[A-Za-zÀ-ÖØ-öø-ÿ0-9_'-]");

final RegExp _chapterVerse = RegExp(r'(\d{1,3})(?:\s*[:.,]\s*(\d{1,3}))?');

/// The whitespace-separated tokens ending at [end], their start indices, at
/// most [_maxReferenceTokens] of them.
List<({String word, int start})> _precedingTokens(String text, int end) {
  final out = <({String word, int start})>[];
  var i = end;
  while (i > 0 && out.length < 3) {
    while (i > 0 && text.codeUnitAt(i - 1) == 32) {
      i--;
    }
    final wordEnd = i;
    while (i > 0 && text.codeUnitAt(i - 1) != 32) {
      i--;
    }
    final word = text.substring(i, wordEnd);
    if (word.isEmpty) break;
    out.insert(0, (word: word, start: i));
  }
  return out;
}

/// Finds the Bible references embedded in [text]: a book (French Bible
/// abbreviation or full name) followed by at least a chapter number. Returns
/// the spans in reading order, never overlapping.
List<TextReference> findReferences(String text) {
  final results = <TextReference>[];
  final matches = _chapterVerse.allMatches(text).toList();
  for (final match in matches) {
    final after = match.end;
    if (after < text.length && _refWordChar.hasMatch(text[after])) {
      continue; // part of a bigger number (« 1948 ») or an affix
    }
    final chapter = int.tryParse(match.group(1)!);
    final verse =
        match.group(2) == null ? null : int.tryParse(match.group(2)!);
    final tokens = _precedingTokens(text, match.start);
    if (tokens.isEmpty) continue;
    for (var k = tokens.length; k >= 1; k--) {
      final start = tokens[tokens.length - k].start;
      final joined = tokens.sublist(tokens.length - k).map((t) => t.word).join(' ');
      final BibleReference? ref;
      final book = _bibleAbbreviations[normalizeForSearch(joined)];
      if (book != null) {
        ref = BibleReference(bookIndex: book, chapter: chapter, verse: verse);
      } else {
        ref = parseReference('$joined $chapter${verse == null ? '' : ':$verse'}');
      }
      if (ref == null) continue;
      if (start > 0 && _refBookPrefixChar.hasMatch(text[start - 1])) {
        break; // a bound word before the book disqualifies the whole window
      }
      if (results.isNotEmpty && start < results.last.end) {
        break; // overlapping a previous reference (a continuation verse)
      }
      results.add(TextReference(start: start, end: after, reference: ref));
      break;
    }
  }
  return results;
}
