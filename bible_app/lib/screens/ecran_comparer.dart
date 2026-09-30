import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../models/verse.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';

/// Une traduction du verset comparé : le texte qu'une version donne pour cette
/// référence.
class VersionBible {
  final String code; // BYM, LSG, DBY…
  final String nom; // nom complet
  final String langue; // FR, EN…
  final String texte;

  const VersionBible({
    required this.code,
    required this.nom,
    required this.langue,
    required this.texte,
  });
}

/// Écran « Comparer » (maquette `interfaces/ecran_comparer.dart`) : le verset
/// courant est affiché dans chaque version présente sur l'appareil — BYM et
/// LSGS embarquées, puis les versions téléchargées qui détiennent ce livre.
///
/// Chaque version est une carte ; des pastilles permettent d'afficher ou de
/// masquer une traduction.
class ComparerScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;
  final int verseNumber;

  /// Où lire les versions téléchargées. Injectable pour les tests (même couture
  /// que `ChapterReader.store`).
  final LibraryStore? store;

  const ComparerScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    this.store,
  });

  @override
  State<ComparerScreen> createState() => _ComparerScreenState();
}

class _ComparerScreenState extends State<ComparerScreen> {
  late final LibraryStore _store = widget.store ?? LibraryStore();
  late final VersionRepository _versions = VersionRepository(store: _store);

  /// Versions actuellement affichées (par code).
  final Set<String> _actives = {};

  List<VersionBible> _versionsDisponibles = const [];
  bool _loading = true;

  /// Reading preferences, for the size and family of the compared verses: this
  /// is a reading surface, so « Taille du texte » must reach it. Null until the
  /// first frame after [initState]; the fallbacks below are the enum defaults.
  AppPreferences? _prefs;

