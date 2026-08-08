import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../widgets/chapter_reader.dart';

/// Standalone full-screen chapter reading (Scaffold + AppBar wrapper around
/// the reusable [ChapterReader] body).
class ChapterScreen extends StatelessWidget {
  final int bookIndex;
  final int chapter;

  const ChapterScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
  });

  @override
  Widget build(BuildContext context) {
    final entry = catalogEntry(bookIndex);
    return Scaffold(
      appBar: AppBar(title: Text('${entry.abbreviation} $chapter')),
      body: ChapterReader(bookIndex: bookIndex, chapter: chapter),
    );
  }
}