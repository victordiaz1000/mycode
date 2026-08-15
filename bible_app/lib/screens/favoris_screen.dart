import 'package:flutter/material.dart';

import '../data/app_database.dart';
import '../data/book_catalog.dart';
import '../data/local_repository.dart';
import '../models/user_data.dart';

/// Type de favori (maquette `interfaces/ecran_favoris.dart`).
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

/// Écran « Favoris » (maquette `interfaces/ecran_favoris.dart`) : chaque verset
/// marqué d'une étoile dans la lecture est listé ici, avec des filtres par
/// type, un cœur pour le retirer et un tap qui rouvre le verset dans la
/// lecture.
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
  late final LocalRepository _repository = widget.repository ?? LocalRepository();

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
    if (_filtre == 'Tous') return _favoris;
    final type = _filtre == 'Versets'
        ? TypeFavori.verset
        : _filtre == 'Strong'
            ? TypeFavori.strong
            : TypeFavori.dictionnaire;
    return _favoris.where((f) => f.type == type).toList();
  }

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
    final theme = Theme.of(context);
    final filtres = _favorisFiltres;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: theme.colorScheme.onSurface,
        centerTitle: true,
        title: Text(
          'Favoris',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            fontFamily: 'Georgia',
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(theme)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ============ FILTRES PAR TYPE ============
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in ['Tous', 'Versets', 'Strong', 'Dictionnaire'])
                              _buildFiltreChip(theme, f),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${filtres.length} favori${filtres.length > 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ============ LISTE OU ÉTAT VIDE ============
                        Expanded(
                          child: filtres.isEmpty
                              ? _buildEtatVide(theme)
                              : ListView.separated(
                                  itemCount: filtres.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) =>
                                      _buildCarteFavori(theme, filtres[i]),
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(
            'Impossible de charger vos favoris.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
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
  Widget _buildFiltreChip(ThemeData theme, String label) {
    final accent = theme.colorScheme.primary;
    final actif = _filtre == label;
    return GestureDetector(
      onTap: () => setState(() => _filtre = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: actif ? accent : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: actif ? accent : Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: actif ? theme.colorScheme.onPrimary : Colors.black87,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // --- État vide ---
  Widget _buildEtatVide(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border_rounded,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            'Aucun favori ici',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Touche le cœur d\'un verset, d\'un mot Strong ou d\'une entrée de dictionnaire pour le retrouver ici.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // --- Carte de favori cliquable ---
  Widget _buildCarteFavori(ThemeData theme, Favori f) {
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: f.book == null ? null : () => _open(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _buildLeading(theme, f),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      f.titre,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                        fontFamily: 'Georgia',
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      f.sousTitre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: theme.colorScheme.onSurfaceVariant,
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
                  child: const Icon(
                    Icons.favorite_rounded,
                    size: 20,
                    color: Color(0xFFC0564C),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Icône de gauche selon le type ---
  Widget _buildLeading(ThemeData theme, Favori f) {
    const kGrec = Color(0xFF1A73E8);
    const kHebreu = Color(0xFFD95300);
    const kAccent = Color(0xFF8C6B4F);
    const kViolet = Color(0xFF5E35B1);

    if (f.type == TypeFavori.strong) {
      final couleur = f.langue == 'Grec' ? kGrec : kHebreu;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          f.badge ?? '',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: couleur,
          ),
        ),
      );
    }

    final couleur = f.type == TypeFavori.verset ? kAccent : kViolet;
    final icone =
        f.type == TypeFavori.verset ? Icons.bookmark_rounded : Icons.menu_book_rounded;

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