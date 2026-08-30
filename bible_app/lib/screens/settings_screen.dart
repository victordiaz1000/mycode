import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/bym_update_service.dart';
import '../data/bym_update_store.dart';
import '../data/fulltext_index.dart';
import '../data/library_store.dart';
import '../data/local_repository.dart';
import '../data/reading_history.dart';
import '../data/theme_catalog.dart';
import '../data/version_catalog.dart';
import '../data/version_repository.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import 'themes_screen.dart';

/// Version de l'**application** telle que `pubspec.yaml` la déclare
/// (`version: 1.0.0+1`). À tenir en phase avec lui à chaque publication sur le
/// store — la version du **texte**, elle, se lit à l'exécution et n'a pas
/// besoin d'être écrite ici.
const String appVersion = '1.0.0';

/// Réglages — destination de la coquille.
///
/// The screen edits the persisted `AppPreferences` that the reader actually
/// reads: default version, text size, alignment, notes mode and disposition.
/// No control lives here that the rest of the app does not honour — a setting
/// that answers nothing reads as broken.
class SettingsScreen extends StatefulWidget {
  /// Injecté par les tests ; l'application prend le vrai. L'écran ne ferme que
  /// le service qu'il a lui-même créé.
  final BymUpdateService? updateService;

  const SettingsScreen({super.key, this.updateService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final LibraryStore _library = LibraryStore();
  AppPreferences? _prefs;
  Map<String, InstalledVersion> _installed = const {};
  Map<String, int> _sizes = {};

  /// Mise à jour du texte BYM. Le service ne crée son client HTTP qu'au premier
  /// appel : le tenir en champ ne coûte donc rien tant qu'on ne vérifie pas.
  late final BymUpdateService _updates = widget.updateService ??
      BymUpdateService();

  /// Date du texte en vigueur (mise à jour installée, sinon embarquée). Null
  /// quand `_source.json` manque des assets — voir `unconfigured`.
  ///
  /// Une date et non plus un numéro de version : il n'y a plus de semver à tenir
  /// à la main, le texte est identifié par le commit amont dont il provient.
  DateTime? _textDate;
  int _updateBytes = 0;

  /// Vérification ou installation en cours : la rangée d'action se verrouille.
  bool _busy = false;
  BymUpdateProgress? _updateProgress;

  /// Dernier retour du service, affiché sous la rangée. Un message d'erreur qui
  /// disparaît en une seconde ne se lit pas : celui-ci reste jusqu'au prochain
  /// geste.
  String? _updateMessage;

  @override
  void initState() {
    super.initState();
    _load();
    // The settings screen survives in the shell's IndexedStack: without this it
    // keeps the registry as it stood when it was built, so a version downloaded
    // in the Bibliothèque would not show up in the storage list.
    LibraryStore.revision.addListener(_onLibraryChanged);
    // Même raison pour le texte BYM : une bascule vers la mise à jour doit se
    // voir dans la section, y compris quand elle vient d'ailleurs (un JSON abîmé
    // que `LocalRepository` a effacé, par exemple).
    BymUpdateStore.revision.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    LibraryStore.revision.removeListener(_onLibraryChanged);
    BymUpdateStore.revision.removeListener(_onLibraryChanged);
    if (widget.updateService == null) _updates.close();
    super.dispose();
  }

  Future<void> _onLibraryChanged() => _load();

  Future<void> _load() async {
    final prefs = await AppPreferences.load();
    final installed = await _installedVersions();
    final sizes = <String, int>{};
    var total = 0;
    for (final code in installed.keys) {
      final size = await _library.sizeOnDisk(code);
      sizes[code] = size;
      total += size;
    }
    sizes['_total'] = total;
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _installed = installed;
      _sizes = sizes;
    });
    // Détaché à dessein : lire la date du texte passe par les assets et, si
    // une mise à jour est installée, par `path_provider`. Aucune des deux ne
    // répond dans la zone fake-async des tests widget — les attendre ici
    // laisserait l'écran entier sur son squelette. Ainsi, au pire, la section
    // annonce une date indéterminée, et le reste des réglages fonctionne.
    _loadTextVersion();
  }

  Future<void> _loadTextVersion() async {
    final textDate = await _updates.effectiveDate();
    // Pas de mise à jour installée, pas de dossier à mesurer : le prédicat est
    // synchrone, donc ce chemin ne touche au disque que s'il y a de quoi.
    final bytes = BymUpdateStore.installedCommit == null
        ? 0
        : await BymUpdateStore().sizeOnDisk();
    if (!mounted) return;
    setState(() {
      _textDate = textDate;
      _updateBytes = bytes;
    });
  }

