import 'package:flutter/material.dart';

import '../data/app_preferences.dart';
import '../data/book_catalog.dart';
import '../data/dictionary_catalog.dart';
import '../data/dictionary_reader.dart';
import '../data/dictionary_store.dart';
import '../data/fredaw_lexicon.dart';
import '../data/lsgs_repository.dart';
import '../data/strong_lexicon.dart';
import '../data/verse_dictionary.dart';
import '../data/version_repository.dart';
import '../models/lsgs.dart';
import '../widgets/fiche_text_settings.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/premium_style.dart';
import '../widgets/strong_lemma.dart';
import '../widgets/strong_senses.dart';
import 'dictionary_entry_screen.dart';
import 'fredaw_entry_screen.dart';
import 'strong_detail_screen.dart';

/// Mode actif de l'écran d'étude d'un verset : lexique Strong (hébreu/grec) ou
/// dictionnaire (Westphal 1932).
enum ModeEtude { lexique, dictionnaire }

/// Entrée de la bibliothèque du mode LEXIQUE : le mot du verset et la fiche
/// Strong qui lui est associée.
class EntreeLexique {
  final String texte;
  final String translit;
  final String prononciation;
  final String original;
  final String strongId;
  final List<String> definitions;
  final StrongDefinition fiche;

  /// Le mot de cette entrée n'a pas d'équivalent français : le verset porte
  /// le code, rien d'autre. La carte le dit au lieu de laisser une fiche muette.
  final bool sansTraduction;

  const EntreeLexique({
    required this.texte,
    required this.translit,
    required this.prononciation,
    required this.original,
    required this.strongId,
    required this.definitions,
    required this.fiche,
    this.sansTraduction = false,
  });
}

/// Entrée de la bibliothèque du mode DICTIONNAIRE : le terme repéré dans le
/// verset et l'article qui le définit — quelle que soit la source, le
/// Westphal embarqué ou un dictionnaire téléchargé (les deux ne portent que
/// le terme et sa définition).
class EntreeDico {
  final String texte;
  final String titre;
  final String section;
  final String extrait;
  final DictionaryArticle fiche;

  const EntreeDico({
    required this.texte,
    required this.titre,
    required this.section,
    required this.extrait,
    required this.fiche,
  });
}

/// Un morceau du verset : du texte simple, ou un mot cliquable qui renvoie à
/// l'entrée [entreeIndex] de la bibliothèque active.
class SegmentVerset {
  final String texte;
  final int? entreeIndex;

  /// Un mot que la traduction ne rend pas (waw, article, préfixe) : [texte]
  /// y porte le code Strong lui-même, et le rendu le montre en pastille
  /// discrète à la place d'une pilule vide.
  final bool sansTraduction;

  const SegmentVerset.plain(this.texte)
      : entreeIndex = null,
        sansTraduction = false;

  const SegmentVerset.mot(
    this.texte,
    this.entreeIndex, {
    this.sansTraduction = false,
  });
}

/// Écran combiné « Lexique & Dictionnaire » du verset courant (maquette
/// `ecran_cliquable_verset_mot_a_mot_mod_lexique&dictionnaire.dart`).
///
/// Le verset est rendu mot à mot, cliquable dans les deux modes :
/// - **Lexique** : les mots porteurs d'un numéro Strong ouvrent la fiche
///   Strong française (hébreu/grec) ; les cartes sont swipables. Le corpus
///   dont viennent les codes se choisit dans l'AppBar — la LSS ou la LSGS.
/// - **Dictionnaire** : les mots qui sont des articles du dictionnaire
///   ouvrent un aperçu de l'article, avec accès à la fiche complète. Le
///   dictionnaire se choisit dans l'AppBar, lui aussi : le Westphal 1932
///   embarqué, ou un dictionnaire téléchargé depuis la Bibliothèque.
///
/// Au goût premium : fond crème, cartes blanches à ombre douce, accents du
/// thème actif.
class EtudeVersetScreen extends StatefulWidget {
  final int bookIndex;
  final int chapter;
  final int verseNumber;
  final List<LsgsToken> tokens;

  /// Fiche Strong à présélectionner à l'ouverture (code, ex. « H7225 »).
  final String? initialStrong;

  /// Les numéros des versets du chapitre courant, dans l'ordre — rend la
  /// navigation « Verset précédent / suivant » possible. Null hors coquille
  /// (tests) : la rangée de navigation est alors masquée.
  final List<int>? verseNumbers;

  /// Charge les tokens d'un autre verset du même chapitre, pour la navigation
  /// précédent / suivant. Null hors coquille : navigation masquée.
  final Future<List<LsgsToken>> Function(int verseNumber)? loadVerseTokens;

  /// Ouvre un verset d'occurrence choisi dans une fiche Strong complète : la
  /// coquille cible ce verset dans l'écran lecture. Null hors coquille : les
  /// occurrences de la fiche restent en lecture seule.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  /// Où les dictionnaires téléchargés par la Bibliothèque sont lus, pour le
  /// choix du dictionnaire. Null hors coquille : l'écran prend le store de
  /// l'appareil ; les tests en injectent un en mémoire, `path_provider`
  /// ne répondant jamais dans le zone fake-async des tests.
  final DictionaryStore? dictionaryStore;

