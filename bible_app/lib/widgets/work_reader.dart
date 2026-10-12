import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/app_preferences.dart';
import '../data/reference_parser.dart';
import '../data/work_catalog.dart';
import '../data/work_reader.dart';
import '../data/work_store.dart';
import 'fiche_text_settings.dart';
import 'loading_skeleton.dart';
import 'note_aware_text.dart';
import 'premium_style.dart';
import 'reader_actions_bar.dart';

/// La lecture d'un **ouvrage** téléchargé, dans la chrome de l'écran Lecture.
///
/// Le pendant en prose de `ChapterReader` : celui-ci est bâti sur le verset
/// (tuiles, codes Strong, feuille d'étude) et n'a rien à faire ici, mais les
/// deux partagent la même barre d'actions, les mêmes flèches ‹ › et la même
/// reprise de position.
///
/// **L'index de lecture est [chapter]** — 0 = sommaire, 1..N = chapitres —
/// exactement la numérotation de `StudyTab.chapter` pour un onglet `work`, et
/// celle de `WorkTocItem.chapter` dans le sommaire.
///
/// **La position de lecture est un index de bloc, 1-based**, stocké dans le
/// même `StudyTab.verse` que la position d'un verset : un ouvrage n'a pas de
/// numérotation de verset, mais son lecteur aussi doit reprendre où il en
/// était. L'index 1 désigne le premier bloc, l'item 0 de la liste étant le
/// titre du chapitre — l'index d'item et l'index de bloc coïncident donc
/// exactement, ce qui rend la fraction de défilement réversible.
class WorkReader extends StatefulWidget {
  /// Code de l'ouvrage : la clé du catalogue (`workCatalog`) et le nom du
  /// fichier sur l'appareil.
  final String code;

  /// Index de lecture : 0 = sommaire, 1..N = chapitres.
  final int chapter;

  /// Position à reprendre, index 1-based du bloc (null = haut de page). 0 n'a
  /// aucun sens ici : le sommaire n'a pas de position.
  final int? initialBlock;

  /// Rapporte le bloc atteint, pour que l'onglet le persiste. Comme pour la
  /// Bible, l'appel est différé hors frame et n'a lieu qu'au changement.
  final ValueChanged<int>? onBlockChanged;

  /// Ouvre un autre index de lecture **dans cet onglet** — les lignes du
  /// sommaire, les flèches ‹ ›, le glissement horizontal.
  ///
  /// Requis : un ouvrage n'a pas d'écran de repli (pas de `ChapterScreen` à
  /// pousser), et une ligne de sommaire qui ne fait rien mentirait au lecteur.
  final ValueChanged<int> onOpenChapter;

  /// Une référence biblique tapée — dans une note ou sous une citation — est
  /// ouverte par la coquille. Null hors coquille (tests) : les références
  /// restent du texte souligné plutôt que des boutons morts.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  /// Ouvre la Bibliothèque depuis le panneau « plus sur l'appareil ». Null
  /// hors coquille : le panneau nomme alors la destination sans y conduire.
  final VoidCallback? onOpenLibrary;

  /// D'où l'ouvrage est lu. Injectable pour les tests, pour les mêmes raisons
  /// que `ChapterReader.store` : une lecture réelle passe par `dart:io`, qui
  /// ne répond pas dans la zone fake-async de `testWidgets`.
  final WorkStore? store;

  const WorkReader({
    super.key,
    required this.code,
    required this.chapter,
    required this.onOpenChapter,
    this.initialBlock,
    this.onBlockChanged,
    this.onOpenVerse,
    this.onOpenLibrary,
    this.store,
  });

  @override
  State<WorkReader> createState() => _WorkReaderState();
}

class _WorkReaderState extends State<WorkReader> {
  late final WorkStore _store = widget.store ?? WorkStore();
  late Future<Work?> _workFuture;

  /// L'ouvrage une fois lu. La barre d'actions en a besoin **avant** le
  /// premier rendu du corps (bornes des flèches ‹ ›), d'où ce champ tenu à
  /// côté du `Future` plutôt que dans son builder.
  Work? _work;

  final ScrollController _scroll = ScrollController();

  /// Débounce du rapport de position : écrire la position sur chaque
  /// notification martèlerait `shared_prefs`, exactement comme dans
  /// `ChapterReader`.
  Timer? _reportTimer;

  /// Dernier bloc rapporté, pour n'écrire qu'aux changements réels.
  int? _lastReported;

  /// Bloc indexé 1-based à révéler : la position restaurée, ou la section
  /// choisie dans le sommaire du chapitre. Sa tuile porte [_anchorKey] (pour
  /// `ensureVisible`) et il fait foi comme position rapportée **jusqu'à ce
  /// que le lecteur tire la liste lui-même** — l'estimation par fraction
  /// retombe sur un voisin et écraserait la position demandée juste après
  /// l'atterrissage.
  int? _anchorBlock;

  /// La restauration n'est lancée qu'une fois, et seulement une fois la
  /// liste montée (données lues).
  bool _restoreScheduled = false;
  final GlobalKey _anchorKey = GlobalKey();

  /// La liste du chapitre, repérée pour [_builtTiles] : elle ne sert qu'à en
  /// trouver le sous-arbre des tuiles réellement construites.
  final GlobalKey _listKey = GlobalKey();

  /// Accumulé du glissement horizontal en cours (pagination, cf. [_onSwipe]).
  double? _swipeDx;

  // ---- Trouver dans l'ouvrage (« trouver dans la page ») ----

  bool _findOpen = false;
  final TextEditingController _findController = TextEditingController();
  final FocusNode _findFocus = FocusNode();
  Timer? _findDebounce;

  /// Index 1-based des blocs contenant la recherche, dans l'ordre de lecture.
  List<int> _findMatches = [];

  /// Index dans [_findMatches] où le lecteur est parqué ; -1 quand aucun.
  int _findIndex = -1;

  /// La frappe brute de la recherche, pour peindre ses occurrences dans le
  /// texte ; vide quand le champ est vide ou fermé.
  String _findQuery = '';