  /// Point size of a compared verse. The cards stack vertically, so they read
  /// one notch below the reader itself — the ratio is set so the default step
  /// (22 pt) lands on the 15 pt this screen has always used.
  double get _verseFontSize =>
      ReadingTextSize.nearest(_prefs?.fontSize ?? ReadingTextSize.extraLarge.fontSize)
          .fontSize *
      .68;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await AppPreferences.load();
    final versions = await _buildVersions();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _versionsDisponibles = versions;
      _actives
        ..clear()
        ..addAll([for (final v in versions) v.code]);
      _loading = false;
    });
  }

  /// Rassemble le verset dans chaque version qui peut le servir, dans l'ordre
  /// du catalogue : BYM et LSGS embarquées d'abord, puis les téléchargées.
  Future<List<VersionBible>> _buildVersions() async {
    final codes = <String>[
      VersionRepository.embeddedCode,
      VersionRepository.lsgsCode,
    ];
    final installed = await _store.installed();
    for (final entry in installed.entries) {
      if (entry.key == VersionRepository.embeddedCode ||
          entry.key == VersionRepository.lsgsCode) {
        continue;
      }
      if (entry.value.has(widget.bookIndex)) codes.add(entry.key);
    }

    final result = <VersionBible>[];
    for (final code in codes) {
      final verse = await _verseIn(code);
      if (verse == null || verse.text.trim().isEmpty) continue;
      final entry = versionByCode(code);
      result.add(
        VersionBible(
          code: code,
          nom: entry?.name ?? code,
          langue: _langueFor(code),
          texte: verse.text.trim(),
        ),
      );
    }
    return result;
  }

  /// Le verset demandé dans [code], ou null si la version ne l'a pas
  /// ([BookNotDownloaded], livre absent, verset absent).
  Future<Verse?> _verseIn(String code) async {
    try {
      final chapter = await _versions.loadChapter(
        code,
        widget.bookIndex,
        widget.chapter,
      );
      for (final verse in chapter.verses) {
        if (verse.number == widget.verseNumber) return verse;
      }
    } catch (_) {
      // Livre non téléchargé dans cette version : la version est simplement
      // sautée, elle n'a rien à comparer.
    }
    return null;
  }

  /// Langue de la version, portée par le catalogue (`languageCode`) : une
  /// deuxième version anglaise n'exigerait aucun changement ici.
  String _langueFor(String code) => versionByCode(code)?.languageCode ?? 'FR';

  String get _reference =>
      '${catalogEntry(widget.bookIndex).shortName} '
      '${widget.chapter}:${widget.verseNumber}';

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final affichees = _versionsDisponibles
        .where((v) => _actives.contains(v.code))
        .toList();

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        // AppBar transparente : le voile d'accent du libellé, comme sur les
        // autres écrans poussés depuis l'accueil.
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
          'Comparer',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        child: _loading
            // Squelette façonné comme la page : en-tête de référence,
            // pastilles de versions, puis les cartes empilées.
            ? const CardsLoadingSkeleton()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEnTete(context),
                    const SizedBox(height: 24),
                    _buildSelection(context, affichees),
                    const SizedBox(height: 16),
                    if (affichees.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Center(
                          child: Text(
                            'Sélectionnez au moins une version à comparer.',
                            style: premiumText(
                              context,
                              14,
                              FontWeight.w500,
                              p.onSurfaceMuted,
                            ),
                          ),
                        ),
                      ),
                    for (final v in affichees) ...[
                      _buildCarteVersion(context, v),
                      const SizedBox(height: 14),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  // --- 1. EN-TÊTE DU VERSET ---
  Widget _buildEnTete(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20.0),
      decoration: premiumSurface(context, radius: 20, depth: 1.2),
      child: Column(
        children: [
          Text(
            _reference,
            style: premiumText(context, 24, FontWeight.w800, p.textDark),
          ),
          const SizedBox(height: 6),
          Text(
            'Comparez les traductions de ce verset',
            style: premiumText(context, 13, FontWeight.w500, p.textGrey),
          ),
        ],
      ),
    );
  }

  // --- 2. SÉLECTION DES VERSIONS ---
  Widget _buildSelection(BuildContext context, List<VersionBible> affichees) {
    final p = premiumPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Filet d'accent : « Versions affichées » se lit comme un
            // intertitre, comme les sections des autres écrans.
            Container(
              width: 4,
              height: 13,
              decoration: BoxDecoration(
                color: p.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            // `Flexible` et non `Text` nu : un enfant non-flex d'une `Row` est
            // mesuré sous une largeur infinie, donc ce titre ne se replie
            // jamais et sortait de l'écran sur les appareils étroits.
            Flexible(
              child: Text(
                'Versions affichées',
                style: premiumText(
                  context,
                  16,
                  FontWeight.w800,
                  p.textDark,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in _versionsDisponibles) _buildVersionChip(context, v),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${affichees.length} version${affichees.length > 1 ? 's' : ''} '
          'affichée${affichees.length > 1 ? 's' : ''}',
          style: premiumText(context, 13, FontWeight.w500, p.textGrey),
        ),
      ],
    );
  }

  // --- Pastille de version (afficher / masquer) ---
  Widget _buildVersionChip(BuildContext context, VersionBible v) {
    final p = premiumPalette(context);
    final actif = _actives.contains(v.code);
    return GestureDetector(
      onTap: () {
        setState(() {
          actif ? _actives.remove(v.code) : _actives.add(v.code);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          // La pastille active porte l'accent en dégradé (comme les puces de
          // filtre des autres écrans) ; la inactive tombe sur la surface.
          gradient: actif ? p.heroGradient : null,
          color: actif ? null : p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif
                ? Colors.transparent
                : premiumCardBorder(context, opacity: .3),
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
          v.code,
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

  // --- Carte d'une traduction ---
  Widget _buildCarteVersion(BuildContext context, VersionBible v) {
    final p = premiumPalette(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: premiumSurface(context, radius: 16, depth: 0.9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: p.primarySoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  v.code,
                  style: premiumText(context, 12, FontWeight.w800, p.primary),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  v.nom,
                  style: premiumText(
                    context,
                    14,
                    FontWeight.w700,
                    p.textDark,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: premiumCardBorder(context)),
                ),
                child: Text(
                  v.langue,
                  style: premiumText(
                    context,
                    11,
                    FontWeight.w800,
                    p.textGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            v.texte,
            style: TextStyle(
              fontSize: _verseFontSize,
              height: 1.7,
              fontFamily: _prefs?.readingFont.fontFamily,
              fontWeight: _prefs?.fontWeight.weight,
              color: p.onSurface,
            ),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }
}
