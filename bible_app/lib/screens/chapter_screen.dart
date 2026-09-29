import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../widgets/chapter_reader.dart';
import '../widgets/premium_style.dart';

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
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: premiumBackground(context),
        foregroundColor: p.primary,
        title: Text(
          '${entry.abbreviation} $chapter',
          style: premiumText(context, 17, FontWeight.w800, p.textDark),
        ),
      ),
      body: ChapterReader(bookIndex: bookIndex, chapter: chapter),
    );
  }
}
