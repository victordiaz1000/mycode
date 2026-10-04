import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/library_store.dart';

/// Un livre téléchargé, tel que [LibraryStore] le reçoit.
Map<String, dynamic> livre(int index, {String texte = 'Au commencement'}) => {
      'nr': index,
      'name': 'Livre $index',
      'chapters': [
        {
          'chapter': 1,
          'verses': [
            {'chapter': '1', 'verse': '1', 'text': texte},
          ],
        },
      ],
    };

void main() {
  // `test()` et non `testWidgets` : le système de fichiers est réellement
  // accessible ici, à l'inverse de la zone fake-async d'un test de widget.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late LibraryStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('bym_gzip_test');
    LibraryStore.useRoot(temp);
    store = LibraryStore();
  });

  tearDown(() async {
    LibraryStore.useAppDirectory();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('LibraryStore en gzip', () {
    test('un livre écrit se relit à l\'identique', () async {
      await store.saveBook('ATI', 1, livre(1));

      final relu = await store.loadBook('ATI', 1);
      expect(relu, isNotNull);
      expect(relu!['name'], 'Livre 1');
      expect(
        (((relu['chapters'] as List).first as Map)['verses'] as List).first,
        containsPair('text', 'Au commencement'),
      );
    });

    test('le fichier sur disque est bien compressé, pas du JSON en clair',
        () async {
      await store.saveBook('ATI', 1, livre(1));

      final fichier = await store.bookFile('ATI', 1);
      expect(fichier.path, endsWith('1.json.gz'));
      expect(await fichier.exists(), isTrue);

      // Les deux octets d'en-tête gzip, 0x1f 0x8b. Décoder le contenu et y
      // retrouver le texte prouve en même temps que ce n'est pas une
      // compression vide.
      final octets = await fichier.readAsBytes();
      expect(octets.take(2), [0x1f, 0x8b]);
      expect(utf8.decode(gzip.decode(octets)), contains('Au commencement'));
    });

    test('gzip pèse moins que le clair sur un livre réaliste', () async {
      // Le gain vient de la répétition : un vrai livre répète ses clés à chaque
      // verset. Sur un objet minuscule, l'en-tête gzip coûterait plus qu'il ne
      // rapporte — ce n'est donc pas mesurable sur `livre(1)`.
      final gros = {
        'nr': 2,
        'name': 'Livre 2',
        'chapters': [
          for (var c = 1; c <= 20; c++)
            {
              'chapter': c,
              'verses': [
                for (var v = 1; v <= 30; v++)
                  {'chapter': '$c', 'verse': '$v', 'text': 'Verset $c:$v'},
              ],
            },
        ],
      };
      await store.saveBook('ATI', 2, gros);

      final surDisque = await (await store.bookFile('ATI', 2)).length();
      final enClair = utf8.encode(jsonEncode(gros)).length;
      expect(surDisque, lessThan(enClair ~/ 2),
          reason: 'le JSON d\'une version est très compressible');
    });

    test('une installation en clair d\'avant la compression se lit toujours',
        () async {
      // La garantie de non-régression : aucune migration n'est exécutée au
      // démarrage, donc une version installée par une version antérieure de
      // l'app doit rester lisible telle quelle. Déposé à la main, sans passer
      // par `saveBook`, qui n'écrit plus jamais ce nom.
      final ancien = await store.legacyBookFile('DBY', 5);
      await ancien.parent.create(recursive: true);
      await ancien.writeAsString(jsonEncode(livre(5, texte: 'Ancien régime')));

      final relu = await store.loadBook('DBY', 5);
      expect(relu, isNotNull);
      expect(relu!['name'], 'Livre 5');
      expect(
        (((relu['chapters'] as List).first as Map)['verses'] as List).first,
        containsPair('text', 'Ancien régime'),
      );
    });

    test('réinstaller un livre en clair ne laisse pas deux fichiers derrière',
        () async {
      // Sinon `sizeOnDisk` annoncerait la somme des deux régimes, et la carte
      // de la Bibliothèque afficherait un poids faux après une réinstallation.
      final ancien = await store.legacyBookFile('DBY', 5);
      await ancien.parent.create(recursive: true);
      await ancien.writeAsString(jsonEncode(livre(5, texte: 'Ancien régime')));

      await store.saveBook('DBY', 5, livre(5, texte: 'Nouveau régime'));

      expect(await ancien.exists(), isFalse);
      final relu = await store.loadBook('DBY', 5);
      expect(
        (((relu!['chapters'] as List).first as Map)['verses'] as List).first,
        containsPair('text', 'Nouveau régime'),
      );
    });

    test('un livre absent donne null, pas une exception', () async {
      expect(await store.loadBook('ATI', 7), isNull);
    });

    test('un fichier .json.gz illisible donne null, pas une exception',
        () async {
      // Un téléchargement tronqué laisse un fichier qui existe et ne se
      // décompresse pas. Le livre doit se relire comme absent — il sera
      // retéléchargé — et non faire tomber le lecteur.
      final fichier = await store.bookFile('ATI', 8);
      await fichier.parent.create(recursive: true);
      await fichier.writeAsBytes([0x1f, 0x8b, 0x08, 0x00, 0x00]);

      expect(await store.loadBook('ATI', 8), isNull);
    });

    test('remove efface les fichiers gzip comme les autres', () async {
      await store.saveBook('ATI', 1, livre(1));
      final dossier = await store.versionDirectory('ATI');
      expect(await dossier.exists(), isTrue);

      await store.remove('ATI');

      expect(await dossier.exists(), isFalse);
      expect(await store.loadBook('ATI', 1), isNull);
    });

    test('sizeOnDisk compte le poids compressé', () async {
      await store.saveBook('ATI', 1, livre(1));
      final attendu = await (await store.bookFile('ATI', 1)).length();

      expect(await store.sizeOnDisk('ATI'), attendu);
    });
  });
}
