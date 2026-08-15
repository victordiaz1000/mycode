import 'package:flutter/material.dart';

import '../data/lsgs_repository.dart';
import '../data/strong_lexicon.dart';
import '../data/strong_occurrences.dart';
import '../models/lsgs.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/strong_code_text.dart';
import 'strong_occurrences_screen.dart';

/// The Strong fiche (maquette `ecran_detail_fiche_strong_2.dart`): the word in
/// a header card with its language and part-of-speech, the short and complete
/// definitions, then the verses where the code actually appears in the
/// embedded LSGS corpus — the first 5 as a preview, « Voir plus » opening the
/// books that contain the word.
class StrongDetailScreen extends StatefulWidget {
  final StrongDefinition strong;

  /// Opens the verse in a reader tab — used from the search screen. Null when
  /// the fiche stands alone (tests): occurrence cards then just state the
  /// reference.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const StrongDetailScreen({super.key, required this.strong, this.onOpenVerse});

  @override
  State<StrongDetailScreen> createState() => _StrongDetailScreenState();
}

class _StrongDetailScreenState extends State<StrongDetailScreen> {
  static const int _limite = 5;

  List<StrongOccurrence> _occurrences = const [];
  final Map<int, List<LsgsToken>> _tokens = {};
  bool _loaded = false;

  bool get _isGreek => widget.strong.language == 'greek' ||
      widget.strong.strong.startsWith('G');

  String get _langue => _isGreek ? 'Grec' : 'Hébreu';

  Color get _langueColor => _isGreek ? const Color(0xFF1A73E8) : const Color(0xFFD95300);