  @override
  void initState() {
    super.initState();
    _workFuture = _load();
    // Le sommaire n'a pas de position : seul un chapitre se reprend au bloc.
    if (widget.chapter > 0) _anchorBlock = widget.initialBlock;
    _scroll.addListener(_onScrollChanged);
    // Un ouvrage supprimé pendant qu'on le lit doit céder la place au
    // panneau « plus sur l'appareil » plutôt que de servir un texte dont le
    // fichier n'existe plus.
    WorkStore.revision.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _reportTimer?.cancel();
    _findDebounce?.cancel();
    _findController.dispose();
    _findFocus.dispose();
    _scroll.removeListener(_onScrollChanged);
    _scroll.dispose();
    WorkStore.revision.removeListener(_onStoreChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WorkReader old) {
    super.didUpdateWidget(old);
    // En usage normal le `ValueKey` posé par l'écran Lecture recrée l'État à
    // chaque changement d'ouvrage ; cette garde couvre les usages isolés qui
    // ne le posent pas, où un autre livre serait sinon lu avec les données du
    // précédent.
    if (old.code != widget.code) {
      _work = null;
      _anchorBlock = widget.chapter > 0 ? widget.initialBlock : null;
      _restoreScheduled = false;
      _workFuture = _load();
    }
  }

  Future<Work?> _load() async {
    final json = await _store.load(widget.code);
    final work = json == null ? null : Work.parse(json);
    _work = work;
    // Premier rendu passé (cet `await` l'est toujours) : la barre peut
    // maintenant mesurer les flèches et le panneau d'erreur apparaître.
    if (mounted) setState(() {});
    return work;
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _work = null;
    _workFuture = _load();
  }

  // ---- Position de lecture ----

  /// Nombre d'items **porteurs d'une position** : le titre (item 0) puis un
  /// item par bloc. 0 hors chapitre (sommaire, ouvrage non lu) — la restitution
  /// et le rapport se taisent alors.
  ///
  /// Le bouton « Continuer » ferme la liste sans entrer dans ce décompte : il
  /// n'est à aucune position. Le compter ajouterait un bloc fantôme au rapport
  /// en pied de page — un index qui n'existe pas, et une reprise qui sauterait
  /// dans le vide.
  int get _itemCount {
    final chapter = _work?.chapterAt(widget.chapter);
    if (chapter == null) return 0;
    return chapter.blocks.length + 1;
  }

  void _onScrollChanged() {
    _reportTimer?.cancel();
    _reportTimer = Timer(const Duration(milliseconds: 400), _reportCurrentBlock);
  }

  /// Estime le bloc du haut du viewport à partir de la fraction de
  /// défilement, puis le rapporte. Une *estimation*, pour la même raison que
  /// dans `ChapterReader` : la liste est paresseuse et ses tuiles ont des
  /// hauteurs variables, une correspondance exacte demanderait que chaque
  /// bloc mesure sa propre géométrie. La fraction est aussi celle que
  /// [_restore] inverse pour revenir au bloc.
  void _reportCurrentBlock() {
    if (widget.chapter == 0) return;
    final pinned = _anchorBlock;
    if (pinned != null) {
      _reportBlock(pinned);
      return;
    }
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final itemCount = _itemCount;
    if (itemCount <= 1 ||
        !position.hasContentDimensions ||
        position.maxScrollExtent <= 0) {
      return;
    }
    final fraction = (position.pixels / position.maxScrollExtent).clamp(
      0.0,
      1.0,
    );
    final itemIndex = (fraction * (itemCount - 1)).round();
    _reportBlock(itemIndex < 1 ? 1 : itemIndex);
  }

  /// Rapporte [block] à l'onglet, hors frame : un rapport lancé depuis
  /// `initState` notifierait le `TabManager` pendant le build et fermerait
  /// l'onglet lui-même en plein montage (`markNeedsBuild during build`).
  void _reportBlock(int block) {
    if (block == _lastReported) return;
    _lastReported = block;
    final cb = widget.onBlockChanged;
    if (cb == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      cb(block);
    });
  }

  /// Arme la restitution — une fois, et seulement quand les données sont là
  /// (la liste n'existe pas avant).
  void _scheduleRestore() {
    if (_restoreScheduled || _anchorBlock == null || widget.chapter == 0) {
      return;
    }
    _restoreScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  /// Ramène au bloc restauré, ou à la section choisie dans le sommaire du
  /// chapitre.
  ///
  /// La liste est paresseuse : la tuile du bloc visé n'existe pas tant qu'on
  /// n'a pas défilé à ses côtés, et l'estimation « index ÷ nombre d'items ×
  /// maxScrollExtent » suppose que chaque bloc pèse le même poids. C'est faux
  /// dès qu'un chapitre alterne paragraphes, citations courtes et titres — un
  /// saut pouvait alors atterrir à 21 000, 16 000 ou 72 000 pixels de la
  /// section demandée, ce que `work_section_jump_test.dart` mesure chapitre
  /// par chapitre sur les deux ouvrages.
  ///
  /// On corrige avec ce que la liste a **déjà construit** : la position
  /// exacte des tuiles vivantes et leur poids réel. Chaque tour mesure le
  /// suivant, jusqu'à ce que la tuile du bloc soit bâtie ; `ensureVisible`
  /// fait alors la mise au point — exacte, elle, puisqu'elle part du rendu
  /// réel et non d'une moyenne.
  ///
  /// Mesurer ne suffit pourtant pas : la hauteur moyenne fait **dépasser**, et
  /// deux dépassements en sens contraire s'enchaînent en cycle. On encadre
  /// donc le visé entre une rive basse et une rive haute, et toute proposition
  /// qui sort de l'encadrement est remplacée par son milieu : une dichotomie
  /// resserre toujours, là où l'extrapolation pouvait battre indéfiniment.
  Future<void> _restore() async {
    if (!mounted || _anchorBlock == null) return;
    if (!_scroll.hasClients) return;
    final itemCount = _itemCount;
    final target = _anchorBlock!;
    if (itemCount <= 1 || target >= itemCount) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
      // La page entient sur l'écran : rien à défiler, tout est déjà là.
      return;
    }
    // Les deux rives : [lowSide] est un décalage dont *toutes* les tuiles
    // bâties précèdent le bloc visé, [highSide] un décalage dont toutes le
    // suivent. Le bon décalage est forcément entre les deux — une proposition
    // qui sort de cet encadrement est fausse par construction.
    double? lowSide;
    double? highSide;
    for (var attempt = 0; attempt < 16; attempt++) {
      final revealed = _anchorKey.currentContext;
      if (revealed != null && revealed.mounted) {
        // Pas de flash : c'est une place où reprendre, pas un saut neuf.
        await Scrollable.ensureVisible(
          revealed,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
        return;
      }
      final built = _builtTiles().keys;
      if (built.isNotEmpty) {
        if (built.every((index) => index < target)) {
          lowSide = position.pixels;
        } else if (built.every((index) => index > target)) {
          highSide = position.pixels;
        }
      }
      var offset = _offsetToward(target, position, itemCount);
      if (offset == null) return;
      if (lowSide != null && highSide != null) {
        if ((highSide - lowSide).abs() < 1) return;
        if (offset <= lowSide || offset >= highSide) {
          // L'extrapolation par la hauteur moyenne pouvait osciller entre les
          // deux rives sans jamais bâtir la tuile du milieu : `ministere`
          // ch. 8 faisait 1680 → 3574 → 1680 … douze fois, ses tuiles sautant
          // de 12 à 18, et la section « I. LA COMMUNION SPIRITUELLE »
          // n'arrivait jamais. La dichotomie, elle, resserre à chaque tour et
          // ne peut pas tourner en rond.
          offset = (lowSide + highSide) / 2;
        }
      }
      position.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _anchorBlock == null) return;
    }
  }

