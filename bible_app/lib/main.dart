import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/bym_update_service.dart';
import 'data/bym_update_store.dart';
import 'data/share_text.dart';
import 'data/tab_manager.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/bible_theme_scope.dart';
import 'widgets/chapter_reader.dart';
import 'widgets/loading_skeleton.dart';
import 'widgets/responsive_text_scaling.dart';
import 'data/app_preferences.dart';
import 'data/theme_catalog.dart';
import 'widgets/premium_style.dart';

void main() {
  runApp(const BymApp());
}

class BymApp extends StatefulWidget {
  const BymApp({super.key});
  @override
  State<BymApp> createState() => _BymAppState();
}

class _BymAppState extends State<BymApp> with WidgetsBindingObserver {
  /// Chargement du registre, gardé pour que la vérification au retour au premier
  /// plan ne puisse pas le devancer : `referenceIndex()` lit
  /// `BymUpdateStore.installedBlobs`, garni par `load()`, et une comparaison
  /// faite trop tôt reproposerait des livres déjà installés.
  late final Future<void> _storeReady;

  @override
  void initState() {
    super.initState();
    AppPreferences.load();
    // Le registre des livres mis à jour d'abord : `LocalRepository.loadBook`
    // interroge `BymUpdateStore.hasUpdate` de façon **synchrone**, donc
    // l'ensemble doit être garni avant le premier livre ouvert — sinon le
    // premier chapitre affiché serait celui de l'APK malgré la correction.
    //
    // La vérification qui suit ne télécharge que le manifest (2 Ko) et ne lève
    // jamais : hors ligne, le démarrage reste silencieux. Aucun livre n'arrive
    // sans un appui de l'utilisateur dans Réglages.
    _storeReady = BymUpdateStore.load();
    _storeReady.then((_) => BymUpdateChecker.maybeCheck());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Seconde occasion de vérifier, et la seule qui rende les 24 h effectives.
  ///
  /// `initState` ne s'exécute qu'au **démarrage à froid** du processus. Android
  /// garde volontiers une application en mémoire pendant des jours : sans ce
  /// crochet, un lecteur qui ne ferme jamais BYM ne verrait jamais une
  /// correction, quel que soit l'intervalle réglé.
  ///
  /// Le plafond d'une vérification par [BymUpdateService.checkInterval] reste
  /// dans `maybeCheck`, donc revenir dix fois dans la journée ne coûte que dix
  /// lectures de préférence : ce crochet ajoute des *occasions* de constater que
  /// le délai est écoulé, pas des requêtes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    _storeReady.then((_) => BymUpdateChecker.maybeCheck());
  }

