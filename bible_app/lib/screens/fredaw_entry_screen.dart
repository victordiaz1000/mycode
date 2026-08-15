import 'package:flutter/material.dart';

import '../data/fredaw_lexicon.dart';
import '../data/reference_parser.dart';
import '../widgets/fredaw_article_view.dart';

/// A single Westphal 1932 article: the term in a header card, then the
/// definition (multi-paragraph) with a « Lire la suite / Réduire » toggle.
///
/// The body is the reusable [FredawArticleView]; this screen only adds the
/// AppBar with the « Ouvrir onglet » escape hatch into the reading tabs.
class FredawEntryScreen extends StatelessWidget {
  final FreDawEntry entry;

  /// Opens the entry in a reader tab instead of the fiche — used by the
  /// search screen, which can also grow the article as a reading page.
  final void Function(String term, String definition)? onOpenDictionary;

  /// Opens a Bible reference found in the article in a reader tab. Null when
  /// the fiche stands alone (tests): references then stay plain text.
  final void Function(int bookIndex, int chapter, int? verse)? onOpenVerse;

  const FredawEntryScreen({
    super.key,
    required this.entry,
    this.onOpenDictionary,
    this.onOpenVerse,
  });

  Future<void> _openEntry(BuildContext context, String term) async {
    final entry = await FreDawLexicon.instance.lookup(term);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FredawEntryScreen(
          entry: entry,
          onOpenDictionary: onOpenDictionary,
          onOpenVerse: onOpenVerse,
        ),
      ),
    );
  }

  void _openVerse(BuildContext context, BibleReference reference) {
    final callback = onOpenVerse;
    if (callback == null) return;
    // Clear the stacked chain of fiches (a reference may be reached several
    // routes deep) before switching to the reading tab: a single pop would
    // leave an intermediate route covering the reader.
    Navigator.of(context).popUntil((route) => route.isFirst);
    callback(reference.bookIndex, reference.chapter ?? 1, reference.verse);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (onOpenDictionary != null)
            Tooltip(
              message: 'Ouvrir dans Lecture',
              child: TextButton.icon(
                key: const Key('openDictionaryTab'),
                onPressed: () {
                  // Clear the stacked chain of fiches (the fiche may sit on top
                  // of the index pushed from the Bibliothèque) before switching
                  // to the reading tab: a single pop would leave an intermediate
                  // route covering the reader.
                  Navigator.of(context).popUntil((route) => route.isFirst);
                  onOpenDictionary!(entry.term, entry.definition);
                },
                icon: const Icon(Icons.tab_outlined, size: 18),
                label: const Text('Ouvrir onglet'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: FredawArticleView(
            entry: entry,
            onTermTap: (term) => _openEntry(context, term),
            onReferenceTap: onOpenVerse == null
                ? null
                : (reference) => _openVerse(context, reference),
          ),
        ),
      ),
    );
  }
}