  const EtudeVersetScreen({
    super.key,
    required this.bookIndex,
    required this.chapter,
    required this.verseNumber,
    required this.tokens,
    this.initialStrong,
    this.verseNumbers,
    this.loadVerseTokens,
    this.onOpenVerse,
    this.dictionaryStore,
  });

  @override
  State<EtudeVersetScreen> createState() => _EtudeVersetScreenState();
}

class _EtudeVersetScreenState extends State<EtudeVersetScreen> {
  /// Colonnes en vigueur — voir [_colonnesPour]. Démarre à 1, ce qui correspond
  /// au contrôleur alloué juste en dessous.
  int _colonnes = 1;

  /// Une carte par page : c'est le `viewportFraction` de ce contrôleur qui
  /// décide combien de cartes tiennent côte à côte. Un `PageController` ne
  /// change pas de fraction après sa création — c'est pourquoi un changement
  /// de [_colonnes] en alloue un neuf ([didChangeDependencies]).
  PageController _pageController = PageController(viewportFraction: 0.9);

  ModeEtude _mode = ModeEtude.lexique;
  int _entreeCourante = 0;

  /// Corpus dont viennent les tokens affichés — la **LSS** de Biblia par
  /// défaut, la LSGS en repli. L'écran le choisit lui-même ; le lecteur
  /// relit la préférence à chaque navigation, c'est ce champ qui pilote le
  /// rechargement.
  String _corpus = EtudePreferences.defaultVersionCode;

  /// Dictionnaire du mode DICTIONNAIRE — le Westphal 1932 embarqué par
  /// défaut, ou un dictionnaire téléchargé depuis la Bibliothèque, ouvert
  /// depuis [EtudePreferences.dictionaryCode]. Un fichier supprimé depuis la
  /// Bibliothèque retombe ici sur l'embarqué : le choix enregistré reste
  /// écrit, et revient tout seul quand le fichier revient.
  VerseDictionary _dictionnaire = const WestphalVerseDictionary();

  late int _verseNumber;
  late List<LsgsToken> _tokens;

  List<SegmentVerset> _segmentsLexique = const [];
  List<EntreeLexique> _entreesLexique = const [];
  bool _lexiqueReady = false;

  List<SegmentVerset> _segmentsDico = const [];
  List<EntreeDico> _entreesDico = const [];
  bool _dicoReady = false;

  bool get _hasNav =>
      widget.verseNumbers != null && widget.loadVerseTokens != null;

  List<SegmentVerset> get _segments =>
      _mode == ModeEtude.lexique ? _segmentsLexique : _segmentsDico;

  int get _nbEntrees =>
      _mode == ModeEtude.lexique ? _entreesLexique.length : _entreesDico.length;

  @override
  void initState() {
    super.initState();
    _verseNumber = widget.verseNumber;
    _tokens = widget.tokens;
    _readCorpus();
    _buildLexique();
    _openDictionnaire();
  }

  /// Le corpus enregistré — affiché au-dessus de la fiche et relut à chaque
  /// changement, l'écran pouvant le modifier lui-même.
  Future<void> _readCorpus() async {
    final prefs = await EtudePreferences.load();
    if (!mounted || prefs.versionCode == _corpus) return;
    setState(() => _corpus = prefs.versionCode);
  }

  /// Ouvre le dictionnaire choisi — [code] passé par le sélecteur, sinon
  /// l'enregistrement de l'utilisateur — puis reconstruit les cartes du
  /// verset dessus.
  ///
  /// Un code que [verseDictionaryFor] ne peut pas servir (fichier supprimé
  /// depuis la Bibliothèque, dictionnaire jamais téléchargé) retombe sur le
  /// Westphal embarqué, qui est le dictionnaire de tous les jours.
  Future<void> _openDictionnaire({String? code}) async {
    final stored = code ?? (await EtudePreferences.load()).dictionaryCode;
    final dictionnaire = await verseDictionaryFor(
          stored,
          store: widget.dictionaryStore,
        ) ??
        const WestphalVerseDictionary();
    if (!mounted) return;
    setState(() {
      _dictionnaire = dictionnaire;
      _dicoReady = false;
    });
    await _buildDico();
  }

  /// Nombre de cartes affichées côte à côte selon la largeur de l'écran.
  ///
  /// Portrait de téléphone : **1**, la carte garde 90 % de la largeur et laisse
  /// voir le bord de la suivante — c'est cette arête qui invite au glissement.
  /// Dès 600 px (paysage de téléphone comme petite tablette) une seule carte
  /// étirée sur toute la largeur vide les côtés : **2**, puis **3** à 900 et
  /// **4** à 1200, au pas de grille des Thèmes. La marge de 6 px de chaque
  /// carte devient la gouttière entre colonnes.
  static int _colonnesPour(double width) =>
      width >= 1200 ? 4 : width >= 900 ? 3 : width >= 600 ? 2 : 1;