  @override
  Widget build(BuildContext context) {
    const shell = HomeShell();
    return ValueListenableBuilder<String>(
      valueListenable: AppPreferences.themeNotifier,
      builder: (context, themeId, _) {
        final bt = themeById(themeId);
        final appBackground = bt.usesLightText
            ? Color.lerp(bt.backgroundTone, Colors.black, .55)!
            : Color.lerp(bt.backgroundTone, Colors.white, .72)!;
        final appSurface = bt.usesLightText
            ? Color.lerp(bt.backgroundTone, Colors.black, .42)!
            : Color.lerp(bt.backgroundTone, Colors.white, .58)!;
        final colorScheme =
            ColorScheme.fromSeed(
              seedColor: bt.accentColor,
              brightness: bt.usesLightText ? Brightness.dark : Brightness.light,
            ).copyWith(
              surface: appSurface,
              surfaceContainer: appSurface,
              surfaceContainerHighest: bt.panelColor,
              onSurface: bt.textColor,
            );
        // La base suit la luminosité du thème : le thème Azur (texte clair)
        // part d'un `ThemeData.dark` pour que les widgets Material nus (chips,
        // boutons…) héritent de surfaces sombres et de textes clairs. Partir
        // toujours de `light` laissait leurs défauts clairs (texte blanc sur
        // chip blanche dans la feuille d'étude, etc.).
        final base = bt.usesLightText
            ? ThemeData.dark(useMaterial3: true)
            : ThemeData.light(useMaterial3: true);
        final theme = base.copyWith(
          colorScheme: colorScheme,
          scaffoldBackgroundColor: appBackground,
          textTheme: base.textTheme.apply(
            bodyColor: bt.textColor,
            displayColor: bt.titleColor,
          ),
          appBarTheme: base.appBarTheme.copyWith(
            backgroundColor: bt.highlightRef.withAlpha((0.06 * 255).round()),
            foregroundColor: bt.titleColor,
          ),
          cardTheme: CardThemeData(
            color: appSurface,
            surfaceTintColor: Colors.transparent,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: appSurface,
            surfaceTintColor: Colors.transparent,
          ),
          bottomSheetTheme: BottomSheetThemeData(
            backgroundColor: appSurface,
            modalBackgroundColor: appSurface,
            surfaceTintColor: Colors.transparent,
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: appSurface,
            surfaceTintColor: Colors.transparent,
            textStyle: TextStyle(color: bt.textColor),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: bt.panelColor,
            hintStyle: TextStyle(color: bt.noteColor),
          ),
          listTileTheme: ListTileThemeData(
            textColor: bt.textColor,
            iconColor: bt.accentColor,
          ),
          dividerTheme: DividerThemeData(color: bt.panelBorderColor),
          iconTheme: IconThemeData(color: bt.accentColor),
        );
        final systemIcons = bt.usesLightText
            ? Brightness.light
            : Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: systemIcons,
            systemNavigationBarColor: appBackground,
            systemNavigationBarIconBrightness: systemIcons,
            systemNavigationBarContrastEnforced: false,
          ),
          child: MaterialApp(
            title: appName,
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) {
              return ResponsiveTextScaling(
                // Le scope doit envelopper le Navigator, pas seulement la page
                // d'accueil : un écran poussé via Navigator.push est une route
                // sœur de `home`, donc hors d'un scope posé sur `home` — il
                // retomberait sur `bibleThemes.first` au lieu du thème choisi.
                child: BibleThemeScope(child: child!),
              );
            },
            home: shell,
          ),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const String _kDestinationKey = 'shell.destination';

  late final TabManager _manager;
  late final ValueNotifier<VerseTarget?> _jumpToVerse;

  /// Requête de recherche demandée depuis l'accueil (puce « Jean 3.16 ») :
  /// écrite ici, consommée par le [SearchScreen] — qui la remet à null.
  late final ValueNotifier<String?> _searchRequest;
  late final List<Widget?> _pageCache;
  int _index = BymDestination.accueil.index;

  @override
  void initState() {
    super.initState();
    _manager = TabManager();
    _jumpToVerse = ValueNotifier<VerseTarget?>(null);
    _searchRequest = ValueNotifier<String?>(null);
    _pageCache = List<Widget?>.filled(BymDestination.values.length, null);
    _ensurePage(_index);
    _restoreDestination();
    _manager.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  /// Reopens on the destination the user was on when the process died in the
  /// background, instead of always landing on the Accueil.
  Future<void> _restoreDestination() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_kDestinationKey);
      if (saved != null && saved >= 0 && saved < BymDestination.values.length) {
        if (mounted) {
          setState(() {
            _index = saved;
            _ensurePage(saved);
          });
        }
      }
    } catch (_) {
      // No preferences available → default to the Accueil.
    }
  }

  Future<void> _persistDestination(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kDestinationKey, index);
    } catch (_) {
      // Persisting the destination is best-effort.
    }
  }

  @override
  void dispose() {
    _jumpToVerse.dispose();
    _searchRequest.dispose();
    _manager.dispose();
    super.dispose();
  }

  void _selectDestination(BymDestination d) {
    setState(() {
      _index = d.index;
      _ensurePage(d.index);
    });
    _persistDestination(d.index);
  }

  void _openReading(int b, int c, {int? verse}) {
    // Le verset demandé suit la position JUSQUE DANS L'ONGLET : sans lui, un
    // onglet naît sans position et seul le rapporteur d'estimation du lecteur
    // (imprécis, basé sur le haut du viewport) enregistre où l'on devait se
    // trouver — la référence tapée ressuscitait alors ailleurs.
    _manager.openReading(b, c, verse: verse);
    _jumpToVerse.value = verse == null
        ? null
        : VerseTarget(bookIndex: b, chapter: c, verse: verse);
    setState(() {
      _index = BymDestination.lecture.index;
      _ensurePage(_index);
    });
    _persistDestination(BymDestination.lecture.index);
  }

  void _ensurePage(int index) {
    _pageCache[index] ??= switch (BymDestination.values[index]) {
      BymDestination.accueil => HomeScreen(
        manager: _manager,
        onSelectDestination: _selectDestination,
        onOpenReading: _openReading,
        onSearchQuery: (query) {
          // La page Recherche peut déjà exister dans la pile : le
          // notificateur atteint les deux cas (montée à neuf ou déjà vivante).
          _searchRequest.value = query;
          _selectDestination(BymDestination.recherche);
        },
      ),
      BymDestination.lecture => ReaderScreen(
        initialManager: _manager,
        jumpToVerse: _jumpToVerse,
        onOpenLibrary: () => _selectDestination(BymDestination.bibliotheque),
        onOpenVerse: (b, c, v) => _openReading(b, c, verse: v),
        // Le bandeau défilant de la lecture n'installe rien non plus : comme la
        // pastille de la Bibliothèque, il conduit à Réglages.
        onOpenSettings: () => _selectDestination(BymDestination.reglages),
      ),
      BymDestination.recherche => SearchScreen(
        onOpenReading: _openReading,
        onOpenLibrary: () => _selectDestination(BymDestination.bibliotheque),
        request: _searchRequest,
      ),
      BymDestination.bibliotheque => LibraryScreen(
        onOpenVerse: (b, c, v) => _openReading(b, c, verse: v),
        // La pastille « MàJ » de la tuile BYM n'installe rien : elle conduit à
        // la section de Réglages, seul endroit qui décide d'un téléchargement.
        onOpenSettings: () => _selectDestination(BymDestination.reglages),
      ),
      BymDestination.reglages => const SettingsScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = width >= 600;
    // Immersion (reading) removes the navigation chrome: the reader shows its
    // own exit pill, and this shell hides rail and bottom bar while it lasts.
    return ValueListenableBuilder<bool>(
      valueListenable: AppPreferences.immersionNotifier,
      builder: (context, immersive, _) {
        final content = IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _pageCache.length; i++)
              _pageCache[i] == null
                  ? const SizedBox.shrink()
                  : InterfaceLoadingGate(
                      key: ValueKey('interface-gate-$i'),
                      variant: i,
                      child: _pageCache[i]!,
                    ),
          ],
        );
        return Scaffold(
          body: tablet
              ? Row(
                  children: [
                    if (!immersive) _buildNavigationRail(context, width),
                    Expanded(child: content),
                  ],
                )
              : content,
          bottomNavigationBar:
              tablet || immersive ? null : _buildNavigationBar(context),
        );
      },
    );
  }

  Widget _buildNavigationRail(BuildContext context, double width) {
    final p = premiumPalette(context);
    return NavigationRail(
      scrollable: true,
      selectedIndex: _index,
      onDestinationSelected: (i) {
        if (i < 0 || i >= BymDestination.values.length) return;
        setState(() {
          _index = i;
          _ensurePage(i);
        });
        _persistDestination(i);
      },
      extended: width >= 840,
      labelType: width >= 840
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      backgroundColor: p.surface,
      leading: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Icon(Icons.menu_book_rounded, color: p.primary, size: 26),
      ),
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: Text('Accueil'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: Text('Lecture'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.search_outlined),
          selectedIcon: Icon(Icons.search),
          label: Text('Recherche'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.download_outlined),
          selectedIcon: Icon(Icons.download),
          label: Text('Bibliothèque'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Réglages'),
        ),
      ],
    );
  }

  Widget _buildNavigationBar(BuildContext context) {
    final p = premiumPalette(context);
    TextStyle labelStyle(bool selected) => TextStyle(
      fontFamily: kUiFontFamily,
      fontSize: 11.5,
      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      letterSpacing: selected ? .2 : 0,
      color: selected ? p.primary : p.onSurfaceMuted,
    );
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(
          top: BorderSide(color: p.primary.withValues(alpha: .16)),
        ),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 68,
          labelBehavior: MediaQuery.sizeOf(context).width < 480
              ? NavigationDestinationLabelBehavior.alwaysHide
              : MediaQuery.sizeOf(context).width < 560
              ? NavigationDestinationLabelBehavior.onlyShowSelected
              : NavigationDestinationLabelBehavior.alwaysShow,
          elevation: 0,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: p.primarySoft,
          iconTheme: WidgetStateProperty.resolveWith(
            (states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? p.primary
                  : p.onSurfaceMuted,
            ),
          ),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => labelStyle(states.contains(WidgetState.selected)),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i < 0 || i >= BymDestination.values.length) return;
            setState(() {
              _index = i;
              _ensurePage(i);
            });
            _persistDestination(i);
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book),
              label: 'Lecture',
            ),
            const NavigationDestination(
              icon: Icon(Icons.search_outlined),
              selectedIcon: Icon(Icons.search),
              label: 'Recherche',
            ),
            const NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Bibliothèque',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Réglages',
            ),
          ],
        ),
      ),
    );
  }
}
