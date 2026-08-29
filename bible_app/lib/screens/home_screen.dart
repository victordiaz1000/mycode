import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../data/reading_history.dart';
import '../data/tab_manager.dart';
import '../models/chapter.dart';
import '../utils/date_format.dart';
import '../widgets/bible_theme_scope.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import 'ecran_comparer.dart';
import 'favoris_screen.dart';
import 'historique_screen.dart';
import 'notes_screen.dart';
import 'themes_screen.dart';

/// Destinations of the bottom navigation bar (maquette § 01).
enum BymDestination { accueil, lecture, recherche, bibliotheque, reglages }

const Color bymGold = Color(0xFFD3A94F);

// ---- Palette (suit le thème actif) ----
class _Pal {
  final Color primary;
  final Color primaryDark;
  final Color primarySoft;
  final Color textDark;
  final Color textGrey;
  final LinearGradient heroGradient;

  const _Pal({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.textDark,
    required this.textGrey,
    required this.heroGradient,
  });
}

_Pal _pal(BuildContext context) {
  final bt = BibleThemeScope.of(context);
  final accent = bt.accentColor;
  return _Pal(
    primary: accent,
    primaryDark: Color.lerp(accent, Colors.black, 0.35)!,
    primarySoft: accent.withValues(alpha: 0.14),
    textDark: bt.titleColor,
    textGrey: bt.textColor.withValues(alpha: 0.62),
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(accent, Colors.white, 0.26)!,
        Color.lerp(accent, Colors.black, 0.30)!,
      ],
    ),
  );
}

List<BoxShadow> _softShadow(
  Color color, {
  double opacity = 0.08,
  double blur = 18,
  Offset offset = const Offset(0, 8),
}) => [
  BoxShadow(
    color: color.withValues(alpha: opacity),
    blurRadius: blur,
    offset: offset,
  ),
];

/// Raccourci local vers [premiumText] : l'Accueil l'appelle 40 fois, d'où le nom
/// court. Il redéfinissait auparavant le style à l'identique via google_fonts,
/// ce qui dupliquait la typographie de l'interface à deux endroits.
TextStyle _t(
  BuildContext context,
  double size,
  FontWeight weight,
  Color color, {
  double? spacing,
  double? height,
  FontStyle? italic,
}) => premiumText(
  context,
  size,
  weight,
  color,
  spacing: spacing,
  height: height,
  italic: italic,
);

// ---- Données statiques des sections ----
class _AlphabetCard {
  final String letter;
  final String glyph;
  final String title;
  final String subtitle;
  const _AlphabetCard(this.letter, this.glyph, this.title, this.subtitle);
}

const List<_AlphabetCard> _kAlphabets = [
  _AlphabetCard('Alèf', 'א', 'Lettres hébraïques', '26 consonnes'),
  _AlphabetCard('Alpha', 'α', 'Lettres grecques', '17 consonnes et 7 voyelles'),
];

const List<String> _kHistoryTopics = [
  "L'histoire biblique",
  "Le Nom d'Élohìm",
  "L'archéologie",
];

class _MeasureSectionData {
  final String badge;
  final String title;
  final IconData icon;
  final bool alignRight;
  final Color tintA;
  final Color tintB;
  final Color iconColor;
  const _MeasureSectionData({
    required this.badge,
    required this.title,
    required this.icon,
    required this.alignRight,
    required this.tintA,
    required this.tintB,
    required this.iconColor,
  });
}

const _MeasureSectionData _kCapacity = _MeasureSectionData(
  badge: 'MESURES DE CAPACITÉ',
  title: 'Mesures de capacité (solides et liquides) dans la Bible',
  icon: Icons.scale_rounded,
  alignRight: true,
  tintA: Color(0xFFF6EFE4),
  tintB: Color(0xFFEAD9C0),
  iconColor: Color(0xFFA9713B),
);

const _MeasureSectionData _kLength = _MeasureSectionData(
  badge: 'MESURES DE LONGUEUR',
  title: 'Mesures de longueur dans la Bible',
  icon: Icons.straighten_rounded,
  alignRight: false,
  tintA: Color(0xFFEFF4EA),
  tintB: Color(0xFFDCE8CC),
  iconColor: Color(0xFF37522A),
);

const List<String> _kConcilesCards = ["Pères de l'église", 'Conciles'];

