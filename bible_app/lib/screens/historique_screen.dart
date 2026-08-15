import 'package:flutter/material.dart';

import '../data/bible_sections.dart';
import '../data/reading_history.dart';
import '../data/reference_parser.dart';
import '../utils/date_format.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      backgroundColor: kPremiumBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Historique',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchField(context),
                    const SizedBox(height: 12),
                    _buildSectionChips(context),
                    const SizedBox(height: 12),
                    Text(
                      '${filtered.length} étude${filtered.length > 1 ? 's' : ''}',
                      style: premiumText(context, 13, FontWeight.w500, p.textGrey),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEtatVide(context)
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 12),
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: premiumShadow(p.primaryDark),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _requete = value),
        style: premiumText(context, 14, FontWeight.w500, p.textDark),
        decoration: InputDecoration(
          hintText: 'Rechercher un livre…',
          hintStyle: premiumText(context, 14, FontWeight.w500, p.textGrey),
          prefixIcon: Icon(Icons.search_rounded, color: p.textGrey),
          suffixIcon: _requete.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _requete = '');
                  },
                ),
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
          color: actif ? null : Colors.white,
          gradient: actif ? p.heroGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? Colors.transparent : Colors.grey.shade300,
          ),
          boxShadow: actif
              ? premiumShadow(p.primary,
                  opacity: 0.3, blur: 12, offset: const Offset(0, 5))
              : null,
        ),
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            actif ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  // --- État vide ---
  Widget _buildEtatVide(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            _entries.isEmpty ? 'Aucune étude pour le moment' : 'Aucun résultat',
            style: premiumText(context, 16, FontWeight.w800, p.textDark),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _entries.isEmpty
                  ? 'Les chapitres que vous ouvrez dans la lecture apparaîtront ici.'
                  : 'Aucune lecture ne correspond à ce filtre.',
              style: premiumText(context, 13, FontWeight.w500, p.textGrey, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // --- Carte de lecture ---
  Widget _buildCarte(BuildContext context, ReadingEntry e) {
    final p = premiumPalette(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(p.primaryDark,
              opacity: 0.07, blur: 16, offset: const Offset(0, 6)),
        ),
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
                  child: Icon(Icons.auto_awesome_rounded, color: p.primary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${e.bookName} ${e.chapter}',
                        style: premiumText(context, 15.5, FontWeight.w700, p.textDark),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Lecture · ${formatRelativeDate(e.dateTime)}',
                        style: premiumText(context, 12.5, FontWeight.w500, p.textGrey),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 22, color: p.textGrey.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}