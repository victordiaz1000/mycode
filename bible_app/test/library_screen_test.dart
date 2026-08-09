import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/download_service.dart';
import 'package:bible_app/data/library_store.dart';
import 'package:bible_app/data/version_catalog.dart';
import 'package:bible_app/screens/library_screen.dart';

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
  }) async {
    tester.view.physicalSize = const Size(1000, 3600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: LibraryScreen(store: store, service: service),
    ));
    await tester.pumpAndSettle();
  }

  group('LibraryScreen', () {
    testWidgets('opens on Bibles and offers a Dictionnaires tab',
        (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      expect(find.byKey(const Key('libraryTabs')), findsOneWidget);
      expect(find.byKey(const Key('libraryBibles')), findsOneWidget);
      expect(find.text('Bible Darby'), findsOneWidget);

      await tester.tap(find.text('Dictionnaires'));
      await tester.pumpAndSettle();

      // No dictionary catalogue exists yet — say so rather than list nothing.
      expect(find.text('Aucun dictionnaire à télécharger'), findsOneWidget);
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
    });

    testWidgets('tapping a sourceless version explains why', (tester) async {
      final store = FakeStore();
      await pumpLibrary(tester, store: store, service: FakeService(store));

      await tester.tap(find.text('Nouvelle Bible Segond'));
      await tester.pumpAndSettle();

      expect(find.text('NBS — bientôt disponible.'), findsOneWidget);
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
      expect(find.text('Supprimer DBY ?'), findsOneWidget);

      // Backing out leaves the files alone.
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(store.removed, isEmpty);

      await tester.tap(find.byKey(const Key('delete-DBY')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmDelete')));
      await tester.pumpAndSettle();

      expect(store.removed, ['DBY']);
      expect(find.text('DBY supprimée de l\'appareil.'), findsOneWidget);
      expect(find.byKey(const Key('download-DBY')), findsOneWidget);
      expect(find.byKey(const Key('delete-DBY')), findsNothing);
    });
  });
}