  /// L'endroit où défile-t-on pour faire apparaître l'item [target] ?
  ///
  /// Les tuiles vivantes donnent leur haut, en coordonnées de contenu, et
  /// leur poids réel. De là :
  ///
  /// - l'item juste au-dessus du visé est connu → son bas vaut **exactement**
  ///   le haut du visé ;
  /// - sinon la moyenne des hauteurs mesurées extrapole — mieux que
  ///   [ScrollPosition.maxScrollExtent], qui ne mélange que des estimations ;
  /// - si tout ce qui est construit est **sous** le visé, on remonte de deux
  ///   écrans au-dessus de la première tuile vue, et le tour suivant mesurera.
  double? _offsetToward(int target, ScrollPosition position, int itemCount) {
    final tiles = _builtTiles();
    if (tiles.isEmpty) {
      // Rien de construit encore : la fraction est la seule boussole.
      return position.maxScrollExtent * (target / (itemCount - 1));
    }
    final above = tiles.keys
        .where((index) => index > target)
        .fold<int?>(null, (a, b) => a == null || b < a ? b : a);
    final below = tiles.keys
        .where((index) => index < target)
        .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
    if (below == null) {
      final first = above == null ? null : tiles[above];
      if (first == null) return null;
      return (first.top - position.viewportDimension * 2)
          .clamp(0.0, position.maxScrollExtent);
    }
    final under = tiles[below]!;
    final next = under.top + under.box.size.height;
    if (below == target - 1) return next; // contigu : position exacte
    final heights = [
      for (final tile in tiles.values) tile.box.size.height,
    ];
    final average = heights.reduce((a, b) => a + b) / heights.length;
    return next + average * (target - below - 1);
  }

  /// Les tuiles que la liste a **réellement** construites : index d'item →
  /// leur RenderBox et le haut de leur contenu.
  ///
  /// Elles seules apparaissent dans l'arbre, et leur clé ([_WorkItemKey],
  /// posée dans `itemBuilder`) dit quel item elles portent. Aucune autre
  /// mesure n'est possible sans forcer la liste à tout construire — et cette
  /// suffit : l'erreur d'une estimation se corrige à partir d'une seule tuile
  /// vraie.
  Map<int, ({RenderBox box, double top})> _builtTiles() {
    final root = _listKey.currentContext;
    if (root == null || !_scroll.hasClients) return const {};
    final origin = (root.findRenderObject() as RenderBox?)?.localToGlobal(
      Offset.zero,
    ).dy;
    if (origin == null) return const {};
    final pixels = _scroll.position.pixels;
    final tiles = <int, ({RenderBox box, double top})>{};
    void walk(Element element) {
      final key = element.widget.key;
      if (key is _WorkItemKey) {
        final render = element.renderObject;
        if (render is RenderBox && render.attached && render.hasSize) {
          tiles[key.value] = (
            box: render,
            top: pixels + (render.localToGlobal(Offset.zero).dy - origin),
          );
        }
      }
      element.visitChildren(walk);
    }

    // `currentContext` est bien un `Element` à l'exécution : c'est le nœud
    // qui porte la liste, et lui seul ouvre l'accès à ses tuiles.
    walk(root as Element);
    return tiles;
  }

  // ---- Navigation ----

  void _openChapter(int chapter) {
    if (chapter < 0) return;
    if (chapter > 0 && chapter > (_work?.chapters.length ?? 0)) return;
    widget.onOpenChapter(chapter);
  }

  /// Un glissement horizontal feuillette : gauche → ce qui suit, droite ce
  /// qui précède, comme un folio. Deux seuils pour qu'un frottement ne
  /// tourne jamais la page par accident : une gâchette rapide (vitesse) ou un
  /// tirage volontaire (distance).
  void _onSwipe(DragEndDetails details) {
    final dx = _swipeDx ?? 0;
    _swipeDx = null;
    final velocity = details.primaryVelocity ?? 0;
    final isFlick = velocity.abs() > 400 && dx.abs() > 70;
    final isLongDrag = dx.abs() > 140;
    if (!isFlick && !isLongDrag) return;
    // La même vibration que le feuillettage biblique : la page tourne, on le
    // sent.
    HapticFeedback.lightImpact();
    _openChapter(dx < 0 ? widget.chapter + 1 : widget.chapter - 1);
  }

  void _openReference(BibleReference ref) {
    final cb = widget.onOpenVerse;
    if (cb == null) return;
    cb(ref.bookIndex, ref.chapter ?? 1, ref.verse ?? 1);
  }

  /// Les lignes du sommaire qui décrivent **le chapitre courant** : son titre
  /// (niveau 0, la ligne dont le chapitre tient son nom) puis ses sections.
  ///
  /// Vide sur le sommaire et pour un ouvrage qui n'en aurait pas : le double
  /// chevron reste alors inerte plutôt que d'ouvrir une feuille vide.
  List<WorkTocItem> get _sections {
    final work = _work;
    if (work == null || widget.chapter == 0) return const [];
    return [
      for (final item in work.toc)
        if (item.chapter == widget.chapter) item,
    ];
  }

