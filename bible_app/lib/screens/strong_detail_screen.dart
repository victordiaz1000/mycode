import 'package:flutter/material.dart';

import '../data/lsgs_repository.dart';
import '../data/strong_lexicon.dart';
import '../data/strong_occurrences.dart';
import '../models/lsgs.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import '../widgets/strong_code_text.dart';
import '../widgets/strong_lemma.dart';
import '../widgets/strong_senses.dart';
import 'strong_occurrences_screen.dart';

/// The Strong fiche (maquette `ecran_detail_fiche_strong.dart`): the word in
/// a header card with its language and part-of-speech, the short and complete
/// definitions, then the verses where the code actually appears in the
/// embedded LSS corpus — the first 5 as a preview, « Voir plus » opening the
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

  bool get _isGreek =>
      widget.strong.language == 'greek' || widget.strong.strong.startsWith('G');

  String get _langue => _isGreek ? 'Grec' : 'Hébreu';

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

  List<StrongOccurrence> get _visibles => _occurrences.take(_limite).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final occurrences = await StrongOccurrenceIndex.instance.occurrences(
      widget.strong.strong,
    );
    final repository = LsgsRepository.strong();
    final tokens = <int, List<LsgsToken>>{};
    final preview = occurrences.take(_limite).toList();
    for (var i = 0; i < preview.length; i++) {
      final occ = preview[i];
      final verseTokens = await repository.verseTokens(
        occ.bookIndex,
        occ.chapter,
        occ.verse,
      );
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
    return FicheTextScope(
      group: DisplayGroup.etude,
      builder: (context, style) => _buildScaffold(context, style),
    );
  }

  Widget _buildScaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        // AppBar transparente : le voile d'accent la rattache au fond sans
        // coûter une ligne de hauteur.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                accent.withValues(alpha: .12),
                accent.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        title: Text(
          'Détail du mot',
          style: premiumText(context, 16, FontWeight.w800, p.textDark),
        ),
        actions: const [FicheDisplayMenuButton(group: DisplayGroup.etude)],
      ),
      body: SafeArea(
        top: false,
        child: _loaded
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, accent),
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      context,
                      'Définition brève',
                      Icons.menu_book_rounded,
                      accent,
                    ),
                    const SizedBox(height: 12),
                    _buildBreveCard(context, accent, style),
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      context,
                      'Définition complète',
                      Icons.format_list_bulleted_rounded,
                      accent,
                    ),
                    const SizedBox(height: 12),
                    _buildCompleteCard(context, accent, style),
                    if (widget.strong.etymology != null &&
                        widget.strong.etymology!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        context,
                        'Origine',
                        Icons.hub_outlined,
                        accent,
                      ),
                      const SizedBox(height: 12),
                      _buildEtymologyCard(context, accent, style),
                    ],
                    if (widget.strong.signification != null &&
                        widget.strong.signification!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        context,
                        'Signification',
                        Icons.lightbulb_outline_rounded,
                        accent,
                      ),
                      const SizedBox(height: 12),
                      _buildSignificationCard(context, accent, style),
                    ],
                    const SizedBox(height: 24),
                    _buildSectionTitle(
                      context,
                      'Occurrences du mot (${_occurrences.length})',
                      Icons.format_quote_rounded,
                      accent,
                    ),
                    const SizedBox(height: 12),
                    if (_occurrences.isEmpty)
                      _buildEmptyOccurrences(context)
                    else ...[
                      for (final occ in _visibles) ...[
                        _buildOccurrenceCard(context, occ),
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
            : const SingleChildScrollView(
                key: Key('strong-detail-loading-skeleton'),
                padding: EdgeInsets.all(20),
                child: LoadingSkeleton(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 210, radius: 20),
                      SizedBox(height: 26),
                      SkeletonBox(width: 175, height: 22),
                      SizedBox(height: 12),
                      SkeletonBox(height: 88, radius: 16),
                      SizedBox(height: 26),
                      SkeletonBox(width: 205, height: 22),
                      SizedBox(height: 12),
                      SkeletonBox(height: 130, radius: 16),
                      SizedBox(height: 26),
                      SkeletonBox(width: 190, height: 22),
                      SizedBox(height: 12),
                      SkeletonBox(height: 92, radius: 14),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color accent) {
    final p = premiumPalette(context);
    final strong = widget.strong;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: premiumSurface(context, radius: 20, depth: 1.2),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Badge(_langue, _isGreek ? p.greek : p.hebrew),
              const SizedBox(width: 8),
              if (strong.partOfSpeech != null &&
                  strong.partOfSpeech!.isNotEmpty)
                _Badge(strong.partOfSpeech!, p.textGrey),
            ],
          ),
          const SizedBox(height: 16),
          StrongLemma(
            lemma: strong.lemma,
            strong: strong.strong,
            language: strong.language,
            // L'en-tête a la place — et le souhait — d'écrire le mot plus
            // grand que la carte d'étude : chaque lettre reste lisible.
            size: 34,
            align: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            strong.transliteration == null
                ? ''
                : _wrapAfterOu(strong.transliteration!),
            textAlign: TextAlign.center,
            style: premiumText(
              context,
              18,
              FontWeight.w500,
              p.textGrey,
              italic: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 20),
          // Filet qui se perd vers les bords plutôt que le trait plein : la
          // carte garde sa ligne de partage sans se couper en deux.
          Container(
            width: double.infinity,
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.textGrey.withValues(alpha: 0),
                  p.textGrey.withValues(alpha: .35),
                  p.textGrey.withValues(alpha: 0),
                ],
                stops: const [0, .5, 1],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Numéro Strong',
                      style: premiumText(
                        context,
                        12,
                        FontWeight.w500,
                        p.textGrey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strong.strong,
                      style: premiumText(context, 16, FontWeight.w800, accent),
                    ),
                  ],
                ),
              ),
              if (strong.pronunciation != null &&
                  strong.pronunciation!.isNotEmpty)
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Prononciation',
                        style: premiumText(
                          context,
                          12,
                          FontWeight.w500,
                          p.textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strong.pronunciation!,
                        textAlign: TextAlign.end,
                        style: premiumText(
                          context,
                          14,
                          FontWeight.w500,
                          p.textDark,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Les translitérations listeront plusieurs formes séparées par « ou »
  /// (ex. « ’Abiygayil ou raccourci ’Abiygal ») : un espace de césure (U+200B)
  /// après le « ou » permet au texte de passer à la ligne juste après lui au
  /// lieu de déborder de la carte.
  String _wrapAfterOu(String text) =>
      text.replaceAllMapped(RegExp(r' ou(?= |\()'), (m) => ' ou\u200B');

  Widget _buildBreveCard(BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .30)),
        boxShadow: premiumShadow(
          accent,
          opacity: 0.10,
          blur: 14,
          offset: const Offset(0, 5),
        ),
      ),
      child: Text(
        _breve,
        textAlign: style.align,
        style: premiumText(
          context,
          style.fontSize,
          FontWeight.w500,
          p.textDark,
          height: 1.5,
          italic: FontStyle.italic,
        ).copyWith(fontFamily: style.fontFamily),
      ),
    );
  }

  Widget _buildCompleteCard(
      BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    // The source's own outline when it numbers its senses, the flat bullets
    // when it does not: the same card either way, one level deeper or not.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: premiumSurface(context, radius: 16),
      child: StrongSenses(
        outline: widget.strong.outline,
        senses: _senses,
        accent: accent,
        textStyle: premiumText(
          context,
          style.fontSize,
          FontWeight.w500,
          p.textDark,
          height: 1.6,
        ).copyWith(fontFamily: style.fontFamily),
        markerStyle: premiumText(
          context,
          style.fontSize,
          FontWeight.w700,
          accent,
          height: 1.6,
        ).copyWith(fontFamily: style.fontFamily),
        align: style.align,
        rowGap: 16,
      ),
    );
  }

  Widget _buildEtymologyCard(
      BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: .30)),
        boxShadow: premiumShadow(
          accent,
          opacity: 0.10,
          blur: 14,
          offset: const Offset(0, 5),
        ),
      ),
      child: StrongCodeText(
        text: widget.strong.etymology!,
        style: premiumText(
          context,
          style.fontSize,
          FontWeight.w500,
          p.textDark,
          height: 1.6,
          italic: FontStyle.italic,
        ).copyWith(fontFamily: style.fontFamily),
        linkBareNumbers: true,
        onStrongTap: _openStrongFiche,
      ),
    );
  }

  /// The gloss the source writes before its list of senses (« Paul ou Paulus
  /// = petit »), shown apart from them: it names the word, the senses list
  /// its uses. An explicit code in it stays tappable — the line often
  /// points at the root (« Vient de H168 »).
  Widget _buildSignificationCard(
      BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: premiumSurface(context, radius: 16),
      child: StrongCodeText(
        text: widget.strong.signification!,
        style: premiumText(
          context,
          style.fontSize,
          FontWeight.w600,
          p.textDark,
          height: 1.6,
        ).copyWith(fontFamily: style.fontFamily),
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
    final definition = await StrongLexicon.instance.lookup(
      await _resolveStrong(strong),
    );
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

  Widget _buildEmptyOccurrences(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: premiumSurface(context, radius: 14),
      child: Text(
        'Aucune occurrence dans la LSS embarquée.',
        style: premiumText(
          context,
          13,
          FontWeight.w500,
          p.textGrey,
          italic: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildOccurrenceCard(BuildContext context, StrongOccurrence occ) {
    final p = premiumPalette(context);
    return StrongOccurrenceCard(
      occ: occ,
      reference: occ.reference,
      tokens: _tokens[_occurrences.indexOf(occ)] ?? const [],
      highlight: widget.strong.strong,
      accent: p.primary,
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        icon: Icon(Icons.menu_book_rounded, color: accent),
        label: Text(
          'Voir plus ($restants autres versets)',
          style: premiumText(context, 15, FontWeight.w600, accent),
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

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
  ) {
    final p = premiumPalette(context);
    return Row(
      children: [
        // L'icône de section prend la même pastille que sur les fiches de
        // dictionnaire : les deux familles de fiche se lisent d'un seul œil.
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: color),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: premiumText(context, 18, FontWeight.w800, p.textDark),
          ),
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
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Text(
        text,
        style: premiumText(context, 12, FontWeight.w700, color),
      ),
    );
  }
}
