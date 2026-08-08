import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/bible_sections.dart';
import '../data/local_repository.dart';
import '../models/bible_book.dart';
import 'chapter_screen.dart';

class ChapterListScreen extends StatefulWidget {
  /// BYM book index (1..66).
  final int bookIndex;

  /// When set, tapping a chapter calls this instead of pushing [ChapterScreen]
  /// (used from a home tab to open a reading tab).
  final void Function(int bookIndex, int chapter)? onOpenChapter;

  const ChapterListScreen({super.key, required this.bookIndex, this.onOpenChapter});

  @override
  State<ChapterListScreen> createState() => _ChapterListScreenState();
}

class _ChapterListScreenState extends State<ChapterListScreen> {
  final LocalRepository _repository = LocalRepository();
  late Future<BibleBook> _bookFuture;

  @override
  void initState() {
    super.initState();
    _bookFuture = _repository.loadBook(widget.bookIndex);
  }

  @override
  Widget build(BuildContext context) {
    final entry = catalogEntry(widget.bookIndex);
    final section = sectionForBook(widget.bookIndex);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.abbreviation),
      ),
      body: FutureBuilder<BibleBook>(
        future: _bookFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Erreur : ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final book = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  book.book,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(section.name),
              ),
              if (book.introduction.isNotEmpty) ...[
                const Divider(),
                Text(
                  book.introduction,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const Divider(),
              GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var c = 1; c <= book.chapters.length; c++)
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: OutlinedButton(
                        onPressed: () {
                          final cb = widget.onOpenChapter;
                          if (cb != null) {
                            cb(widget.bookIndex, c);
                            Navigator.of(context).popUntil(
                              (route) => route.isFirst,
                            );
                          } else {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChapterScreen(
                                  bookIndex: widget.bookIndex,
                                  chapter: c,
                                ),
                              ),
                            );
                          }
                        },
                        child: Text('$c'),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}