import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_download_service.dart';
import 'package:bible_app/data/dictionary_store.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/fredaw_lexicon.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/strong_lexicon.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/screens/library_screen.dart';

import 'support/fake_fredaw_bundle.dart';
import 'support/fake_strong_lexicon_bundle.dart';

/// The registry, in memory: the screen only reads [installed] / [sizeOnDisk]
/// and calls [remove], so the disk never has to be involved here.
class FakeStore extends LibraryStore {
  FakeStore([Map<String, Set<int>>? initial]) : books = initial ?? {};

  final Map<String, Set<int>> books;
  final List<String> removed = [];

  @override
  Future<Map<String, InstalledVersion>> installed() async => {
        for (final entry in books.entries)
          entry.key: InstalledVersion(code: entry.key, books: entry.value),
      };

  @override
  Future<int> sizeOnDisk(String code) async =>
      (books[code]?.length ?? 0) * 40000;

  @override
  Future<void> remove(String code) async {
    removed.add(code);
    books.remove(code);
  }
}

/// Same, for dictionaries: the tab reads [installed] / [sizeOnDisk] and calls
/// [remove] / [load].
class FakeDictionaryStore extends DictionaryStore {
  FakeDictionaryStore([Set<String>? initial])
      : codes = initial ?? <String>{};

  final Set<String> codes;
  final List<String> removed = [];
  final Map<String, Map<String, dynamic>> saved = {};

  @override
  Future<Set<String>> installed() async => Set.of(codes);

  @override
  Future<int> sizeOnDisk(String code) async => 100000;

  @override
  Future<void> remove(String code) async {
    removed.add(code);
    codes.remove(code);
  }

  @override
  Future<Map<String, dynamic>?> load(String code) async => saved[code];
}

/// A dictionary install with a gate, so the bar is observable mid-flight.
class FakeDictionaryService extends DictionaryDownloadService {
  FakeDictionaryService({
    this.status = DictionaryDownloadStatus.complete,
    this.hold = false,
  }) : super(client: MockClient((_) async => http.Response('', 404)));

  final DictionaryDownloadStatus status;
  final bool hold;
  final Completer<void> gate = Completer<void>();
  final List<String> installed = [];
  FakeDictionaryStore? target;

  @override
  Future<DictionaryDownloadOutcome> install(
    DictionaryEntry entry, {
    void Function(DictionaryDownloadProgress)? onProgress,
  }) async {
    installed.add(entry.code);
    if (hold) await gate.future;
    target?.codes.add(entry.code);
    return DictionaryDownloadOutcome(code: entry.code, status: status);
  }
}

/// An install that can be held mid-flight, so the progress bar is observable.
class FakeService extends DownloadService {
  FakeService(
    this.store, {
    this.status = DownloadStatus.complete,
    this.booksObtained = 66,
    this.hold = false,
  }) : super(client: MockClient((_) async => http.Response('', 404)));

  final FakeStore store;
  final DownloadStatus status;
  final int booksObtained;

  /// When true, [install] waits on [gate] between the two progress calls.
  final bool hold;
  final Completer<void> gate = Completer<void>();

  bool cancelled = false;
  final List<String> installed = [];

  @override
  void cancel() => cancelled = true;

  @override
  Future<DownloadOutcome> install(
    VersionEntry entry, {
    void Function(DownloadProgress)? onProgress,
  }) async {
    installed.add(entry.code);
    final total = bookCatalog.length;
    onProgress?.call(DownloadProgress(
        code: entry.code, done: 0, total: total, currentBook: 1));
    if (hold) await gate.future;
    if (booksObtained > 0) {
      store.books[entry.code] = {for (var i = 1; i <= booksObtained; i++) i};
    }
    onProgress?.call(
        DownloadProgress(code: entry.code, done: booksObtained, total: total));
    return DownloadOutcome(
      code: entry.code,
      status: status,
      done: booksObtained,
      total: total,
    );
  }
}

