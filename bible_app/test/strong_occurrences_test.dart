import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/strong_occurrences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LsgsRepository.useRootBundle();
    StrongOccurrenceIndex.useAmbientRepository();
  });

  tearDown(() {
    LsgsRepository.useRootBundle();
    StrongOccurrenceIndex.useAmbientRepository();
  });

  test('the index scans the LSS corpus, where the extended codes live',
      () async {
    // H8799, le waw : la LSGS ne le numérote pas du tout, la LSS lui consacre
    // 19 883 jetons répartis sur 11 857 versets. C'est l'objet même de ce
    // corpus — la fiche ne doit plus répondre « 0 occurrence ».
    final waw = await StrongOccurrenceIndex.instance.occurrences('H8799');
    expect(waw, hasLength(11857));

    // Un seul enregistrement par verset, même quand la particule y revient.
    final cles = [for (final o in waw) '${o.bookIndex}:${o.chapter}:${o.verse}'];
    expect(cles.toSet(), hasLength(cles.length));
    expect(waw.first.reference, matches(RegExp(r'^\S+ \d+:\d+$')));

    // Un code ordinaire reste couvert par le même index.
    expect(await StrongOccurrenceIndex.instance.count('H7225'), 49);
  });

  test('the three codes only the LSGS carries answer no occurrence', () async {
    // G0090, G0821 et H1585 n'existent que dans la LSGS : la fiche le dit —
    // « Aucune occurrence dans la LSS embarquée » — plutôt que de renvoyer un
    // autre corpus que celui que l'étude lit.
    for (final code in ['G0090', 'G0821', 'H1585']) {
      expect(
        await StrongOccurrenceIndex.instance.count(code),
        0,
        reason: 'code absent de la LSS : $code',
      );
    }
  });
}
