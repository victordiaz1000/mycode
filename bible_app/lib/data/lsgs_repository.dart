import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../models/bible_book.dart';
import '../models/chapter.dart';
import '../models/lsgs.dart';
import '../models/verse.dart';

/// Loads the embedded LSGS books from `assets/bible/lsgs/`.
///
/// The schema differs from BYM: each verse carries `tokens` with optional
/// Strong numbers. The reader still displays plain text, while the Strong
/// tokens stay available for lexicon rendering.
class LsgsRepository {
  static const String assetPrefix = 'assets/bible/lsgs/';

  static const List<String> _assetFiles = [
    '01-Genèse.json',
    '02-Exode.json',
    '03-Lévitique.json',
    '04-Nombres.json',
    '05-Deutéronome.json',
    '06-Josué.json',
    '07-Juges.json',
    '08-1Samuel.json',
    '09-2Samuel.json',
    '10-1Rois.json',
    '11-2Rois.json',
    '12-Ésaïe.json',
    '13-Jérémie.json',
    '14-Ézéchiel.json',
    '15-Osée.json',
    '16-Joël.json',
    '17-Amos.json',
    '18-Abdias.json',
    '19-Jonas.json',
    '20-Michée.json',
    '21-Nahum.json',
    '22-Habakuk.json',
    '23-Sophonie.json',
    '24-Aggée.json',
    '25-Zacharie.json',
    '26-Malachie.json',
    '27-Psaumes.json',
    '28-Proverbes.json',
    '29-Job.json',
    '30-Cantique.json',
    '31-Ruth.json',
    '32-Lamentations.json',
    '33-Ecclésiaste.json',
    '34-Esther.json',
    '35-Daniel.json',
    '36-Esdras.json',
    '37-Néhémie.json',
    '38-1Chroniques.json',
    '39-2Chroniques.json',
    '40-Matthieu.json',
    '41-Marc.json',
    '42-Luc.json',
    '43-Jean.json',
    '44-Actes.json',
    '45-Jacques.json',
    '46-Galates.json',
    '47-1Thessaloniciens.json',
    '48-2Thessaloniciens.json',
    '49-1Corinthiens.json',
    '50-2Corinthiens.json',
    '51-Romains.json',
    '52-Éphésiens.json',
    '53-Philippiens.json',
    '54-Colossiens.json',
    '55-Philémon.json',
    '56-1Timothée.json',
    '57-Tite.json',
    '58-1Pierre.json',
    '59-2Pierre.json',
    '60-2Timothée.json',
    '61-Jude.json',
    '62-Hébreux.json',
    '63-1Jean.json',
    '64-2Jean.json',
    '65-3Jean.json',
    '66-Apocalypse.json',
  ];

  static final Map<int, LsgsBook> _cache = {};
  static AssetBundle _bundle = rootBundle;

  static AssetBundle get bundle => _bundle;

  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    _cache.clear();
  }

  static void useRootBundle() => useBundle(rootBundle);

  String assetPath(int bookNumber) {
    if (bookNumber < 1 || bookNumber > _assetFiles.length) {
      throw RangeError.range(bookNumber, 1, _assetFiles.length);
    }
    return '$assetPrefix${_assetFiles[bookNumber - 1]}';
  }

  Future<LsgsBook> loadBook(int bookNumber) async {
    final cached = _cache[bookNumber];
    if (cached != null) return cached;

    final raw = await _bundle.loadString(assetPath(bookNumber));
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final book = LsgsBook.fromJson(decoded);
    _cache[bookNumber] = book;
    return book;
  }

  Future<Chapter> loadChapter(int bookNumber, int chapter) async {
    final book = await loadBook(bookNumber);
    final found = book.chapters.firstWhere(
      (c) => c.chapter == chapter,
      orElse: () => LsgsChapter(chapter: chapter, verses: const []),
    );
    return Chapter(
      chapter: found.chapter,
      verses: found.verses
          .map((verse) => Verse(
                verse: '${found.chapter}:${verse.verse}',
                text: verse.tokens.map((t) => t.text).join(),
                textWithNotes: verse.tokens.map((t) => t.text).join(),
              ))
          .toList(),
    );
  }

  static BibleBook toBibleBook(LsgsBook lsgsBook) {
    final chapters = lsgsBook.chapters
        .map((chapter) => Chapter(
              chapter: chapter.chapter,
              verses: chapter.verses
                  .map((verse) => Verse(
                        verse: '${chapter.chapter}:${verse.verse}',
                        text: _renderVerseText(verse.tokens),
                        textWithNotes: _renderVerseText(verse.tokens),
                      ))
                  .toList(),
            ))
        .toList();

    return BibleBook(
      number: lsgsBook.bymIndex,
      book: lsgsBook.book,
      abbreviation: lsgsBook.abbreviation,
      metadata: const BookMetadata(
        signification: '',
        auteur: '',
        theme: '',
        date: '',
      ),
      introduction: '',
      chapters: chapters,
    );
  }

  static String _renderVerseText(List<LsgsToken> tokens) {
    final buffer = StringBuffer();
    for (final token in tokens) {
      final rawText = token.text;
      if (rawText.isEmpty) continue;

      final text = rawText.trimRight();
      if (text.isEmpty) continue;

      final previous = buffer.toString();
      final needsLeadingSpace = buffer.isNotEmpty &&
          (!previous.endsWith(' ') &&
              !previous.endsWith('\n') &&
              !previous.endsWith('\t') &&
              !text.startsWith(' ') &&
              !text.startsWith('.') &&
              !text.startsWith(',') &&
              !text.startsWith(';') &&
              !text.startsWith(':') &&
              !text.startsWith('!') &&
              !text.startsWith('?') &&
              !text.startsWith(')') &&
              !text.startsWith('"') &&
              !text.startsWith('«') &&
              !text.startsWith('('));

      if (needsLeadingSpace) {
        buffer.write(' ');
      }

      if (token.strong != null && token.strong!.isNotEmpty) {
        buffer.write('$text ${token.strong!}');
      } else {
        buffer.write(text);
      }
    }
    return buffer.toString().trim();
  }
}
