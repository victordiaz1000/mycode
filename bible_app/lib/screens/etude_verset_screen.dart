import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/fredaw_lexicon.dart';
import '../data/lsgs_repository.dart';
import '../data/strong_lexicon.dart';
import '../models/lsgs.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import 'fredaw_entry_screen.dart';
import 'strong_detail_screen.dart';

/// Mode actif de l'écran d'étude d'un verset : lexique Strong (hébreu/grec) ou
/// dictionnaire (Westphal 1932).
enum ModeEtude { lexique, dictionnaire }

/// Entrée de la bibliothèque du mode LEXIQUE : le mot du verset et la fiche
/// Strong qui lui est associée.
class EntreeLexique {
  final String texte;
  final String translit;
  final String prononciation;
  final String original;
  final String strongId;
  final List<String> definitions;
  final StrongDefinition fiche;

  const EntreeLexique({
    required this.texte,
    required this.translit,
    required this.prononciation,
    required this.original,
    required this.strongId,
    required this.definitions,
    required this.fiche,
  });
}

/// Entrée de la bibliothèque du mode DICTIONNAIRE : le terme repéré dans le
/// verset et l'article Westphal qui le définit.
class EntreeDico {
  final String texte;
  final String titre;
  final String section;
  final String extrait;
  final FreDawEntry fiche;

  const EntreeDico({
    required this.texte,
    required this.titre,
    required this.section,
    required this.extrait,
    required this.fiche,
  });
}

/// Un morceau du verset : du texte simple, ou un mot cliquable qui renvoie à
/// l'entrée [entreeIndex] de la bibliothèque active.
class SegmentVerset {
  final String texte;
  final int? entreeIndex;

  const SegmentVerset.plain(this.texte) : entreeIndex = null;
  const SegmentVerset.mot(this.texte, this.entreeIndex);
}

/// Écran combiné « Lexique & Dictionnaire » du verset courant (maquette
/// `ecran_cliquable_verset_mot_a_mot_mod_lexique&dictionnaire.dart`).
///
/// Le verset est rendu mot à mot, cliquable dans les deux modes :
/// - **Lexique** : les mots porteurs d'un numéro Strong ouvrent la fiche
///   Strong française (hébreu/grec) ; les cartes sont swipables.
/// - **Dictionnaire** : les mots qui sont des articles du dictionnaire
///   (Westphal 1932, `FredawLexicon.linkPattern`) ouvrent un aperçu de
///   l'article, avec accès à la fiche complète.
///
/// Au goût premium : fond crème, cartes blanches à ombre douce, accents du
/// thème actif.
class EtudeVersetScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;
  final int verseNumber;
  final List<LsgsToken> tokens;

  /// Fiche Strong à présélectionner à l'ouverture (code, ex. « H7225 »).
  final String? initialStrong;

  /// Les numéros des versets du chapitre courant, dans l'ordre — rend la
  /// navigation « Verset précédent / suivant » possible. Null hors coquille
  /// (tests) : la rangée de navigation est alors masquée.
  final List<int>? verseNumbers;

  /// Charge les tokens d'un autre verset du même chapitre, pour la navigation
  /// précédent / suivant. Null hors coquille : navigation masquée.
  final Future<List<LsgsToken>> Function(int verseNumber)? loadVerseTokens;

  /// Ouvre un verset d'occurrence choisi dans une fiche Strong complète : la
  /// coquille cible ce verset dans l'écran lecture. Null hors coquille : les
  /// occurrences de la fiche restent en lecture seule.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  const EtudeVersetScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.tokens,
    this.initialStrong,
    this.verseNumbers,
    this.loadVerseTokens,
    this.onOpenVerse,
  });

  @override
  State<EtudeVersetScreen> createState() => _EtudeVersetScreenState();
}

