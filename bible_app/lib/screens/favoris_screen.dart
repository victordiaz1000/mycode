import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../models/user_data.dart';
import '../widgets/premium_style.dart';
import '../widgets/loading_skeleton.dart';

/// Type de favori (maquette `interfaces/ecran_favoris.dart`). Seul [verset]
/// a une source aujourd'hui (la table `favorites`, alimentée par le cœur de
/// la feuille d'étude) ; les valeurs Strong et dictionnaire préparent
/// l'avenir — aucun écran n'en crée encore, et l'écran ne propose les filtres
/// correspondants que si de tels favoris existent.
enum TypeFavori { verset, strong, dictionnaire }

/// Un favori affiché par l'écran : un verset (seul à avoir une source
/// aujourd'hui — la table `favorites`), ou, à terme, une fiche Strong ou une
/// entrée de dictionnaire. Les coordonnées du verset ne sont portées que par
/// `TypeFavori.verset`.
class Favori {
  final TypeFavori type;
  final String titre;
  final String sousTitre;
  final String? badge; // "G25" / "H3068" (pour les Strong)
  final String? langue; // "Grec" / "Hébreu"
  final int? book;
  final int? chapter;
  final int? verse;

  const Favori({
    required this.type,
    required this.titre,
    required this.sousTitre,
    this.badge,
    this.langue,
    this.book,
    this.chapter,
    this.verse,
  });
}

/// Écran « Favoris » (maquette `interfaces/ecran_favoris.dart`) dans le langage
/// visuel premium de l'Accueil : chaque verset marqué d'une étoile dans la
/// lecture est listé ici, avec des filtres par type, un cœur pour le retirer
/// et un tap qui rouvre le verset dans la lecture.
///
/// [db] et [repository] sont injectables pour les tests (même couture que
/// `store` sur les autres écrans) : `AppDatabase.instance` et le bundle réel
/// ouvrent via des canaux de plateforme muets dans la zone fake-async.
class FavorisScreen extends StatefulWidget {
  /// Ouvre [bookIndex]/[chapter]/[verse] dans la lecture. Null hors coquille :
  /// la carte affiche la référence sans prétendre naviguer.
  final void Function(int bookIndex, int chapter, int verse)? onOpenVerse;

  final AppDatabase? db;
  final LocalRepository? repository;

  const FavorisScreen({super.key, this.onOpenVerse, this.db, this.repository});

  @override
  State<FavorisScreen> createState() => _FavorisScreenState();
}

class _FavorisScreenState extends State<FavorisScreen> {
  late final AppDatabase _db = widget.db ?? AppDatabase.instance;
  late final LocalRepository _repository =
      widget.repository ?? LocalRepository();

