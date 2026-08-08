import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/book_catalog.dart';
import 'chapter_list_screen.dart';

class BooksScreen extends StatelessWidget {
  /// When set, tapping a chapter calls this instead of pushing the screens
  /// (used from a home tab to open a reading tab inside the tab system).
  final void Function(int bookIndex, int chapter)? onOpenChapter;

  const BooksScreen({super.key, this.onOpenChapter});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: bibleSections.length,
        itemBuilder: (context, sectionIndex) {
          final section = bibleSections[sectionIndex];
          return _SectionCard(
            section: section,
            onBookTap: (bymIndex) {
              final cb = onOpenChapter;
              if (cb != null) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChapterListScreen(
                      bookIndex: bymIndex,
                      onOpenChapter: cb,
                    ),
                  ),
                );
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChapterListScreen(bookIndex: bymIndex),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final BibleSection section;
  final void Function(int bymIndex) onBookTap;

  const _SectionCard({required this.section, required this.onBookTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          section.name,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(section.subtitle),
        children: [
          for (var i = section.from; i <= section.to; i++)
            ListTile(
              dense: true,
              title: Text(bookCatalog[i - 1].name),
              trailing: Text(
                bookCatalog[i - 1].abbreviation,
                style: theme.textTheme.bodySmall,
              ),
              onTap: () => onBookTap(i),
            ),
        ],
      ),
    );
  }
}