  /// Fraction de viewport d'une carte pour [colonnes] colonnes. En colonne
  /// unique, 0.9 comme toujours : carte centrée, arête de la suivante visible.
  static double _fraction(int colonnes) => colonnes == 1 ? 0.9 : 1 / colonnes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seul endroit où l'on a le droit de lire `MediaQuery` — et donc celui où
    // la rotation de l'écran est vue. Le contrôleur est réalloué en gardant la
    // carte affichée ; l'ancien n'est libéré qu'après la frame, parce que le
    // `PageView` ne se rattache au neuf qu'au moment de sa reconstruction.
    final colonnes = _colonnesPour(MediaQuery.sizeOf(context).width);
    if (colonnes == _colonnes) return;
    final page = _pageController.hasClients
        ? _pageController.page?.round() ?? 0
        : 0;
    final retire = _pageController;
    _colonnes = colonnes;
    _pageController = PageController(
      viewportFraction: _fraction(colonnes),
      initialPage: page,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => retire.dispose());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Construit la bibliothèque et les segments du mode LEXIQUE depuis les
  /// tokens du verset : chaque numéro Strong devient un mot cliquable relié à
  /// sa fiche (une fiche par code, les répétitions partagent la même entrée).
  Future<void> _buildLexique() async {
    final entries = <EntreeLexique>[];
    final segments = <SegmentVerset>[];
    final indexByStrong = <String, int>{};
    for (final token in _tokens) {
      final strong = token.strong;
      if (strong == null || strong.isEmpty) {
        segments.add(SegmentVerset.plain(token.text));
        continue;
      }
      final codes = StrongLexicon.codesOf(strong);
      if (codes.isEmpty) {
        segments.add(SegmentVerset.plain(token.text));
        continue;
      }
      // Un mot que la traduction ne rend pas (waw, article, préfixe) : le code
      // Strong est le seul libellé qu'il puisse avoir — il devient le texte de
      // la pastille et de la carte, au lieu d'un blanc.
      final texte = token.text.trim();
      final sansTraduction = texte.isEmpty;
      final libelle = sansTraduction ? codes.first : texte;
      // Un mot du corpus peut porter deux codes Strong d'un coup (« G3588
      // G4674 » en Jean 18.35) : chacun a sa fiche et son entrée, le segment
      // du mot se rattache au premier.
      var index = -1;
      for (final code in codes) {
        final known = indexByStrong[code];
        if (known != null) {
          if (index < 0) index = known;
          continue;
        }
        final definition = await StrongLexicon.instance.lookup(code);
        final fresh = entries.length;
        indexByStrong[code] = fresh;
        entries.add(
          EntreeLexique(
            texte: libelle,
            translit: definition.transliteration ?? '',
            prononciation: definition.pronunciation ?? '',
            original: definition.lemma ?? '',
            strongId: definition.strong,
            definitions: definition.senses.isNotEmpty
                ? definition.senses
                : [definition.definition],
            fiche: definition,
            sansTraduction: sansTraduction,
          ),
        );
        if (index < 0) index = fresh;
      }
      segments.add(
        SegmentVerset.mot(libelle, index, sansTraduction: sansTraduction),
      );
    }
    if (!mounted) return;
    setState(() {
      _entreesLexique = entries;
      _segmentsLexique = segments;
      _lexiqueReady = true;
    });
    final initial = widget.initialStrong;
    if (initial != null && indexByStrong.containsKey(initial)) {
      _selectEntree(indexByStrong[initial]!, scroll: false);
    }
  }

  /// Construit la bibliothèque et les segments du mode DICTIONNAIRE : le texte
  /// nu du verset est découpé sur les termes que le dictionnaire connaît
  /// ([VerseDictionary.linkPattern]), chaque terme devenant un mot cliquable.
  ///
  /// Le dictionnaire vient de [_dictionnaire] — le Westphal ou un téléchargé
  /// — et c'est lui qui donne le visage des cartes : un mot que l'un connaît
  /// peut être inconnu de l'autre.
  Future<void> _buildDico() async {
    final dictionnaire = _dictionnaire;
    final plain = LsgsRepository.joinTokens(_tokens);
    final pattern = await dictionnaire.linkPattern();
    if (!mounted) return;
    final entries = <EntreeDico>[];
    final segments = <SegmentVerset>[];
    if (pattern == null) {
      segments.add(SegmentVerset.plain(plain));
    } else {
      var cursor = 0;
      for (final match in pattern.allMatches(plain)) {
        if (match.start > cursor) {
          segments.add(
            SegmentVerset.plain(plain.substring(cursor, match.start)),
          );
        }
        final term = match.group(0)!;
        final article = await dictionnaire.lookup(term);
        if (!mounted) return;
        if (article == null) {
          // Le motif d'un dictionnaire téléchargé ne devrait jamais proposer
          // un mot qu'il n'a pas : si le fichier est tronqué, le verset
          // garde ce mot en texte nu plutôt qu'une fiche muette.
          segments.add(
            SegmentVerset.plain(plain.substring(cursor, match.end)),
          );
          cursor = match.end;
          continue;
        }
        final index = entries.length;
        entries.add(_dicoEntry(term, article));
        segments.add(SegmentVerset.mot(term, index));
        cursor = match.end;
      }
      if (cursor < plain.length) {
        segments.add(SegmentVerset.plain(plain.substring(cursor)));
      }
    }
    if (!mounted) return;
    setState(() {
      _entreesDico = entries;
      _segmentsDico = segments;
      _dicoReady = true;
    });
  }