  String _filtre = 'Tous';
  List<Favori> _favoris = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final favoris = await _buildFavoris(await _db.allFavorites());
      if (!mounted) return;
      setState(() {
        _favoris = favoris;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  /// Transforme les favoris de la base (des versets) en cartes. Chaque livre
  /// est chargé une seule fois — les favoris sont déjà triés dans l'ordre de
  /// lecture, et la charge par chapitre relirait le même livre 3–4 fois.
  Future<List<Favori>> _buildFavoris(List<UserFavorite> favorites) async {
    final byBook = <int, List<UserFavorite>>{};
    for (final f in favorites) {
      byBook.putIfAbsent(f.bookIndex, () => []).add(f);
    }

    final result = <Favori>[];
    for (final entry in byBook.entries) {
      // Les numéros de verset recommencent à 1 dans chaque chapitre : indexer
      // par (chapitre, verset), sinon « 2:2 » écrase « 1:2 ».
      final texts = <(int, int), String>{};
      try {
        final book = await _repository.loadBook(entry.key);
        for (final c in book.chapters) {
          for (final v in c.verses) {
            texts[(c.chapter, v.number)] = v.text;
          }
        }
      } catch (_) {
        // Livre illisible : la référence reste, sans extrait — le cœur n'est
        // pas le bon endroit pour faire échouer tout l'écran.
      }
      for (final f in entry.value) {
        result.add(_versetFavori(f, texts[(f.chapter, f.verse)] ?? ''));
      }
    }
    return result;
  }

  Favori _versetFavori(UserFavorite f, String texte) => Favori(
    type: TypeFavori.verset,
    titre: '${catalogEntry(f.bookIndex).shortName} ${f.chapter}:${f.verse}',
    sousTitre: texte,
    book: f.bookIndex,
    chapter: f.chapter,
    verse: f.verse,
  );

  List<Favori> get _favorisFiltres {
    if (_filtreActif == 'Tous') return _favoris;
    final type = _filtreActif == 'Versets'
        ? TypeFavori.verset
        : _filtreActif == 'Strong'
        ? TypeFavori.strong
        : TypeFavori.dictionnaire;
    return _favoris.where((f) => f.type == type).toList();
  }

  /// Les filtres qui ont un sens : « Tous », puis un onglet par type réellement
  /// présent dans la liste. Un menu de choix ne liste que ce qui est
  /// choisissable — proposer « Strong » alors qu'aucune fabrique n'en crée
  /// encore donnerait des puces qui ne renvoient jamais rien.
  List<String> get _filtresDisponibles => [
    'Tous',
    if (_favoris.any((f) => f.type == TypeFavori.verset)) 'Versets',
    if (_favoris.any((f) => f.type == TypeFavori.strong)) 'Strong',
    if (_favoris.any((f) => f.type == TypeFavori.dictionnaire)) 'Dictionnaire',
  ];

  /// Le filtre courant, retombé sur « Tous » si le rechargement de la liste a
  /// fait disparaître son onglet (le favori du type a été retiré ailleurs).
  String get _filtreActif =>
      _filtresDisponibles.contains(_filtre) ? _filtre : 'Tous';

  /// Retire un favori de l'écran, puis de la base. La suppression visuelle est
  /// immédiate ; l'échec d'écriture est silencieux (au pire le favori
  /// réapparaîtra au prochain lancement).
  Future<void> _retirer(Favori f) async {
    setState(() => _favoris = [..._favoris]..remove(f));
    final book = f.book;
    final chapter = f.chapter;
    final verse = f.verse;
    if (book == null || chapter == null || verse == null) return;
    try {
      await _db.setFavorite(book, chapter, verse, false);
    } catch (_) {
      // best effort
    }
  }

  void _open(Favori f) {
    final book = f.book;
    final chapter = f.chapter;
    final verse = f.verse;
    if (book == null || chapter == null || verse == null) return;
    widget.onOpenVerse?.call(book, chapter, verse);
  }

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    final filtres = _favorisFiltres;

    return Scaffold(
      backgroundColor: premiumBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Favoris',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _loading
              ? const ListLoadingSkeleton(padding: EdgeInsets.zero)
              : _error != null
              ? _buildError(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ============ FILTRES PAR TYPE ============
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in _filtresDisponibles)
                          _buildFiltreChip(context, f),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${filtres.length} favori${filtres.length > 1 ? 's' : ''}',
                      style: premiumText(
                        context,
                        13,
                        FontWeight.w500,
                        p.textGrey,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ============ LISTE OU ÉTAT VIDE ============
                    Expanded(
                      child: filtres.isEmpty
                          ? _buildEtatVide(context)
                          : ListView.separated(
                              itemCount: filtres.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, i) =>
                                  _buildCarteFavori(context, filtres[i]),
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'Impossible de charger vos favoris.',
            style: premiumText(context, 15, FontWeight.w800, p.textDark),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  // --- Chip de filtre ---
  Widget _buildFiltreChip(BuildContext context, String label) {
    final p = premiumPalette(context);
    final actif = _filtre == label;
    return GestureDetector(
      onTap: () => setState(() => _filtre = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? null : p.surfaceAlt,
          gradient: actif ? p.heroGradient : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: actif
                ? Colors.transparent
                : p.textGrey.withValues(alpha: .3),
          ),
          boxShadow: actif
              ? premiumShadow(
                  p.primary,
                  opacity: 0.3,
                  blur: 12,
                  offset: const Offset(0, 5),
                )
              : null,
        ),
        child: Text(
          label,
          style: premiumText(
            context,
            13,
            FontWeight.w700,
            actif ? p.onPrimary : p.textDark,
          ),
        ),
      ),
    );
  }

  // --- État vide ---
  Widget _buildEtatVide(BuildContext context) {
    final p = premiumPalette(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.favorite_border_rounded,
            size: 56,
            color: p.textGrey.withValues(alpha: .4),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucun favori ici',
            style: premiumText(context, 16, FontWeight.w800, p.textDark),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Touche le cœur d\'un verset dans la lecture pour le retrouver ici.',
              style: premiumText(
                context,
                13,
                FontWeight.w500,
                p.textGrey,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // --- Carte de favori cliquable ---
  Widget _buildCarteFavori(BuildContext context, Favori f) {
    final p = premiumPalette(context);
    return Material(
      color: p.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 0,
      shadowColor: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: premiumShadow(
            p.primaryDark,
            opacity: 0.07,
            blur: 16,
            offset: const Offset(0, 6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: f.book == null ? null : () => _open(f),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                _buildLeading(context, f),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.titre,
                        style: premiumText(
                          context,
                          16,
                          FontWeight.w800,
                          p.textDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        f.sousTitre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: premiumText(
                          context,
                          13,
                          FontWeight.w500,
                          p.textGrey,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Cœur pour retirer le favori
                GestureDetector(
                  onTap: () => _retirer(f),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 20,
                      color: p.favorite,
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

  // --- Icône de gauche selon le type ---
  Widget _buildLeading(BuildContext context, Favori f) {
    final p = premiumPalette(context);

    if (f.type == TypeFavori.strong) {
      final couleur = f.langue == 'Grec' ? p.greek : p.hebrew;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          f.badge ?? '',
          style: premiumText(context, 12, FontWeight.w700, couleur),
        ),
      );
    }

    final couleur = f.type == TypeFavori.verset ? p.primary : p.primaryDark;
    final icone = f.type == TypeFavori.verset
        ? Icons.bookmark_rounded
        : Icons.menu_book_rounded;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icone, size: 18, color: couleur),
    );
  }
}
