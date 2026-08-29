import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_preferences.dart';
import '../data/custom_background.dart';
import '../data/theme_catalog.dart';
import '../widgets/premium_style.dart';

/// Ordre d'affichage des thèmes dans la grille : les familles proches (gris,
/// beiges, bruns) sont intercalées pour qu'aucun voisin — côte à côte ou juste
/// au-dessus — ne soit de la même famille. `bibleThemes` reste l'ordre canonique
/// (son premier élément est le thème de secours) ; seul l'affichage est réordonné.
List<BibleTheme> _displayThemes() {
  const order = [
    'azur',
    'forest',
    'minimal',
    'sepia',
    'oliveraie',
    'metal',
    'parchemin',
    'vitrail',
    'desert',
    'papyrus',
    'sinai',
    'nuit',
  ];
  return [for (final id in order) themeById(id)];
}

class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  // Synchronisé dès le départ via le notifier (qui porte le défaut « forest »)
  // : partir sur bibleThemes.first faisait flotter une coche erronée pendant
  // le chargement des préférences — et, depuis que le défaut n'est plus le
  // premier thème du catalogue, une transition visible en pleine frame.
  String _selectedThemeId = AppPreferences.themeNotifier.value;
  double _panelOpacity = .80;
  bool _customBusy = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await AppPreferences.load();
    if (!mounted) return;
    setState(() {
      _selectedThemeId = prefs.themeId;
      _panelOpacity = prefs.panelOpacity;
    });
  }

  Future<void> _saveTheme(String id) async {
    final prefs = await AppPreferences.load();
    // A new theme means a new background: the panel opacity was dialled for
    // the previous one and would fight this one. Reset to the default on an
    // actual change — re-tapping the current theme keeps the dial.
    final changed = prefs.themeId != id;
    prefs.themeId = id;
    if (changed) {
      prefs.panelOpacity = .80;
      prefs.textColorOverride = null;
    }
    await prefs.save();
    if (!mounted) return;
    setState(() {
      _selectedThemeId = id;
      if (changed) _panelOpacity = .80;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Thème enregistré')));
  }

  Future<void> _pickCustomPhoto() async {
    if (_customBusy) return;
    setState(() => _customBusy = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked != null) {
        final json = await CustomBackgroundStore.install(picked.path);
        final prefs = await AppPreferences.load();
        prefs.themeId = customThemeId;
        // New picture, new background: same reset rule as the named themes.
        prefs.panelOpacity = .80;
        prefs.textColorOverride = null;
        // The slot first, then the broadcast: `themeById('custom')` must
        // resolve when the notifier wakes main.dart.
        await prefs.saveCustomTheme(json);
        await prefs.save();
        if (!mounted) return;
        setState(() {
          _selectedThemeId = customThemeId;
          _panelOpacity = .80;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fond personnalisé appliqué')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de charger la photo')),
      );
    } finally {
      if (mounted) setState(() => _customBusy = false);
    }
  }

  Future<void> _deleteCustomPhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Supprimer le fond personnalisé ?'),
        content: const Text(
          'La photo est retirée de l\'application. Le thème courant '
          'revient au thème par défaut.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CustomBackgroundStore.delete();
    final prefs = await AppPreferences.load();
    prefs.themeId = bibleThemes.first.id;
    prefs.panelOpacity = .80;
    prefs.textColorOverride = null;
    await prefs.saveCustomTheme(null);
    await prefs.save();
    if (!mounted) return;
    setState(() {
      _selectedThemeId = prefs.themeId;
      _panelOpacity = .80;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fond personnalisé supprimé')));
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    // Grille responsive : 2 colonnes sur téléphone, 3 sur tablette, 4 sur
    // grand écran. La hauteur des cartes suit, pour garder la proportion du
    // bandeau d'aperçu.
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 900 ? 4 : width >= 600 ? 3 : 2;
    final extent = width >= 900 ? 152.0 : width >= 600 ? 140.0 : 118.0;
    final custom = CustomBackgroundStore.current;
    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Thèmes',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              'Choisis un thème de lecture : palette + fond.',
              style: premiumText(context, 15, FontWeight.w600, p.textDark),
            ),
            const SizedBox(height: 18),
            Text(
              'THÈMES NOMMÉS',
              style: premiumText(
                context,
                11,
                FontWeight.w800,
                p.textGrey,
                spacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            GridView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: extent,
              ),
              children: [
                for (final theme in _displayThemes())
                  _ThemeCard(
                    theme: theme,
                    selected: theme.id == _selectedThemeId,
                    panelOpacity: _panelOpacity,
                    onTap: () => _saveTheme(theme.id),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Les thèmes nommés appliquent une palette complète. Seuls les noms '
              'sont affichés.',
              style: premiumText(
                context,
                12,
                FontWeight.w500,
                p.textGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'FOND PERSONNALISÉ',
              style: premiumText(
                context,
                11,
                FontWeight.w800,
                p.textGrey,
                spacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            _CustomBackgroundCard(
              theme: custom,
              selected: _selectedThemeId == customThemeId,
              panelOpacity: _panelOpacity,
              busy: _customBusy,
              onPick: _pickCustomPhoto,
              onSelect: custom == null ? null : () => _saveTheme(customThemeId),
              onDelete: custom == null ? null : _deleteCustomPhoto,
            ),
            const SizedBox(height: 8),
            Text(
              'Choisis une photo de la galerie : la palette s\'adapte à sa '
              'luminosité (texte clair sur photo sombre, texte foncé sur photo '
              'claire).',
              style: premiumText(
                context,
                12,
                FontWeight.w500,
                p.textGrey,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Carte d'un thème : le bandeau d'aperçu est une **mini-lecture fidèle** —
/// le vrai fond (tuilé ou couvrant selon le thème) sous le même voile que le
/// lecteur, avec le panneau semi-transparent et ses couleurs (« Aa » = corps,
/// numéro = chiffre de verset). Ce qui est choisi à l'écran est donc ce que
/// la lecture affichera, au lieu du dégradé approximatif d'avant.
class _ThemeCard extends StatelessWidget {
  final BibleTheme theme;
  final bool selected;
  final double panelOpacity;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.panelOpacity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? p.primary : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.06,
            blur: 14,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bandeau aperçu = mini-lecture — s'étire sur la hauteur restante.
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          image: theme.decorationImage(),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: _MiniReadingPanel(
                        theme: theme,
                        panelOpacity: panelOpacity,
                      ),
                    ),
                    if (selected)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: p.surface,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(Icons.check, size: 16, color: p.primary),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.accentColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        theme.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                          context,
                          13.5,
                          FontWeight.w700,
                          selected ? p.primary : p.textDark,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The reading panel in miniature: same rounded box, same derived colors,
/// same opacity dial as the reader — « 12 Aa » (verse number + body sample).
class _MiniReadingPanel extends StatelessWidget {
  final BibleTheme theme;
  final double panelOpacity;

  const _MiniReadingPanel({required this.theme, required this.panelOpacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: theme.readingPanelColor(panelOpacity),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.panelBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            '12',
            style: premiumText(context, 10.5, FontWeight.w700,
                theme.verseNumColor),
          ),
          const SizedBox(width: 6),
          Text(
            'Aa',
            style: premiumText(context, 17, FontWeight.w700, theme.textColor),
          ),
        ],
      ),
    );
  }
}

/// The « FOND PERSONNALISÉ » row: a pick card when no photo is installed,
/// else the photo's mini-reading preview with select + delete.
class _CustomBackgroundCard extends StatelessWidget {
  final BibleTheme? theme;
  final bool selected;
  final double panelOpacity;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback? onSelect;
  final VoidCallback? onDelete;

  const _CustomBackgroundCard({
    required this.theme,
    required this.selected,
    required this.panelOpacity,
    required this.busy,
    required this.onPick,
    this.onSelect,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final t = theme;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? p.primary : p.primary.withValues(alpha: .25),
            width: 1.5,
          ),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.06,
            blur: 14,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: t == null ? onPick : onSelect,
          child: t == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 22, color: p.primary),
                      const SizedBox(width: 10),
                      Text(
                        busy ? 'Chargement de la photo…' : 'Choisir une photo',
                        style: premiumText(
                          context,
                          14,
                          FontWeight.w700,
                          p.primary,
                        ),
                      ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    // Aperçu mini-lecture, même construction que les cartes.
                    Container(
                      width: 96,
                      height: 88,
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        image: t.decorationImage(),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: _MiniReadingPanel(
                        theme: t,
                        panelOpacity: panelOpacity,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: t.accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  t.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: premiumText(
                                    context,
                                    14,
                                    FontWeight.w700,
                                    selected ? p.primary : p.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selected
                                ? 'Thème actif — toucher pour confirmer'
                                : 'Toucher pour appliquer',
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
                    if (onDelete != null)
                      IconButton(
                        tooltip: 'Supprimer le fond personnalisé',
                        icon: const Icon(Icons.delete_outline),
                        color: p.textGrey,
                        onPressed: onDelete,
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
        ),
      ),
    );
  }
}
