import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/bym_update_service.dart';
import '../data/dictionary_catalog.dart';
import '../data/dictionary_download_service.dart';
import '../data/dictionary_store.dart';
import '../data/download_service.dart';
import '../data/fulltext_index.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import 'bym_lexicon_index_screen.dart';
import 'dictionary_browse_screen.dart';
import 'fredaw_index_screen.dart';
import 'strong_index_screen.dart';

/// Bibliothèque (décision 6) : deux onglets — Bibles / Dictionnaires — où les
/// versions libres de droit se téléchargent livre par livre sur l'appareil.
///
/// C'est la destination promise par la feuille « Version » de la lecture, et le
/// seul endroit qui écrit dans [LibraryStore]. Un téléchargement interrompu
/// n'est pas du travail perdu : la ligne repasse en « Reprendre » et
/// [DownloadService] repart du premier livre manquant. Au goût premium :
/// fond crème, cartes blanches à ombre douce, accents du thème.
class LibraryScreen extends StatefulWidget {
  /// Injectés par les tests ; l'application prend les vrais.
  final LibraryStore? store;
  final DownloadService? service;
  final DictionaryStore? dictionaryStore;
  final DictionaryDownloadService? dictionaryService;

  /// Catalogue de dictionnaires. L'application prend [dictionaryCatalog] ; les
  /// tests injectent un catalogue avec une URL configurée pour observer le
  /// téléchargement.
  final List<DictionaryEntry>? dictionaryCatalog;

  /// Opens a Strong occurrence verse in a reading tab. Null when the screen
  /// stands alone (tests): the occurrence cards then just state their
  /// reference instead of pretending to be buttons.
  final void Function(int bookIndex, int chapter, int? verse)? onOpenVerse;

  /// Conduit à Réglages, où la mise à jour du texte BYM s'installe. Null quand
  /// l'écran est monté seul : la pastille de rappel s'affiche alors sans être
  /// cliquable, plutôt que de faire semblant.
  final VoidCallback? onOpenSettings;

  const LibraryScreen({
    super.key,
    this.store,
    this.service,
    this.dictionaryStore,
    this.dictionaryService,
    this.dictionaryCatalog,
    this.onOpenVerse,
    this.onOpenSettings,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryStore _store = widget.store ?? LibraryStore();
  late final DownloadService _service = widget.service ?? DownloadService();
  late final DictionaryStore _dictStore =
      widget.dictionaryStore ?? DictionaryStore();
  late final DictionaryDownloadService _dictService =
      widget.dictionaryService ??
          DictionaryDownloadService(store: _dictStore);

  Map<String, InstalledVersion> _installed = const {};
  Map<String, int> _sizes = const {};
  bool _loading = true;

  /// Version en cours de téléchargement. Une seule à la fois : deux versions en
  /// parallèle, ce sont 132 requêtes en vol sur un réseau de téléphone.
  String? _activeCode;
  DownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    // Le store documente sa revision comme contrat d'observation : un écran
    // qui copie installed() une fois garde cette réponse pour toujours. Ici,
    // toute écriture (téléchargement, suppression) déclenche une relecture —
    // sauf pendant le téléchargement lui-même, qui émet une révision par
    // livre et dont la fin rafraîchit déjà.
    LibraryStore.revision.addListener(_onStoreRevision);
    _refresh();
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onStoreRevision);
    // Les services possèdent leur client HTTP quand personne ne les injecte :
    // le rendre plutôt que le fuir.
    _service.close();
    _dictService.close();
    super.dispose();
  }

  void _onStoreRevision() {
    if (!mounted || _activeCode != null) return;
    _refresh();
  }

