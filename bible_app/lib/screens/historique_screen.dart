import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/reading_history.dart';
import '../data/reference_parser.dart';
import '../utils/date_format.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';

/// Historique complet des lectures (bouton « Tout voir » de l'Accueil).
///
/// Liste toutes les entrées de l'historique, de la plus récente à la plus
/// ancienne, filtrables par section (puces) et par nom de livre (champ de
/// recherche insensible aux accents). Le tap d'une carte rouvre le chapitre
/// dans la lecture — ou rien si [onOpenReading] est nul (écran isolé, tests).
///
/// [history] est injectable pour les tests (même couture que les autres
/// écrans) ; par défaut il lit `shared_preferences`, qui répond sous
/// `testWidgets` (pas de `dart:io` ni de canal de plateforme).
class HistoriqueScreen extends StatefulWidget {
  final void Function(int bookIndex, int chapter)? onOpenReading;
  final ReadingHistory? history;

  const HistoriqueScreen({super.key, this.onOpenReading, this.history});

  @override
  State<HistoriqueScreen> createState() => _HistoriqueScreenState();
}

class _HistoriqueScreenState extends State<HistoriqueScreen> {
  late final ReadingHistory _history = widget.history ?? ReadingHistory();

  List<ReadingEntry> _entries = const [];
  bool _loading = true;
  String _filtre = 'Tous';
  String _requete = '';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
    _load();
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChange);
    _searchFocus.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchFocusChange() {
    if (mounted && _searchFocused != _searchFocus.hasFocus) {
      setState(() => _searchFocused = _searchFocus.hasFocus);
    }
  }

  Future<void> _load() async {
    final entries = await _history.load();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  /// Les entrées, filtrées par section puis par nom de livre (recherche
  /// insensible aux accents, comme la recherche plein texte).
  List<ReadingEntry> get _filtered {
    var list = _entries;
    if (_filtre != 'Tous') {
      list = list
          .where((e) => sectionForBook(e.bookIndex).name == _filtre)
          .toList();
    }
    final q = normalizeForSearch(_requete);
    if (q.isNotEmpty) {
      list = list.where((e) {
        final name = normalizeForSearch(e.bookName);
        return name.contains(q) || normalizeForSearch(e.label).contains(q);
      }).toList();
    }
    return list;
  }

  void _open(ReadingEntry e) {
    widget.onOpenReading?.call(e.bookIndex, e.chapter);
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        // AppBar transparente : un voile d'accent l'ancre au fond, comme sur
        // Favoris, Notes et la Bibliothèque.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                p.primary.withValues(alpha: .12),
                p.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        title: Text(
          'Historique',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: _loading
              ? const Center(child: ListLoadingSkeleton())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchField(context),
                    const SizedBox(height: 12),
                    _buildSectionChips(context),
                    const SizedBox(height: 12),
                    _SectionLabel(
                      '${filtered.length} lecture${filtered.length > 1 ? 's' : ''}',
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEtatVide(context)
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) =>
                                  _buildCarte(context, filtered[i]),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // --- Champ de recherche ---
  Widget _buildSearchField(BuildContext context) {
    final p = premiumPalette(context);
    // Même protocole que la barre de Notes : au repos le voile se pose sans
    // faire de bruit, au focus il s'allume — liseré qui durcit, halo d'accent,
    // icône qui prend la couleur de l'accent. Le liseré reste **neutre** dans
    // les deux états : l'accent ne borde pas une surface (règle 2), il la
    // marque ici par le halo et l'icône.
    final actif = _searchFocused;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: actif
          ? premiumSurface(context, radius: 20, depth: 0.9).copyWith(
              border: Border.all(
                color: premiumCardBorder(context, opacity: .55),
                width: 1.4,
              ),
              boxShadow: [
                ...premiumShadow(
                  p.primaryDark,
                  opacity: .10,
                  blur: 22,
                  offset: const Offset(0, 9),
                ),
                ...premiumShadow(
                  p.primary,
                  opacity: .26,
                  blur: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            )
          : premiumSurface(context, radius: 20, depth: 0.35),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (value) => setState(() => _requete = value),
        style: premiumText(context, 14, FontWeight.w500, p.textDark),
        decoration: InputDecoration(
          hintText: 'Rechercher un livre…',
          hintStyle: premiumText(context, 14, FontWeight.w500, p.textGrey),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: actif ? p.primary : p.textGrey,
          ),
          suffixIcon: _requete.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Effacer',
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _requete = '');
                  },
                ),
          // Le thème global (main.dart) pose `filled: true` + `panelColor` :
          // sans ce drapeau l'`InputDecorator` hérite de la valeur et peint un
          // fond **carré** par-dessus le voile arrondi de l'`AnimatedContainer`
          // — « deux bordures, une ronde et une carrée », les coins du carré
          // dépassant là où le rond a été rogné.
          filled: false,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  // --- Puces de section ---
  Widget _buildSectionChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChip(context, 'Tous'),
        for (final section in bibleSections) _buildChip(context, section.name),
      ],
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final p = premiumPalette(context);
    final actif = _filtre == label;
    return GestureDetector(
      onTap: () => setState(() => _filtre = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? null : p.surfaceAlt,
          gradient: actif ? p.heroGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif
                ? Colors.transparent
                : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: actif
              ? premiumShadow(
                  p.primary,
                  opacity: 0.3,
                  blur: 12,
                  offset: const Offset(0, 5),
                )
              : null,
        ),
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            actif ? p.onPrimary : p.textDark,
          ),
        ),
      ),
    );
  }

  // --- État vide ---
  //
  // Centré quand la place le permet, défilable quand elle manque. Le bloc fait
  // ~143 px à police agrandie (icône 56 + titre + phrase sur deux lignes) : en
  // paysage 360 px de haut, ce qui reste sous le champ de recherche et les
  // puces descend sous cette hauteur, et la `Column` débordait alors de 114 px.
  //
  // `minHeight: maxHeight` dans un `SingleChildScrollView` est la recette qui
  // tient les deux cas : hauteur libre → le `Center` reçoit au moins tout le
  // viewport et centre ; hauteur trop courte → le contenu garde sa taille
  // naturelle et défile au lieu de rogner.
  Widget _buildEtatVide(BuildContext context) {
    final p = premiumPalette(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 56,
                  color: p.textGrey.withValues(alpha: .4),
                ),
                const SizedBox(height: 12),
                Text(
                  _entries.isEmpty
                      ? 'Aucune lecture pour le moment'
                      : 'Aucun résultat',
                  style: premiumText(context, 16, FontWeight.w800, p.textDark),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    _entries.isEmpty
                        ? 'Les chapitres que vous ouvrez dans la lecture apparaîtront ici.'
                        : 'Aucune lecture ne correspond à ce filtre.',
                    style: premiumText(
                      context,
                      13,
                      FontWeight.w500,
                      p.textGrey,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Carte de lecture ---
  Widget _buildCarte(BuildContext context, ReadingEntry e) {
    final p = premiumPalette(context);
    // Coquille sans forme côté Material : la lisière [premiumCardBorder] et les
    // deux ombres sont peintes par l'`Ink`, qu'un Material « façonné »
    // rognerait au contour arrondi. Le fond n'était pas non plus un aplat — le
    // même `p.surface` porté à la fois par le Material et par l'`Ink`, sans
    // liseré : il passe au voile `premiumSurface`, comme les cartes de Favoris
    // et de Notes.
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: premiumSurface(context, radius: 20, depth: 0.9),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onOpenReading == null ? null : () => _open(e),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: p.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: p.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e.bookName} ${e.chapter}',
                        style: premiumText(
                          context,
                          15.5,
                          FontWeight.w700,
                          p.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Lecture · ${formatRelativeDate(e.dateTime)}',
                        style: premiumText(
                          context,
                          12.5,
                          FontWeight.w500,
                          p.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: p.textGrey.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Intertitre de section : un filet d'accent, puis le libellé exact tel quel.
/// Même façonnage que `_SectionLabel` (Favoris, Notes, Thèmes) et
/// `_SectionBadge` (Réglages) : « 3 lectures » se lit comme un intertitre,
/// pas comme une ligne de liste.
class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Row(
      children: [
        Container(
          width: 4,
          height: 13,
          decoration: BoxDecoration(
            color: p.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: premiumText(
              context,
              11,
              FontWeight.w800,
              p.textGrey,
              spacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}
