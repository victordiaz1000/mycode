import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/strong_lexicon.dart';
import '../models/lsgs.dart';
import '../widgets/clickable_verse.dart';

/// Word-by-word rendering of a verse from the embedded LSGS (maquette v8,
/// `Qwen_maquette_lexique_suite.html`).
///
/// Every token carrying a Strong code is drawn underlined-dotted and opens its
/// fiche (Strong French definition) below, with navigation between the strong
/// words of the verse (« Mot X / N du verset »).
class StrongLexiqueScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;
  final int verseNumber;
  final List<LsgsToken> tokens;

  /// A Strong code preselected by the caller (tap in the reader); its fiche is
  /// opened on arrival instead of leaving the empty prompt.
  final String? initialStrong;

  const StrongLexiqueScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.tokens,
    this.initialStrong,
  });

  @override
  State<StrongLexiqueScreen> createState() => _StrongLexiqueScreenState();
}

class _StrongLexiqueScreenState extends State<StrongLexiqueScreen> {
  StrongDefinition? _definition;
  int? _selectedStrongIndex;
  int _selectedToken = -1;

  /// Positions of the tokens that carry a Strong code — the navigable words.
  List<int> get _strongIndices => [
        for (var i = 0; i < widget.tokens.length; i++)
          if (widget.tokens[i].strong case final strong?)
            if (strong.isNotEmpty) i
      ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialStrong;
    if (initial != null && initial.isNotEmpty) {
      final indices = _strongIndices;
      for (final i in indices) {
        if (widget.tokens[i].strong == initial) {
          _select(i);
          break;
        }
      }
    }
  }

  Future<void> _select(int tokenIndex) async {
    final strong = widget.tokens[tokenIndex].strong;
    if (strong == null) return;
    final definition = await StrongLexicon.instance.lookup(strong);
    if (!mounted) return;
    setState(() {
      _selectedToken = tokenIndex;
      _selectedStrongIndex = _strongIndices.indexOf(tokenIndex);
      _definition = definition;
    });
  }

  void _previous() {
    final strongIndex = _selectedStrongIndex;
    final indices = _strongIndices;
    if (strongIndex == null || indices.isEmpty) return;
    _select(indices[(strongIndex - 1 + indices.length) % indices.length]);
  }

  void _next() {
    final strongIndex = _selectedStrongIndex;
    final indices = _strongIndices;
    if (strongIndex == null || indices.isEmpty) return;
    _select(indices[(strongIndex + 1) % indices.length]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = catalogEntry(widget.bookIndex);
    final strongCount = _strongIndices.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lexique — ${entry.shortName} '
                '${widget.chapter}.${widget.verseNumber}'),
            Text(
              'Verset mot à mot',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (strongCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '☞ Touchez un mot souligné du verset pour afficher '
                        'sa fiche',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ClickableVerse(
                  tokens: widget.tokens,
                  onStrongTap: (index, _) => _select(index),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_definition != null)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.tokens[_selectedToken].text,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: .14,
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              _definition!.strong,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _definition!.definition,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _previous,
                            icon: const Icon(Icons.chevron_left),
                            label: const Text('Mot préc.'),
                          ),
                          Expanded(
                            child: Text(
                              'Mot ${(_selectedStrongIndex ?? 0) + 1} / '
                              '$strongCount du verset',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _next,
                            iconAlignment: IconAlignment.end,
                            icon: const Icon(Icons.chevron_right),
                            label: const Text('Mot suiv.'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Touchez un mot souligné du verset pour afficher sa fiche.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            const Spacer(),
            Text(
              'Module : Lexique Strong français — '
              'FreStrongs (CrossWire/SWORD)',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}