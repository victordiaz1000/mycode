import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/theme_catalog.dart';
import '../widgets/premium_style.dart';

class ThemesScreen extends StatefulWidget {
  const ThemesScreen({super.key});

  @override
  State<ThemesScreen> createState() => _ThemesScreenState();
}

class _ThemesScreenState extends State<ThemesScreen> {
  String _selectedThemeId = bibleThemes.first.id;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await AppPreferences.load();
    if (!mounted) return;
    setState(() => _selectedThemeId = prefs.themeId);
  }

  Future<void> _saveTheme(String id) async {
    final prefs = await AppPreferences.load();
    prefs.themeId = id;
    await prefs.save();
    if (!mounted) return;
    setState(() => _selectedThemeId = id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thème enregistré')),
    );
  }

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
          'Thèmes',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Choisis un thème de lecture : palette + fond.',
            style: premiumText(context, 15, FontWeight.w600, p.textDark),
          ),
          const SizedBox(height: 18),
          Text(
            'THÈMES NOMMÉS',
            style: premiumText(context, 11, FontWeight.w800, p.textGrey, spacing: 1.1),
          ),
          const SizedBox(height: 12),
          Column(
            children: bibleThemes.where((t) => t.name != 'REMOVED').map((theme) {
              final selected = theme.id == _selectedThemeId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ThemeCard(
                  theme: theme,
                  selected: selected,
                  onTap: () => _saveTheme(theme.id),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            'Les thèmes nommés appliquent une palette complète. Seuls les noms '
            'sont affichés.',
            style: premiumText(context, 12, FontWeight.w500, p.textGrey, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Carte premium d'un thème : aperçu de la palette (dégradé accent → texte,
/// « Aa » dans la couleur de titre), pastille d'accent et nom. La sélection se
/// marque d'un liseré d'accent et d'une coche.
class _ThemeCard extends StatelessWidget {
  final BibleTheme theme;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 32,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [theme.accentColor, theme.textColor],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Aa',
                    style: TextStyle(
                      color: theme.titleColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: theme.accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    theme.name,
                    style: premiumText(
                      context,
                      15,
                      FontWeight.w700,
                      selected ? p.primary : p.textDark,
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: p.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.check, size: 18, color: p.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}