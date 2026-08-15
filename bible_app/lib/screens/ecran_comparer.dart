import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../models/verse.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final versions = await _buildVersions();
    if (!mounted) return;
    setState(() {
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
      result.add(VersionBible(
        code: code,
        nom: entry?.name ?? code,
        langue: _langueFor(code),
        texte: verse.text.trim(),
      ));
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

  /// Langue de la version — le catalogue ne la porte pas, KJV est la seule
  /// anglaise aujourd'hui.
  String _langueFor(String code) => code == 'KJV' ? 'EN' : 'FR';

  String get _reference =>
      '${catalogEntry(widget.bookIndex).shortName} '
      '${widget.chapter}:${widget.verseNumber}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final affichees =
        _versionsDisponibles.where((v) => _actives.contains(v.code)).toList();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Comparer',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Georgia',
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildEnTete(theme),
                        const SizedBox(height: 24),
                        _buildSelection(theme, affichees),
                        const SizedBox(height: 16),
                        if (affichees.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text(
                                'Sélectionnez au moins une version à comparer.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                        for (final v in affichees) ...[
                          _buildCarteVersion(theme, v),
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
  Widget _buildEnTete(ThemeData theme) {
    return Container(
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
          Text(
            _reference,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
              fontFamily: 'Georgia',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Comparez les traductions de ce verset',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // --- 2. SÉLECTION DES VERSIONS ---
  Widget _buildSelection(ThemeData theme, List<VersionBible> affichees) {
    final accent = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.compare_arrows_rounded, size: 20, color: accent),
            const SizedBox(width: 8),
            Text(
              'Versions affichées',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in _versionsDisponibles) _buildVersionChip(theme, v),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${affichees.length} version${affichees.length > 1 ? 's' : ''} '
          'affichée${affichees.length > 1 ? 's' : ''}',
          style: TextStyle(
            fontSize: 13,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  // --- Pastille de version (afficher / masquer) ---
  Widget _buildVersionChip(ThemeData theme, VersionBible v) {
    final accent = theme.colorScheme.primary;
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
          color: actif ? accent : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif ? accent : Colors.grey.shade300,
          ),
        ),
        child: Text(
          v.code,
          style: TextStyle(
            color: actif ? theme.colorScheme.onPrimary : Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // --- Carte d'une traduction ---
  Widget _buildCarteVersion(ThemeData theme, VersionBible v) {
    final accent = theme.colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  v.code,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  v.nom,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  v.langue,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            v.texte,
            style: TextStyle(
              fontSize: 15,
              height: 1.7,
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.justify,
          ),
        ],
      ),
    );
  }
}