void main() {
  /// The catalogue is 13 rows: a tall surface keeps them all built, so the
  /// tests can tap a row without scrolling first.
  Future<void> pumpLibrary(
    WidgetTester tester, {
    required FakeStore store,
    required FakeService service,
    FakeDictionaryStore? dictionaryStore,
    FakeDictionaryService? dictionaryService,
    List<DictionaryEntry>? dictionaryCatalog,
  }) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(
        store: store,
        service: service,
        dictionaryStore: dictionaryStore ?? FakeDictionaryStore(),
        dictionaryService: dictionaryService ?? FakeDictionaryService(),
        dictionaryCatalog: dictionaryCatalog,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// A downloadable dictionary with a configured URL, for the download-flow
  /// tests (the real catalogue leaves them unconfigured on purpose).
  const configuredBailly = DictionaryEntry(
    code: 'BAILLY',
    name: 'Bailly — Grec-français',
    rights: 'libre',
    description: 'Dictionnaire grec-français.',
    availability: DictionaryAvailability.downloadable,
    url: 'https://s3.filebase.example/dictionaries/bailly.json',
  );

  group('LibraryScreen', () {
    /// Paysage : Android empile ses boutons de navigation sur un côté (la
    /// droite, 60 px logiques ici) et l'écran passe dessous. Ces insets sont
    /// dans `MediaQuery.padding` : l'`AppBar` les applique déjà — d'où le
    /// titre toujours lisible sur les captures — mais l'onglet, lui, n'était
    /// dans aucun `SafeArea` et courait jusqu'au bord, sous les boutons.
    testWidgets('en paysage, l\'onglet reste dans la zone sûre',
        (tester) async {
      tester.view.physicalSize = const Size(800, 360);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 360),
            devicePixelRatio: 1,
            padding: EdgeInsets.only(left: 44, right: 60, top: 24),
          ),
          child: MaterialApp(
            home: LibraryScreen(
              store: FakeStore(),
              service: FakeService(FakeStore()),
              dictionaryStore: FakeDictionaryStore(),
              dictionaryService: FakeDictionaryService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(find.byType(TabBarView));
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(rect.left, greaterThanOrEqualTo(44),
          reason: 'L\'onglet commence à ${rect.left} : il passe sous '
              'l\'encoche de gauche (44 px), comme sous les boutons Android '
              'à droite.');
      expect(rect.right, lessThanOrEqualTo(800 - 60),
          reason: 'L\'onglet finit à ${rect.right} : il passe sous les '
              'boutons Android (à partir de 740).');
    });

    testWidgets('la carte de la Septuaginta nomme ses deux traducteurs',
        (tester) async {
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
      );

      expect(
        find.text('Septuaginta — la Septante en français'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Pierre Giguet'),
        findsOneWidget,
        reason: 'Le traducteur de la première version française, sous le '
            'copyright de la carte',
      );
      expect(
        find.textContaining('Marguerite Harl'),
        findsOneWidget,
        reason: 'La direction de la Bible d\'Alexandrie, seconde traduction',
      );
    });

    testWidgets('le téléchargement se détache sur une pastille d\'action',
        (tester) async {
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
      );

      // La rangée « à télécharger » est le geste de l'écran : son bouton garde
      // son gabarit (un TextButton, clé et type compris) mais se peint d'un
      // fond d'accent.
      final download = tester.widget<TextButton>(
        find.byKey(const Key('download-DBY')),
      );
      final fond = download.style?.backgroundColor?.resolve(const <WidgetState>{});
      expect(fond, isNotNull,
          reason: 'l\'action de téléchargement doit se détacher du fond de '
              'la carte');
      expect(download.onPressed, isNotNull);

      // Les cartes des deux onglets partagent la surface premium : voile
      // vertical, liseré net et les deux ombres (ambiante + de contact). La
      // coquille les peint par un `Ink` — elle est faite pour rester sous le
      // frisson de l'appui.
      final surfaces = tester.widgetList<Ink>(find.byType(Ink)).where((ink) {
        final box = ink.decoration;
        return box is BoxDecoration &&
            box.gradient != null &&
            box.border != null &&
            (box.boxShadow?.length ?? 0) == 2;
      });
      expect(surfaces, isNotEmpty,
          reason: 'chaque tuile porte la surface premium partagée');
    });

    testWidgets('opens on Bibles and offers a Dictionnaires tab',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      expect(find.byKey(const Key('libraryTabs')), findsOneWidget);
      expect(find.byKey(const Key('libraryBibles')), findsOneWidget);
      expect(find.text('Bible Darby'), findsOneWidget);

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('libraryDictionaries')), findsOneWidget);
      // Le lexique « Notes BYM Lexique » a été débranché du catalogue.
      expect(find.text('Notes BYM Lexique'), findsNothing);
      expect(find.text('Strong FR'), findsOneWidget);
      expect(find.text('Westphal 1932'), findsOneWidget);
      // Nave reste sans source : elle s'affiche « Bientôt disponible ».
      expect(find.text('Bientôt disponible'), findsOneWidget);
      // GBM a une URL configurée : elle s'offre au téléchargement.
      expect(find.byKey(const Key('dict-download-GBM')), findsOneWidget);
      // Bailly a été retirée du catalogue.
      expect(find.byKey(const Key('dict-download-BAILLY')), findsNothing);
    });

    testWidgets('tapping Westphal opens the FreDAW index, not a stub',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      FreDawLexicon.useBundle(FakeFreDawBundle());
      addTearDown(FreDawLexicon.useRootBundle);

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Westphal 1932'));
      await tester.pumpAndSettle();

      // The index screen took over: it loads entries from the fake bundle
      // (2 entrées) instead of the static detail stub.
      expect(find.text('2 entrées'), findsOneWidget);
      expect(find.text('ABBA'), findsOneWidget);
      expect(find.text('Verset'), findsOneWidget);
    });

    // « Notes BYM Lexique » n'est plus dans le catalogue : il n'y a plus de
    // rangée à ouvrir (verrouillé par le test de liste ci-dessus).

    testWidgets('tapping Strong FR opens the Strong index, not a stub',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      StrongLexicon.useBundle(FakeStrongLexiconBundle());
      addTearDown(StrongLexicon.useRootBundle);

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Strong FR'));
      await tester.pumpAndSettle();

      expect(find.text('Dictionnaire Strong'), findsOneWidget);
      // The fake lexicon serves 5 entries, visible through the index screen.
      expect(find.text('5 entrées'), findsOneWidget);
      expect(find.text('H0001'), findsOneWidget);
    });

    testWidgets('a fresh device: BYM and LSGS are integrated, DBY downloadable',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      expect(find.byKey(const Key('download-BYM')), findsNothing);
      expect(find.byKey(const Key('download-LSGS')), findsNothing);
      expect(find.text('Intégrée à l\'application · hors ligne'),
          findsNWidgets(2),
          reason: 'BYM and the embedded LSGS both ship inside the app');
      expect(find.byKey(const Key('download-DBY')), findsOneWidget);
      expect(find.byKey(const Key('delete-DBY')), findsNothing);
      expect(find.text('Bientôt disponible'), findsWidgets);
      // Rien sur l'appareil : pas de bandeau récapitulatif.
      expect(find.textContaining('sur l\'appareil ·'), findsNothing);
    });

    testWidgets('the installed summary sits above the groups', (tester) async {
      final store = FakeStore({
        'DBY': {for (var i = 1; i <= bookCatalog.length; i++) i},
      });
      await pumpLibrary(tester, store: store, service: FakeService(store));

      // 66 × 40 000 o factices ≈ 2,5 Mo.
      expect(find.text('1 version sur l\'appareil · 2,5 Mo'), findsOneWidget);
    });

    testWidgets('tapping a sourceless version explains why', (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      await tester.tap(find.text('Nouvelle Bible Segond'));
      await tester.pumpAndSettle();

      expect(find.text('NBS — bientôt disponible.'), findsOneWidget);
    });

    testWidgets('the locked versions gather last, below the downloadable ones',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      // Elles quittent leurs groupes d'origine pour un intertitre dédié en bas.
      expect(find.text('BIENTÔT DISPONIBLES'), findsOneWidget);

      // Une version téléchargeable passe au-dessus d'une cadenassée.
      final lastAvailable =
          tester.getTopLeft(find.text('King James Version (anglais)')).dy;
      final firstLocked =
          tester.getTopLeft(find.text('Nouvelle Bible Segond')).dy;
      expect(lastAvailable, lessThan(firstLocked));
    });

    testWidgets('downloading shows the bar, then the size and the outcome',
        (tester) async {
      final store = FakeStore();
      final service = FakeService(store, hold: true);
      await pumpLibrary(tester, store: store, service: service);

      await tester.tap(find.byKey(const Key('download-DBY')));
      await tester.pump();

      expect(find.byKey(const Key('progress-DBY')), findsOneWidget);
      expect(find.text('0/${bookCatalog.length} livres · Genèse'),
          findsOneWidget);
      expect(find.byKey(const Key('cancel-DBY')), findsOneWidget);

      service.gate.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('progress-DBY')), findsNothing);
      expect(find.text('Téléchargement terminé.'), findsOneWidget);
      expect(find.byKey(const Key('delete-DBY')), findsOneWidget);
      expect(find.byKey(const Key('download-DBY')), findsNothing);
      expect(find.text('${bookCatalog.length} livres · 2,5 Mo'), findsOneWidget);
    });

    testWidgets('another version cannot start while one is downloading',
        (tester) async {
      final store = FakeStore();
      final service = FakeService(store, hold: true);
      await pumpLibrary(tester, store: store, service: service);

      await tester.tap(find.byKey(const Key('download-DBY')));
      await tester.pump();

      final other =
          tester.widget<TextButton>(find.byKey(const Key('download-LSG')));
      expect(other.onPressed, isNull, reason: 'one download at a time');

      service.gate.complete();
      await tester.pumpAndSettle();
      expect(service.installed, ['DBY']);
    });

    testWidgets('cancel reaches the service', (tester) async {
      final store = FakeStore();
      final service = FakeService(store, hold: true);
      await pumpLibrary(tester, store: store, service: service);

      await tester.tap(find.byKey(const Key('download-DBY')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('cancel-DBY')));
      await tester.pump();

      expect(service.cancelled, isTrue);
      service.gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a partial version offers to resume, and resumes', (tester) async {
      final store = FakeStore({'DBY': {1, 2, 3}});
      final service = FakeService(store);
      await pumpLibrary(tester, store: store, service: service);

      expect(
        find.text('3/${bookCatalog.length} livres — téléchargement à reprendre'),
        findsOneWidget,
      );
      expect(find.text('Reprendre'), findsOneWidget);
      // A half-installed version can also be thrown away without finishing it.
      expect(find.byKey(const Key('delete-DBY')), findsOneWidget);

      await tester.tap(find.byKey(const Key('download-DBY')));
      await tester.pumpAndSettle();

      expect(service.installed, ['DBY']);
      expect(find.text('${bookCatalog.length} livres · 2,5 Mo'), findsOneWidget);
    });

    testWidgets('a failed download keeps what landed and says so',
        (tester) async {
      final store = FakeStore();
      final service = FakeService(store,
          status: DownloadStatus.failed, booksObtained: 2);
      await pumpLibrary(tester, store: store, service: service);

      await tester.tap(find.byKey(const Key('download-DBY')));
      await tester.pumpAndSettle();

      expect(find.textContaining('2/${bookCatalog.length} livres conservés'),
          findsOneWidget);
      expect(find.text('Reprendre'), findsOneWidget);
    });

    testWidgets('delete asks first, then clears the version', (tester) async {
      final store = FakeStore({
        'DBY': {for (var i = 1; i <= bookCatalog.length; i++) i},
      });
      await pumpLibrary(tester, store: store, service: FakeService(store));

      await tester.tap(find.byKey(const Key('delete-DBY')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer Bible Darby ?'), findsOneWidget);
      // La taille libérée est annoncée avant de confirmer.
      expect(find.textContaining('(2,5 Mo)'), findsOneWidget);

      // Backing out leaves the files alone.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.removed, isEmpty);

      await tester.tap(find.byKey(const Key('delete-DBY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();

      expect(store.removed, ['DBY']);
      expect(find.text('Bible Darby supprimée de l\'appareil.'),
          findsOneWidget);
      expect(find.byKey(const Key('download-DBY')), findsOneWidget);
      expect(find.byKey(const Key('delete-DBY')), findsNothing);
    });

    testWidgets(
        'a configured downloadable dictionary offers Télécharger, then 🗑',
        (tester) async {
      final dictStore = FakeDictionaryStore();
      final dictService = FakeDictionaryService()..target = dictStore;
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: dictService,
        dictionaryCatalog: const [configuredBailly],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      expect(find.text('Bailly — Grec-français'), findsOneWidget);
      expect(find.byKey(const Key('dict-download-BAILLY')), findsOneWidget);
      expect(find.byKey(const Key('dict-delete-BAILLY')), findsNothing);

      await tester.tap(find.byKey(const Key('dict-download-BAILLY')));
      await tester.pumpAndSettle();

      expect(dictService.installed, ['BAILLY']);
      expect(find.text('Dictionnaire téléchargé.'), findsOneWidget);
      expect(find.byKey(const Key('dict-download-BAILLY')), findsNothing);
      expect(find.byKey(const Key('dict-delete-BAILLY')), findsOneWidget);
      expect(find.textContaining('Téléchargé ·'), findsOneWidget);
    });

    testWidgets('dictionary progress shows a bar, cancel reaches the service',
        (tester) async {
      final dictStore = FakeDictionaryStore();
      final dictService = FakeDictionaryService(hold: true);
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: dictService,
        dictionaryCatalog: const [configuredBailly],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dict-download-BAILLY')));
      await tester.pump();

      expect(find.byKey(const Key('dict-progress-BAILLY')), findsOneWidget);
      expect(find.byKey(const Key('dict-cancel-BAILLY')), findsOneWidget);

      await tester.tap(find.byKey(const Key('dict-cancel-BAILLY')));
      dictService.gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a failed dictionary download says so and stays empty',
        (tester) async {
      final dictStore = FakeDictionaryStore();
      final dictService = FakeDictionaryService(
          status: DictionaryDownloadStatus.noConnection);
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: dictService,
        dictionaryCatalog: const [configuredBailly],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dict-download-BAILLY')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Échec du téléchargement'), findsOneWidget);
      expect(find.byKey(const Key('dict-download-BAILLY')), findsOneWidget);
      expect(find.byKey(const Key('dict-delete-BAILLY')), findsNothing);
    });

    testWidgets('delete asks first, then clears the dictionary', (tester) async {
      final dictStore = FakeDictionaryStore({'BAILLY'});
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: FakeDictionaryService(),
        dictionaryCatalog: const [configuredBailly],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dict-delete-BAILLY')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer Bailly — Grec-français ?'), findsOneWidget);

      // Backing out leaves the files alone.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(dictStore.removed, isEmpty);

      await tester.tap(find.byKey(const Key('dict-delete-BAILLY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDictionaryDelete')));
      await tester.pumpAndSettle();

      expect(dictStore.removed, ['BAILLY']);
      expect(find.textContaining('supprimé de l\'appareil.'), findsOneWidget);
      expect(find.byKey(const Key('dict-download-BAILLY')), findsOneWidget);
      expect(find.byKey(const Key('dict-delete-BAILLY')), findsNothing);
    });

    testWidgets('an unconfigured downloadable dictionary cannot be downloaded',
        (tester) async {
      const unconfigured = DictionaryEntry(
        code: 'BAILLY',
        name: 'Bailly — Grec-français',
        rights: 'libre',
        description: 'Dictionnaire grec-français.',
        availability: DictionaryAvailability.downloadable,
      );
      final dictStore = FakeDictionaryStore();
      final dictService = FakeDictionaryService();
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: dictService,
        dictionaryCatalog: const [unconfigured],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dict-download-BAILLY')), findsNothing);
      expect(find.text('URL à configurer pour télécharger'), findsOneWidget);

      await tester.tap(find.text('Bailly — Grec-français'));
      await tester.pumpAndSettle();

      expect(dictService.installed, isEmpty);
      expect(find.textContaining('URL non configurée'), findsOneWidget);
    });

    testWidgets('tapping a downloaded dictionary opens the generic reader',
        (tester) async {
      final dictStore = FakeDictionaryStore({'BAILLY'})
        ..saved['BAILLY'] = {
          'entries': {
            'ALPHA': {'term': 'ALPHA', 'definition': 'Première lettre.'},
          },
        };
      await pumpLibrary(
        tester,
        store: FakeStore(),
        service: FakeService(FakeStore()),
        dictionaryStore: dictStore,
        dictionaryService: FakeDictionaryService(),
        dictionaryCatalog: const [configuredBailly],
      );

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bailly — Grec-français'));
      await tester.pumpAndSettle();

      expect(find.text('1 entrée'), findsOneWidget);
      expect(find.text('ALPHA'), findsOneWidget);
    });
  });
}