class _TimeTopic {
  final String title;
  final String subtitle;
  final IconData icon;
  const _TimeTopic(this.title, this.subtitle, this.icon);
}

const List<_TimeTopic> _kTimeTopics = [
  _TimeTopic(
    'Les 7 fêtes de YHWH',
    "Les fêtes qu'Israël devait observer chaque année.",
    Icons.celebration_rounded,
  ),
  _TimeTopic(
    "Les mois de l'année",
    "L'origine des mois de notre calendrier.",
    Icons.calendar_month_rounded,
  ),
  _TimeTopic(
    'Les temps bibliques',
    'Les jours, mois et années chez les hébreux.',
    Icons.schedule_rounded,
  ),
];

/// The premium « Bym classic » home page (maquette `ecran_accueil.dart`) :
/// header, search, quick actions, a « Reprendre la lecture » hero card, the
/// recent studies and the discovery sections (alphabets, measures, conciles…).
///
/// It shares the app's [TabManager], so the gradient counter matches the
/// reading tabs and opening anything from here lands in the Lecture
/// destination. The static discovery sections respond « bientôt disponible »
/// until their screens exist.
class HomeScreen extends StatefulWidget {
  final TabManager manager;

  /// Switches the bottom navigation to another destination.
  final void Function(BymDestination destination) onSelectDestination;

  /// Opens a chapter (and optional verse) in the Lecture destination, with the
  /// verse-jump that the shell owns. Null outside the shell: falls back to
  /// [manager.openReading] without a verse target.
  final void Function(int bookIndex, int chapter, {int? verse})? onOpenReading;

  /// Lance une recherche depuis l'accueil (la puce « Jean 3.16 ») : le shell
  /// l'écrit dans le notificateur que [SearchScreen] écoute, puis bascule sur
  /// la destination Recherche. Null hors du shell.
  final ValueChanged<String>? onSearchQuery;

  /// Chargé en paresseux pour l'extrait de la carte « Reprendre la lecture ».
  final LocalRepository? repository;

