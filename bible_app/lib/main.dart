import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/tab_manager.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/chapter_reader.dart';
import 'data/app_preferences.dart';
import 'data/theme_catalog.dart';
import 'widgets/bible_theme_scope.dart';
import 'widgets/premium_style.dart';

/// Couleur neutre des destinations inactives de la barre de navigation.
const Color _navInactive = Color(0xFF9C9387);

void main() {
  runApp(BymApp());
}

class BymApp extends StatefulWidget {
  const BymApp({super.key});

  @override
  State<BymApp> createState() => _BymAppState();
}

class _BymAppState extends State<BymApp> {
  @override
  void initState() {
    super.initState();
    // Ensure AppPreferences notifier reflects stored value when app starts.
    AppPreferences.load();
  }

  @override
  Widget build(BuildContext context) {
    final shell = const HomeShell();
    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.themeNotifier,
      builder: (context, themeId, _) {
        final bt = themeById(themeId);
        final colorScheme = ColorScheme.fromSeed(seedColor: bt.accentColor);
        final base = ThemeData.light(useMaterial3: true);
        final theme = base.copyWith(
          colorScheme: colorScheme,
          textTheme: base.textTheme.apply(
            bodyColor: bt.textColor,
            displayColor: bt.titleColor,
          ),
          appBarTheme: base.appBarTheme.copyWith(
            backgroundColor: bt.highlightRef.withAlpha((0.06 * 255).round()),
            foregroundColor: bt.titleColor,
          ),
        );

        return MaterialApp(
          title: 'BYM — Bible de Yehoshoua Ha Mashiah',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: BibleThemeScope(child: shell),
        );
      },
    );
  }
}

/// Bottom navigation shell (maquette § 01): Accueil · Lecture · Recherche ·
/// Bibliothèque · Réglages. Owns the single app-wide [TabManager] so the gold
/// counter on the home screen matches the reading tabs.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final TabManager _manager;
  late final ValueNotifier<VerseTarget?> _jumpToVerse;
  int _index = BymDestination.accueil.index;

  @override
  void initState() {
    super.initState();
    _manager = TabManager();
    _manager.load().then((_) {
      if (mounted) setState(() {});
    });
    _jumpToVerse = ValueNotifier<VerseTarget?>(null);
  }

  @override
  void dispose() {
    _jumpToVerse.dispose();
    _manager.dispose();
    super.dispose();
  }

  void _selectDestination(BymDestination destination) {
    setState(() => _index = destination.index);
  }

  void _openReading(int bookIndex, int chapter, {int? verse}) {
    _manager.openReading(bookIndex, chapter);
    // Cleared when no verse is asked for: a stale target would otherwise be
    // replayed by the next chapter opened fresh (ChapterReader reads the
    // current value in initState).
    _jumpToVerse.value = verse == null
        ? null
        : VerseTarget(bookIndex: bookIndex, chapter: chapter, verse: verse);
    setState(() => _index = BymDestination.lecture.index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            manager: _manager,
            onSelectDestination: _selectDestination,
            onOpenReading: _openReading,
          ),
          ReaderScreen(
            initialManager: _manager,
            jumpToVerse: _jumpToVerse,
            onOpenLibrary: () =>
                _selectDestination(BymDestination.bibliotheque),
          ),
          SearchScreen(
            onOpenReading: _openReading,
            onOpenDictionary: (term, definition) {
              _manager.openDictionary(term, definition);
              _selectDestination(BymDestination.lecture);
            },
            onOpenLibrary: () =>
                _selectDestination(BymDestination.bibliotheque),
          ),
          LibraryScreen(
            onOpenVerse: (b, c, v) => _openReading(b, c, verse: v),
            onOpenDictionary: (term, definition) {
              _manager.openDictionary(term, definition);
              _selectDestination(BymDestination.lecture);
            },
          ),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildNavigationBar(context),
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    final p = premiumPalette(context);
    final family = GoogleFonts.plusJakartaSans().fontFamily;
    TextStyle labelStyle(bool selected) => TextStyle(
          fontFamily: family,
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          letterSpacing: selected ? .2 : 0,
          color: selected ? p.primary : _navInactive,
        );
    return Container(
      decoration: BoxDecoration(
        color: kPremiumBackground,
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: .06)),
        ),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 68,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: p.primarySoft,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? p.primary
                  : _navInactive,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => labelStyle(states.contains(WidgetState.selected)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Accueil'),
            NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: 'Lecture'),
            NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Recherche'),
            NavigationDestination(
                icon: Icon(Icons.download_outlined),
                selectedIcon: Icon(Icons.download),
                label: 'Bibliothèque'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Réglages'),
          ],
        ),
      ),
    );
  }
}
