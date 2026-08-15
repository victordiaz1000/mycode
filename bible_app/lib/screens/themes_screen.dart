import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/theme_catalog.dart';
import '../widgets/bible_theme_scope.dart';

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
    // ensure the scope is referenced so its `of` method isn't flagged unused
    final _ = BibleThemeScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Thèmes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Choisis un thème de lecture : palette + fond.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 16),
          Text(
            'Thèmes nommés',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: bibleThemes.where((t) => t.name != 'REMOVED').map((theme) {
              final selected = theme.id == _selectedThemeId;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // small rectangular preview showing palette
                    Container(
                      width: 36,
                      height: 20,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.accentColor, theme.textColor],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.black12, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Aa',
                        style: TextStyle(
                          color: theme.titleColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.accentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(theme.name),
                  ],
                ),
                avatar: selected ? const Icon(Icons.check, size: 18) : null,
                selected: selected,
                onSelected: (_) => _saveTheme(theme.id),
                selectedColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withAlpha(220),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text(
            'Les thèmes nommés appliquent une palette complète. Seuls les noms sont affichés.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // Image preloading removed — previews are not displayed anymore.
}
