import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_database.dart';
import 'package:bible_app/data/dictionary_reader.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/lexicon_index.dart' as lexicon;
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/strong_occurrences.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/data/version_repository.dart';
import 'package:bible_app/models/lsgs.dart';
import 'package:bible_app/models/user_data.dart';
import 'package:bible_app/screens/bym_lexicon_entry_screen.dart';
import 'package:bible_app/screens/bym_lexicon_index_screen.dart';
import 'package:bible_app/screens/chapter_screen.dart';
import 'package:bible_app/screens/dictionary_browse_screen.dart';
import 'package:bible_app/screens/dictionary_entry_screen.dart';
import 'package:bible_app/screens/ecran_comparer.dart';
import 'package:bible_app/screens/etude_verset_screen.dart';
import 'package:bible_app/screens/favoris_screen.dart';
import 'package:bible_app/screens/fredaw_entry_screen.dart';
import 'package:bible_app/screens/fredaw_index_screen.dart';
import 'package:bible_app/screens/historique_screen.dart';
import 'package:bible_app/screens/notes_screen.dart';
import 'package:bible_app/screens/parallel_reading_screen.dart';
import 'package:bible_app/screens/strong_detail_screen.dart';
import 'package:bible_app/screens/strong_index_screen.dart';
import 'package:bible_app/screens/strong_occurrences_screen.dart';
import 'package:bible_app/screens/themes_screen.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/note_editor_sheet.dart';
import 'package:bible_app/widgets/responsive_text_scaling.dart';
import 'package:bible_app/widgets/study_sheet.dart';
import 'package:bible_app/widgets/tab_switcher.dart';

import 'dictionary_browse_screen_test.dart'
    show FakeDictionaryStore, bailly, sampleData;
