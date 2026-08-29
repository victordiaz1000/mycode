import 'reference_parser.dart';

/// Detection of the scripture references embedded in the BYM notes
/// (« Voir Es. 7:14. », « Jos. 22:22 ; 2 S. 22:32 ; Es. 9:5, 10:21, 43:12 »),
/// per `regles-liens-references-bibliques.md` (repo root).
///
/// Grammar:
/// - a run starts on a book abbreviation from [noteAbbreviations] followed by
///   at least a chapter (`Ge. 37`, `Es. 7:14`) — an abbreviation without its
///   numbers is not a reference;
/// - `,` and « et » continue in the same book — with a `:` the item is a new
///   chapter (`10:21`), without one it stays in the current context (verses
///   after `9:5`, chapters after `Za. 14`);
/// - `;` separates references; the book only changes when a new abbreviation
///   appears right after (`De. 16:13, 14 et 16 ; 31:10` keeps Deutéronome);
/// - `-` marks a range within the same chapter (or between chapters when no
///   verse exists, `Ez. 38-39`);
/// - numeric-prefixed abbreviations (`1 S.`, `2 Co.`…) are matched as one
///   atomic block BEFORE any digit is read as a verse or chapter.
///
/// Guard rails: a number that was not reached through this process is never
/// linked (years, note numbers, « 18 heures »); the visible span of a link is
/// exactly the original sub-token (`10:21`, not `Es. 10:21`) while the target
/// carries the reconstructed book/chapter/verse; anything ambiguous stays
/// plain text.

/// `abbreviations.txt` (repo root), verbatim — `number;abbreviation`, 66
/// entries, single source of truth. Deliberately different from
/// `bookCatalog` where the notes differ: the notes write « Lu. » (Luc),
/// « Jud. » (Jude), « Job. », « Joë. »…
const Map<String, int> noteAbbreviations = {
  'Ge.': 1,
  'Ex.': 2,
  'Lé.': 3,
  'No.': 4,
  'De.': 5,
  'Jos.': 6,
  'Jg.': 7,
  '1 S.': 8,
  '2 S.': 9,
  '1 R.': 10,
  '2 R.': 11,
  'Es.': 12,
  'Jé.': 13,
  'Ez.': 14,
  'Os.': 15,
  'Joë.': 16,
  'Am.': 17,
  'Ab.': 18,
  'Jon.': 19,
  'Mi.': 20,
  'Na.': 21,
  'Ha.': 22,
  'So.': 23,
  'Ag.': 24,
  'Za.': 25,
  'Mal.': 26,
  'Ps.': 27,
  'Pr.': 28,
  'Job.': 29,
  'Ca.': 30,
  'Ru.': 31,
  'La.': 32,
  'Ec.': 33,
  'Est.': 34,
  'Da.': 35,
  'Esd.': 36,
  'Né.': 37,
  '1 Ch.': 38,
  '2 Ch.': 39,
  'Mt.': 40,
  'Mc.': 41,
  'Lu.': 42,
  'Jn.': 43,
  'Ac.': 44,
  'Ja.': 45,
  'Ga.': 46,
  '1 Th.': 47,
  '2 Th.': 48,
  '1 Co.': 49,
  '2 Co.': 50,
  'Ro.': 51,
  'Ep.': 52,
  'Ph.': 53,
  'Col.': 54,
  'Phm.': 55,
  '1 Ti.': 56,
  'Tit.': 57,
  '1 Pi.': 58,
  '2 Pi.': 59,
  '2 Ti.': 60,
  'Jud.': 61,
  'Hé.': 62,
  '1 Jn.': 63,
  '2 Jn.': 64,
  '3 Jn.': 65,
  'Ap.': 66,
};

/// A book abbreviation at [start]: letters (optionally preceded by a digit +
/// space) ending with a period. The atomicity of `1 S.` lives here — the
/// digit belongs to the token, never to the surrounding arithmetic.
final RegExp _abbrShape = RegExp(r'(?:(\d)\s?)?[A-Za-zÀ-ÖØ-öø-ÿ]{1,4}\.');

/// Chapter/verse tail. Groups: 1 chapter · 2 verse (after `:`) · 3 verse
/// range end · 4 chapter range end. The lookahead refuses a number flowing
/// into a bigger number or an affix (« 1948 », « 26e »).
final RegExp _headedTailAt = RegExp(
    r'\s*(\d{1,3})(?:\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?)?(?:\s*-\s*(\d{1,3}))?(?![\da-zA-ZÀ-ÖØ-öø-ÿ])');
final RegExp _bareTailAt = RegExp(
    r'(\d{1,3})(?:\s*:\s*(\d{1,3})(?:\s*-\s*(\d{1,3}))?)?(?:\s*-\s*(\d{1,3}))?(?![\da-zA-ZÀ-ÖØ-öø-ÿ])');

