import 'package:flutter/material.dart';

import '../data/book_catalog.dart';
import '../data/download_service.dart';
import '../data/fulltext_index.dart';
import '../data/library_store.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../widgets/premium_style.dart';
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

  /// Opens a Strong occurrence verse in a reading tab. Null when the screen
  /// stands alone (tests): the occurrence cards then just state their
  /// reference instead of pretending to be buttons.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  /// Opens a FreDAW entry in a reading tab. Null when the screen stands alone
  /// (tests): the fiche then shows no « Ouvrir onglet » button.
  final void Function(String term, String definition)? onOpenDictionary;

  const LibraryScreen({
    super.key,
    this.store,
    this.service,
    this.onOpenVerse,
    this.onOpenDictionary,
  });

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
    final p = premiumPalette(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kPremiumBackground,
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
            unselectedLabelStyle: premiumText(context, 13, FontWeight.w600, p.textGrey),
            tabs: const [
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
            _DictionariesTab(
              onOpenVerse: widget.onOpenVerse,
              onOpenDictionary: widget.onOpenDictionary,
            ),
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
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: premiumText(context, 11, FontWeight.w800, p.textGrey, spacing: 1.1),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: dimmed
            ? null
            : premiumShadow(p.primaryDark, opacity: 0.06, blur: 14, offset: const Offset(0, 6)),
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
                          style: premiumText(context, 12, FontWeight.w500, p.textGrey),
                        ),
                      ],
                    ),
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
                    style: premiumText(
                      context,
                    12,
                    FontWeight.w600,
                    state.isComplete ? p.primary : p.textGrey,
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
        color: dimmed ? Colors.grey.shade200 : p.primarySoft,
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

/// Onglet Dictionnaires. Il présente les ressources déjà embarquées et
/// signale les dictionnaires externes prévus sans en faire de faux boutons.
class _DictionariesTab extends StatelessWidget {
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;
  final void Function(String term, String definition)? onOpenDictionary;

  const _DictionariesTab({this.onOpenVerse, this.onOpenDictionary});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return ListView(
      key: const Key('libraryDictionaries'),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      children: [
        for (final resource in _dictionaryResources) ...[
          _DictionaryTile(
            resource: resource,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => switch (resource.code) {
                  'FREDAW' => FredawIndexScreen(
                    onOpenVerse: onOpenVerse == null
                        ? null
                        : (book, chapter, verse) =>
                              onOpenVerse!(book, chapter, verse ?? 1),
                    onOpenDictionary: onOpenDictionary,
                  ),
                  'STRONG_FR' => StrongIndexScreen(
                    onOpenVerse: onOpenVerse == null
                        ? null
                        : (book, chapter, verse) {
                            // Clear the stacked chain of fiches (index →
                            // fiche → occurrences) before switching to the
                            // reading tab: a single pop would leave an
                            // intermediate route covering the reader.
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                            onOpenVerse!(book, chapter, verse);
                          },
                  ),
                  _ => _DictionaryDetailScreen(resource: resource),
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Le lexique BYM, le Strong FR et le dictionnaire FreDAW sont déjà '
            'embarqué·e·s. Les autres dictionnaires externes (hébreu, grec, '
            'autres versions Strong) arriveront ici lorsqu\'ils seront prêts.',
            textAlign: TextAlign.center,
            style: premiumText(context, 12, FontWeight.w500, p.textGrey, height: 1.5),
          ),
        ),
      ],
    );
  }
}

const List<_DictionaryResource> _dictionaryResources = [
  _DictionaryResource(
    code: 'BYM',
    name: 'Lexique BYM',
    description: 'Dictionnaire intégré construit à partir des notes de la BYM.',
    available: true,
    note: 'Intégré',
  ),
  _DictionaryResource(
    code: 'STRONG_FR',
    name: 'Strong FR',
    description: 'Lexique Strong français embarqué depuis CrossWire/SWORD.',
    available: true,
    note: 'Intégré',
  ),
  _DictionaryResource(
    code: 'SWORD',
    name: 'Modules SWORD',
    description:
        'Source Strong hébreu et grec utilisée pour le lexique et la recherche.',
    available: true,
    note: 'Existe',
  ),
  _DictionaryResource(
    code: 'FREDAW',
    name: 'Westphal 1932',
    description:
        'Dictionnaire encyclopédique de la Bible A. Westphal (1932) embarqué localement.',
    available: true,
    note: 'Intégré',
  ),
  _DictionaryResource(
    code: 'NAVE',
    name: 'Nave',
    description: 'Catégorie thématique sans source disponible pour l\'instant.',
    available: false,
    note: 'À venir',
  ),
];

class _DictionaryResource {
  final String code;
  final String name;
  final String description;
  final bool available;
  final String note;

  const _DictionaryResource({
    required this.code,
    required this.name,
    required this.description,
    required this.available,
    required this.note,
  });
}

class _DictionaryDetailScreen extends StatelessWidget {
  final _DictionaryResource resource;

  const _DictionaryDetailScreen({required this.resource});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: kPremiumBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          resource.name,
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
                resource.description,
                style: premiumText(context, 16, FontWeight.w700, p.textDark),
              ),
              const SizedBox(height: 18),
              _DetailRow(label: 'Statut', value: resource.note),
              const SizedBox(height: 10),
              _DetailRow(
                label: 'Source',
                value: resource.code == 'STRONG_FR'
                    ? 'CrossWire/SWORD — FreStrongsHebrew + FreStrongsGreek'
                    : resource.code == 'FREDAW'
                    ? 'Catalogue SWORD — FreDAW (A. Westphal) à intégrer'
                    : resource.code == 'SWORD'
                    ? 'CrossWire/SWORD modules Strong en cours d\'utilisation'
                    : 'Données internes de la BYM',
              ),
              const SizedBox(height: 18),
              if (!resource.available)
                Text(
                  'Cette ressource est prévue mais pas encore disponible directement '
                  'dans l\'application. Elle apparaîtra ici lorsqu\'elle sera intégrée.',
                  style: premiumText(context, 12, FontWeight.w500, p.textGrey, height: 1.5),
                ),
            ],
          ),
        ),
      ),
    );
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
          style: premiumText(context, 11, FontWeight.w800, p.primary, spacing: 1.05),
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

class _DictionaryTile extends StatelessWidget {
  final _DictionaryResource resource;
  final VoidCallback? onTap;

  const _DictionaryTile({required this.resource, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final color = resource.available ? p.primary : p.textGrey;
    return _LibraryCard(
      dimmed: !resource.available,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: resource.available ? .16 : .08),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                resource.available ? Icons.book_outlined : Icons.lock_outline,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resource.name,
                    style: premiumText(context, 15, FontWeight.w700, p.textDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    resource.description,
                    style: premiumText(context, 12, FontWeight.w500, p.textGrey, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
              decoration: BoxDecoration(
                color: resource.available ? p.primarySoft : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                resource.note,
                style: premiumText(
                  context,
                  11,
                  FontWeight.w700,
                  resource.available ? p.primary : p.textGrey,
                ),
              ),
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