  /// Découpe la définition : le premier paragraphe fait office de section
  /// (« 1. Introduction. » chez Westphal), le reste est l'extrait défilable.
  EntreeDico _dicoEntry(String term, DictionaryArticle article) {
    final paragraphs = article.definition
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final section = paragraphs.length > 1 ? paragraphs.first : '';
    final extrait = paragraphs.length > 1
        ? paragraphs.skip(1).join('\n\n')
        : article.definition;
    return EntreeDico(
      texte: term,
      titre: article.term,
      section: section,
      extrait: extrait,
      fiche: article,
    );
  }

  void _changerMode(ModeEtude m) {
    if (m == _mode) return;
    setState(() {
      _mode = m;
      _entreeCourante = 0;
    });
    // revient à la première carte après le changement de mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
  }

  void _selectEntree(int index, {bool scroll = true}) {
    setState(() => _entreeCourante = index);
    if (scroll && _pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// Navigation « Verset précédent / suivant » dans le chapitre courant.
  Future<void> _navigateTo(int verseNumber) async {
    final loader = widget.loadVerseTokens;
    if (loader == null || verseNumber == _verseNumber) return;
    final tokens = await loader(verseNumber);
    if (!mounted) return;
    setState(() {
      _verseNumber = verseNumber;
      _tokens = tokens;
      _entreeCourante = 0;
      _lexiqueReady = false;
      _dicoReady = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) _pageController.jumpToPage(0);
    });
    _buildLexique();
    _buildDico();
  }

  int get _verseIndex {
    final numbers = widget.verseNumbers;
    if (numbers == null) return 0;
    return numbers.indexOf(_verseNumber);
  }

  /// Choix du corpus dont vient la fiche.
  ///
  /// Il n'y en a que deux, et c'est [VersionRepository.tokensFor] qui en
  /// décide : la LSS de Biblia, qui numérote les particules que la LSGS
  /// ignore, et la LSGS que lit le texte. Proposer le catalogue entier serait
  /// trompeur — une version sans ancre Strong retomberait en silence sur la
  /// LSGS, sans que le choix de l'utilisateur ait rien changé.
  Future<void> _pickCorpus() async {
    final p = premiumPalette(context);
    final options = [
      (
        code: VersionRepository.lssCode,
        name: 'LSS — Segond Louis + Strong',
        note: 'Ancre aussi les particules que la traduction ne rend pas '
            '(waw, article, préfixes) : c\'est le lexique le plus complet.',
      ),
      (
        code: VersionRepository.lsgsCode,
        name: 'LSGS — Segond 1910 + Strongs',
        note: 'Le texte que vous lisez, ancre par ancre.',
      ),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: premiumBackground(context),
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          decoration: premiumSurface(context, radius: 24, depth: 1.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Corpus du lexique',
                  style: premiumText(context, 16, FontWeight.w800, p.textDark),
                ),
              ),
              for (final option in options)
                _OptionLigne(
                  name: option.name,
                  note: option.note,
                  selected: option.code == _corpus,
                  onTap: () {
                    Navigator.of(context).pop();
                    _useCorpus(option.code);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Enregistre le corpus choisi et recharge le verset courant dessus.
  Future<void> _useCorpus(String code) async {
    if (code == _corpus) return;
    final prefs = await EtudePreferences.load();
    prefs.versionCode = code;
    await prefs.save();
    if (!mounted) return;
    setState(() {
      _corpus = code;
      _entreeCourante = 0;
      _lexiqueReady = false;
      _dicoReady = false;
    });
    // Le lecteur relit la préférence à chaque navigation : c'est donc le même
    // chemin que « verset suivant », qui recharge depuis le corpus choisi.
    final tokens = await widget.loadVerseTokens?.call(_verseNumber);
    if (!mounted) return;
    setState(() => _tokens = tokens ?? _tokens);
    _buildLexique();
    _buildDico();
  }

  /// Choix du dictionnaire du mode DICTIONNAIRE.
  ///
  /// Il n'y en a que deux sortes : le Westphal 1932 embarqué, et ce que la
  /// Bibliothèque a téléchargé sur l'appareil — la même honnêteté que le
  /// sélecteur de version de la lecture, qui ne propose que ce qui a du
  /// texte à servir. Le catalogue entier ne serait pas vrai : un
  /// dictionnaire non téléchargé n'a rien à ouvrir, Nave n'a aucune source,
  /// et le Strong français est indexé par numéro et non par mot — sa place
  /// est l'onglet Lexique.
  Future<void> _pickDictionnaire() async {
    final p = premiumPalette(context);
    final dictionnaires = await availableVerseDictionaries(
      store: widget.dictionaryStore,
    );
    if (!mounted || dictionnaires.isEmpty) return;
    final catalogue = {
      for (final entry in dictionaryCatalog) entry.code: entry,
    };

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: premiumBackground(context),
      builder: (context) => SafeArea(
        top: false,
        child: Container(
          decoration: premiumSurface(context, radius: 24, depth: 1.3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Dictionnaire de l\'étude',
                  style: premiumText(context, 16, FontWeight.w800, p.textDark),
                ),
              ),
              for (final dictionnaire in dictionnaires)
                _OptionLigne(
                  name: dictionnaire.name,
                  note: '${catalogue[dictionnaire.code]?.rights ?? ''} — '
                      '${dictionnaire.embedded ? 'embarqué, hors ligne' : 'téléchargé sur l\'appareil'}.',
                  selected: dictionnaire.code == _dictionnaire.code,
                  onTap: () {
                    Navigator.of(context).pop();
                    _useDictionnaire(dictionnaire.code);
                  },
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text(
                  'D\'autres dictionnaires se téléchargent depuis la '
                  'Bibliothèque, puis se choisissent ici.',
                  style: premiumText(
                    context,
                    12,
                    FontWeight.w500,
                    p.textGrey,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Enregistre le dictionnaire choisi et reconstruit le verset dessus.
  Future<void> _useDictionnaire(String code) async {
    if (code == _dictionnaire.code) return;
    final prefs = await EtudePreferences.load();
    prefs.dictionaryCode = code;
    await prefs.save();
    if (!mounted) return;
    setState(() => _entreeCourante = 0);
    // Même chemin que « ouvrir » : c'est lui qui relit le store, donc un
    // téléchargement qui vient d'atterrir est déjà ouvrable.
    await _openDictionnaire(code: code);
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) _pageController.jumpToPage(0);
      });
    }
  }

  void _stubSnack(String label) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label — bientôt disponible.')));
  }

  @override
  Widget build(BuildContext context) {
    return FicheTextScope(
      group: DisplayGroup.etude,
      builder: (context, style) => _scaffold(context, style),
    );
  }

  Widget _scaffold(BuildContext context, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    final entry = catalogEntry(widget.bookIndex);
    final reference = '${entry.shortName} ${widget.chapter}:$_verseNumber';

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        // L'AppBar est transparente : ce voile d'accent la rattache au fond
        // sans coûter une ligne de hauteur.
        flexibleSpace: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.center,
              colors: [
                accent.withValues(alpha: .12),
                accent.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        actions: [
          // Le bouton suit le mode : corpus du lexique dans l'onglet
          // Lexique, dictionnaire dans l'onglet Dictionnaire. Ce sont les
          // deux mêmes pilules — le code en libellé, l'infobulle dit ce
          // qu'elles choisissent.
          _mode == ModeEtude.lexique
              ? _CorpusButton(
                  code: _corpus,
                  tooltip: 'Corpus du lexique',
                  onTap: _pickCorpus,
                  accent: accent,
                )
              : _CorpusButton(
                  code: _dictionnaire.code,
                  tooltip: 'Dictionnaire de l\'étude',
                  onTap: _pickDictionnaire,
                  accent: accent,
                ),
          const FicheDisplayMenuButton(group: DisplayGroup.etude),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              reference,
              style: premiumText(context, 17, FontWeight.w800, p.textDark),
            ),
            Text(
              _mode == ModeEtude.lexique
                  ? 'Lexique hébreu & grec'
                  : 'Dictionnaire',
              style: premiumText(context, 12, FontWeight.w500, p.textGrey),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: _buildBottomBar(context, accent),
      ),
      // Les boutons Android empilés à droite en paysage vivent dans
      // `MediaQuery.padding` : sans ce `SafeArea`, le corps file jusqu'au bord
      // de l'écran et passe dessous. L'`AppBar` les applique déjà — d'où le
      // titre toujours visible quand le contenu, lui, disparaissait.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // ============ 1. CARTE DU VERSET ============
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20.0),
                decoration: premiumSurface(context, radius: 20, depth: 1.2),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: premiumBadge(context, '$_verseNumber'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildVersetRich(context, accent, style),
                        ),
                      ],
                    ),
                    if (_hasNav) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (_verseIndex > 0)
                            _buildNavVerset(
                              context,
                              'Verset précédent',
                              Icons.arrow_circle_left_outlined,
                              false,
                              accent,
                            ),
                          const Spacer(),
                          if (_verseIndex < (widget.verseNumbers!.length - 1))
                            _buildNavVerset(
                              context,
                              'Verset suivant',
                              Icons.arrow_circle_right_outlined,
                              true,
                              accent,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ============ 2. CARTES SWIPABLES (selon le mode) ============
              _buildCardsArea(context, accent, style),
            ],
          ),
        ),
      ),
    );
  }

  // --- Verset fluide avec mots cliquables (selon le mode) ---
  Widget _buildVersetRich(
    BuildContext context,
    Color accent,
    FicheTextStyle style,
  ) {
    final p = premiumPalette(context);
    return Text.rich(
      textAlign: style.align,
      TextSpan(
        children: [
          for (final s in _segments)
            if (s.entreeIndex == null)
              TextSpan(
                text: s.texte,
                style: premiumText(
                  context,
                  style.fontSize,
                  FontWeight.w500,
                  p.textDark,
                  height: 2.0,
                ).copyWith(fontFamily: style.fontFamily),
              )
            else
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _motCliquable(
                  context,
                  s,
                  accent,
                  style,
                  sansTraduction: s.sansTraduction,
                ),
              ),
        ],
      ),
    );
  }

  /// Un segment cliquable du verset.
  ///
  /// Le mot ordinaire garde sa pastille pleine. Le code d'un mot que la
  /// traduction ne rend pas ([sansTraduction]) se montre autrement, pour ne
  /// pas se faire passer pour un mot : corps réduit, teinte atténuée, filet
  /// fin — une pastille qu'on lit comme une annotation, pas comme un terme du
  /// verset.
  Widget _motCliquable(
    BuildContext context,
    SegmentVerset s,
    Color accent,
    FicheTextStyle style, {
    required bool sansTraduction,
  }) {
    final p = premiumPalette(context);
    final actif = _entreeCourante == s.entreeIndex;
    return GestureDetector(
      onTap: () => _selectEntree(s.entreeIndex!),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: sansTraduction ? 5 : 7,
          vertical: sansTraduction ? 1 : 3,
        ),
        decoration: BoxDecoration(
          color: actif
              ? accent
              : accent.withValues(alpha: sansTraduction ? 0.10 : 0.15),
          borderRadius: BorderRadius.circular(sansTraduction ? 5 : 6),
          border: sansTraduction
              ? Border.all(color: accent.withValues(alpha: actif ? 1 : 0.5))
              : null,
        ),
        child: Text(
          s.texte,
          style: premiumText(
            context,
            sansTraduction ? style.fontSize * 0.72 : style.fontSize,
            FontWeight.w700,
            actif
                ? p.onPrimary
                : (sansTraduction ? accent : p.textDark),
          ).copyWith(
            fontFamily: sansTraduction ? null : style.fontFamily,
            letterSpacing: sansTraduction ? 0.3 : null,
          ),
        ),
      ),
    );
  }

  Widget _buildNavVerset(
    BuildContext context,
    String label,
    IconData icon,
    bool droite,
    Color accent,
  ) {
    return GestureDetector(
      onTap: () =>
          _navigateTo(widget.verseNumbers![_verseIndex + (droite ? 1 : -1)]),
      child: Row(
        children: [
          if (!droite) ...[Icon(icon, color: accent), const SizedBox(width: 6)],
          // Couleur de l'action, pas du texte courant : ces deux libellés
          // annoncent un déplacement.
          Text(
            label,
            style: premiumText(context, 14, FontWeight.w600, accent),
          ),
          if (droite) ...[const SizedBox(width: 6), Icon(icon, color: accent)],
        ],
      ),
    );
  }

  /// Le libellé au-dessus des sens. Une fiche que le lexique ne porte pas le
  /// dit : « hors lexique » plutôt qu'un « Définition » qui n'en ouvre aucune,
  /// et « sans équivalent français » quand le verset lui-même n'a pas de mot à
  /// montrer — le code est alors tout ce dont on dispose. Un code de la
  /// numérotation étendue, lui, a bien une réponse à donner : elle décrit une
  /// forme, pas un mot, et le dit en ces termes.
  String _libelleFiche(EntreeLexique e) {
    if (!e.fiche.introuvable) {
      return e.fiche.etendu
          ? 'Forme grammaticale - ${e.strongId}'
          : 'Définition - ${e.strongId}';
    }
    return e.sansTraduction
        ? 'Sans équivalent français - ${e.strongId}'
        : 'Hors lexique embarqué - ${e.strongId}';
  }

  // --- Carte du mode LEXIQUE ---
  Widget _buildCarteLexique(BuildContext context, EntreeLexique e, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: premiumSurface(context, radius: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          // Sans translittération — un code hors lexique n'en
                          // a pas — c'est le code qui titre la carte.
                          text: e.translit.isNotEmpty
                              ? e.translit
                              : e.strongId,
                          style: premiumText(
                            context,
                            18,
                            FontWeight.w800,
                            accent,
                          ),
                        ),
                        TextSpan(
                          text: e.prononciation.isEmpty
                              ? ''
                              : ' ${e.prononciation}',
                          style: premiumText(
                            context,
                            14,
                            FontWeight.w500,
                            p.textGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fiche Strong complète',
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(p.primarySoft),
                    shape: const WidgetStatePropertyAll(CircleBorder()),
                  ),
                  icon: Icon(
                    Icons.open_in_full_rounded,
                    color: accent,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StrongDetailScreen(
                        strong: e.fiche,
                        onOpenVerse: widget.onOpenVerse,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StrongLemma(
              lemma: e.original,
              strong: e.strongId,
              language: e.fiche.language,
            ),
            const SizedBox(height: 10),
            // Filet d'accent qui se perd vers la droite, plutôt que le pavé
            // uni : la carte garde son repère, la ligne reste légère.
            Container(
              width: 56,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [accent, accent.withValues(alpha: 0)],
                ),
              ),
            ),
            const SizedBox(height: 14),
            premiumBadge(context, _libelleFiche(e)),
            if (e.sansTraduction && !e.fiche.introuvable) ...[
              const SizedBox(height: 6),
              Text(
                'Le code figure dans le verset : la traduction ne rend pas '
                'ce mot.',
                style: premiumText(
                  context,
                  13,
                  FontWeight.w500,
                  p.textGrey,
                  height: 1.4,
                ),
              ),
            ],
            const SizedBox(height: 8),
            StrongSenses(
              outline: e.fiche.outline,
              senses: e.definitions,
              accent: accent,
              textStyle: premiumText(
                context,
                style.fontSize,
                FontWeight.w500,
                p.textDark,
                height: 1.5,
              ).copyWith(fontFamily: style.fontFamily),
              markerStyle: premiumText(
                context,
                style.fontSize,
                FontWeight.w700,
                accent,
                height: 1.5,
              ).copyWith(fontFamily: style.fontFamily),
              align: style.align,
              // The card has always numbered its senses itself; the source's
              // own codes take over as soon as there is an outline to show.
              numbered: true,
              rowGap: 6,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => StrongDetailScreen(
                      strong: e.fiche,
                      onOpenVerse: widget.onOpenVerse,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: p.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Ouvrir la fiche Strong complète →',
                    style: premiumText(context, 14, FontWeight.w700, accent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Carte du mode DICTIONNAIRE ---
  Widget _buildCarteDico(BuildContext context, EntreeDico e, FicheTextStyle style) {
    final p = premiumPalette(context);
    final accent = p.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      padding: const EdgeInsets.all(18.0),
      decoration: premiumSurface(context, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.titre,
                  style: premiumText(context, 22, FontWeight.w800, p.textDark),
                ),
              ),
              IconButton(
                tooltip: 'Fiche complète du dictionnaire',
                style: ButtonStyle(
                  backgroundColor: WidgetStatePropertyAll(p.primarySoft),
                  shape: const WidgetStatePropertyAll(CircleBorder()),
                ),
                icon: Icon(Icons.open_in_full_rounded, color: accent, size: 18),
                onPressed: () => _openFicheComplett(e),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: 56,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [accent, accent.withValues(alpha: 0)],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (e.section.isNotEmpty) ...[
                    Text(
                      e.section,
                      style: premiumText(
                        context,
                        15,
                        FontWeight.w700,
                        p.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    e.extrait,
                    textAlign: style.align,
                    style: premiumText(
                      context,
                      style.fontSize,
                      FontWeight.w500,
                      p.textDark,
                      height: 1.7,
                    ).copyWith(fontFamily: style.fontFamily),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _openFicheComplett(e),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: p.primarySoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Ouvrir la fiche complète →',
                  style: premiumText(context, 14, FontWeight.w700, accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La fiche complète de l'article courant — chaque famille porte la sienne.
  ///
  /// Le Westphal a son écran ([FredawEntryScreen]), avec ses renvois internes
  /// au lexique ; un dictionnaire téléchargé le générique
  /// ([DictionaryEntryScreen]), dont les renvois remontent son propre
  /// fichier. Le verset n'a rien à faire de ces détails : c'est le mot
  /// cliqué qui décide.
  void _openFicheComplett(EntreeDico e) {
    final dictionnaire = _dictionnaire;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => dictionnaire is DownloadedVerseDictionary
            ? DictionaryEntryScreen(
                entry: dictionnaire.entry,
                article: e.fiche,
                reader: dictionnaire.reader,
                // Le callback de l'écran d'étude (fourni par le lecteur) vide
                // déjà la pile de fiches avant le saut lecture : on le
                // transmet tel quel.
                onOpenVerse: widget.onOpenVerse,
              )
            : FredawEntryScreen(
                entry: FreDawEntry(
                  term: e.fiche.term,
                  definition: e.fiche.definition,
                ),
                onOpenVerse: widget.onOpenVerse,
              ),
      ),
    );
  }

  // --- Zone des cartes swipables ---
  Widget _buildCardsArea(BuildContext context, Color accent, FicheTextStyle style) {
    final p = premiumPalette(context);
    final ready = _mode == ModeEtude.lexique ? _lexiqueReady : _dicoReady;
    if (!ready) {
      return const SizedBox(
        key: Key('lexique-loading-skeleton'),
        height: 430,
        child: LoadingSkeleton(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 190, height: 22),
                SizedBox(height: 20),
                SkeletonBox(width: 118, height: 34),
                SizedBox(height: 20),
                SkeletonBox(width: 150, height: 14),
                SizedBox(height: 14),
                SkeletonBox(height: 15),
                SizedBox(height: 10),
                SkeletonBox(height: 15),
                SizedBox(height: 10),
                SkeletonBox(width: 210, height: 15),
                SizedBox(height: 26),
                SkeletonBox(width: 165, height: 14),
                SizedBox(height: 14),
                SkeletonBox(height: 15),
              ],
            ),
          ),
        ),
      );
    }
    if (_nbEntrees == 0) {
      final message = _mode == ModeEtude.lexique
          ? 'Ce verset ne contient aucun mot associé à un numéro Strong.'
          : 'Aucun terme de ce verset ne figure dans le dictionnaire.';
      return SizedBox(
        height: 430,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: premiumSurface(context, radius: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _mode == ModeEtude.lexique
                      ? Icons.translate_rounded
                      : Icons.menu_book_rounded,
                  size: 34,
                  color: accent.withValues(alpha: .55),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: premiumText(
                    context,
                    14,
                    FontWeight.w500,
                    p.textGrey,
                    italic: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 430,
      child: PageView.builder(
        controller: _pageController,
        // `padEnds` centre la première et la dernière carte dans le viewport :
        // juste en colonne unique (le comportement d'origine), mais en colonnes
        // multiples il laisserait un vide d'un demi-écran avant la première.
        padEnds: _colonnes == 1,
        onPageChanged: (i) => _selectEntree(i, scroll: false),
        itemCount: _nbEntrees,
        // Clé stable par carte : c'est elle qui laisse au test le comptage des
        // cartes réellement tenues par la largeur, colonne par colonne.
        itemBuilder: (context, i) => KeyedSubtree(
          key: Key('etude-card-$i'),
          child: _mode == ModeEtude.lexique
              ? _buildCarteLexique(context, _entreesLexique[i], style)
              : _buildCarteDico(context, _entreesDico[i], style),
        ),
      ),
    );
  }

  // --- Barre du bas : bascule Lexique / Dictionnaire ---
  Widget _buildBottomBar(BuildContext context, Color accent) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: premiumSurface(context, radius: 24, depth: 1.4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            'Lexique',
            Icons.translate_rounded,
            _mode == ModeEtude.lexique,
            () => _changerMode(ModeEtude.lexique),
            accent,
          ),
          _buildNavItem(
            'Dictionnaire',
            Icons.menu_book_rounded,
            _mode == ModeEtude.dictionnaire,
            () => _changerMode(ModeEtude.dictionnaire),
            accent,
          ),
          _buildNavItem(
            'Thèmes',
            Icons.category_outlined,
            false,
            () => _stubSnack('Thèmes'),
            accent,
          ),
          _buildNavItem(
            'Références',
            Icons.list_alt_rounded,
            false,
            () => _stubSnack('Références'),
            accent,
          ),
          _buildNavItem(
            'Comment.',
            Icons.chat_bubble_outline_rounded,
            false,
            () => _stubSnack('Commentaires'),
            accent,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    String label,
    IconData icon,
    bool actif,
    VoidCallback onTap,
    Color accent,
  ) {
    final p = premiumPalette(context);
    final iconsOnly = MediaQuery.sizeOf(context).width < 360;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Tooltip(
          message: label,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            // Mêmes mesures que le Padding précédent : seul l'état actif
            // change, la barre ne bouge pas d'un pixel.
            padding: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: iconsOnly ? 5 : 0,
            ),
            decoration: BoxDecoration(
              color: actif ? accent.withValues(alpha: .14) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: iconsOnly ? 24 : 22,
                  color: actif ? accent : p.textGrey,
                ),
                if (!iconsOnly) ...[
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: premiumText(
                      context,
                      11,
                      FontWeight.w600,
                      actif ? accent : p.textGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La source en vigueur, dans l'AppBar de l'étude — tappable pour en changer :
/// le corpus du lexique, ou le dictionnaire selon l'onglet ouvert.
///
/// Le libellé est le code (« LSS », « FREDAW », « GBM ») : quelques lettres
/// tiennent dans une barre d'actions où le bouton d'affichage occupe déjà la
/// droite, et c'est la même écriture que la fiche.
class _CorpusButton extends StatelessWidget {
  final String code;
  final String tooltip;
  final VoidCallback onTap;
  final Color accent;

  const _CorpusButton({
    required this.code,
    required this.tooltip,
    required this.onTap,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          code,
          style: premiumText(context, 11, FontWeight.w800, accent),
        ),
      ),
    );
  }
}

/// Une ligne d'un sélecteur de source — corpus du lexique, dictionnaire de
/// l'étude : nom, note, et l'état sélectionné.
class _OptionLigne extends StatelessWidget {
  final String name;
  final String note;
  final bool selected;
  final VoidCallback onTap;

  const _OptionLigne({
    required this.name,
    required this.note,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? p.primary : p.textGrey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: premiumText(
                        context, 14, FontWeight.w700, p.textDark),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
                    style: premiumText(
                        context, 12, FontWeight.w500, p.textGrey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
