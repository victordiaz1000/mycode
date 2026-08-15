import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/fredaw_lexicon.dart';
import '../data/lsgs_repository.dart';
import '../data/strong_lexicon.dart';
import '../models/lsgs.dart';
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
  final String traductions;
  final StrongDefinition fiche;

  const EntreeLexique({
    required this.texte,
    required this.translit,
    required this.prononciation,
    required this.original,
    required this.strongId,
    required this.definitions,
    required this.traductions,
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

  const EtudeVersetScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.tokens,
    this.initialStrong,
    this.verseNumbers,
    this.loadVerseTokens,
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

  int get _nbEntrees => _mode == ModeEtude.lexique
      ? _entreesLexique.length
      : _entreesDico.length;

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
        entries.add(EntreeLexique(
          texte: token.text.trim(),
          translit: definition.transliteration ?? '',
          prononciation: definition.pronunciation ?? '',
          original: definition.lemma ?? '',
          strongId: definition.strong,
          definitions:
              definition.senses.isNotEmpty ? definition.senses : [definition.definition],
          traductions: definition.definition,
          fiche: definition,
        ));
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
              SegmentVerset.plain(plain.substring(cursor, match.start)));
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
    final extrait =
        paragraphs.length > 1 ? paragraphs.skip(1).join('\n\n') : entry.definition;
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — bientôt disponible.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final entry = catalogEntry(widget.bookIndex);
    final reference =
        '${entry.shortName} ${widget.chapter}:$_verseNumber';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reference,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                fontFamily: 'Georgia',
                color: theme.colorScheme.onSurface,
              ),
            ),
            Text(
              _mode == ModeEtude.lexique ? 'Lexique hébreu & grec' : 'Dictionnaire',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(top: false, child: _buildBottomBar(theme, accent)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ============ 1. CARTE DU VERSET ============
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
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
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _buildVersetRich(accent)),
                    ],
                  ),
                  if (_hasNav) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (_verseIndex > 0)
                          _buildNavVerset(
                            'Verset précédent',
                            Icons.arrow_circle_left_outlined,
                            false,
                            accent,
                          ),
                        const Spacer(),
                        if (_verseIndex < (widget.verseNumbers!.length - 1))
                          _buildNavVerset(
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
            _buildCardsArea(theme, accent),
          ],
        ),
      ),
    );
  }

  // --- Verset fluide avec mots cliquables (selon le mode) ---
  Widget _buildVersetRich(Color accent) {
    final theme = Theme.of(context);
    return Text.rich(
      TextSpan(
        children: [
          for (final s in _segments)
            if (s.entreeIndex == null)
              TextSpan(
                text: s.texte,
                style: TextStyle(
                  fontSize: 17,
                  height: 2.0,
                  color: theme.colorScheme.onSurface,
                ),
              )
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: GestureDetector(
                  onTap: () => _selectEntree(s.entreeIndex!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: _entreeCourante == s.entreeIndex
                          ? accent
                          : accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.texte,
                      style: TextStyle(
                        fontSize: 17,
                        color: _entreeCourante == s.entreeIndex
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildNavVerset(
      String label, IconData icon, bool droite, Color accent) {
    return GestureDetector(
      onTap: () => _navigateTo(widget.verseNumbers![_verseIndex + (droite ? 1 : -1)]),
      child: Row(
        children: [
          if (!droite) ...[Icon(icon, color: accent), const SizedBox(width: 6)],
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (droite) ...[const SizedBox(width: 6), Icon(icon, color: accent)],
        ],
      ),
    );
  }

  // --- Carte du mode LEXIQUE ---
  Widget _buildCarteLexique(ThemeData theme, EntreeLexique e) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8C6B4F),
                          ),
                        ),
                        TextSpan(
                          text: ' ${e.prononciation}',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fiche Strong complète',
                  icon: const Icon(Icons.open_in_full_rounded,
                      color: Color(0xFF8C6B4F), size: 20),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StrongDetailScreen(strong: e.fiche),
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
                  color: theme.colorScheme.onSurface,
                  fontFamily: 'serif',
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(width: 40, height: 3, color: const Color(0xFF8C6B4F)),
            const SizedBox(height: 14),
            Text(
              'Définition - ${e.strongId}',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < e.definitions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${i + 1}) ${e.definitions[i]}',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'Généralement traduit par',
              style: TextStyle(
                fontSize: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              e.traductions,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StrongDetailScreen(strong: e.fiche),
                  ),
                ),
                child: Text(
                  'Ouvrir la fiche Strong complète →',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8C6B4F),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Carte du mode DICTIONNAIRE ---
  Widget _buildCarteDico(ThemeData theme, EntreeDico e) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.titre,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                    fontFamily: 'Georgia',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Fiche complète du dictionnaire',
                icon: const Icon(Icons.open_in_full_rounded,
                    color: Color(0xFF8C6B4F), size: 18),
                onPressed: () => _openFicheComplett(e),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(width: 40, height: 3, color: const Color(0xFF8C6B4F)),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.section.isNotEmpty) ...[
                    Text(
                      e.section,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    e.extrait,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.7,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _openFicheComplett(e),
            child: const Text(
              'Ouvrir la fiche complète →',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8C6B4F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFicheComplett(EntreeDico e) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FredawEntryScreen(entry: e.fiche),
      ),
    );
  }

  // --- Zone des cartes swipables ---
  Widget _buildCardsArea(ThemeData theme, Color accent) {
    final ready = _mode == ModeEtude.lexique ? _lexiqueReady : _dicoReady;
    if (!ready) {
      return const SizedBox(
        height: 430,
        child: Center(child: CircularProgressIndicator()),
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
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
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
            ? _buildCarteLexique(theme, _entreesLexique[i])
            : _buildCarteDico(theme, _entreesDico[i]),
      ),
    );
  }

  // --- Barre du bas : bascule Lexique / Dictionnaire ---
  Widget _buildBottomBar(ThemeData theme, Color accent) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
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
      String label, IconData icon, bool actif, VoidCallback onTap, Color accent) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 22, color: actif ? accent : Colors.grey.shade400),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: actif ? accent : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}