  Future<Map<String, InstalledVersion>> _installedVersions() async {
    try {
      return await _library.installed();
    } catch (_) {
      return const {};
    }
  }

  AppPreferences get _p => _prefs!;

  Future<void> _save() async {
    final prefs = _prefs;
    if (prefs == null) return;
    // Do not let this long-lived IndexedStack screen overwrite a theme chosen
    // from the dedicated theme screen with its stale preferences snapshot.
    prefs.themeId = AppPreferences.themeNotifier.value;
    await prefs.save();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _pickDefaultVersion() {
    final prefs = _prefs;
    if (prefs == null) return;
    final p = premiumPalette(context);

    // A choice menu lists only what is choosable: the embedded BYM and LSGS,
    // plus every version holding books on the device. A downloadable-but-absent
    // version has no text to default to — getting one belongs to the
    // Bibliothèque.
    bool readable(VersionEntry v) =>
        v.embedded || _installed[v.code]?.isEmpty == false;
    final groups = [
      for (final group in versionCatalog)
        if (group.versions.any(readable))
          (
            title: group.title,
            versions: group.versions.where(readable).toList(),
          ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: premiumBackground(context),
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Version de lecture par défaut',
                style: premiumText(context, 16, FontWeight.w800, p.textDark),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 6),
                      child: Text(
                        group.title,
                        style: premiumText(
                          context,
                          11,
                          FontWeight.w800,
                          p.textGrey,
                          spacing: 1,
                        ),
                      ),
                    ),
                    for (final version in group.versions)
                      _VersionOption(
                        version: version,
                        selected: version.code == prefs.versionCode,
                        installedLine: _installedLine(version),
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() => prefs.versionCode = version.code);
                          _save();
                          _snack('Version par défaut : ${version.name}.');
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickReadingFont() {
    final prefs = _prefs;
    if (prefs == null) return;
    final p = premiumPalette(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: premiumBackground(context),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'Police de lecture',
                    style: premiumText(
                      context,
                      17,
                      FontWeight.w800,
                      p.textDark,
                    ),
                  ),
                ),
                for (final font in ReadingFont.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: font == prefs.readingFont
                          ? p.primarySoft
                          : p.surface,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Navigator.of(context).pop();
                          setState(() => prefs.readingFont = font);
                          _save();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      font.label,
                                      style: TextStyle(
                                        fontFamily: font.fontFamily,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: p.textDark,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Au commencement Élohîm créa les cieux et la Terre.',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: font.fontFamily,
                                        fontSize: 15,
                                        height: 1.35,
                                        color: p.textDark,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (font == prefs.readingFont)
                                Icon(Icons.check_circle, color: p.primary),
                            ],
                          ),
                        ),
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

  /// "2/66 livres" under a partially installed version in the picker.
  String? _installedLine(VersionEntry version) {
    final state = _installed[version.code];
    if (state == null || state.isEmpty || state.isComplete) return null;
    return '${state.bookCount}/66 livres téléchargés';
  }

  void _clearCache() {
    LocalRepository.clearCache();
    VersionRepository.clearCache();
    for (final code in _installed.keys) {
      FulltextIndex.forget(code);
    }
    _snack('Cache vidé — les textes seront relus depuis le disque.');
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer l’historique ?'),
        content: const Text(
          'Les chapitres récemment ouverts seront oubliés. Vos notes, '
          'surlignages et favoris ne sont pas touchés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ReadingHistory().clear();
    if (!mounted) return;
    _snack('Historique effacé.');
  }

  /// Interroge le dépôt : un commit et un arbre, aucun livre.
  Future<void> _checkUpdates() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _updateMessage = null;
    });
    final check = await _updates.checkForUpdate();
    if (!mounted) return;
    // Une seule source de vérité pour les deux emplacements : la Bibliothèque
    // lit ce même notificateur, donc la pastille suit sans pouvoir contredire.
    BymUpdateChecker.available.value = check.hasUpdate ? check : null;
    setState(() {
      _busy = false;
      _updateMessage = check.hasUpdate ? null : check.status.message;
    });
  }

  /// Télécharge, convertit et installe les livres annoncés. Rien n'est écrit
  /// tant que tous ne sont pas vérifiés.
  Future<void> _applyUpdate(BymUpdateCheck plan) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _updateMessage = null;
      _updateProgress = BymUpdateProgress(done: 0, total: plan.bookCount);
    });
    final outcome = await _updates.apply(
      plan,
      onProgress: (progress) {
        if (mounted) setState(() => _updateProgress = progress);
      },
    );
    if (!mounted) return;
    if (outcome.applied) BymUpdateChecker.clear();
    setState(() {
      _busy = false;
      _updateProgress = null;
      _updateMessage = outcome.message;
    });
    await _load();
  }

  Future<void> _revertToEmbedded() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revenir au texte embarqué ?'),
        content: const Text(
          'Les livres corrigés téléchargés seront supprimés et le texte livré '
          'avec l’application reprendra sa place. Vos notes, surlignages et '
          'favoris ne sont pas touchés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revenir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _updates.revertToEmbedded();
    // La correction redevient « disponible » à l'instant même, mais la
    // reproposer ici serait harceler quelqu'un qui vient de la refuser. La
    // prochaine vérification (24 h) la remontera d'elle-même.
    BymUpdateChecker.clear();
    if (!mounted) return;
    setState(() => _updateMessage = 'Texte embarqué rétabli.');
    await _load();
  }

  /// La section « MISE À JOUR DU TEXTE », qui suit [BymUpdateChecker.available].
  Widget _updateSection() {
    final installedCommit = BymUpdateStore.installedCommit;
    final count = BymUpdateStore.updatedCount;

    final String stateLine;
    if (_textDate == null) {
      stateLine = 'Date indéterminée';
    } else if (installedCommit == null) {
      stateLine = 'Texte du ${_dayMonthYear(_textDate!)} · embarqué dans '
          'l’application';
    } else {
      stateLine = [
        'Texte du ${_dayMonthYear(_textDate!)}',
        '$count livre${count > 1 ? 's' : ''} corrigé${count > 1 ? 's' : ''}',
        if (_updateBytes > 0) _formatBytes(_updateBytes),
      ].join(' · ');
    }

    return ValueListenableBuilder<BymUpdateCheck?>(
      valueListenable: BymUpdateChecker.available,
      builder: (context, plan, _) => _SettingsCard(
        children: [
          _SettingsRow(
            icon: Icons.article_outlined,
            title: 'Texte BYM installé',
            subtitle: stateLine,
          ),
          _Divider(),
          _SettingsRow(
            icon: plan == null
                ? Icons.cloud_sync_outlined
                : Icons.download_for_offline_outlined,
            title: _busy && _updateProgress != null
                ? 'Mise à jour en cours…'
                : plan == null
                    ? 'Vérifier les mises à jour'
                    : 'Mettre à jour (${plan.bookLabel})',
            subtitle: _updateSubtitle(plan),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(plan == null ? Icons.refresh : Icons.download),
            onTap: _busy
                ? null
                : plan == null
                    ? _checkUpdates
                    : () => _applyUpdate(plan),
            below: _updateBelow(),
          ),
          if (installedCommit != null) ...[
            _Divider(),
            _SettingsRow(
              icon: Icons.settings_backup_restore,
              title: 'Revenir au texte embarqué',
              subtitle: 'Supprime les livres corrigés téléchargés',
              onTap: _busy ? null : _revertToEmbedded,
            ),
          ],
        ],
      ),
    );
  }

  String? _updateSubtitle(BymUpdateCheck? plan) {
    if (_busy && _updateProgress != null) return null;
    if (plan == null) {
      return _updateMessage ?? 'Corrections du texte publiées depuis la source';
    }
    // Les notes sont les titres des commits amont : le lecteur voit ce qui a
    // réellement changé. Une seule ligne ici, pour ne pas faire enfler la
    // rangée — les autres sont comptées.
    final lines = plan.notes.split('\n').where((l) => l.isNotEmpty).toList();
    final date = plan.committedAt == null
        ? null
        : 'Modifié le ${_dayMonthYear(plan.committedAt!)}';
    if (lines.isEmpty) return date;
    if (lines.length == 1) return lines.first;
    return '${lines.first} · +${lines.length - 1} autre'
        '${lines.length > 2 ? 's' : ''}';
  }

  /// La barre pendant l'installation, avec son bouton d'abandon. Un abandon ne
  /// laisse rien derrière lui : la zone de transit est jetée.
  Widget? _updateBelow() {
    final progress = _updateProgress;
    if (progress == null) return null;
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              key: const Key('bymUpdateProgress'),
              value: progress.fraction,
              minHeight: 6,
              color: p.primary,
              backgroundColor: p.primarySoft,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${progress.done}/${progress.total} livres'
                  '${progress.current == null ? '' : ' · ${progress.current}'}',
                  style: premiumText(context, 12, FontWeight.w500, p.textGrey),
                ),
              ),
              TextButton(
                onPressed: _updates.cancel,
                child: Text(
                  'Annuler',
                  style: premiumText(context, 13, FontWeight.w700, p.primary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
          'Réglages',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _prefs == null
            // Même façonnage que les rangées qui arrivent (pastille + titre),
            // sous les mêmes marges que la liste réelle.
            ? const ListLoadingSkeleton(
                itemCount: 8,
                padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _SectionBadge('LECTURE'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsRow(
                        icon: Icons.menu_book_outlined,
                        title: 'Version par défaut',
                        subtitle: _versionLabel(_p.versionCode),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickDefaultVersion,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.format_size,
                        title: 'Taille du texte',
                        below: _SizePicker(
                          current: ReadingTextSize.nearest(_p.fontSize),
                          onChanged: (size) {
                            setState(() => _p.fontSize = size.fontSize);
                            _save();
                          },
                        ),
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.font_download_outlined,
                        title: 'Police de lecture',
                        subtitle: _p.readingFont.label,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _pickReadingFont,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.format_align_justify,
                        title: 'Alignement',
                        trailing: _AlignPicker(
                          current: _p.textAlign,
                          onChanged: (align) {
                            setState(() => _p.textAlign = align);
                            _save();
                          },
                        ),
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.note_alt_outlined,
                        title: 'Notes',
                        subtitle: _p.notesMode ? 'Texte + notes' : 'Texte seul',
                        trailing: Switch(
                          value: _p.notesMode,
                          onChanged: (value) {
                            setState(() => _p.notesMode = value);
                            _save();
                          },
                        ),
                      ),
                      if (_p.notesMode) ...[
                        _Divider(),
                        _SettingsRow(
                          icon: Icons.view_headline,
                          title: 'Disposition des notes',
                          trailing: _DispositionPicker(
                            current: _p.disposition,
                            onChanged: (value) {
                              setState(() => _p.disposition = value);
                              _save();
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionBadge('APPARENCE'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsRow(
                        icon: Icons.palette_outlined,
                        title: 'Thème de lecture',
                        subtitle: themeById(_p.themeId).name,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ThemesScreen(),
                            ),
                          );
                          if (mounted) await _load();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionBadge('DONNÉES'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      if (_installed.isNotEmpty) ...[
                        _SettingsRow(
                          icon: Icons.storage_outlined,
                          title: 'Versions téléchargées',
                          subtitle:
                              '${_formatBytes(_sizes['_total'] ?? 0)} '
                              'sur l’appareil',
                        ),
                        _Divider(),
                        for (final entry in _installed.entries) ...[
                          _SettingsRow(
                            icon: Icons.folder_outlined,
                            title: versionByCode(entry.key)?.name ?? entry.key,
                            subtitle:
                                '${entry.value.bookCount}/66 livres · '
                                '${_formatBytes(_sizes[entry.key] ?? 0)}',
                          ),
                          if (entry.key != _installed.keys.last) _Divider(),
                        ],
                      ],
                      if (_installed.isEmpty) ...[
                        _SettingsRow(
                          icon: Icons.storage_outlined,
                          title: 'Versions téléchargées',
                          subtitle: 'Aucune — tout est embarqué',
                        ),
                      ],
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.cleaning_services_outlined,
                        title: 'Vider le cache',
                        subtitle: 'Relit les textes depuis le disque',
                        onTap: _clearCache,
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.history,
                        title: 'Effacer l’historique',
                        subtitle: 'Chapitres récemment ouverts',
                        onTap: _clearHistory,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SectionBadge('MISE À JOUR DU TEXTE'),
                  const SizedBox(height: 10),
                  _updateSection(),
                  const SizedBox(height: 18),
                  _SectionBadge('À PROPOS'),
                  const SizedBox(height: 10),
                  _SettingsCard(
                    children: [
                      _SettingsRow(
                        icon: Icons.menu_book,
                        title: 'BYM — Bible de Yehoshoua Ha Mashiah',
                        // Version de l'application, pas du texte : les deux
                        // évoluent séparément, et c'est tout l'intérêt du
                        // système de mise à jour. La section ci-dessus dit la
                        // version du texte.
                        subtitle: 'Application $appVersion',
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.translate,
                        title: 'Textes embarqués',
                        subtitle: 'BYM · Segond 1910 + Strongs (LSGS)',
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.import_contacts_outlined,
                        title: 'Dictionnaires & lexiques',
                        subtitle:
                            'Westphal 1932 · Strong français '
                            '(CrossWire/SWORD)',
                      ),
                      _Divider(),
                      _SettingsRow(
                        icon: Icons.cloud_outlined,
                        title: 'Versions téléchargeables',
                        subtitle: 'getbible.net · catalogue configurable',
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  /// "BYM" / "LSG" — the code, except when only a readable name exists.
  String _versionLabel(String code) {
    final entry = versionByCode(code);
    return entry?.name ?? code;
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
}

/// « 30/08/2026 » — la date d'une publication de texte, sans l'heure : elle ne
/// dit rien d'utile ici, contrairement à l'export de notes.
String _dayMonthYear(DateTime when) =>
    '${when.day.toString().padLeft(2, '0')}/'
    '${when.month.toString().padLeft(2, '0')}/${when.year}';

class _SectionBadge extends StatelessWidget {
  final String label;
  const _SectionBadge(this.label);

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Text(
      label,
      style: premiumText(
        context,
        11,
        FontWeight.w800,
        p.textGrey,
        spacing: 1.2,
      ),
    );
  }
}

/// A white rounded card holding a column of rows (maquette premium).
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: 0.06,
          blur: 14,
          offset: const Offset(0, 6),
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Contenu affiché sur sa propre ligne SOUS la rangée, à largeur bornée.
  /// Les pickers trop larges pour un `trailing` (les 6 tailles de texte)
  /// passent par là : dans la Row, un enfant non-flex reçoit une largeur
  /// infinie, le Wrap tient tout sur une ligne et la carte déborde sur les
  /// écrans étroits.
  final Widget? below;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: p.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 20, color: p.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: premiumText(
                          context,
                          14,
                          FontWeight.w700,
                          p.textDark,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: premiumText(
                            context,
                            12,
                            FontWeight.w500,
                            p.textGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
            if (below != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 50),
                child: below!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 66),
      child: Divider(height: 1, color: Colors.black.withValues(alpha: .06)),
    );
  }
}

/// One of the six reading sizes, as a compact selectable chip.
class _SizePicker extends StatelessWidget {
  final ReadingTextSize current;
  final ValueChanged<ReadingTextSize> onChanged;

  const _SizePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final size in ReadingTextSize.values)
          _OptionChip(
            label: 'A',
            selected: size == current,
            tooltip: 'Texte ${size.label}',
            fontSize: size.fontSize > 24 ? 24 : size.fontSize,
            onTap: () => onChanged(size),
          ),
      ],
    );
  }
}

/// The four text alignments, as selectable chips.
class _AlignPicker extends StatelessWidget {
  final ReadingTextAlign current;
  final ValueChanged<ReadingTextAlign> onChanged;

  const _AlignPicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final align in ReadingTextAlign.values)
          _OptionChip(
            label: _alignIcon(align),
            selected: align == current,
            tooltip: 'Aligner ${align.label}',
            onTap: () => onChanged(align),
          ),
      ],
    );
  }

  String _alignIcon(ReadingTextAlign align) => switch (align) {
    ReadingTextAlign.left => '⇤',
    ReadingTextAlign.center => '≡',
    ReadingTextAlign.right => '⇥',
    ReadingTextAlign.justify => '☰',
  };
}

/// The two note dispositions, as selectable chips.
class _DispositionPicker extends StatelessWidget {
  final NoteDisposition current;
  final ValueChanged<NoteDisposition> onChanged;

  const _DispositionPicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _OptionChip(
          label: 'Suite',
          selected: current == NoteDisposition.inline,
          tooltip: 'Notes à la suite',
          onTap: () => onChanged(NoteDisposition.inline),
        ),
        _OptionChip(
          label: 'Sous',
          selected: current == NoteDisposition.below,
          tooltip: 'Notes sous le verset',
          onTap: () => onChanged(NoteDisposition.below),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final String tooltip;
  final double? fontSize;
  final VoidCallback onTap;

  const _OptionChip({
    required this.label,
    required this.selected,
    required this.tooltip,
    required this.onTap,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: selected ? accent.withValues(alpha: .15) : null,
            border: Border.all(
              color: selected ? accent : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize ?? 13,
              color: selected ? accent : theme.colorScheme.onSurface,
              fontWeight: selected ? FontWeight.bold : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One version of the default-version picker: pastille of the code, name,
/// licence, and a check when selected.
class _VersionOption extends StatelessWidget {
  final VersionEntry version;
  final bool selected;
  final String? installedLine;
  final VoidCallback onTap;

  const _VersionOption({
    required this.version,
    required this.selected,
    required this.onTap,
    this.installedLine,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? p.primarySoft
                    : p.primarySoft.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                version.code,
                style: premiumText(
                  context,
                  11,
                  FontWeight.w800,
                  p.primary,
                  spacing: .3,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    version.name,
                    style: premiumText(
                      context,
                      14,
                      FontWeight.w700,
                      p.textDark,
                    ),
                  ),
                  Text(
                    installedLine ?? version.rights,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w500,
                      p.textGrey,
                    ),
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: p.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
