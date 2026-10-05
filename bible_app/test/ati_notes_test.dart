import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/ati_notes.dart';

/// Un bundle qui sert le glossaire qu'on lui donne — ou rien du tout pour la
/// voie de la panne.
class _FakeNotesBundle extends AssetBundle {
  _FakeNotesBundle([this.raw]);

  final String? raw;

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (raw == null) throw ArgumentError('Asset inconnu : $key');
    return raw!;
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = utf8.encode(await loadString(key));
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('le glossaire embarqué', () {
    test('les 37 pages se lisent depuis le bundle', () async {
      expect(AtiNotes.assetPath, 'assets/ati/notes.json');
      expect(await AtiNotes.instance.size(), 37);
    });

    test(
      'un renvoi connu donne son intitulé, son titre et son corps',
      () async {
        final note = await AtiNotes.instance.lookup('n12');

        expect(note, isNotNull);
        expect(note!.id, 'n12');
        expect(note.name, 'Note 12');
        expect(note.title, startsWith('Mot rare, hapax'));
        expect(note.html, contains('<h1>'));
        expect(note.heading, note.title);
      },
    );

    test('les trois familles de renvois de l’interlinéaire existent', () async {
      for (final id in ['n12', 'd12', 'r2', 'abr']) {
        expect(
          await AtiNotes.instance.lookup(id),
          isNotNull,
          reason: 'renvoi $id',
        );
      }
      expect((await AtiNotes.instance.lookup('r2'))!.name, 'Remarque 2');
      final abr = (await AtiNotes.instance.lookup('abr'))!;
      expect(abr.name, 'Abréviations');
      expect(abr.title, startsWith('Liste des abr'));
    });

    test('un renvoi hors table se lit « absent », pas en erreur', () async {
      expect(await AtiNotes.instance.lookup('zzz'), isNull);
      expect(
        await AtiNotes.instance.lookup('  n12  '),
        await AtiNotes.instance.lookup('n12'),
        reason: 'le renvoi porte parfois des espaces de source',
      );
      expect(await AtiNotes.instance.headingOf('zzz'), isNull);
      expect(await AtiNotes.instance.headingOf('n12'), isNotNull);
    });
  });

  group('voie de panne', () {
    tearDown(AtiNotes.useRootBundle);

    test('un bundle absent rend un glossaire vide', () async {
      AtiNotes.useBundle(_FakeNotesBundle());

      expect(await AtiNotes.instance.size(), 0);
      expect(await AtiNotes.instance.lookup('n12'), isNull);
    });

    test('un JSON abîmé rend un glossaire vide, pas une exception', () async {
      AtiNotes.useBundle(_FakeNotesBundle('ceci n’est pas du json'));

      expect(await AtiNotes.instance.size(), 0);
    });

    test(
      'un glossaire dont une page est mal formée garde les autres',
      () async {
        AtiNotes.useBundle(
          _FakeNotesBundle(
            jsonEncode({
              'n12': {
                'name': 'Note 12',
                'title': 'Mot rare',
                'html': '<p>corps',
              },
              'cassée': 'une chaîne à la place d’une page',
            }),
          ),
        );

        expect(await AtiNotes.instance.size(), 1);
        expect((await AtiNotes.instance.lookup('n12'))!.heading, 'Mot rare');
      },
    );

    test('le bundle réel reprend la main pour les tests suivants', () async {
      AtiNotes.useBundle(_FakeNotesBundle());
      expect(await AtiNotes.instance.size(), 0);

      AtiNotes.useRootBundle();
      expect(await AtiNotes.instance.size(), 37);
    });
  });
}