  /// La feuille « Sommaire du chapitre » : les titres et sous-titres de ce
  /// qu'on lit, et rien d'autre.
  ///
  /// Feuilletter les chapitres un par un, ‹ › le font déjà ; les chapitres
  /// en entier, la pastille du titre et le sommaire du livre les portent. Ce
  /// que cherche un lecteur qui a atteint le double chevron au milieu d'une
  /// page, c'est *où il en est dans ce qu'il lit* — « I. D'ABORD
  /// L'ADORATION », « II. AIMER LE SEIGNEUR » — et un tap pour y aller sans
  /// retourner au début.
  ///
  /// La feuille se dimensionne sur son contenu : cinq lignes ne méritent pas
  /// les sept dixièmes de l'écran que prendrait une liste de chapitres.
  Future<void> _showChapterPicker(BuildContext context) {
    final sections = _sections;
    if (sections.isEmpty) return Future.value();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: premiumBackground(context),
      builder: (sheetContext) => Padding(
        // Android peut recouvrir une feuille modale : on réserve sa marge de
        // navigation autour de la feuille elle-même, pas seulement en fin de
        // liste (même garde que la feuille « Livres »).
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(sheetContext).bottom,
        ),
        child: Container(
          decoration: premiumSurface(sheetContext, radius: 24, depth: 1.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHeader(title: 'Sommaire du chapitre'),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * .6,
                  ),
                  child: ListView(
                    key: const Key('workChapterPicker'),
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      for (var i = 0; i < sections.length; i++)
                        _sectionRow(sheetContext, sections[i], i),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Une section : indentée comme dans le sommaire imprimé, tapable dès
  /// qu'on en trouve le bloc dans le texte.
  ///
  /// Le titre du chapitre même (niveau 0) y revient en haut de page. Une
  /// section annoncée par le sommaire mais absente du corps reste du texte :
  /// un lien qui ne mène nulle part ne doit pas se faire passer pour un
  /// lien.
  Widget _sectionRow(BuildContext context, WorkTocItem item, int index) {
    final p = premiumPalette(context);
    final level0 = item.level == 0;
    final target = level0 ? 0 : _blockForSection(item.title);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('work-section-$index'),
        onTap: target == null
            ? null
            : () {
                Navigator.of(context).pop();
                _jumpToBlock(target);
              },
        child: Padding(
          padding: EdgeInsets.fromLTRB(20 + 18.0 * item.level, 12, 20, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: premiumText(
                    context,
                    level0 ? 14.5 : 13.5,
                    level0 ? FontWeight.w800 : FontWeight.w600,
                    level0 ? p.textDark : p.textGrey,
                    height: 1.4,
                  ),
                ),
              ),
              if (target != null)
                Icon(Icons.chevron_right, size: 18, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// Le bloc (index 1-based) où commence [title] dans le chapitre courant,
  /// ou null si le sommaire annonce une section que le corps ne porte pas.
  ///
  /// Trois passes, de la plus sûre à la plus tolérante : égalité stricte,
  /// égalité à séparateur près, inclusion. L'ordre compte — une tolérance
  /// qui précéderait l'égalité déplacerait des sauts qui fonctionnent déjà,
  /// et le test de saut les mesure un par un sur les deux ouvrages.
  ///
  /// L'égalité tolère l'espacement : la ligne du sommaire et le titre
  /// effectif peuvent avoir été normalisés différemment, et renvoyer rien
  /// là où la section existe rendrait la ligne inerte pour une faute de
  /// ponctuation.
  int? _blockForSection(String title) {
    final chapter = _work?.chapterAt(widget.chapter);
    if (chapter == null) return null;
    final wanted = _normalizeSection(title);
    if (wanted.isEmpty) return null;
    final blocks = chapter.blocks;
    // 1. Égalité stricte — le cas courant, sommaire et titres sortant du
    //    même extracteur.
    for (var i = 0; i < blocks.length; i++) {
      if (_normalizeSection(blocks[i].text) == wanted) return i + 1;
    }
    // 2. Égalité à séparateur près. Le sommaire d'ANIMALITE assemble deux
    //    lignes de titre en une entrée avec un tiret que le titre du corps
    //    n'a pas : « A/ Le lion - Premier empire : Babylone » au sommaire,
    //    « A/ Le lion Premier empire : Babylone » dans le texte. Les quatre
    //    seules sections muettes du livre l'étaient pour ce tiret seul, et
    //    une ligne de sommaire sans cible est une ligne morte : pas de
    //    chevron, et un tap qui ne fait rien — exactement le symptôme signalé.
    final loose = _sectionKey(title);
    int? inHeadings;
    int? anywhere;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (_sectionKey(block.text) != loose) continue;
      if (block.kind.isHeading) return i + 1;
      anywhere ??= i + 1;
    }
    if (anywhere != null) return anywhere;
    // 3. Inclusion — un titre du sommaire plus long que le bloc, ou un bloc
    //    qui le cite.
    inHeadings = null;
    anywhere = null;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final text = _normalizeSection(block.text);
      if (text.length < 8) continue;
      if (!(text.contains(wanted) || wanted.contains(text))) continue;
      // Un titre suivi d'un paragraphe qui le cite ne doit pas voler la
      // place du titre : les blocs-titres passent d'abord.
      if (block.kind.isHeading) inHeadings ??= i + 1;
      anywhere ??= i + 1;
    }
    return inHeadings ?? anywhere;
  }

  static String _normalizeSection(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  /// La même normalisation, à séparateur près : un tiret entouré d'espaces
  /// est une ponctuation de mise en page, pas une lettre, et il sépare
  /// précisément ce que le sommaire a réuni en une ligne.
  ///
  /// Le tiret **entre** deux mots d'un même titre (`XVe - XVIe siècle`) est
  /// conservé : seul le tiret flanqué d'espaces saute, et les deux textes
  /// passent par la même clé — une comparaison ne ment que si l'un des deux
  /// la subit.
  static String _sectionKey(String text) =>
      _normalizeSection(text).replaceAll(RegExp(r'\s+-\s+'), ' ');

  /// Met le lecteur au bloc [block] (1-based, 0 = titre du chapitre) par la
  /// même mécanique que la reprise de position : l'ancre porte la clé de la
  /// tuile, [_restore] saute, mesure, resaute jusqu'à ce qu'elle soit bâtie,
  /// puis fait la mise au point. L'épingle se lève au prochain geste du
  /// pour une position restaurée — le bloc atteint vaut position tant qu'on
  /// n'a pas défilé soi-même.
  ///
  /// Le titre du chapitre (0) n'appartient à aucune position : on annule
  /// l'ancre et on remonte directement, plutôt que d'y faire entrer un bloc
  /// que le sommaire appelle titre et que l'onglet lirait pour un verset.
  void _jumpToBlock(int block) {
    if (block <= 0) {
      setState(() => _anchorBlock = null);
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    if (block >= _itemCount) return;
    setState(() {
      _anchorBlock = block;
      // L'armé est consommé par ce saut : sans quoi le prochain build, en
      // voyant une ancre là où il n'y en avait pas, lancerait une seconde
      // [_restore] en parallèle de celle-ci.
      _restoreScheduled = true;
    });
    // Après le rebuild : tant que la tuile du nouveau bloc n'a pas repris
    // l'ancre, `_restore` la trouverait encore sur celle de l'ancien, et
    // `ensureVisible` ferait la mise au point au mauvais endroit.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  // ---- Chrome ----

  /// Le titre de la pastille gauche : le catalogue jusqu'à la lecture du
  /// fichier, le titre du JSON ensuite (il peut différer d'une ligne du
  /// catalogue, et c'est lui que l'ouvrage porte sur sa page de garde).
  String get _title => _work?.title ?? workByCode(widget.code)?.title ?? widget.code;

  Widget _actionsBar(BuildContext context) {
    final chapters = _work?.chapters.length ?? 0;
    return ReaderActionsBar(
      title: _title,
      // Un ouvrage n'a ni traduction ni numérotation de verset : ni pastille
      // de version, ni saut au verset. Le double chevron, lui, reste — il
      // déplie les titres du chapitre qu'on lit, parce que le sommaire du
      // livre est deux écrans et trois gestes derrière soi.
      showVersion: false,
      // Inerte quand il n'y a rien à déplier : le sommaire du livre (page 0,
      // qui n'a pas encore de chapitre), l'ouvrage sans sommaire, et tout
      // chapitre dont le sommaire ne porte aucune ligne propre. Un bouton
      // qui rouvre ce qui est à l'écran ment sur ce qu'il fait.
      onChapters:
          chapters == 0 || _sections.isEmpty
              ? null
              : () => _showChapterPicker(context),
      // Le sommaire est déjà la page 0 : la pastille devient inerte plutôt
      // que de rouvrir ce qui est à l'écran.
      onTapTitle: widget.chapter == 0 ? null : () => _openChapter(0),
      onPreviousChapter: widget.chapter > 0
          ? () => _openChapter(widget.chapter - 1)
          : null,
      onNextChapter: widget.chapter < chapters
          ? () => _openChapter(widget.chapter + 1)
          : null,
      onOpenLibrary: widget.onOpenLibrary,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // La recherche dans l'ouvrage vit de la largeur, comme la lecture
          // parallèle du lecteur biblique : tablettes et au-dessus, sur la
          // même rangée que l'affichage. Le sommaire n'a rien à chercher.
          if (_findIconInBar && widget.chapter > 0)
            IconButton(
              tooltip: 'Trouver dans le chapitre',
              icon: const Icon(Icons.search),
              onPressed: _openFind,
              visualDensity: VisualDensity.compact,
            ),
          // L'immersion suit le même seuil : l'ouvrage sait déjà en sortir
          // (pastille), il lui manquait le bouton pour y entrer.
          if (_immersionInBar)
            IconButton(
              tooltip: 'Mode immersion',
              icon: const Icon(Icons.fullscreen),
              onPressed: _enterImmersion,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            tooltip: 'Affichage du texte',
            icon: const Icon(Icons.more_vert),
            visualDensity: VisualDensity.compact,
            // Taille, police et alignement — la famille `fiche.*`, la seule que
            // ce lecteur sache écrire. Feuille propre à l'ouvrage : sur les
            // écrans étroits elle recueille aussi l'immersion et la recherche,
            // que la barre ne porte qu'à partir de 600 — même régime que la
            // feuille ⋯ Bible.
            onPressed: () => showOuvrageDisplaySheet(
              context,
              onOpenFind: _findIconInBar || widget.chapter <= 0
                  ? null
                  : _openFind,
              onSetImmersion: _immersionInBar
                  ? null
                  : (value) =>
                        value ? _enterImmersion() : _exitImmersion(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // L'immersion est une préférence globale de l'app, pas propre à la Bible :
    // elle est entrée depuis la feuille d'affichage du lecteur biblique, et
    // sans cette garde un onglet d'ouvrage garderait ses barres pendant que
    // la coquille cache les siennes — sans aucun bouton pour en sortir.
    return ListenableBuilder(
      listenable: AppPreferences.immersionNotifier,
      builder: (context, _) {
        final immersive = AppPreferences.immersionNotifier.value;
        return Stack(
          children: [
            Column(
              children: [
                if (!immersive) ...[
                  _actionsBar(context),
                  if (_findOpen) _buildFindBar(),
                ],
                Expanded(
                  child: FicheTextScope(
                    builder: (context, style) => _body(context, style),
                  ),
                ),
              ],
            ),
            if (immersive)
              Positioned(
                right: 16,
                bottom: 16,
                child: FloatingActionButton.small(
                  // Le code porte l'onglet : deux onglets d'ouvrages coexistent
                  // dans l'`IndexedStack`, et deux héros de même tag dans une
                  // même route font échouer la transition.
                  heroTag: 'exit-immersion-work-${widget.code}',
                  tooltip: 'Quitter le mode immersion',
                  onPressed: _exitImmersion,
                  child: const Icon(Icons.fullscreen_exit),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _exitImmersion() async {
    final prefs = await AppPreferences.load();
    if (!prefs.immersion) return;
    prefs.immersion = false;
    await prefs.save();
  }

  Future<void> _enterImmersion() async {
    if (_findOpen) _closeFind();
    final prefs = await AppPreferences.load();
    if (prefs.immersion) return;
    prefs.immersion = true;
    await prefs.save();
  }

  // ---- Trouver dans le chapitre ----

  /// La barre d'un ouvrage suit le même seuil que la lecture parallèle du
  /// lecteur biblique : à partir de 600 de large l'icône rejoint la rangée.
  /// En deçà, pas de recherche plein texte — le sommaire du chapitre et le
  /// feuilletage portent la navigation.
  bool get _findIconInBar => MediaQuery.sizeOf(context).width >= 600;

  /// Le mode immersion suit le même seuil que la recherche : à partir de 600
  /// de large son icône rejoint la rangée de la barre.
  bool get _immersionInBar => MediaQuery.sizeOf(context).width >= 600;

  void _openFind() {
    setState(() => _findOpen = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    _findDebounce?.cancel();
    setState(() {
      _findOpen = false;
      _findController.clear();
      _findMatches = const [];
      _findIndex = -1;
      _findQuery = '';
    });
  }

  /// Debounced: balayer tous les blocs à chaque frappe brouterait sur les
  /// longs chapitres.
  void _onFindChanged(String query) {
    _findDebounce?.cancel();
    _findDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _runFind(query);
    });
  }

  void _runFind(String query) {
    final blocks = _work?.chapterAt(widget.chapter)?.blocks;
    final needle = normalizeForSearch(query);
    if (!mounted) return;
    if (needle.isEmpty || blocks == null) {
      setState(() {
        _findMatches = const [];
        _findIndex = -1;
        _findQuery = query;
      });
      return;
    }
    final matches = <int>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final hay = normalizeForSearch(
        '${block.text} ${block.gloss ?? ''} ${block.reference ?? ''}',
      );
      if (hay.contains(needle)) matches.add(i + 1);
    }
    setState(() {
      _findMatches = matches;
      _findIndex = matches.isEmpty ? -1 : 0;
      _findQuery = query;
    });
    _jumpToCurrentMatch();
  }

  void _stepFind(int direction) {
    if (_findMatches.isEmpty) return;
    var next = _findIndex + direction;
    if (next < 0) next = _findMatches.length - 1;
    if (next >= _findMatches.length) next = 0;
    setState(() => _findIndex = next);
    _jumpToCurrentMatch();
  }

  void _jumpToCurrentMatch() {
    if (_findIndex < 0 || _findIndex >= _findMatches.length) return;
    _jumpToBlock(_findMatches[_findIndex]);
  }

  /// Le compteur entre les flèches — « 3/12 », ou « 0 » quand rien ne matche.
  String get _findCounter {
    if (_findMatches.isEmpty) return '0';
    return '${_findIndex + 1}/${_findMatches.length}';
  }

  /// La ligne de recherche sous la barre d'actions : champ, compteur,
  /// précédent/suivant, fermer — le même visage que le lecteur biblique.
  Widget _buildFindBar() {
    final p = premiumPalette(context);
    return Material(
      color: premiumBackground(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _findController,
                focusNode: _findFocus,
                onChanged: _onFindChanged,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _stepFind(1),
                style: premiumText(context, 14, FontWeight.w500, p.textDark),
                decoration: InputDecoration(
                  hintText: 'Trouver dans le chapitre',
                  hintStyle: premiumText(
                    context,
                    14,
                    FontWeight.w400,
                    p.textGrey,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: p.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: premiumCardBorder(context, opacity: .34),
                    ),
                  ),
                  prefixIcon: Icon(Icons.search, size: 20, color: p.primary),
                ),
              ),
            ),
            Text(
              _findCounter,
              style: premiumText(context, 13, FontWeight.w700, p.textGrey),
            ),
            IconButton(
              tooltip: 'Occurrence précédente',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: _findMatches.isEmpty ? null : () => _stepFind(-1),
            ),
            IconButton(
              tooltip: 'Occurrence suivante',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _findMatches.isEmpty ? null : () => _stepFind(1),
            ),
            IconButton(
              tooltip: 'Fermer la recherche',
              icon: const Icon(Icons.close),
              onPressed: _closeFind,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Corps ----

  Widget _body(BuildContext context, FicheTextStyle style) {
    return FutureBuilder<Work?>(
      future: _workFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _MessagePanel(
            icon: Icons.error_outline,
            title: 'Lecture impossible',
            message: 'Le fichier de cet ouvrage est illisible.',
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          // Même squelette que la Bible, sans en-tête de livre : l'ouvrage
          // qui arrive est une suite de blocs, pas un chapitre numéroté.
          return ChapterLoadingSkeleton(header: widget.chapter == 0);
        }
        final work = snapshot.data;
        if (work == null) {
          return _MessagePanel(
            icon: Icons.menu_book_outlined,
            title: 'Ce livre n\'est plus sur l\'appareil',
            message: 'Téléchargez-le à nouveau depuis la Bibliothèque '
                'pour le lire ici.',
            action: widget.onOpenLibrary == null
                ? null
                : (
                    label: 'Bibliothèque',
                    onPressed: widget.onOpenLibrary!,
                  ),
          );
        }
        final chapter = work.chapterAt(widget.chapter);
        if (widget.chapter != 0 && chapter == null) {
          // Onglet restauré sur un chapitre que l'ouvrage ne porte plus :
          // revenir au sommaire vaut mieux qu'un blanc.
          return _MessagePanel(
            icon: Icons.menu_book_outlined,
            title: 'Chapitre introuvable',
            message: 'Cet ouvrage ne compte que ${work.chapters.length} '
                'chapitres.',
            action: (label: 'Sommaire', onPressed: () => _openChapter(0)),
          );
        }
        _scheduleRestore();
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _swipeDx = 0,
          onHorizontalDragUpdate: (d) =>
              _swipeDx = (_swipeDx ?? 0) + d.delta.dx,
          onHorizontalDragEnd: _onSwipe,
          child: widget.chapter == 0
              ? _sommaire(context, work, style)
              : _chapterBody(context, work, chapter!, style),
        );
      },
    );
  }

  /// Le texte de l'ouvrage lit à la taille, la police et l'alignement de la
  /// famille `fiche.*` : un seul `Theme` posé sur la liste, plutôt qu'un
  /// style recopié bloc par bloc — `NoteAwareVerseText` lit `bodyLarge` dans
  /// le thème, et ses glyphs de note dérivent de la même mesure, donc les
  /// deux suivent le curseur sans qu'aucun code n'ait à les reprendre.
  Widget _themed(BuildContext context, FicheTextStyle style, Widget child) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge?.fontSize ?? 16;
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          fontSizeFactor: style.fontSize / base,
          fontFamily: style.fontFamily,
        ),
      ),
      child: child,
    );
  }

  // ---- Chapitre 0 : le sommaire ----

  Widget _sommaire(BuildContext context, Work work, FicheTextStyle style) {
    final p = premiumPalette(context);
    final cover = workByCode(work.code)?.cover;
    return _themed(
      context,
      style,
      ListView(
        key: const Key('workSommaire'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          if (cover != null) ...[
            Center(child: _SommaireCover(asset: cover)),
            const SizedBox(height: 18),
          ],
          Text(
            work.title,
            textAlign: TextAlign.center,
            style: premiumText(context, 20, FontWeight.w800, p.textDark, height: 1.25),
          ),
          if (work.subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              work.subtitle,
              textAlign: TextAlign.center,
              style: premiumText(
                context,
                13.5,
                FontWeight.w700,
                p.primary,
                height: 1.3,
              ),
            ),
          ],
          if (work.author.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              work.author,
              textAlign: TextAlign.center,
              style: premiumText(context, 12.5, FontWeight.w500, p.textGrey),
            ),
          ],
          const SizedBox(height: 26),
          Text(
            'SOMMAIRE',
            style: premiumText(
              context,
              11,
              FontWeight.w800,
              p.primary,
              spacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: p.primary.withValues(alpha: .16)),
          const SizedBox(height: 4),
          for (var i = 0; i < work.toc.length; i++)
            _tocRow(context, work.toc[i], i),
          if (work.publisher.isNotEmpty || work.isbn.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              [
                if (work.publisher.isNotEmpty) work.publisher,
                if (work.isbn.isNotEmpty) 'ISBN ${work.isbn}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: premiumText(context, 11.5, FontWeight.w500, p.textGrey),
            ),
          ],
          if (work.rights.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(height: 1, color: p.textGrey.withValues(alpha: .18)),
            const SizedBox(height: 10),
            Text(
              work.rights,
              textAlign: TextAlign.center,
              style: premiumText(context, 11, FontWeight.w600, p.textGrey, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  /// Une ligne du sommaire : indentée par son niveau, et tapable dès qu'elle
  /// mène à un chapitre. Une section imprimée sans destination (`chapter` 0)
  /// reste du texte — une ligne qui ne mène nulle part ne doit pas se faire
  /// passer pour un lien.
  Widget _tocRow(BuildContext context, WorkTocItem item, int index) {
    final p = premiumPalette(context);
    final opens = item.hasDestination;
    final level0 = item.level == 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('work-toc-$index'),
        onTap: opens ? () => _openChapter(item.chapter) : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(4 + 22.0 * item.level, 11, 4, 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: premiumText(
                    context,
                    level0 ? 14.5 : 13.5,
                    level0 ? FontWeight.w800 : FontWeight.w600,
                    level0 ? p.textDark : p.textGrey,
                    height: 1.4,
                  ),
                ),
              ),
              if (opens)
                Icon(Icons.chevron_right, size: 18, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Chapitres 1..N ----

  Widget _chapterBody(
    BuildContext context,
    Work work,
    WorkChapter chapter,
    FicheTextStyle style,
  ) {
    // Le pied « Continuer » ferme la liste : un item de plus que [_itemCount],
    // qui ne compte que les positions.
    final footer = _continueFooter(work);
    final itemCount = chapter.blocks.length + 1 + (footer == null ? 0 : 1);
    return _themed(
      context,
      style,
      NotificationListener<ScrollNotification>(
        // Un lecteur qui tire la liste lui-même lève l'épingle du bloc
        // restauré : les rapports redeviennent une estimation honnête.
        // `dragDetails` ne porte que sur un geste tactile — un saut
        // programmatique (jumpTo, ensureVisible) passe ici sans la lever.
        onNotification: (notification) {
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null &&
              _anchorBlock != null) {
            setState(() => _anchorBlock = null);
          }
          return false;
        },
        child: ListView.builder(
          key: _listKey,
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            final Widget content;
            if (index == 0) {
              content = _chapterHeader(context, chapter);
            } else if (footer != null && index == itemCount - 1) {
              content = footer;
            } else {
              final block = chapter.blocks[index - 1];
              content = Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: _block(context, block, style),
              );
            }
            // Chaque tuile porte l'index de son item : [_builtTiles] lit ces
            // clés dans l'arbre pour savoir quelles tuiles la liste a
            // réellement construites, et où elles se trouvent — l'unique
            // mesure dont dépend un saut juste. Un `KeyedSubtree` ne coûte
            // rien : c'est un nœud de plus, pas un rendu de plus.
            final tile = KeyedSubtree(
              key: _WorkItemKey(index),
              child: content,
            );
            // La tuile de la position courante porte la clé d'ancre ; deux
            // d'entre elles ne la portent jamais à la fois (un `GlobalKey`
            // dupliqué dans une même route est une erreur), et elle ne se
            // déplace que sur une reprise ou un saut de section.
            final anchored = index == _anchorBlock
                ? Container(key: _anchorKey, child: tile)
                : tile;
            final wash = _matchWash(index);
            if (wash == null) return anchored;
            return Container(color: wash, child: anchored);
          },
        ),
      ),
    );
  }

  /// La recherche active à peindre dans le texte, ou null : champ fermé ou
  /// frappe vide, le rendu reste nu.
  String? get _activeHighlight {
    if (!_findOpen) return null;
    final query = _findQuery.trim();
    return query.isEmpty ? null : query;
  }

  /// La wash d'un item de la liste : tous les blocs matchés se voient en
  /// défilant, le courant plus fort — le régime exact du lecteur biblique
  /// (`isSearchMatch`). Les index 1-based des matchs sont ceux des items.
  Color? _matchWash(int itemIndex) {
    if (!_findOpen || _findMatches.isEmpty) return null;
    if (!_findMatches.contains(itemIndex)) return null;
    final p = premiumPalette(context);
    if (_findIndex >= 0 &&
        _findIndex < _findMatches.length &&
        _findMatches[_findIndex] == itemIndex) {
      return p.primary.withValues(alpha: .22);
    }
    return p.primarySoft;
  }

  /// Un texte avec les occurrences de la recherche peintes — le pendant
  /// ouvrage du `_HighlightedText` de l'écran Recherche. Sans recherche
  /// active, le Text nu d'origine, à style identique.
  Widget _richText(String text, {TextStyle? style}) {
    final query = _activeHighlight;
    if (query == null) {
      return Text(text, style: style);
    }
    final p = premiumPalette(context);
    return Text.rich(
      TextSpan(
        children: highlightedSpans(
          text: text,
          query: query,
          highlight: TextStyle(
            backgroundColor: p.primary.withValues(alpha: .28),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      style: style,
    );
  }

  /// Le bouton « Continuer » en pied de chapitre, ou null.
  ///
  /// La fin de la page est l'endroit où un lecteur cherche la suite : les
  /// flèches ‹ › du haut sont hors écran quand on y arrive. C'est exactement
  /// la raison d'être du même bouton dans `ChapterReader`, et les deux se
  /// comportent pareil — absent du sommaire (une table ne se « continue »
  /// pas), absent du dernier chapitre, absent en immersion où toutes les
  /// commandes cèdent la place au texte.
  Widget? _continueFooter(Work work) {
    if (widget.chapter == 0 || widget.chapter >= work.chapters.length) {
      return null;
    }
    if (AppPreferences.immersionNotifier.value) return null;
    final next = widget.chapter + 1;
    return _ContinueWorkTile(
      label: work.labelAt(next),
      onTap: () => _openChapter(next),
    );
  }

  Widget _chapterHeader(BuildContext context, WorkChapter chapter) {
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapter.title,
            style: premiumText(context, 18, FontWeight.w800, p.primary, height: 1.3),
          ),
          const SizedBox(height: 12),
          // Filet d'accent éteint aux extrémités, le même que celui de la
          // barre d'actions : le chapitre s'ouvre sur la langue du lecteur.
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  p.primary.withValues(alpha: .45),
                  p.primary.withValues(alpha: .06),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _block(BuildContext context, WorkBlock block, FicheTextStyle style) {
    final p = premiumPalette(context);
    final body = Theme.of(context).textTheme.bodyLarge;
    switch (block.kind) {
      case WorkBlockKind.heading2:
      case WorkBlockKind.heading3:
      case WorkBlockKind.heading4:
        // Le rang se lit à la mesure : h2 au-dessus du corps, h4 en-dessous —
        // les intertitres d'un livre sont de taille décroissante, jamais
        // croissante.
        final factor = switch (block.kind) {
          WorkBlockKind.heading2 => 1.18,
          WorkBlockKind.heading3 => 1.06,
          _ => 0.95,
        };
        return Padding(
          padding: EdgeInsets.only(
            top: block.kind == WorkBlockKind.heading2 ? 14 : 10,
            bottom: 6,
          ),
          child: _richText(
            block.text,
            style: body?.copyWith(
              fontSize: (body.fontSize ?? 16) * factor,
              fontWeight: FontWeight.w800,
              height: 1.35,
              letterSpacing: .2,
            ),
          ),
        );

      case WorkBlockKind.paragraph:
        // Le widget de notes de la BYM, tel quel : même convention
        // `text`/`textWithNotes`/`notes`, donc rien à lui apprendre. La
        // disposition est **inline** et non la préférence biblique — les
        // notes d'un ouvrage sont des notes de bas de page, faire disparaître
        // celle qui est éteinte ailleurs couperait le texte de son appareil.
        // La recherche y peint ses occurrences comme dans les autres blocs.
        return NoteAwareVerseText(
          verse: block.asVerse(),
          disposition: NoteDisposition.inline,
          textAlign: style.align,
          highlightQuery: _activeHighlight,
          onReferenceTap: widget.onOpenVerse == null
              ? null
              : (ref) => _openReference(ref),
        );

      case WorkBlockKind.quote:
        final reference = block.reference;
        final parsed = reference == null ? null : parseReference(reference);
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: p.primarySoft,
            // Bordure gauche seule : une citation se détache par son retrait,
            // pas par une boîte fermée — le texte imprimé fait pareil.
            border: Border(left: BorderSide(color: p.primary, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _richText(
                block.text,
                style: body?.copyWith(
                  fontStyle: FontStyle.italic,
                  height: 1.6,
                ),
              ),
              if (reference != null) ...[
                const SizedBox(height: 8),
                if (parsed == null || widget.onOpenVerse == null)
                  _richText(
                    reference,
                    style: body?.copyWith(
                      fontSize: (body.fontSize ?? 16) * .87,
                      fontWeight: FontWeight.w700,
                      color: p.primary,
                    ),
                  )
                else
                  InkWell(
                    key: ValueKey('work-reference'),
                    onTap: () => _openReference(parsed),
                    child: _richText(
                      reference,
                      style: body?.copyWith(
                        fontSize: (body.fontSize ?? 16) * .87,
                        fontWeight: FontWeight.w700,
                        color: p.primary,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                        decorationColor: p.primary,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );

      case WorkBlockKind.item:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('•', style: body?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(
              child: _richText(
                block.text,
                style: body?.copyWith(height: 1.6),
              ),
            ),
          ],
        );

      case WorkBlockKind.pair:
        // Le tableau des noms : l'original à gauche, sa glose française à
        // droite — deux colonnes que la liste garde alignées d'une ligne à
        // l'autre.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _richText(
                block.text,
                style: body?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            if (block.gloss case final String gloss)
              Expanded(
                child: _richText(
                  gloss,
                  style: body?.copyWith(color: p.textGrey),
                ),
              ),
          ],
        );
    }
  }
}

/// La clé d'une tuile du chapitre : elle porte l'index de l'item dans la
/// liste.
///
/// Elle est de type dédié, et non `ValueKey<int>` nu, parce que [_builtTiles]
/// promène cette clé dans tout le sous-arbre de la liste pour mesurer les
/// tuiles vivantes : un `ValueKey<int>` posé plus bas, par un bloc ou par une
/// dépendance, serait lu comme une tuile de la liste et déplacerait le saut.
/// Une classe privée ne peut pas être fabriquée ailleurs — la confusion
/// devient impossible par construction.
class _WorkItemKey extends ValueKey<int> {
  const _WorkItemKey(super.value);
}

/// Le bouton « Continuer » en pied de chapitre d'un ouvrage — le jumeau de
/// celui de `ChapterReader`, en langue premium puisque ce lecteur n'est pas
/// dans la coquille biblique.
///
/// Le libellé est tronqué à une ligne : les intitulés de ce livre vont jusqu'à
/// 58 caractères (`CONCLUSION : LE SEIGNEUR OU LE MINISTÈRE QUE PRÉFÈRES-TU ?`)
/// et le bouton doit rester un bouton, pas une déclaration sur trois lignes.
/// `OutlinedButton.icon` enveloppe son libellé d'un `Flexible`, l'ellipse tient
/// donc dans la largeur que la liste lui donne.
class _ContinueWorkTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ContinueWorkTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: p.textGrey.withValues(alpha: .22),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Fin du chapitre',
                  style: premiumText(context, 11, FontWeight.w600, p.textGrey),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: p.textGrey.withValues(alpha: .22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              // Liseré neutre plutôt que la tranche d'accent : le libellé et
              // l'icône gardent la couleur du thème, le contour rejoint les
              // cartes premium.
              side: BorderSide(
                color: premiumCardBorder(context, opacity: .45),
              ),
              foregroundColor: p.primary,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
            ),
            icon: const Icon(Icons.arrow_downward, size: 18),
            label: Text(
              'Continuer — $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// La pochette en tête du sommaire, à la largeur d'une vignette de couverture
/// imprimée — assez grande pour lire le titre dessus, assez petite pour que la
/// page reste un sommaire.
///
/// L'`errorBuilder` n'est pas une précaution de style : un ouvrage catalogué
/// dont la page 1 ne portait aucune image n'a pas de pochette, et la page doit
/// alors s'ouvrir sur son texte plutôt que sur la croix rouge de Flutter.
class _SommaireCover extends StatelessWidget {
  final String asset;

  const _SommaireCover({required this.asset});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: premiumShadow(
          p.primaryDark,
          opacity: .22,
          blur: 16,
          offset: const Offset(0, 6),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          asset,
          width: 156,
          fit: BoxFit.fitWidth,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Le panneau de repli du lecteur : un ouvrage absent, illisible ou dont le
/// chapitre demandé n'existe plus. Même langue que les panneaux vides du
/// reste de l'app — un disque teinté, un titre, une phrase, une action.
class _MessagePanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  /// L'action de sortie, ou null pour un panneau qui se contente de dire.
  final ({String label, VoidCallback onPressed})? action;

  const _MessagePanel({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          decoration: premiumSurface(context, radius: 20, depth: 1.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: p.primarySoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 32, color: p.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: premiumText(context, 17, FontWeight.w800, p.textDark),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: premiumText(
                  context,
                  13,
                  FontWeight.w500,
                  p.textGrey,
                  height: 1.5,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: action!.onPressed,
                  child: Text(action!.label),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