class _EtudeVersetScreenState extends State<EtudeVersetScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.9);
  ModeEtude _mode = ModeEtude.lexique;
  int _entreeCourante = 0;

  late int _verseNumber;
  late List<LsgsToken> _tokens;

  List<SegmentVerset> _segmentsLexique = const [];
  List<EntreeLexique> _entreesLexique = const [];
  bool _lexiqueReady = false;

  List<SegmentVerset> _segmentsDico = const [];
  List<EntreeDico> _entreesDico = const [];
  bool _dicoReady = false;

  bool get _hasNav =>
      widget.verseNumbers != null && widget.loadVerseTokens != null;

  List<SegmentVerset> get _segments =>
      _mode == ModeEtude.lexique ? _segmentsLexique : _segmentsDico;

  int get _nbEntrees =>
      _mode == ModeEtude.lexique ? _entreesLexique.length : _entreesDico.length;

  @override
  void initState() {
    super.initState();
    _verseNumber = widget.verseNumber;
    _tokens = widget.tokens;
    _buildLexique();
    _buildDico();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Construit la bibliothèque et les segments du mode LEXIQUE depuis les
  /// tokens du verset : chaque numéro Strong devient un mot cliquable relié à
  /// sa fiche (une fiche par code, les répétitions partagent la même entrée).
  Future<void> _buildLexique() async {
    final entries = <EntreeLexique>[];
    final segments = <SegmentVerset>[];
    final indexByStrong = <String, int>{};
    for (final token in _tokens) {
      final strong = token.strong;
      if (strong == null || strong.isEmpty) {
        segments.add(SegmentVerset.plain(token.text));
        continue;
      }
      var index = indexByStrong[strong];
      if (index == null) {
        final definition = await StrongLexicon.instance.lookup(strong);
        index = entries.length;
        indexByStrong[strong] = index;
        entries.add(
          EntreeLexique(
            texte: token.text.trim(),
            translit: definition.transliteration ?? '',
            prononciation: definition.pronunciation ?? '',
            original: definition.lemma ?? '',
            strongId: definition.strong,
            definitions: definition.senses.isNotEmpty
                ? definition.senses
                : [definition.definition],
            fiche: definition,
          ),
        );
      }
      segments.add(SegmentVerset.mot(token.text.trim(), index));
    }
    if (!mounted) return;
    setState(() {
      _entreesLexique = entries;
      _segmentsLexique = segments;
      _lexiqueReady = true;
    });
    final initial = widget.initialStrong;
    if (initial != null && indexByStrong.containsKey(initial)) {
      _selectEntree(indexByStrong[initial]!, scroll: false);
    }
  }

  /// Construit la bibliothèque et les segments du mode DICTIONNAIRE : le texte
  /// nu du verset est découpé sur les termes que le dictionnaire connaît
  /// ([FreDawLexicon.linkPattern]), chaque terme devenant un mot cliquable.
  Future<void> _buildDico() async {
    final plain = LsgsRepository.joinTokens(_tokens);
    final pattern = await FreDawLexicon.instance.linkPattern();
    if (!mounted) return;
    final entries = <EntreeDico>[];
    final segments = <SegmentVerset>[];
    if (pattern == null) {
      segments.add(SegmentVerset.plain(plain));
    } else {
      var cursor = 0;
      for (final match in pattern.allMatches(plain)) {
        if (match.start > cursor) {
          segments.add(
            SegmentVerset.plain(plain.substring(cursor, match.start)),
          );
        }
        final term = match.group(0)!;
        final entry = await FreDawLexicon.instance.lookup(term);
        if (!mounted) return;
        final index = entries.length;
        entries.add(_dicoEntry(term, entry));
        segments.add(SegmentVerset.mot(term, index));
        cursor = match.end;
      }
      if (cursor < plain.length) {
        segments.add(SegmentVerset.plain(plain.substring(cursor)));
      }
    }
    if (!mounted) return;
    setState(() {
      _entreesDico = entries;
      _segmentsDico = segments;
      _dicoReady = true;
    });
  }

  /// Découpe la définition Westphal : le premier paragraphe fait office de
  /// section (« 1. Introduction. »), le reste est l'extrait défilable.
  EntreeDico _dicoEntry(String term, FreDawEntry entry) {
    final paragraphs = entry.definition
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final section = paragraphs.length > 1 ? paragraphs.first : '';
    final extrait = paragraphs.length > 1
        ? paragraphs.skip(1).join('\n\n')
        : entry.definition;
    return EntreeDico(
      texte: term,
      titre: entry.term,
      section: section,
      extrait: extrait,
      fiche: entry,
    );
  }

  void _changerMode(ModeEtude m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _entreeCourante = 0;
    });
    // revient à la première carte après le changement de mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
  }

  void _selectEntree(int index, {bool scroll = true}) {
    setState(() => _entreeCourante = index);
    if (scroll && _pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Navigation « Verset précédent / suivant » dans le chapitre courant.
  Future<void> _navigateTo(int verseNumber) async {
    final loader = widget.loadVerseTokens;
    if (loader == null || verseNumber == _verseNumber) return;
    final tokens = await loader(verseNumber);
    if (!mounted) return;
    setState(() {
      _verseNumber = verseNumber;
      _tokens = tokens;
      _entreeCourante = 0;
      _lexiqueReady = false;
      _dicoReady = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
    _buildLexique();
    _buildDico();
  }

  int get _verseIndex {
    final numbers = widget.verseNumbers;
    if (numbers == null) return 0;
    return numbers.indexOf(_verseNumber);
  }

  void _stubSnack(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label — bientôt disponible.')));
  }

  @override
  Widget build(BuildContext context) {
    return FicheTextScope(
      group: DisplayGroup.etude,
      builder: (context, style) => _scaffold(context, style),
    );
  }

  Widget _scaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    final entry = catalogEntry(widget.bookIndex);
    final reference = '${entry.shortName} ${widget.chapter}:$_verseNumber';

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: const [FicheDisplayMenuButton(group: DisplayGroup.etude)],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              reference,
              style: premiumText(context, 17, FontWeight.w800, p.textDark),
            ),
            Text(
              _mode == ModeEtude.lexique
                  ? 'Lexique hébreu & grec'
                  : 'Dictionnaire',
              style: premiumText(context, 12, FontWeight.w500, p.textGrey),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomBar(context, accent),
      ),
      // Les boutons Android empilés à droite en paysage vivent dans
      // `MediaQuery.padding` : sans ce `SafeArea`, le corps file jusqu'au bord
      // de l'écran et passe dessous. L'`AppBar` les applique déjà — d'où le
      // titre toujours visible quand le contenu, lui, disparaissait.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // ============ 1. CARTE DU VERSET ============
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: premiumShadow(
                    p.primaryDark,
                    opacity: 0.04,
                    blur: 12,
                    offset: const Offset(0, 6),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '$_verseNumber',
                            style: premiumText(
                              context,
                              12,
                              FontWeight.w500,
                              p.textGrey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildVersetRich(context, accent, style),
                        ),
                      ],
                    ),
                    if (_hasNav) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_verseIndex > 0)
                            _buildNavVerset(
                              context,
                              'Verset précédent',
                              Icons.arrow_circle_left_outlined,
                              false,
                              accent,
                            ),
                          const Spacer(),
                          if (_verseIndex < (widget.verseNumbers!.length - 1))
                            _buildNavVerset(
                              context,
                              'Verset suivant',
                              Icons.arrow_circle_right_outlined,
                              true,
                              accent,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ============ 2. CARTES SWIPABLES (selon le mode) ============
              _buildCardsArea(context, accent, style),
            ],
          ),
        ),
      ),
    );
  }

  // --- Verset fluide avec mots cliquables (selon le mode) ---
  Widget _buildVersetRich(
    BuildContext context,
    Color accent,
    FicheTextStyle style,
  ) {
    final p = premiumPalette(context);
    return Text.rich(
      textAlign: style.align,
      TextSpan(
        children: [
          for (final s in _segments)
            if (s.entreeIndex == null)
              TextSpan(
                text: s.texte,
                style: premiumText(
                  context,
                  style.fontSize,
                  FontWeight.w500,
                  p.textDark,
                  height: 2.0,
                ).copyWith(fontFamily: style.fontFamily),
              )
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: () => _selectEntree(s.entreeIndex!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _entreeCourante == s.entreeIndex
                          ? accent
                          : accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.texte,
                      style: premiumText(
                        context,
                        style.fontSize,
                        FontWeight.w700,
                        _entreeCourante == s.entreeIndex
                            ? p.onPrimary
                            : p.textDark,
                      ).copyWith(fontFamily: style.fontFamily),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildNavVerset(
    BuildContext context,
    String label,
    IconData icon,
    bool droite,
    Color accent,
  ) {
    final p = premiumPalette(context);
    return GestureDetector(
      onTap: () =>
          _navigateTo(widget.verseNumbers![_verseIndex + (droite ? 1 : -1)]),
      child: Row(
        children: [
          if (!droite) ...[Icon(icon, color: accent), const SizedBox(width: 6)],
          Text(
            label,
            style: premiumText(context, 14, FontWeight.w600, p.textGrey),
          ),
          if (droite) ...[const SizedBox(width: 6), Icon(icon, color: accent)],
        ],
      ),
    );
  }

  // --- Carte du mode LEXIQUE ---
  Widget _buildCarteLexique(BuildContext context, EntreeLexique e, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.05,
          blur: 10,
          offset: const Offset(0, 4),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: e.translit,
                          style: premiumText(
                            context,
                            18,
                            FontWeight.w800,
                            accent,
                          ),
                        ),
                        TextSpan(
                          text: ' ${e.prononciation}',
                          style: premiumText(
                            context,
                            14,
                            FontWeight.w500,
                            p.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fiche Strong complète',
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: accent,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StrongDetailScreen(
                        strong: e.fiche,
                        onOpenVerse: widget.onOpenVerse,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: e.fiche.language == 'hebrew'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Text(
                e.original,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: p.textDark,
                  fontFamily: 'serif',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(width: 40, height: 3, color: accent),
            const SizedBox(height: 14),
            Text(
              'Définition - ${e.strongId}',
              style: premiumText(context, 14, FontWeight.w500, p.textGrey),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < e.definitions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${i + 1}) ${e.definitions[i]}',
                  textAlign: style.align,
                  style: premiumText(
                    context,
                    style.fontSize,
                    FontWeight.w500,
                    p.textDark,
                    height: 1.5,
                  ).copyWith(fontFamily: style.fontFamily),
                ),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StrongDetailScreen(
                      strong: e.fiche,
                      onOpenVerse: widget.onOpenVerse,
                    ),
                  ),
                ),
                child: Text(
                  'Ouvrir la fiche Strong complète →',
                  style: premiumText(context, 14, FontWeight.w700, accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Carte du mode DICTIONNAIRE ---
  Widget _buildCarteDico(BuildContext context, EntreeDico e, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.05,
          blur: 10,
          offset: const Offset(0, 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.titre,
                  style: premiumText(context, 22, FontWeight.w800, p.textDark),
                ),
              ),
              IconButton(
                tooltip: 'Fiche complète du dictionnaire',
                icon: Icon(Icons.open_in_full_rounded, color: accent, size: 18),
                onPressed: () => _openFicheComplett(e),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(width: 40, height: 3, color: accent),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.section.isNotEmpty) ...[
                    Text(
                      e.section,
                      style: premiumText(
                        context,
                        15,
                        FontWeight.w700,
                        p.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    e.extrait,
                    textAlign: style.align,
                    style: premiumText(
                      context,
                      style.fontSize,
                      FontWeight.w500,
                      p.textDark,
                      height: 1.7,
                    ).copyWith(fontFamily: style.fontFamily),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _openFicheComplett(e),
            child: Text(
              'Ouvrir la fiche complète →',
              style: premiumText(context, 14, FontWeight.w700, accent),
            ),
          ),
        ],
      ),
    );
  }

  void _openFicheComplett(EntreeDico e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FredawEntryScreen(
          entry: e.fiche,
          // Le callback de l'écran d'étude (fourni par le lecteur) vide déjà
          // la pile de fiches avant le saut lecture : on le transmet tel quel.
          onOpenVerse: widget.onOpenVerse,
        ),
      ),
    );
  }

  // --- Zone des cartes swipables ---
  Widget _buildCardsArea(BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    final ready = _mode == ModeEtude.lexique ? _lexiqueReady : _dicoReady;
    if (!ready) {
      return const SizedBox(
        key: Key('lexique-loading-skeleton'),
        height: 430,
        child: LoadingSkeleton(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 190, height: 22),
                SizedBox(height: 20),
                SkeletonBox(width: 118, height: 34),
                SizedBox(height: 20),
                SkeletonBox(width: 150, height: 14),
                SizedBox(height: 14),
                SkeletonBox(height: 15),
                SizedBox(height: 10),
                SkeletonBox(height: 15),
                SizedBox(height: 10),
                SkeletonBox(width: 210, height: 15),
                SizedBox(height: 26),
                SkeletonBox(width: 165, height: 14),
                SizedBox(height: 14),
                SkeletonBox(height: 15),
              ],
            ),
          ),
        ),
      );
    }
    if (_nbEntrees == 0) {
      final message = _mode == ModeEtude.lexique
          ? 'Ce verset ne contient aucun mot associé à un numéro Strong.'
          : 'Aucun terme de ce verset ne figure dans le dictionnaire.';
      return SizedBox(
        height: 430,
        child: Center(
          child: Card(
            elevation: 0,
            color: p.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: premiumShadow(
                  p.primaryDark,
                  opacity: 0.05,
                  blur: 10,
                  offset: const Offset(0, 4),
                ),
              ),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  14,
                  FontWeight.w500,
                  p.textGrey,
                  italic: FontStyle.italic,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 430,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (i) => _selectEntree(i, scroll: false),
        itemCount: _nbEntrees,
        itemBuilder: (context, i) => _mode == ModeEtude.lexique
            ? _buildCarteLexique(context, _entreesLexique[i], style)
            : _buildCarteDico(context, _entreesDico[i], style),
      ),
    );
  }

  // --- Barre du bas : bascule Lexique / Dictionnaire ---
  Widget _buildBottomBar(BuildContext context, Color accent) {
    final p = premiumPalette(context);
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.08,
          blur: 12,
          offset: const Offset(0, 4),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            'Lexique',
            Icons.translate_rounded,
            _mode == ModeEtude.lexique,
            () => _changerMode(ModeEtude.lexique),
            accent,
          ),
          _buildNavItem(
            'Dictionnaire',
            Icons.menu_book_rounded,
            _mode == ModeEtude.dictionnaire,
            () => _changerMode(ModeEtude.dictionnaire),
            accent,
          ),
          _buildNavItem(
            'Thèmes',
            Icons.category_outlined,
            false,
            () => _stubSnack('Thèmes'),
            accent,
          ),
          _buildNavItem(
            'Références',
            Icons.list_alt_rounded,
            false,
            () => _stubSnack('Références'),
            accent,
          ),
          _buildNavItem(
            'Comment.',
            Icons.chat_bubble_outline_rounded,
            false,
            () => _stubSnack('Commentaires'),
            accent,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    String label,
    IconData icon,
    bool actif,
    VoidCallback onTap,
    Color accent,
  ) {
    final p = premiumPalette(context);
    final iconsOnly = MediaQuery.sizeOf(context).width < 360;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: label,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: iconsOnly ? 5 : 0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: iconsOnly ? 24 : 22,
                  color: actif ? accent : p.textGrey,
                ),
                if (!iconsOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w600,
                      actif ? accent : p.textGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