  /// The complete definition, as bullet points: the structured senses when the
  /// entry carries them, the bulleted `definition` otherwise.
  List<String> get _senses {
    final senses = widget.strong.senses;
    if (senses.isNotEmpty) return senses;
    final def = widget.strong.definition;
    final bullets = def
        .split(RegExp(r'[•\n]'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    return bullets.toList();
  }

  /// The short definition: the first sense, or the first line of the
  /// definition when the entry has no structured senses.
  String get _breve {
    final senses = _senses;
    if (senses.isNotEmpty) return senses.first;
    final first = widget.strong.definition
        .split(RegExp(r'[•\n]'))
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    return first;
  }

  List<StrongOccurrence> get _visibles =>
      _occurrences.take(_limite).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final occurrences = await StrongOccurrenceIndex.instance
        .occurrences(widget.strong.strong);
    final repository = LsgsRepository();
    final tokens = <int, List<LsgsToken>>{};
    final preview = occurrences.take(_limite).toList();
    for (var i = 0; i < preview.length; i++) {
      final occ = preview[i];
      final verseTokens =
          await repository.verseTokens(occ.bookIndex, occ.chapter, occ.verse);
      if (verseTokens.isNotEmpty) tokens[i] = verseTokens;
    }
    if (!mounted) return;
    setState(() {
      _occurrences = occurrences;
      _tokens.addAll(tokens);
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bibleTheme = BibleThemeScope.of(context);
    final accent = bibleTheme.accentColor;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: _loaded
            ? SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(theme, accent),
                    const SizedBox(height: 24),
                    _buildSectionTitle(theme, 'Définition brève',
                        Icons.menu_book_rounded, accent),
                    const SizedBox(height: 12),
                    _buildBreveCard(theme, accent),
                    const SizedBox(height: 24),
                    _buildSectionTitle(theme, 'Définition complète',
                        Icons.format_list_bulleted_rounded, accent),
                    const SizedBox(height: 12),
                    _buildCompleteCard(theme, accent),
                    if (widget.strong.etymology != null &&
                        widget.strong.etymology!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle(theme, 'Origine',
                          Icons.hub_outlined, accent),
                      const SizedBox(height: 12),
                      _buildEtymologyCard(theme, accent),
                    ],
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                        theme,
                        'Occurrences du mot (${_occurrences.length})',
                        Icons.format_quote_rounded,
                        accent),
                    const SizedBox(height: 12),
                    if (_occurrences.isEmpty)
                      _buildEmptyOccurrences(theme)
                    else ...[
                      for (final occ in _visibles) ...[
                        _buildOccurrenceCard(theme, occ),
                        const SizedBox(height: 12),
                      ],
                      if (_occurrences.length > _limite) ...[
                        const SizedBox(height: 4),
                        _buildVoirPlusButton(accent),
                      ],
                    ],
                    const SizedBox(height: 30),
                  ],
                ),
              )
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color accent) {
    final strong = widget.strong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(_langue, _langueColor),
              const SizedBox(width: 8),
              if (strong.partOfSpeech != null &&
                  strong.partOfSpeech!.isNotEmpty)
                _Badge(strong.partOfSpeech!, theme.colorScheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strong.lemma != null && strong.lemma!.isNotEmpty
                ? strong.lemma!
                : strong.strong,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strong.transliteration ?? '',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: theme.dividerColor, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Numéro Strong',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(
                    strong.strong,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                  ),
                ],
              ),
              if (strong.pronunciation != null &&
                  strong.pronunciation!.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Prononciation',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text(
                      strong.pronunciation!,
                      style: TextStyle(
                          fontSize: 14, color: theme.colorScheme.onSurface),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBreveCard(ThemeData theme, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: Text(
        _breve,
        style: theme.textTheme.bodyLarge?.copyWith(
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildCompleteCard(ThemeData theme, Color accent) {
    final senses = _senses;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < senses.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    senses[i],
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                ),
              ],
            ),
            if (i < senses.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildEtymologyCard(ThemeData theme, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .25)),
      ),
      child: StrongCodeText(
        text: widget.strong.etymology!,
        style: theme.textTheme.bodyMedium?.copyWith(
          height: 1.6,
          fontStyle: FontStyle.italic,
        ),
        linkBareNumbers: true,
        onStrongTap: _openStrongFiche,
      ),
    );
  }

  /// Resolves a Strong code as written in an etymology to a lexicon key.
  ///
  /// A started code (« H1 » for H0001) is zero-padded from the [StrongCodeText]
  /// format. A bare number (« 5975 ») first carries the letter of the entry
  /// being read — an etymology in French refers to the lexicon of its own
  /// language — then, when that code does not exist, the other letter (a
  /// Greek entry can point at « 8450 », an Hebrew code).
  Future<String> _resolveStrong(String strong) async {
    if (RegExp(r'^[GH]', caseSensitive: false).hasMatch(strong)) {
      return StrongCodeText.padToFour(strong.toUpperCase());
    }
    final padded = strong.padLeft(4, '0');
    final primary = '${_isGreek ? 'G' : 'H'}$padded';
    final other = '${_isGreek ? 'H' : 'G'}$padded';
    if (await StrongLexicon.instance.contains(primary)) return primary;
    if (await StrongLexicon.instance.contains(other)) return other;
    return primary;
  }

  /// The codes inside an etymology are written unpadded (« H1 » for H0001,
  /// sometimes « 7225 » for H7225): resolve them to a lexicon key before
  /// opening the definition.
  Future<void> _openStrongFiche(String strong) async {
    final definition =
        await StrongLexicon.instance.lookup(await _resolveStrong(strong));
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StrongDetailScreen(
          strong: definition,
          onOpenVerse: widget.onOpenVerse,
        ),
      ),
    );
  }

  Widget _buildEmptyOccurrences(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        'Aucune occurrence dans la LSGS embarquée.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildOccurrenceCard(ThemeData theme, StrongOccurrence occ) {
    final accent = BibleThemeScope.of(context).accentColor;
    return StrongOccurrenceCard(
      occ: occ,
      reference: occ.reference,
      tokens: _tokens[_occurrences.indexOf(occ)] ?? const [],
      highlight: widget.strong.strong,
      accent: accent,
      onTap: widget.onOpenVerse == null
          ? null
          : () => widget.onOpenVerse!(occ.bookIndex, occ.chapter, occ.verse),
    );
  }

  Widget _buildVoirPlusButton(Color accent) {
    final restants = _occurrences.length - _limite;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent.withValues(alpha: .4)),
          backgroundColor: accent.withValues(alpha: .05),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(Icons.menu_book_rounded, color: accent),
        label: Text(
          'Voir plus ($restants autres versets)',
          style: TextStyle(color: accent, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StrongOccurrencesScreen(
              code: widget.strong.strong,
              occurrences: _occurrences,
              onOpenVerse: widget.onOpenVerse,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}