/// The written-out separator, always lowercase in the corpus.
final RegExp _etAt = RegExp(r'\s+et\s');

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D;

class _Segment {
  final int end;
  final BibleReference reference;
  final int book;
  final int chapter;
  final bool hadVerse;

  const _Segment(
      this.end, this.reference, this.book, this.chapter, this.hadVerse);
}

/// Finds every reference embedded in a note text: ordered spans, never
/// overlapping, each carrying its fully resolved [BibleReference].
List<TextReference> findNoteReferences(String text) {
  final results = <TextReference>[];
  var i = 0;
  while (i < text.length) {
    final head = _headedSegment(text, i);
    if (head == null) {
      i++;
      continue;
    }
    results.add(TextReference(
        start: i, end: head.end, reference: head.reference));
    var cursor = head.end;
    var book = head.book;
    var chapter = head.chapter;
    var hadVerse = head.hadVerse;
    while (cursor < text.length) {
      final sep = _separatorEnd(text, cursor);
      if (sep == null) break;
      final next = _nextSegment(text, sep, book, chapter, hadVerse);
      if (next == null) break; // the run closes before its separator
      results.add(TextReference(
          start: sep, end: next.end, reference: next.reference));
      cursor = next.end;
      book = next.book;
      chapter = next.chapter;
      hadVerse = next.hadVerse;
    }
    i = cursor;
  }
  return results;
}

_Segment? _headedSegment(String text, int start) {
  final shape = _abbrShape.matchAsPrefix(text, start);
  if (shape == null) return null;
  final book = noteAbbreviations[shape.group(0)!];
  if (book == null) return null;
  final tail = _headedTailAt.matchAsPrefix(text, shape.end);
  if (tail == null) return null; // abbreviation without its numbers
  final chapter = int.parse(tail.group(1)!);
  final verse =
      tail.group(2) == null ? null : int.parse(tail.group(2)!);
  return _Segment(tail.end,
      BibleReference(bookIndex: book, chapter: chapter, verse: verse), book,
      chapter, verse != null);
}

/// One continuation item after `,` / `;` / « et ». A book-shaped token absent
/// from the table (`3 X.`) refuses rather than letting its digit pass for a
/// verse.
_Segment? _nextSegment(
    String text, int start, int book, int chapter, bool hadVerse) {
  final shape = _abbrShape.matchAsPrefix(text, start);
  if (shape != null) {
    final next = noteAbbreviations[shape.group(0)!];
    if (next == null) return null;
    final tail = _headedTailAt.matchAsPrefix(text, shape.end);
    if (tail == null) return null;
    final c = int.parse(tail.group(1)!);
    final v = tail.group(2) == null ? null : int.parse(tail.group(2)!);
    return _Segment(tail.end,
        BibleReference(bookIndex: next, chapter: c, verse: v), next, c,
        v != null);
  }
  final tail = _bareTailAt.matchAsPrefix(text, start);
  if (tail == null) return null;
  final first = int.parse(tail.group(1)!);
  if (tail.group(2) != null) {
    final v = int.parse(tail.group(2)!);
    // `25:1-3`: new chapter of the same book, verses ranged.
    return _Segment(tail.end,
        BibleReference(bookIndex: book, chapter: first, verse: v), book,
        first, true);
  }
  if (hadVerse) {
    // `…26:20,26-27,35` : verses of the current chapter (range end kept out
    // of the target — navigation opens the first verse of the range).
    return _Segment(tail.end,
        BibleReference(bookIndex: book, chapter: chapter, verse: first), book,
        chapter, true);
  }
  // After a chapter-only item (`Lé. 13 et 15`), a bare number is a chapter.
  return _Segment(tail.end, BibleReference(bookIndex: book, chapter: first),
      book, first, false);
}

/// End of the separator sitting at [pos], or null — a `,` or `;` (tolerating
/// spaces on either side, « … et 16 ; 31:10 ») or a lowercase « et »
/// surrounded by spaces. Whatever follows must still parse as an item for the
/// run to continue.
int? _separatorEnd(String text, int pos) {
  if (pos >= text.length) return null;
  if (_isSpace(text.codeUnitAt(pos))) {
    final et = _etAt.matchAsPrefix(text, pos);
    if (et != null) return et.end;
  }
  var j = pos;
  while (j < text.length && _isSpace(text.codeUnitAt(j))) {
    j++;
  }
  if (j >= text.length) return null;
  final unit = text.codeUnitAt(j);
  if (unit != 0x2C && unit != 0x3B) return null;
  j++;
  while (j < text.length && _isSpace(text.codeUnitAt(j))) {
    j++;
  }
  return j;
}