import 'reader_version_test.dart' show FakeStore;
import 'support/fake_bible_bundle.dart';
import 'support/fake_fredaw_bundle.dart';
import 'support/fake_lsgs_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// Balayage anti-débordement des écrans *poussés* par-dessus le shell.
///
/// `responsive_overflow_test.dart` couvre les cinq destinations de la barre :
/// il navigue dans l'application réelle, mais n'ouvre aucun écran empilé par
/// `Navigator.push`. Ce fichier prend l'autre moitié — les surfaces qu'un
/// testeur atteint en deux touches et que rien n'éprouvait sous contrainte
/// d'écran.
///
/// Chaque surface est montée directement plutôt qu'atteinte par navigation :
/// une chaîne de taps se casse au premier libellé qui bouge, et surtout elle
/// échoue *en silence* — le test passe alors sur un écran qu'il n'a jamais
/// ouvert. C'est exactement le piège qui laissait l'ancien audit d'échelle au
/// vert (voir `text_scaling_audit_test.dart`).
///
/// Le montage passe par [ResponsiveTextScaling] : sans lui le balayage
/// testerait une police non bornée, donc signalerait des débordements que
/// l'application, qui plafonne à 1.18×, ne connaît pas.
///
/// Les deux moitiés du harnais ont été vérifiées par canari :
/// - au montage, en trouvant un vrai débordement (l'état vide de l'Historique,
///   114 px en paysage) ;
/// - au défilement, en enfouissant une `Row` de 5000 px derrière 3000 px de
///   remplissage dans la lecture parallèle. Elle n'est signalée que par les
///   entrées « défilé à … », jamais par « montage » — la preuve que le
///   balayage voit bien ce que la seule première peinture manque.

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3, verses: 12));
    LsgsRepository.useBundle(FakeLsgsBundle());
    StrongLexicon.useBundle(FakeStrongLexiconBundle());
    FreDawLexicon.useBundle(FakeFreDawBundle());
    StrongOccurrenceIndex.useRepository(LsgsRepository());
    lexicon.LexiconIndex.instance.clearIndex();
    VersionRepository.clearCache();
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
    StrongLexicon.useRootBundle();
    FreDawLexicon.useRootBundle();
    StrongOccurrenceIndex.clear();
    lexicon.LexiconIndex.instance.clearIndex();
    VersionRepository.clearCache();
  });

  /// Les extrêmes du parc, pas tout le parc : le premier balayage a montré que
  /// les débordements se déclarent aux bornes (320 px de large, 360 px de haut
  /// en paysage) et jamais uniquement au milieu.
  const devices = <String, Size>{
    '320x568': Size(320, 568),
    '360x640': Size(360, 640),
    '412x915': Size(412, 915),
    '800x360 paysage': Size(800, 360),
    '834x1112 tablette': Size(834, 1112),
  };

  const tokens = <LsgsToken>[
    LsgsToken(text: 'Au ', strong: null),
    LsgsToken(text: 'commencement ', strong: 'H7225'),
    LsgsToken(text: 'Dieu ', strong: 'H0430'),
    LsgsToken(text: 'créa les cieux et la terre.', strong: null),
  ];

  /// Une fiche Strong écrite à la main : les champs longs (étymologie, sens
  /// multiples) sont ceux qui mettent la mise en page sous tension.
  const strong = StrongDefinition(
    strong: 'H7225',
    definition: 'commencement, principe, ce qui vient en premier dans le temps '
        'comme dans le rang — la primeur, les prémices.',
    language: 'Hébreu',
    lemma: 'רֵאשִׁית',
    transliteration: 'reshith',
    pronunciation: 'ray-sheeth',
    partOfSpeech: 'nom féminin',
    etymology: 'De la racine רֹאשׁ (rosh), « tête », donc « ce qui est en tête ».',
    senses: [
      'commencement, origine',
      'prémices, première part d\'une récolte',
      'le meilleur, le plus excellent',
      'le principe, le fondement d\'une chose',
    ],
  );

  TabManager tabsWithHistory() {
    final manager = TabManager();
    manager.openReading(1, 1);
    manager.openReading(23, 40);
    manager.close(0);
    manager.openReading(43, 3, verse: 16);
    return manager;
  }

  /// Quelques occurrences réparties sur plusieurs livres : l'écran les regroupe
  /// par livre, donc une seule ne montrerait ni les en-têtes ni les compteurs.
  const occurrences = <StrongOccurrence>[
    StrongOccurrence(bookIndex: 1, chapter: 1, verse: 1, reference: 'Gen 1:1'),
    StrongOccurrence(bookIndex: 1, chapter: 2, verse: 4, reference: 'Gen 2:4'),
    StrongOccurrence(bookIndex: 23, chapter: 1, verse: 1, reference: 'Ps 1:1'),
    StrongOccurrence(bookIndex: 43, chapter: 3, verse: 16, reference: 'Jn 3:16'),
  ];

  /// Une entrée du lexique BYM avec une définition longue et une référence
  /// biblique dedans : les deux tensions de cet écran (texte qui se replie,
  /// portion cliquable insérée dans le flux).
  const bymEntry = lexicon.DictionaryEntry(
    word: 'Yod',
    definition:
        'Dixième lettre de l\'alphabet hébreu, la plus petite de toutes — '
        'voir Matthieu 5:18, où pas un seul iota ne disparaîtra de la loi.',
    bookIndex: 40,
    chapter: 5,
    verseNumber: 18,
    occurrences: 3,
  );

  const fredawEntry = FreDawEntry(
    term: 'Alliance',
    definition:
        'Engagement solennel entre Dieu et les hommes, scellé par un signe et '
        'assorti de promesses comme de responsabilités.',
  );

  /// Le shell des surfaces poussées : le thème du lecteur et la règle d'échelle
  /// réelle, comme `main.dart` les pose autour du `Navigator`.
  Widget host(Widget child) => MaterialApp(
    home: ResponsiveTextScaling(child: BibleThemeScope(child: child)),
  );

  /// Nom → constructeur de la surface. Une entrée, un `testWidgets`.
  final surfaces = <String, Widget Function()>{
    'Sélecteur d\'onglets': () => TabSwitcher(manager: tabsWithHistory()),
    'Étude du verset': () => const EtudeVersetScreen(
      bookIndex: 1,
      chapter: 1,
      verseNumber: 1,
      tokens: tokens,
    ),
    'Détail Strong': () => const StrongDetailScreen(strong: strong),
    'Index Strong': () => const StrongIndexScreen(),
    'Index FreDaw': () => const FredawIndexScreen(),
    'Index lexique BYM': () => const BymLexiconIndexScreen(),
    'Historique': () => const HistoriqueScreen(),
    'Thèmes': () => const ThemesScreen(),
    'Lecture parallèle': () =>
        const ParallelReadingScreen(bookIndex: 1, chapter: 1),
    'Comparer': () => ComparerScreen(
      bookIndex: 1,
      chapter: 1,
      verseNumber: 1,
      store: FakeStore({}),
    ),
    'Chapitres du livre': () => const ChapterScreen(bookIndex: 1, chapter: 1),
    'Occurrences Strong': () => const StrongOccurrencesScreen(
      code: 'H7225',
      occurrences: occurrences,
    ),
    'Occurrences par livre': () => const StrongBookOccurrencesScreen(
      bookIndex: 1,
      bookName: 'Bereshit (Genèse)',
      occurrences: occurrences,
      highlight: 'H7225',
    ),
    'Entrée FreDaw': () => const FredawEntryScreen(entry: fredawEntry),
    'Entrée lexique BYM': () => const BymLexiconEntryScreen(entry: bymEntry),
    'Dictionnaire — parcours': () => DictionaryBrowseScreen(
      entry: bailly,
      store: FakeDictionaryStore(sampleData()),
    ),
    'Dictionnaire — article': () => DictionaryEntryScreen(
      entry: bailly,
      article: const DictionaryArticle(
        term: 'AGAPÈ',
        definition:
            'Amour inconditionnel et gratuit, distinct de l\'affection '
            'naturelle comme de l\'amitié : le mot que le Nouveau Testament '
            'réserve à l\'amour de Dieu.',
      ),
      reader: DictionaryReader.fromJson(sampleData()),
    ),
    'Notes': () => NotesScreen(db: _FakeDb()),
    // Variante vide : l'état « Aucune note pour l'instant » est la seule
    // branche de Notes qui ne défile pas — c'est elle qui débordait en
    // paysage (capture du 02/10/2026), et une base pleine ne l'exerçait pas.
    'Notes (vides)': () => NotesScreen(db: _VideDb()),
    'Favoris': () => FavorisScreen(db: _FakeDb()),
  };

  for (final surface in surfaces.entries) {
    testWidgets('aucun débordement — ${surface.key}', (tester) async {
      final overflows = <String>[];

      for (final scale in const [1.0, 2.0]) {
        for (final device in devices.entries) {
          tester.view.physicalSize = device.value;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;

          void collect(String where) {
            for (var i = 0; i < 40; i++) {
              final error = tester.takeException();
              if (error == null) break;
              overflows.add(
                '${device.key} @x$scale — $where :: '
                '${error.toString().split('\n').first}',
              );
            }
          }

          Future<void> settle() async {
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 250));
            }
          }

          await tester.pumpWidget(host(surface.value()));
          await settle();
          collect('montage');

          // Même raison que dans le balayage du shell : le contenu sous la
          // ligne de flottaison n'est ni mis en page ni peint tant qu'il n'est
          // pas entré dans le viewport.
          for (var index = 0; index < 6; index++) {
            final scrollables = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .toList();
            if (index >= scrollables.length) break;
            final position = scrollables[index].position;
            if (!position.hasContentDimensions) continue;
            final viewport = position.viewportDimension;
            if (viewport <= 0) continue;
            var guard = 0;
            while (position.pixels < position.maxScrollExtent && guard++ < 40) {
              position.jumpTo(
                (position.pixels + viewport * 0.8).clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ),
              );
              await settle();
              collect('défilé à ${position.pixels.toStringAsFixed(0)}');
            }
          }

          // Repartir d'un arbre vide : sans cela le widget précédent est
          // rebâti sous la nouvelle taille, et son état (index de page,
          // contrôleurs de défilement) brouille la mesure suivante.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }

      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      expect(
        overflows.toSet(),
        isEmpty,
        reason:
            'Débordements sur « ${surface.key} » :\n'
            '${overflows.toSet().join('\n')}',
      );
    });
  }

  /// Les feuilles modales ne sont pas des écrans : elles se montent en les
  /// ouvrant depuis un bouton, comme le fait le lecteur. Une contrainte de plus
  /// que les écrans — une `showModalBottomSheet` se plafonne à une fraction de
  /// la hauteur, donc en paysage elle travaille sur très peu de place.
  final sheets = <String, void Function(BuildContext)>{
    'feuille d\'étude': (context) => showStudySheet(
      context,
      reference: 'Jn. 3:16',
      excerpt:
          'Car Dieu a tant aimé le monde qu\'il a donné son Fils unique, afin '
          'que quiconque croit en lui ne périsse point, mais qu\'il ait la vie '
          'éternelle.',
      isFavorite: false,
      currentHighlight: null,
      lexiqueEnabled: true,
      lexiqueLabel: 'Lexique & Dictionnaire — verset mot à mot',
      onHighlight: (_) async {},
      onFavorite: (_) async {},
    ),
    'éditeur de note': (context) => showNoteEditorSheet(
      context: context,
      db: _FakeDb(),
      reference: 'Jean 3:16',
      verseText:
          'Car Dieu a tant aimé le monde qu\'il a donné son Fils unique, afin '
          'que quiconque croit en lui ne périsse point.',
      bookIndex: 43,
      chapter: 3,
      verse: 16,
    ),
    // Hors BYM la feuille porte une ligne de plus sous le bouton Lexique grisé
    // (« Disponible depuis le texte BYM. ») : c'est une variante de hauteur, donc
    // elle repasse ici, à x2 et sur les écrans les plus courts.
    'feuille d\'étude — lexique grisé': (context) => showStudySheet(
      context,
      reference: 'Jn. 3:16',
      excerpt:
          'Car Dieu a tant aimé le monde qu\'il a donné son Fils unique, afin '
          'que quiconque croit en lui ne périsse point, mais qu\'il ait la vie '
          'éternelle.',
      isFavorite: false,
      currentHighlight: null,
      lexiqueEnabled: false,
      lexiqueLabel: 'Lexique & Dictionnaire — verset mot à mot',
      onHighlight: (_) async {},
      onFavorite: (_) async {},
    ),
  };

  for (final sheet in sheets.entries) {
    testWidgets('aucun débordement — ${sheet.key}', (tester) async {
      final overflows = <String>[];
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      for (final scale in const [1.0, 2.0]) {
        for (final device in devices.entries) {
          tester.view.physicalSize = device.value;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;

          void collect(String where) {
            for (var i = 0; i < 40; i++) {
              final error = tester.takeException();
              if (error == null) break;
              overflows.add(
                '${device.key} @x$scale — $where :: '
                '${error.toString().split('\n').first}',
              );
            }
          }

          Future<void> settle() async {
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 250));
            }
          }

          await tester.pumpWidget(
            host(
              Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => sheet.value(context),
                    child: const Text('ouvrir'),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.tap(find.text('ouvrir'));
          await settle();
          collect('ouverture');

          // Même raison que pour les écrans : le bas d'une feuille défilable
          // n'est pas peint tant qu'il n'est pas entré dans le viewport.
          for (var index = 0; index < 4; index++) {
            final scrollables = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .toList();
            if (index >= scrollables.length) break;
            final position = scrollables[index].position;
            if (!position.hasContentDimensions) continue;
            final viewport = position.viewportDimension;
            if (viewport <= 0) continue;
            var guard = 0;
            while (position.pixels < position.maxScrollExtent && guard++ < 40) {
              position.jumpTo(
                (position.pixels + viewport * 0.8).clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ),
              );
              await settle();
              collect('défilé à ${position.pixels.toStringAsFixed(0)}');
            }
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }

      expect(
        overflows.toSet(),
        isEmpty,
        reason:
            'Débordements sur « ${sheet.key} » :\n'
            '${overflows.toSet().join('\n')}',
      );
    });
  }
}