  const HomeScreen({
    super.key,
    required this.manager,
    required this.onSelectDestination,
    this.onOpenReading,
    this.onSearchQuery,
    this.repository,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final LocalRepository _repository = widget.repository ?? LocalRepository();
  List<ReadingEntry> _recent = const [];
  bool _loading = true;
  int _concilesPage = 0;
  final PageController _concilesController = PageController(
    viewportFraction: 0.9,
  );

  @override
  void initState() {
    super.initState();
    widget.manager.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.manager.removeListener(_reload);
    _concilesController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final recent = await widget.manager.history.load();
    if (!mounted) return;
    setState(() {
      _recent = recent;
      _loading = false;
    });
  }

  void _openReading(int bookIndex, int chapter, {int? verse}) {
    final open = widget.onOpenReading;
    if (open != null) {
      open(bookIndex, chapter, verse: verse);
      return;
    }
    widget.manager.openReading(bookIndex, chapter);
    widget.onSelectDestination(BymDestination.lecture);
  }

  void _soon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — bientôt disponible.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openFavorites() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavorisScreen(
          onOpenVerse: (book, chapter, verse) {
            Navigator.of(context).pop();
            _openReading(book, chapter, verse: verse);
          },
        ),
      ),
    );
  }

  void _openNotes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotesScreen(
          onOpenVerse: (book, chapter, verse) {
            Navigator.of(context).pop();
            _openReading(book, chapter, verse: verse);
          },
        ),
      ),
    );
    // Live via AppDatabase.notesRevision — pas de rechargement explicite.
  }

  void _openCompare() {
    final resume = _recent.isEmpty ? null : _recent.first;
    // Sans historique : Genèse 1:1, un passage réel plutôt qu'un refus —
    // l'écran existe et sert n'importe quelle référence.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComparerScreen(
          bookIndex: resume?.bookIndex ?? 1,
          chapter: resume?.chapter ?? 1,
          // L'historique de lecture ne garde que le chapitre,
          // pas le verset : on compare depuis le début.
          verseNumber: 1,
        ),
      ),
    );
  }

  void _openTabs() {
    if (!widget.manager.hasTabs) widget.manager.openHome();
    widget.onSelectDestination(BymDestination.lecture);
  }

  /// « Tout voir » des études récentes : l'historique complet, filtrable.
  void _openHistorique() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoriqueScreen(
          onOpenReading: (book, chapter) {
            Navigator.of(context).pop();
            _openReading(book, chapter);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resume = _recent.isEmpty ? null : _recent.first;
    return ColoredBox(
      color: premiumBackground(context),
      child: SafeArea(
        child: Stack(
          children: [
            _backgroundDecor(context),
            ListView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
              children: [
                _header(context),
                const SizedBox(height: 24),
                _searchBar(context),
                const SizedBox(height: 24),
                _quickActions(context, resume),
                const SizedBox(height: 26),
                if (_loading)
                  const HomeLoadingSkeleton()
                else ...[
                  if (resume == null)
                    _emptyResume(context)
                  else
                    _heroCard(context, resume),
                  const SizedBox(height: 30),
                  _studiesHeader(context),
                  const SizedBox(height: 14),
                  ..._recentStudies(context),
                  const SizedBox(height: 30),
                ],
                _alphabetsSection(context),
                const SizedBox(height: 30),
                _historySection(context),
                const SizedBox(height: 30),
                _measureSection(context, _kCapacity),
                const SizedBox(height: 30),
                _measureSection(context, _kLength),
                const SizedBox(height: 30),
                _denominationsSection(context),
                const SizedBox(height: 30),
                _concilesSection(context),
                const SizedBox(height: 30),
                _emperorsSection(context),
                const SizedBox(height: 30),
                _falseGodsSection(context),
                const SizedBox(height: 30),
                _timeTopicsSection(context),
                const SizedBox(height: 30),
                _weekDaysSection(context),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Halos décoratifs en arrière-plan
  Widget _backgroundDecor(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Stack(
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: _glow(context, 260, const Color(0xFFDCE8CC)),
          ),
          Positioned(
            top: 150,
            left: -100,
            child: _glow(context, 220, const Color(0xFFF0E9DC)),
          ),
        ],
      ),
    );
  }

  Widget _glow(BuildContext context, double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.7), color.withValues(alpha: 0.0)],
        ),
      ),
    );
  }

  // En-tête
  Widget _header(BuildContext context) {
    final p = _pal(context);
    final compact = MediaQuery.sizeOf(context).width < 400;
    return Row(
      children: [
        // `Expanded` + `FittedBox` : le titre est la seule pièce élastique de
        // la barre (les deux boutons font 44 px chacun, plus leur écart). Sans
        // contrainte il débordait de 25 à 65 px sur les téléphones de 320, 360
        // et 412 px de large — 412 y passait aussi car au-delà de 400 px le
        // titre repasse à 32/24 pt, plus large que le gain de place.
        //
        // `Expanded` et non `Flexible` : la boîte du titre doit occuper TOUT
        // l'espace restant pour coller les deux boutons au bord droit, comme le
        // faisait la `Spacer` d'origine. Un `Flexible` se contente de la largeur
        // du texte et laisse le reliquat après le dernier enfant, ce qui décolle
        // les boutons du bord. Le `FittedBox` garde le titre à gauche de cette
        // boîte et ne le réduit que s'il n'entre pas.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 2, top: 4, bottom: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: ShaderMask(
                shaderCallback: (rect) => p.heroGradient.createShader(rect),
                child: RichText(
                  // `RichText` ne consulte pas le `MediaQuery` : sans ce
                  // scaler le titre ignorerait l'échelle de texte du système,
                  // là où le compteur d'onglets à sa droite la suit.
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Bym',
                        style: _t(
                          context,
                          compact ? 26 : 32,
                          FontWeight.w800,
                          Colors.white,
                          spacing: -0.5,
                        ),
                      ),
                      TextSpan(
                        text: ' classic',
                        style: _t(
                          context,
                          compact ? 19 : 24,
                          FontWeight.w300,
                          Colors.white,
                          spacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _Pressable(
          label: 'Thèmes',
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ThemesScreen())),
          child: _squareButton(context, Icons.palette_outlined),
        ),
        SizedBox(width: compact ? 6 : 12),
        _Pressable(
          label: 'Onglets ouverts : ${widget.manager.count}',
          onTap: _openTabs,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: p.heroGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _softShadow(
                p.primary,
                opacity: 0.35,
                blur: 12,
                offset: const Offset(0, 6),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '${widget.manager.count}',
              style: _t(context, 16, FontWeight.w800, Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _squareButton(
    BuildContext context,
    IconData icon,
  ) {
    final p = _pal(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: premiumPalette(context).surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.primary.withValues(alpha: 0.10)),
        boxShadow: _softShadow(p.primaryDark),
      ),
      child: Icon(icon, size: 22, color: p.primary),
    );
  }

  // Recherche
  Widget _searchBar(BuildContext context) {
    final p = _pal(context);
    return _Pressable(
      label: 'Rechercher un verset, un livre',
      onTap: () => widget.onSelectDestination(BymDestination.recherche),
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.primary.withValues(alpha: 0.12)),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.11, blur: 22),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [p.primarySoft, p.primarySoft.withValues(alpha: 0.05)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.search_rounded, color: p.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Rechercher un verset, un livre…',
                overflow: TextOverflow.ellipsis,
                style: _t(context, 15, FontWeight.w500, p.textGrey),
              ),
            ),
            const SizedBox(width: 8),
            _Pressable(
              label: 'Rechercher Jean 3:16',
              onTap: widget.onSearchQuery == null
                  ? null
                  : () => widget.onSearchQuery!('Jean 3:16'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  gradient: p.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _softShadow(
                    p.primary,
                    opacity: 0.30,
                    blur: 10,
                    offset: const Offset(0, 4),
                  ),
                ),
                child: Text(
                  'Jean 3.16',
                  style: _t(context, 12.5, FontWeight.w700, Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Actions rapides
  Widget _quickActions(BuildContext context, ReadingEntry? resume) {
    final p = _pal(context);
    final actions = [
      _QuickActionData(
        'Reprendre',
        Icons.menu_book_rounded,
        const Color(0xFFEAF0E2),
        p.primary,
        enabled: resume != null,
        onTap: resume == null
            ? null
            : () => _openReading(resume.bookIndex, resume.chapter),
      ),
      _QuickActionData(
        'Favoris',
        Icons.star_rounded,
        const Color(0xFFFDF3DC),
        const Color(0xFFC98A1B),
        onTap: _openFavorites,
      ),
      _QuickActionData(
        'Notes',
        Icons.edit_note_rounded,
        const Color(0xFFE7F0F7),
        const Color(0xFF3E6E91),
        onTap: _openNotes,
      ),
      _QuickActionData(
        'Comparer',
        Icons.compare_arrows_rounded,
        const Color(0xFFF3EAF0),
        const Color(0xFF8A4F74),
        onTap: _openCompare,
      ),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => _quickActionChip(context, actions[i]),
      ),
    );
  }

  Widget _quickActionChip(BuildContext context, _QuickActionData a) {
    final p = _pal(context);
    final labelColor = a.enabled
        ? p.textDark
        : p.textGrey.withValues(alpha: 0.5);
    return _Pressable(
      onTap: a.enabled ? a.onTap : null,
      label: a.label,
      child: Container(
        width: 96,
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.07),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    a.tint.withValues(alpha: a.enabled ? 1 : 0.45),
                    Color.lerp(a.tint, Colors.white, 0.45)!
                        .withValues(alpha: a.enabled ? 1 : 0.45),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                a.icon,
                color: a.enabled
                    ? a.iconColor
                    : p.textGrey.withValues(alpha: 0.5),
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(a.label, style: _t(context, 13, FontWeight.w700, labelColor)),
          ],
        ),
      ),
    );
  }

  // Carte héro « reprise de lecture »
  Widget _emptyResume(BuildContext context) {
    final p = _pal(context);
    return _Pressable(
      label: 'Aller à la Lecture',
      onTap: () => widget.onSelectDestination(BymDestination.lecture),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: p.heroGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: _softShadow(
            p.primaryDark,
            opacity: 0.35,
            blur: 26,
            offset: const Offset(0, 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'En cours',
                    style: _t(context, 11, FontWeight.w700, Colors.white),
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: Colors.white.withValues(alpha: .9),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Aucune lecture pour l’instant',
              style: _t(context, 20, FontWeight.w800, Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              'Ouvrez un chapitre depuis l’onglet Lecture ou la recherche.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _t(
                context,
                14,
                FontWeight.w500,
                Colors.white.withValues(alpha: 0.85),
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, ReadingEntry entry) {
    final p = _pal(context);
    return Container(
      decoration: BoxDecoration(
        gradient: p.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: _softShadow(
          p.primaryDark,
          opacity: 0.35,
          blur: 26,
          offset: const Offset(0, 12),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // Voile brillant diagonal — la lumière accroche le haut gauche,
            // comme un reflet sur une couverture reliée.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      stops: const [0.0, 0.42],
                      colors: [
                        Colors.white.withValues(alpha: 0.13),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: -55,
              right: -45,
              child: _decoCircle(context, 160, 0.10),
            ),
            Positioned(
              bottom: -70,
              right: 40,
              child: _decoCircle(context, 130, 0.08),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'En cours',
                          style: _t(context, 11, FontWeight.w700, Colors.white),
                        ),
                      ),
                      const Spacer(),
                      FutureBuilder<int>(
                        future: _repository.chapterCount(entry.bookIndex),
                        builder: (context, count) => Text(
                          'ch. ${entry.chapter} / ${count.data ?? '…'}',
                          style: _t(
                            context,
                            12,
                            FontWeight.w600,
                            Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${catalogEntry(entry.bookIndex).name} — chapitre ${entry.chapter}',
                    style: _t(context, 20, FontWeight.w800, Colors.white),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<Chapter>(
                    future: _repository.loadChapter(
                      entry.bookIndex,
                      entry.chapter,
                    ),
                    builder: (context, snapshot) {
                      final excerpt =
                          snapshot.hasData && snapshot.data!.verses.isNotEmpty
                          ? snapshot.data!.verses.first.text
                          : '';
                      return Text(
                        '« $excerpt »',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _t(
                          context,
                          14,
                          FontWeight.w500,
                          Colors.white.withValues(alpha: 0.85),
                          height: 1.55,
                          italic: FontStyle.italic,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<int>(
                    future: _repository.chapterCount(entry.bookIndex),
                    builder: (context, count) {
                      final total = count.data ?? 0;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: total <= 0
                              ? 0
                              : (entry.chapter / total).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _Pressable(
                    label: 'Reprendre la lecture — ${catalogEntry(entry.bookIndex).name} ${entry.chapter}',
                    onTap: () => _openReading(entry.bookIndex, entry.chapter),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reprendre la lecture',
                            style: _t(
                              context,
                              15,
                              FontWeight.w700,
                              Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: _softShadow(
                              Colors.black,
                              opacity: 0.18,
                              blur: 12,
                              offset: const Offset(0, 5),
                            ),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: p.primary,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decoCircle(BuildContext context, double size, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }

  // Études récentes
  Widget _studiesHeader(BuildContext context) {
    final p = _pal(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Études récentes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _t(context, 18, FontWeight.w800, p.textDark),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _openHistorique,
          child: Text(
            'Tout voir',
            style: _t(context, 13, FontWeight.w700, p.primary),
          ),
        ),
      ],
    );
  }

  List<Widget> _recentStudies(BuildContext context) {
    // 5 positions au plus — « Tout voir » ouvre l'historique complet. La
    // première entrée est la carte « Reprendre la lecture », pas une carte ici.
    final entries = _recent.length > 1
        ? _recent.sublist(1, math.min(6, _recent.length))
        : const <ReadingEntry>[];
    if (entries.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Vos derniers chapitres ouverts apparaîtront ici.',
            style: _t(context, 13, FontWeight.w500, _pal(context).textGrey),
          ),
        ),
      ];
    }
    return entries.map((e) => _studyCard(context, e)).toList();
  }

  Widget _studyCard(BuildContext context, ReadingEntry s) {
    final p = _pal(context);
    return _Pressable(
      onTap: () => _openReading(s.bookIndex, s.chapter),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.06),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: p.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                color: p.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${s.bookName} ${s.chapter}',
                    style: _t(context, 15.5, FontWeight.w700, p.textDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Lecture · ${formatRelativeDate(s.dateTime)}',
                    style: _t(context, 12.5, FontWeight.w500, p.textGrey),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: p.textGrey.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  // Section Alphabets
  Widget _alphabetsSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(context, 'ALPHABETS'),
        const SizedBox(height: 12),
        Text(
          'Découvrez les alphabets hébraïque, grec et leurs significations',
          style: _t(context, 20, FontWeight.w800, p.textDark, height: 1.3),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _alphabetCard(context, _kAlphabets[0])),
            const SizedBox(width: 14),
            Expanded(child: _alphabetCard(context, _kAlphabets[1])),
          ],
        ),
      ],
    );
  }

  Widget _alphabetCard(BuildContext context, _AlphabetCard a) {
    final p = _pal(context);
    return _Pressable(
      onTap: () => _soon('Alphabets'),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.07),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 132,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF2F6EC), Color(0xFFE4EDD8)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -4,
                      bottom: -16,
                      child: Text(
                        a.glyph,
                        style: _t(
                          context,
                          84,
                          FontWeight.w800,
                          p.primary.withValues(alpha: 0.10),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        a.letter,
                        style: _t(context, 19, FontWeight.w800, p.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(a.title, style: _t(context, 15, FontWeight.w800, p.textDark)),
            const SizedBox(height: 3),
            Text(
              a.subtitle,
              style: _t(context, 12.5, FontWeight.w500, p.textGrey),
            ),
          ],
        ),
      ),
    );
  }

  // Section La Bible et l'histoire
  Widget _historySection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "La Bible et l'histoire",
          style: _t(context, 20, FontWeight.w800, p.textDark),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: _kHistoryTopics
              .map((label) => _topicChip(context, label))
              .toList(),
        ),
      ],
    );
  }

  Widget _topicChip(BuildContext context, String label) {
    final p = _pal(context);
    return _Pressable(
      onTap: () => _soon(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.primary.withValues(alpha: 0.35)),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.05),
        ),
        child: Text(
          label,
          style: _t(context, 13.5, FontWeight.w700, p.primary),
        ),
      ),
    );
  }

  // Sections Mesures
  Widget _measureSection(BuildContext context, _MeasureSectionData m) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: m.alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        _badge(context, m.badge),
        const SizedBox(height: 12),
        Text(
          m.title,
          textAlign: m.alignRight ? TextAlign.right : TextAlign.left,
          style: _t(context, 20, FontWeight.w800, p.textDark, height: 1.3),
        ),
        const SizedBox(height: 16),
        _Pressable(
          onTap: () => _soon('Mesures'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              height: 190,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [m.tintA, m.tintB],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -30,
                    left: -30,
                    child: _tintCircle(context, 120, m.iconColor, 0.10),
                  ),
                  Positioned(
                    bottom: -40,
                    right: -20,
                    child: _tintCircle(context, 150, m.iconColor, 0.12),
                  ),
                  Center(
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: _softShadow(
                          p.primaryDark,
                          opacity: 0.15,
                          blur: 16,
                          offset: const Offset(0, 8),
                        ),
                      ),
                      child: Icon(m.icon, size: 34, color: m.iconColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tintCircle(
    BuildContext context,
    double size,
    Color color,
    double opacity,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }

  // Section Dénominations
  Widget _denominationsSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(context, 'DÉNOMINATIONS'),
        const SizedBox(height: 12),
        Text(
          'Les dénominations à travers les siècles',
          style: _t(context, 20, FontWeight.w800, p.textDark, height: 1.3),
        ),
        const SizedBox(height: 12),
        _Pressable(
          onTap: () => _soon('Dénominations'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  "Le paysage chrétien moderne est marqué par une prolifération inquiétante des dénominations comme en témoignent les nombreuses affiches et écriteaux placardés dans les villes. Alors que Yéhoshoua (Jésus) n'a donné aucun nom spécifique à son Assemblée, les humains …",
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: _t(
                    context,
                    15,
                    FontWeight.w500,
                    p.textGrey,
                    height: 1.65,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: p.primary, size: 24),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Pressable(
          onTap: () => _soon('Dénominations'),
          child: _voirPlusButton(context),
        ),
      ],
    );
  }

  Widget _voirPlusButton(BuildContext context) {
    final p = _pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        gradient: p.heroGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: _softShadow(
          p.primary,
          opacity: 0.35,
          blur: 14,
          offset: const Offset(0, 6),
        ),
      ),
      child: Text(
        'Voir plus',
        style: _t(context, 13, FontWeight.w800, Colors.white, spacing: 1),
      ),
    );
  }

  // Section Conciles & Pères de l'église (carrousel)
  Widget _concilesSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(context, "CONCILES ET PÈRES DE L'ÉGLISE ORGANISÉE"),
        const SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: PageView(
            controller: _concilesController,
            onPageChanged: (i) => setState(() => _concilesPage = i),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _concileCard(context, _kConcilesCards[0]),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _concileCard(context, _kConcilesCards[1]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _kConcilesCards.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _concilesPage ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == _concilesPage
                    ? p.primary
                    : p.textGrey.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _concileCard(BuildContext context, String label) {
    final p = _pal(context);
    return _Pressable(
      onTap: () => _soon(label),
      child: Container(
        decoration: BoxDecoration(
          gradient: p.heroGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: _softShadow(
            p.primaryDark,
            opacity: 0.35,
            blur: 22,
            offset: const Offset(0, 10),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            children: [
              Positioned(
                top: -40,
                right: -40,
                child: _decoCircle(context, 130, 0.10),
              ),
              Positioned(
                bottom: -50,
                left: -30,
                child: _decoCircle(context, 120, 0.08),
              ),
              Center(
                child: Text(
                  label,
                  style: _t(context, 18, FontWeight.w800, Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Section Empereurs anti-Mashiah (mosaïque)
  Widget _emperorsSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(context, 'EMPEREURS ANTI-MASHIAH'),
        const SizedBox(height: 12),
        Text(
          'Les premiers et les principaux empereurs antimashiah',
          style: _t(context, 20, FontWeight.w800, p.textDark, height: 1.3),
        ),
        const SizedBox(height: 16),
        _Pressable(
          onTap: () => _soon('Empereurs'),
          child: Row(
            children: [
              Expanded(
                flex: 11,
                child: _emperorTile(context, height: 220, iconSize: 60),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 10,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _emperorTile(
                            context,
                            height: 105,
                            iconSize: 32,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _emperorTile(
                            context,
                            height: 105,
                            iconSize: 32,
                            alt: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _emperorTile(
                            context,
                            height: 105,
                            iconSize: 32,
                            alt: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _emperorTile(
                            context,
                            height: 105,
                            iconSize: 32,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: p.primary, size: 24),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emperorTile(
    BuildContext context, {
    required double height,
    required double iconSize,
    bool alt = false,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: alt
                ? const [Color(0xFFE7DFD3), Color(0xFFD6C9B4)]
                : const [Color(0xFFF1ECE3), Color(0xFFE2D7C4)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -12,
              bottom: -16,
              child: _tintCircle(context, 90, const Color(0xFF8A7A62), 0.12),
            ),
            Center(
              child: Icon(
                Icons.person_rounded,
                size: iconSize,
                color: const Color(0xFF8A7A62),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Section Fausses divinités (alignée à droite)
  Widget _falseGodsSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _badge(context, 'FAUSSES DIVINITÉS'),
        const SizedBox(height: 12),
        Text(
          'Fausses divinités',
          textAlign: TextAlign.right,
          style: _t(context, 20, FontWeight.w800, p.textDark),
        ),
        const SizedBox(height: 8),
        Text(
          'Quelques divinités adorées par les païens dans la Bible.',
          textAlign: TextAlign.right,
          style: _t(context, 15, FontWeight.w500, p.textGrey, height: 1.5),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _Pressable(
              onTap: () => _soon('Fausses divinités'),
              child: _voirPlusButton(context),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right_rounded, color: p.primary, size: 24),
          ],
        ),
      ],
    );
  }

  // Fêtes / Mois / Temps bibliques
  Widget _timeTopicsSection(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < _kTimeTopics.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _timeTopicCard(context, _kTimeTopics[i]),
        ],
      ],
    );
  }

  Widget _timeTopicCard(BuildContext context, _TimeTopic t) {
    final p = _pal(context);
    return _Pressable(
      onTap: () => _soon(t.title),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: premiumPalette(context).surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: _softShadow(p.primaryDark, opacity: 0.06),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: p.heroGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: _softShadow(
                  p.primary,
                  opacity: 0.3,
                  blur: 10,
                  offset: const Offset(0, 4),
                ),
              ),
              child: Icon(t.icon, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    style: _t(context, 15.5, FontWeight.w800, p.textDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    t.subtitle,
                    style: _t(
                      context,
                      12.5,
                      FontWeight.w500,
                      p.textGrey,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.primary, size: 22),
          ],
        ),
      ),
    );
  }

  // Jours de la semaine (système solaire)
  Widget _weekDaysSection(BuildContext context) {
    final p = _pal(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(context, 'JOURS DE LA SEMAINE'),
        const SizedBox(height: 16),
        _Pressable(
          onTap: () => _soon('Jours de la semaine'),
          child: Row(
            children: [
              Expanded(child: _solarSystemTile(context)),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: p.primary, size: 24),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Saviez-vous ceci concernant les romains ?',
          style: _t(context, 20, FontWeight.w800, p.textDark, height: 1.3),
        ),
        const SizedBox(height: 10),
        Text(
          'Chaque jour de la semaine chez les romains correspond à une divinité dans leur mythologie mais également à un astre.',
          style: _t(context, 15, FontWeight.w500, p.textGrey, height: 1.65),
        ),
      ],
    );
  }

  Widget _solarSystemTile(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 210,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF151D29), Color(0xFF0A0E14)],
          ),
        ),
        child: Stack(
          children: [
            // Orbites
            Center(child: _orbit(context, 250)),
            Center(child: _orbit(context, 170)),
            Center(child: _orbit(context, 95)),
            // Soleil
            Align(
              alignment: const Alignment(0.30, -0.20),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [Color(0xFFFFE29A), Color(0xFFF2A93B)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF2A93B).withValues(alpha: 0.55),
                      blurRadius: 26,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            // Planètes
            Align(
              alignment: const Alignment(-0.55, -0.55),
              child: _planet(context, 30, const Color(0xFFD8A06B)),
            ),
            Align(
              alignment: const Alignment(-0.30, 0.50),
              child: _planet(context, 24, const Color(0xFF6FA8DC)),
            ),
            Align(
              alignment: const Alignment(0.60, 0.55),
              child: _planet(context, 20, const Color(0xFFC46A4A)),
            ),
            Align(
              alignment: const Alignment(-0.75, 0.05),
              child: _planet(context, 14, const Color(0xFFE3C58F)),
            ),
            Align(
              alignment: const Alignment(0.05, -0.80),
              child: _planet(context, 10, const Color(0xFFDDE6EE)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orbit(BuildContext context, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
    );
  }

  Widget _planet(BuildContext context, double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  // Puce de section réutilisable
  Widget _badge(BuildContext context, String label) {
    final p = _pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: p.primarySoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: p.primary,
            ),
          ),
          const SizedBox(width: 6),
          // `Flexible` et non `Text` nu : dans une `Row`, un enfant non-flex est
          // mesuré sous une contrainte de largeur infinie, donc ce label ne se
          // replie jamais — il sortait de l'écran. Le plus long
          // (« CONCILES ET PÈRES DE L'ÉGLISE ORGANISÉE ») débordait de 21 px sur
          // un 320 px à taille de texte normale, et de 60 px avec la police
          // système agrandie. `Flexible` reste *loose* : la pastille continue de
          // se serrer autour des libellés courts, seuls les longs passent sur
          // deux lignes.
          Flexible(
            child: Text(
              label,
              style: _t(context, 11, FontWeight.w800, p.primary, spacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toute surface interactive de l'accueil : enfoncement visuel au toucher
/// (léger rétrécissement), retour haptique discret, et sémantique « bouton »
/// pour les lecteurs d'écran — les cartes n'étaient jusque là que des
/// [GestureDetector] muets.
class _Pressable extends StatefulWidget {
  final Widget child;

  /// Null = inertie (l'enfant reste visible mais ne répond pas).
  final VoidCallback? onTap;

  /// Libellé pour les lecteurs d'écran ; sans lui, le contenu textuel de
  /// l'enfant sert de label.
  final String? label;

  const _Pressable({required this.child, this.onTap, this.label});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: widget.onTap != null,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown:
            widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        child: AnimatedScale(
          scale: _down ? 0.965 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _QuickActionData {
  final String label;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final bool enabled;
  final VoidCallback? onTap;

  const _QuickActionData(
    this.label,
    this.icon,
    this.tint,
    this.iconColor, {
    this.enabled = true,
    this.onTap,
  });
}
