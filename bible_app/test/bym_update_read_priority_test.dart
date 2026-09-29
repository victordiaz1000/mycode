import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/book_catalog.dart';
import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/data/bym_update_store.dart';
import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/models/bible_book.dart';

import 'support/fake_bible_bundle.dart';

/// `LocalRepository.loadBook` est le goulot de toute la BYM : favoris, accueil,
/// notes, recherche, lexique et occurrences Strong y passent tous. Ces tests
/// vérifient donc l'unique endroit où la priorité de lecture est branchée.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const genese = '01-Genese.json';
  late Directory temp;
  late BymUpdateStore store;

  /// Empreinte de blob du `.md` d'origine : la forme compte, la valeur non — ce
  /// test porte sur la priorité de lecture, pas sur la vérification.
  const blob = '6551d038aabbccddeeff00112233445566778899';

  /// Dépose et enregistre [contents] comme le ferait une mise à jour installée.
  Future<void> install(String contents) async {
    await store.stage(genese, contents);
    await store.install(
      commit: 'cb535d4a3c9f1e2b7d8a4c5e6f708192a3b4c5d6',
      committedAt: DateTime.utc(2026, 8, 30),
      notes: 'Correction Genèse',
      blobs: const {genese: blob},
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_read_priority_test');
    BymUpdateStore.useRoot(temp);
    BymUpdateStore.resetInMemory();
    // Sert des livres synthétiques : `useBundle` vide aussi le cache statique
    // de `LocalRepository`, partagé entre les tests.
    LocalRepository.useBundle(FakeBibleBundle());
    store = BymUpdateStore();
  });

  tearDown(() async {
    LocalRepository.useRootBundle();
    BymUpdateStore.useAppDirectory();
    BymUpdateStore.resetInMemory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('sans mise à jour, le livre vient de l\'asset embarqué', () async {
    final book = await LocalRepository().loadBook(1);
    expect(book.book, catalogEntry(1).name);
  });

  test('un livre mis à jour l\'emporte sur l\'asset', () async {
    await install(jsonEncode({
      'book': 'Bereshit (Genèse) corrigé',
      'abbreviation': 'Ge.',
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {'verse': '1:2', 'text': 'La terre devint informe et vide.'},
          ],
        },
      ],
    }));

    final book = await LocalRepository().loadBook(1);

    expect(book.book, 'Bereshit (Genèse) corrigé');
    expect(book.chapters.single.verses.single.text,
        'La terre devint informe et vide.');
    // Les 65 autres livres continuent de venir de l'APK : une publication ne
    // liste que son delta.
    expect((await LocalRepository().loadBook(2)).book, catalogEntry(2).name);
  });

  test('un JSON abîmé retombe sur l\'asset et désinstalle la mise à jour',
      () async {
    await install('{ ceci n\'est pas du JSON');

    final book = await LocalRepository().loadBook(1);

    // Sans ce filet, un livre — voire l'application — resterait illisible sans
    // aucun recours depuis l'interface.
    expect(book.book, catalogEntry(1).name);
    // Retour au texte embarqué en entier, pas un panachage : la date et le
    // compte affichés ne décriraient plus ce qui est lu.
    expect(BymUpdateStore.hasUpdate(genese), isFalse);
    expect(BymUpdateStore.installedCommit, isNull);
    expect(await store.sizeOnDisk(), 0);
  });

  test('un fichier disparu retombe sur l\'asset sans lever', () async {
    // Cas d'un `clear()` interrompu : le registre est en avance sur le disque.
    SharedPreferences.setMockInitialValues({
      BymUpdateStore.blobsKey:
          jsonEncode({genese: '6551d038aabbccddeeff00112233445566778899'}),
      BymUpdateStore.commitKey: 'cb535d4a3c9f1e2b7d8a4c5e6f708192a3b4c5d6',
    });
    await BymUpdateStore.load();
    expect(BymUpdateStore.hasUpdate(genese), isTrue);

    final book = await LocalRepository().loadBook(1);

    expect(book.book, catalogEntry(1).name);
  });

  test('le retour au texte embarqué reprend effet après vidage du cache',
      () async {
    await install(jsonEncode({
      'book': 'Bereshit (Genèse) corrigé',
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {'verse': '1:1', 'text': 'Corrigé.'},
          ],
        },
      ],
    }));
    expect((await LocalRepository().loadBook(1)).book,
        'Bereshit (Genèse) corrigé');

    await store.clear();
    // Le cache doit être vidé, sinon la recherche et la lecture continueraient
    // de servir l'ancien texte : c'est ce que fait `invalidateCaches`.
    LocalRepository.clearCache();

    expect((await LocalRepository().loadBook(1)).book, catalogEntry(1).name);
  });

  test(
    'quand textRevision prévient, une relecture donne déjà le texte corrigé',
    () async {
      // L'écran de lecture se rafraîchit sur cette notification
      // (`chapter_reader.dart:_onTextRevisionChanged`). Tout l'intérêt est
      // l'ordre : le cache doit être vide *avant* que la notification parte,
      // sinon la relecture ressort le livre d'avant — exactement celui que la
      // mise à jour vient de remplacer. C'est la raison d'être de
      // `textRevision` plutôt que de `BymUpdateStore.revision`, qui prévient au
      // moment de l'écriture du registre, donc trop tôt.

      // Le cache tient le texte embarqué, comme un onglet resté ouvert.
      expect((await LocalRepository().loadBook(1)).book, catalogEntry(1).name);

      await install(jsonEncode({
        'book': 'Bereshit (Genèse) corrigé',
        'chapters': [
          {
            'chapter': 1,
            'verses': [
              {'verse': '1:1', 'text': 'Corrigé.'},
            ],
          },
        ],
      }));

      Future<BibleBook>? reread;
      void listener() => reread = LocalRepository().loadBook(1);
      BymUpdateService.textRevision.addListener(listener);
      addTearDown(() => BymUpdateService.textRevision.removeListener(listener));

      BymUpdateService.invalidateCaches();

      expect(reread, isNotNull, reason: 'la notification n\'est pas partie');
      expect((await reread!).book, 'Bereshit (Genèse) corrigé');
    },
  );
}