/// Base de données en mémoire pour les surfaces qui lisent SQLite : elle couvre
/// à elle seule Notes, Favoris et l'éditeur de note.
///
/// Volontairement PAS `sqflite_common_ffi` : le FFI fait de vraies I/O, qui ne
/// se terminent jamais dans la zone fake-async de `testWidgets` sans passer par
/// `runAsync` — incompatible avec les boucles de pump serrées de ce balayage.
/// Ici seule la mise en page est en jeu, donc des microtâches suffisent.
class _FakeDb extends AppDatabase {
  static UserNote note(int book, int chapter, int verse, String titre) =>
      UserNote(
        id: book * 1000 + chapter * 10 + verse,
        bookIndex: book,
        chapter: chapter,
        verse: verse,
        title: titre,
        text:
            'Note de test assez longue pour éprouver le retour à la ligne, '
            'les marges et la hauteur des cartes à police agrandie.',
        updatedAt: 1700000000000,
      );

  @override
  Future<List<UserNote>> allNotes() async => [
    note(1, 1, 1, 'Au commencement'),
    note(43, 3, 16, 'L\'amour de Dieu pour le monde'),
    note(23, 40, 2, 'Une prière exaucée'),
  ];

  @override
  Future<List<UserNote>> notesForVerse(int book, int chapter, int verse) async =>
      [note(book, chapter, verse, 'Note existante')];

  @override
  Future<List<UserFavorite>> allFavorites() async => const [
    UserFavorite(bookIndex: 1, chapter: 1, verse: 1),
    UserFavorite(bookIndex: 43, chapter: 3, verse: 16),
    UserFavorite(bookIndex: 23, chapter: 40, verse: 2),
  ];
}

/// Base vide — l'état « Aucune note pour l'instant », qui ne défile pas.
class _VideDb extends AppDatabase {
  @override
  Future<List<UserNote>> allNotes() async => const [];

  @override
  Future<List<UserNote>> notesForVerse(int book, int chapter, int verse) async =>
      const [];

  @override
  Future<List<UserFavorite>> allFavorites() async => const [];
}
