import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/download_service.dart';
import '../data/fulltext_index.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';

/// Bibliothèque (décision 6) : deux onglets — Bibles / Dictionnaires — où les
/// versions libres de droit se téléchargent livre par livre sur l'appareil.
///
/// C'est la destination promise par la feuille « Version » de la lecture, et le
/// seul endroit qui écrit dans [LibraryStore]. Un téléchargement interrompu
/// n'est pas du travail perdu : la ligne repasse en « Reprendre » et
/// [DownloadService] repart du premier livre manquant.
class LibraryScreen extends StatefulWidget {
  /// Injectés par les tests ; l'application prend les vrais.
  final LibraryStore? store;
  final DownloadService? service;

  const LibraryScreen({super.key, this.store, this.service});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final LibraryStore _store = widget.store ?? LibraryStore();
  late final DownloadService _service = widget.service ?? DownloadService();

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Supprimer ${entry.code} ?'),
        content: const Text(
          'Les livres téléchargés seront effacés de l\'appareil. '
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
    _say('${entry.code} supprimée de l\'appareil.');
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliothèque'),
          bottom: const TabBar(
            key: Key('libraryTabs'),
            tabs: [
              Tab(text: 'Bibles'),
              Tab(text: 'Dictionnaires'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              _bibles(context),
            const _DictionariesTab(),
          ],
        ),
      ),
    );
  }

  Widget _bibles(BuildContext context) {
    return ListView(
      key: const Key('libraryBibles'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final group in versionCatalog) ...[
          _GroupHeader(title: group.title),
          for (final version in group.versions)
            _VersionTile(
              version: version,
              state: _stateOf(version.code),
              sizeOnDisk: _sizes[version.code] ?? 0,
              progress: _activeCode == version.code ? _progress : null,
              otherBusy: _activeCode != null && _activeCode != version.code,
              onDownload: () => _download(version),
              onDelete: () => _delete(version),
              onCancel: _service.cancel,
              onUnavailable: () =>
                  _say('${version.code} — bientôt disponible.'),
            ),
        ],
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;

  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// Une version et son état sur l'appareil : rien / partielle / complète, ou la
/// barre pendant que les livres arrivent.
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
    final theme = Theme.of(context);
    final status = _status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: _dimmed ? .2 : .4),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _dimmed
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            version.rights,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (version.hasAudio)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.volume_up_outlined,
                            size: 16, color: theme.colorScheme.outline),
                      ),
                    _action(context),
                  ],
                ),
                if (_downloading)
                  _bar(context)
                else if (status != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      status,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: state.isComplete
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final p = progress!;
    final book = p.currentBookName;
    return Padding(
      padding: const EdgeInsets.only(top: 10, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: Key('progress-${version.code}'),
              value: p.fraction,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${p.done}/${p.total} livres${book == null ? '' : ' · $book'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _action(BuildContext context) {
    final theme = Theme.of(context);

    if (_downloading) {
      return TextButton(
        key: Key('cancel-${version.code}'),
        onPressed: onCancel,
        child: const Text('Annuler'),
      );
    }
    if (version.embedded) {
      return Icon(Icons.verified_outlined,
          size: 20, color: theme.colorScheme.primary);
    }
    if (_dimmed) {
      return Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.outline);
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          key: Key('download-${version.code}'),
          onPressed: otherBusy ? null : onDownload,
          icon: Icon(state.isPartial ? Icons.refresh : Icons.download_outlined,
              size: 18),
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

class _CodeBadge extends StatelessWidget {
  final String code;
  final bool dimmed;

  const _CodeBadge({required this.code, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 46,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: dimmed
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        code,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: dimmed
              ? theme.colorScheme.onSurfaceVariant
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Onglet Dictionnaires. Il n'y a pas de catalogue à afficher : le lexique est
/// dérivé des notes de la BYM, donc déjà embarqué. Mieux vaut le dire que
/// d'inventer des entrées qui ne se téléchargeraient nulle part.
class _DictionariesTab extends StatelessWidget {
  const _DictionariesTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_outlined,
                size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(
              'Aucun dictionnaire à télécharger',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Le lexique de l\'application est construit à partir des notes de '
              'la BYM : il est déjà embarqué et n\'a rien à télécharger. Les '
              'dictionnaires externes (Strong, hébreu et grec) arriveront ici.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
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