  Future<void> _refresh() async {
    final installed = await _store.installed();
    final sizes = <String, int>{};
    for (final code in installed.keys) {
      sizes[code] = await _store.sizeOnDisk(code);
    }
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _sizes = sizes;
      _loading = false;
    });
  }

  InstalledVersion _stateOf(String code) =>
      _installed[code] ?? InstalledVersion.empty(code);

  Future<void> _download(VersionEntry entry) async {
    if (_activeCode != null) return;
    setState(() {
      _activeCode = entry.code;
      // Une barre dès le premier cadre : la première requête peut mettre
      // quelques secondes, et une ligne muette se lit comme un bouton mort.
      _progress = DownloadProgress(
        code: entry.code,
        done: _stateOf(entry.code).bookCount,
        total: bookCatalog.length,
      );
    });

    final outcome = await _service.install(
      entry,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _activeCode = null;
      _progress = null;
    });
    // Des livres se sont ajoutés : un index construit sur le téléchargement
    // partiel d'avant ne couvrirait pas les nouveaux.
    _invalidate(entry.code);
    await _refresh();
    if (!mounted) return;
    _say(outcome.message);
  }

  Future<void> _delete(VersionEntry entry) async {
    final size = _sizes[entry.code] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${entry.name} ?'),
        content: Text(
          'Les livres téléchargés${size > 0 ? ' (${_formatSize(size)})' : ''} '
          'seront effacés de l\'appareil. '
          'La version restera téléchargeable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _store.remove(entry.code);
    _invalidate(entry.code);
    await _refresh();
    if (!mounted) return;
    _say('${entry.name} supprimée de l\'appareil.');
  }

  /// Efface tout ce que la version laissait en mémoire.
  ///
  /// Les fichiers sont partis mais le cache de [VersionRepository] et l'index
  /// plein texte, eux, survivraient : la lecture continuerait d'afficher la
  /// version supprimée et la recherche de la trouver. Les deux se reconstruisent
  /// tout seuls au prochain téléchargement.
  void _invalidate(String code) {
    VersionRepository.forget(code);
    FulltextIndex.forget(code);
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: premiumBackground(context),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: p.textDark,
          centerTitle: true,
          title: Text(
            'Bibliothèque',
            style: premiumText(context, 18, FontWeight.w800, p.textDark),
          ),
          bottom: TabBar(
            key: const Key('libraryTabs'),
            labelColor: p.primary,
            unselectedLabelColor: p.textGrey,
            indicatorColor: p.primary,
            indicatorWeight: 2,
            labelStyle: premiumText(context, 13, FontWeight.w700, p.primary),
            unselectedLabelStyle: premiumText(
              context,
              13,
              FontWeight.w600,
              p.textGrey,
            ),
            tabs: const [
              Tab(text: 'Bibles'),
              Tab(text: 'Dictionnaires'),
            ],
          ),
        ),
        // Même règle que l'étude du verset : les boutons Android empilés à
        // droite en paysage sont dans `MediaQuery.padding`, et ce n'est qu'ici
        // qu'on les écoute — l'onglet court alors jusqu'au bord, sous les
        // boutons, alors que l'AppBar au-dessus les contourne déjà.
        body: SafeArea(
          child: TabBarView(
            children: [
              if (_loading)
                // Même façonnage que les tuiles qui arrivent : pastille + nom +
                // action. Le spinner nu n'annonçait rien.
                const ListLoadingSkeleton(
                  itemCount: 7,
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
                )
              else
                _bibles(context),
              _DictionariesTab(
                store: _dictStore,
                service: _dictService,
                catalog: widget.dictionaryCatalog ?? dictionaryCatalog,
                onOpenVerse: widget.onOpenVerse,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bibles(BuildContext context) {
    // Les versions cadenassées (sans source libre) sont repoussées en fin de
    // liste, sous leur propre intertitre, pour ne pas couper les versions
    // réellement intégrées ou téléchargeables.
    final locked = <VersionEntry>[];
    final openGroups = <VersionGroup>[];

    for (final group in versionCatalog) {
      final available = group.versions
          .where((v) => v.availability != VersionAvailability.unavailable)
          .toList();
      locked.addAll(group.versions.where(
          (v) => v.availability == VersionAvailability.unavailable));
      if (available.isNotEmpty) {
        openGroups.add(VersionGroup(group.title, available));
      }
    }

    // Récapitulatif de ce que l'appareil détient : une ligne discrète avant
    // les groupes, pour répondre d'un coup d'œil « qu'est-ce qui est là ? »
    final deviceBytes =
        _sizes.values.fold<int>(0, (total, size) => total + size);

    return ListView(
      key: const Key('libraryBibles'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_installed.isNotEmpty) ...[
          _DeviceSummary(
            label:
                '${_installed.length} version${_installed.length > 1 ? 's' : ''} '
                'sur l\'appareil · ${_formatSize(deviceBytes)}',
          ),
        ],
        for (final group in openGroups) ...[
          _GroupHeader(title: group.title),
          for (final version in group.versions) _tile(version),
        ],
        if (locked.isNotEmpty) ...[
          _GroupHeader(title: 'Bientôt disponibles'),
          for (final version in locked) _tile(version),
        ],
      ],
    );
  }

  Widget _tile(VersionEntry version) {
    Widget build(String? updateLabel) => _VersionTile(
          version: version,
          state: _stateOf(version.code),
          sizeOnDisk: _sizes[version.code] ?? 0,
          progress: _activeCode == version.code ? _progress : null,
          otherBusy: _activeCode != null && _activeCode != version.code,
          onDownload: () => _download(version),
          onDelete: () => _delete(version),
          onCancel: _service.cancel,
          onUnavailable: () => _say('${version.code} — bientôt disponible.'),
          updateLabel: updateLabel,
          onOpenSettings: widget.onOpenSettings,
        );

    // Seule la BYM peut recevoir une mise à jour de texte : elle est embarquée
    // dans l'APK, donc corriger une coquille passerait sinon par le store. Les
    // autres versions se téléchargent en entier depuis la Bibliothèque.
    if (version.code != VersionRepository.embeddedCode) return build(null);
    return ValueListenableBuilder<BymUpdateCheck?>(
      valueListenable: BymUpdateChecker.available,
      builder: (context, plan, _) => build(plan?.bookLabel),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;

  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: premiumText(
          context,
          11,
          FontWeight.w800,
          p.textGrey,
          spacing: 1.1,
        ),
      ),
    );
  }
}

/// Bandeau récapitulatif « ce que l'appareil détient », en tête de l'onglet
/// Bibles : nombre de versions et poids total, sur fond doux d'accent.
class _DeviceSummary extends StatelessWidget {
  final String label;

  const _DeviceSummary({required this.label});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: p.primarySoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.download_done_outlined, size: 18, color: p.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: premiumText(context, 12.5, FontWeight.w600, p.textDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une version et son état sur l'appareil : rien / partielle / complète, ou la
/// barre pendant que les livres arrivent.
/// La coquille de carte partagée par les deux onglets de la Bibliothèque :
/// la carte blanche à ombre douce et l'onde de tap. Chaque tuile (version comme
/// dictionnaire) hérite de ce composant et n'apporte que son contenu.
class _LibraryCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  /// La ressource est indisponible : la carte s'efface et n'ouvre rien.
  final bool dimmed;

  const _LibraryCard({required this.child, this.onTap, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final card = Ink(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dimmed
            ? null
            : premiumShadow(
                p.primaryDark,
                opacity: 0.06,
                blur: 14,
                offset: const Offset(0, 6),
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: child,
      ),
    );
    return Material(
      color: Colors.transparent,
      child: dimmed ? Opacity(opacity: .55, child: card) : card,
    );
  }
}

class _VersionTile extends StatelessWidget {
  final VersionEntry version;
  final InstalledVersion state;
  final int sizeOnDisk;

  /// Non nul seulement pour la version en cours de téléchargement.
  final DownloadProgress? progress;

  /// Une autre version se télécharge : le bouton reste visible mais inerte.
  final bool otherBusy;

  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onUnavailable;

  /// Ce que la mise à jour en attente remplacerait (« 21 livres »), null quand
  /// il n'y a rien de neuf. Purement un rappel : rien ne se télécharge depuis
  /// cette tuile.
  final String? updateLabel;
  final VoidCallback? onOpenSettings;

  const _VersionTile({
    required this.version,
    required this.state,
    required this.sizeOnDisk,
    required this.progress,
    required this.otherBusy,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
    required this.onUnavailable,
    this.updateLabel,
    this.onOpenSettings,
  });

  bool get _downloading => progress != null;

  bool get _dimmed => version.availability == VersionAvailability.unavailable;

  /// La ligne sous le nom. Null quand le bouton dit déjà tout.
  String? get _status {
    if (version.embedded) return 'Intégrée à l\'application · hors ligne';
    if (_dimmed) return 'Bientôt disponible';
    if (state.isComplete) {
      return '${state.bookCount} livres · ${_formatSize(sizeOnDisk)}';
    }
    if (state.isPartial) {
      return '${state.bookCount}/${bookCatalog.length} livres — '
          'téléchargement à reprendre';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final status = _status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _LibraryCard(
        dimmed: _dimmed,
        onTap: _dimmed ? onUnavailable : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _CodeBadge(code: version.code, dimmed: _dimmed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          version.name,
                          style: premiumText(
                            context,
                            15,
                            FontWeight.w700,
                            _dimmed ? p.textGrey : p.textDark,
                          ),
                        ),
                        Text(
                          version.rights,
                          style: premiumText(
                            context,
                            12,
                            FontWeight.w500,
                            p.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _action(context),
                ],
              ),
              if (_downloading)
                _bar(context)
              else if (status != null || updateLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      if (status != null)
                        Expanded(
                          child: Text(
                            status,
                            style: premiumText(
                              context,
                              12,
                              FontWeight.w600,
                              state.isComplete ? p.primary : p.textGrey,
                            ),
                          ),
                        ),
                      if (updateLabel != null) ...[
                        if (status != null) const SizedBox(width: 8),
                        _UpdatePill(
                          label: updateLabel!,
                          onTap: onOpenSettings,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final p = premiumPalette(context);
    final progress = this.progress!;
    final book = progress.currentBookName;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: Key('progress-${version.code}'),
              value: progress.fraction,
              minHeight: 6,
              color: p.primary,
              backgroundColor: p.primarySoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${progress.done}/${progress.total} livres${book == null ? '' : ' · $book'}',
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final p = premiumPalette(context);

    if (_downloading) {
      return TextButton(
        key: Key('cancel-${version.code}'),
        onPressed: onCancel,
        child: Text(
          'Annuler',
          style: premiumText(context, 13, FontWeight.w700, p.primary),
        ),
      );
    }
    if (version.embedded) {
      return Icon(Icons.verified_outlined, size: 20, color: p.primary);
    }
    if (_dimmed) {
      return Icon(Icons.lock_outline, size: 18, color: p.textGrey);
    }
    if (state.isComplete) {
      return IconButton(
        key: Key('delete-${version.code}'),
        tooltip: 'Supprimer de l\'appareil',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      );
    }
    // Rien ou une version partielle : le même bouton, l'étiquette change. La
    // reprise n'est pas une action à part — c'est le même téléchargement.
    // Responsive : sur petit écran (<400) seul l'icône reste pour éviter
    // l'overflow et garder la carte lisible (360 est la largeur iPhone SE).
    final compact = MediaQuery.sizeOf(context).width < 400;
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: Key('download-${version.code}'),
            tooltip: state.isPartial ? 'Reprendre' : 'Télécharger',
            onPressed: otherBusy ? null : onDownload,
            icon: Icon(
              state.isPartial ? Icons.refresh : Icons.download_outlined,
              size: 20,
              color: otherBusy ? null : p.primary,
            ),
          ),
          if (state.isPartial)
            IconButton(
              key: Key('delete-${version.code}'),
              tooltip: 'Supprimer de l\'appareil',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          key: Key('download-${version.code}'),
          onPressed: otherBusy ? null : onDownload,
          icon: Icon(
            state.isPartial ? Icons.refresh : Icons.download_outlined,
            size: 18,
          ),
          label: Text(state.isPartial ? 'Reprendre' : 'Télécharger'),
        ),
        if (state.isPartial)
          IconButton(
            key: Key('delete-${version.code}'),
            tooltip: 'Supprimer de l\'appareil',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    );
  }
}

/// Rappel « une correction du texte BYM est en ligne », sur la tuile BYM.
///
/// L'appui conduit à Réglages et **rien d'autre** : le choix de télécharger
/// appartient à l'utilisateur, dans l'écran qui montre les notes de publication
/// et le poids. Une pastille qui lancerait 9 Mo au premier effleurement serait un
/// piège.
class _UpdatePill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _UpdatePill({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const Key('bymUpdatePill'),
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: p.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: 12, color: p.onPrimary),
              const SizedBox(width: 5),
              Text(
                'MàJ · $label',
                style: premiumText(context, 11, FontWeight.w800, p.onPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  final String code;
  final bool dimmed;

  const _CodeBadge({required this.code, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      width: 46,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: dimmed ? p.surfaceAlt : p.primarySoft,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        code,
        overflow: TextOverflow.ellipsis,
        style: premiumText(
          context,
          11,
          FontWeight.w800,
          dimmed ? p.textGrey : p.primary,
        ),
      ),
    );
  }
}

/// Onglet Dictionnaires, piloté par [dictionaryCatalog].
///
/// Chaque dictionnaire a son état sur l'appareil, exactement comme les
/// versions : intégré (✓, sans bouton), téléchargeable une fois son URL
/// configurée (⬇), en cours (barre + Annuler), téléchargé (taille + 🗑), ou à
/// venir (grisé, cadenassé). Le même modèle que l'onglet Bibles, à un détail
/// près : un dictionnaire est **un** fichier, donc le téléchargement n'a pas de
/// progression par livre — la barre est une simple attente.
class _DictionariesTab extends StatefulWidget {
  final DictionaryStore store;
  final DictionaryDownloadService service;
  final List<DictionaryEntry> catalog;
  final void Function(int bookIndex, int chapter, int? verse)? onOpenVerse;

  const _DictionariesTab({
    required this.store,
    required this.service,
    required this.catalog,
    this.onOpenVerse,
  });

  @override
  State<_DictionariesTab> createState() => _DictionariesTabState();
}

class _DictionariesTabState extends State<_DictionariesTab> {
  Set<String> _installed = const {};
  Map<String, int> _sizes = const {};
  bool _loading = true;

  /// Dictionnaire en cours de téléchargement. Un seul à la fois.
  String? _activeCode;

  /// Octets reçus pour le téléchargement en cours — la barre devient
  /// déterminée dès que le serveur annonce la taille du fichier.
  DictionaryDownloadProgress? _progress;

  @override
  void initState() {
    super.initState();
    // Même contrat que l'onglet Bibles : suivre les écritures du registre
    // plutôt que copier installed() une fois pour toutes.
    DictionaryStore.revision.addListener(_onStoreRevision);
    _refresh();
  }

  @override
  void dispose() {
    DictionaryStore.revision.removeListener(_onStoreRevision);
    super.dispose();
  }

  void _onStoreRevision() {
    if (!mounted || _activeCode != null) return;
    _refresh();
  }

  Future<void> _refresh() async {
    final installed = await widget.store.installed();
    final sizes = <String, int>{};
    for (final code in installed) {
      sizes[code] = await widget.store.sizeOnDisk(code);
    }
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _sizes = sizes;
      _loading = false;
    });
  }

  Future<void> _download(DictionaryEntry entry) async {
    if (_activeCode != null) return;
    setState(() => _activeCode = entry.code);

    final outcome = await widget.service.install(
      entry,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );

    if (!mounted) return;
    setState(() {
      _activeCode = null;
      _progress = null;
    });
    await _refresh();
    if (!mounted) return;
    _say(outcome.message);
  }

  Future<void> _delete(DictionaryEntry entry) async {
    final size = _sizes[entry.code] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${entry.name} ?'),
        content: Text(
          'Le dictionnaire téléchargé${size > 0 ? ' (${_formatSize(size)})' : ''} '
          'sera effacé de l\'appareil. '
          'Il restera téléchargeable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('confirmDictionaryDelete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.remove(entry.code);
    await _refresh();
    if (!mounted) return;
    _say('${entry.name} supprimé de l\'appareil.');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// L'écran qu'un dictionnaire **intégré** ouvre au tap.
  Widget _embeddedScreen(BuildContext context, DictionaryEntry entry) {
    // Le callback de saut lecture, commun à tous les dictionnaires : la pile
    // de fiches est vidée avant de basculer sur l'onglet Lecture, sinon une
    // route intermédiaire resterait au-dessus du lecteur.
    final onOpenVerse = widget.onOpenVerse == null
        ? null
        : (int book, int chapter, int? verse) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            widget.onOpenVerse!(book, chapter, verse);
          };
    return switch (entry.code) {
      'BYM' => BymLexiconIndexScreen(onOpenVerse: onOpenVerse),
      'FREDAW' => FredawIndexScreen(onOpenVerse: onOpenVerse),
      'STRONG_FR' => StrongIndexScreen(onOpenVerse: onOpenVerse),
      _ => _DictionaryDetailScreen(entry: entry),
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    if (_loading) {
      return const ListLoadingSkeleton(
        itemCount: 5,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
      );
    }
    return ListView(
      key: const Key('libraryDictionaries'),
      // Pas de padding horizontal ici : chaque tuile porte le sien (16 px),
      // aligné sur l'onglet Bibles. Le doubler décalait ces cartes de 32 px.
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: [
        for (final entry in widget.catalog) ...[
          _DictionaryTile(
            entry: entry,
            installed: _installed.contains(entry.code),
            sizeOnDisk: _sizes[entry.code] ?? 0,
            downloading: _activeCode == entry.code,
            progress:
                _activeCode == entry.code ? _progress : null,
            otherBusy: _activeCode != null && _activeCode != entry.code,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _openScreen(context, entry),
              ),
            ),
            onDownload: () => _download(entry),
            onDelete: () => _delete(entry),
            onCancel: widget.service.cancel,
            onUnavailable: () =>
                _say(entry.configured
                    ? '${entry.name} — bientôt disponible.'
                    : '${entry.name} — URL non configurée, à publier sur '
                        'l\'hébergement.'),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Le lexique BYM, le Strong FR et le dictionnaire FreDAW sont déjà '
            'embarqué·e·s. Les autres dictionnaires se téléchargent dès que '
            'leur fichier JSON est publié et son URL renseignée.',
            textAlign: TextAlign.center,
            style: premiumText(
              context,
              12,
              FontWeight.w500,
              p.textGrey,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _openScreen(BuildContext context, DictionaryEntry entry) {
    if (entry.embedded) return _embeddedScreen(context, entry);
    // Un dictionnaire téléchargé s'ouvre dans le lecteur générique.
    return DictionaryBrowseScreen(
      entry: entry,
      store: widget.store,
    );
  }
}

class _DictionaryDetailScreen extends StatelessWidget {
  final DictionaryEntry entry;

  const _DictionaryDetailScreen({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          entry.name,
          style: premiumText(context, 17, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                entry.description,
                style: premiumText(context, 16, FontWeight.w700, p.textDark),
              ),
              const SizedBox(height: 18),
              _DetailRow(label: 'Statut', value: _status()),
              const SizedBox(height: 10),
              _DetailRow(label: 'Source', value: entry.rights),
            ],
          ),
        ),
      ),
    );
  }

  String _status() {
    if (entry.embedded) return 'Intégré à l\'application';
    if (entry.configured) return 'Téléchargeable depuis une URL';
    if (entry.downloadable) return 'URL à configurer';
    return 'À venir';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: premiumText(
            context,
            11,
            FontWeight.w800,
            p.primary,
            spacing: 1.05,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: premiumText(context, 14, FontWeight.w500, p.textDark),
        ),
      ],
    );
  }
}

/// Un dictionnaire et son état sur l'appareil : intégré / rien / en cours /
/// téléchargé / à venir. Le même langage que [_VersionTile].
class _DictionaryTile extends StatelessWidget {
  final DictionaryEntry entry;
  final bool installed;
  final int sizeOnDisk;
  final bool downloading;

  /// Non nul pendant le téléchargement de CE dictionnaire : octets reçus et
  /// taille annoncée. La barre est déterminée quand le serveur a parlé.
  final DictionaryDownloadProgress? progress;

  final bool otherBusy;

  final VoidCallback onOpen;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  final VoidCallback onUnavailable;

  const _DictionaryTile({
    required this.entry,
    required this.installed,
    required this.sizeOnDisk,
    required this.downloading,
    this.progress,
    required this.otherBusy,
    required this.onOpen,
    required this.onDownload,
    required this.onDelete,
    required this.onCancel,
    required this.onUnavailable,
  });

  /// Un dictionnaire est grisé quand il ne peut être ni ouvert ni téléchargé :
  /// cadenassé (sans source) ou en attente de son URL.
  bool get _dimmed => !entry.embedded && !installed && !entry.configured;

  /// La ligne sous le nom. Null quand le bouton dit déjà tout.
  String? get _status {
    if (entry.embedded) return 'Intégré à l\'application · hors ligne';
    if (downloading) return null;
    if (installed) return 'Téléchargé · ${_formatSize(sizeOnDisk)}';
    if (!entry.configured) {
      return entry.downloadable
          ? 'URL à configurer pour télécharger'
          : 'Bientôt disponible';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final status = _status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: _LibraryCard(
        dimmed: _dimmed,
        onTap: _dimmed
            ? onUnavailable
            : (entry.embedded || installed) ? onOpen : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _DictionaryIcon(entry: entry, dimmed: _dimmed),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          style: premiumText(
                            context,
                            15,
                            FontWeight.w700,
                            _dimmed ? p.textGrey : p.textDark,
                          ),
                        ),
                        Text(
                          entry.rights,
                          style: premiumText(
                            context,
                            12,
                            FontWeight.w500,
                            p.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _action(context),
                ],
              ),
              if (downloading)
                _bar(context)
              else if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    status,
                    style: premiumText(
                      context,
                      12,
                      FontWeight.w600,
                      installed ? p.primary : p.textGrey,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final p = premiumPalette(context);
    final progress = this.progress;
    final total = progress?.total;
    // Même langage que les Bibles : une barre ET une légende. Déterminée dès
    // que le serveur annonce sa taille — Bailly pèse ~11 Mo, l'attente doit
    // se lire comme un travail en cours, pas un écran figé.
    final caption = total == null
        ? 'Téléchargement…'
        : 'Téléchargement… '
            '${_formatSize(progress!.received)} / ${_formatSize(total)}';
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: Key('dict-progress-${entry.code}'),
              value: progress?.fraction,
              minHeight: 6,
              color: p.primary,
              backgroundColor: p.primarySoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: premiumText(context, 12, FontWeight.w500, p.textGrey),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final p = premiumPalette(context);

    if (downloading) {
      return TextButton(
        key: Key('dict-cancel-${entry.code}'),
        onPressed: onCancel,
        child: Text(
          'Annuler',
          style: premiumText(context, 13, FontWeight.w700, p.primary),
        ),
      );
    }
    if (entry.embedded) {
      return Icon(Icons.verified_outlined, size: 20, color: p.primary);
    }
    if (_dimmed) {
      return Icon(Icons.lock_outline, size: 18, color: p.textGrey);
    }
    if (installed) {
      return IconButton(
        key: Key('dict-delete-${entry.code}'),
        tooltip: 'Supprimer de l\'appareil',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      );
    }
    final compact = MediaQuery.sizeOf(context).width < 400;
    if (compact) {
      return IconButton(
        key: Key('dict-download-${entry.code}'),
        tooltip: 'Télécharger',
        onPressed: otherBusy ? null : onDownload,
        icon: Icon(Icons.download_outlined, size: 20, color: otherBusy ? null : p.primary),
      );
    }
    return TextButton.icon(
      key: Key('dict-download-${entry.code}'),
      onPressed: otherBusy ? null : onDownload,
      icon: const Icon(Icons.download_outlined, size: 18),
      label: const Text('Télécharger'),
    );
  }
}

class _DictionaryIcon extends StatelessWidget {
  final DictionaryEntry entry;
  final bool dimmed;

  const _DictionaryIcon({required this.entry, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final color = dimmed ? p.textGrey : p.primary;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: dimmed ? .08 : .16),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(
        dimmed ? Icons.lock_outline : Icons.book_outlined,
        color: color,
        size: 24,
      ),
    );
  }
}

/// « 3,2 Mo » — la virgule décimale française, comme le reste de l'interface.
String _formatSize(int bytes) {
  const mo = 1024 * 1024;
  if (bytes >= mo) {
    return '${(bytes / mo).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} Ko';
  return '$bytes o';
}
