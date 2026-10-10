import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/models/lsgs.dart';

/// Genèse 1.1 en LSS : deux codes sans mot français (H8804, le waw consécutif,
/// et H0853, le marqueur d'accusatif) entre les mots que la traduction rend.
const verseSansMot = [
  LsgsToken(text: 'Béla ', strong: 'H1106'),
  LsgsToken(text: 'mourut ', strong: 'H4191'),
  LsgsToken(text: '', strong: 'H8799'),
  LsgsToken(text: '; et Jobab', strong: null),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final repo = LsgsRepository();

  test('LSGS asset paths use the embedded accented filenames', () {
    expect(repo.assetPath(1), 'assets/bible/lsgs/01-Genèse.json');
    expect(repo.assetPath(12), 'assets/bible/lsgs/12-Ésaïe.json');
    expect(repo.assetPath(14), 'assets/bible/lsgs/14-Ézéchiel.json');
    expect(repo.assetPath(52), 'assets/bible/lsgs/52-Éphésiens.json');
  });

  test('LSGS assetPath rejects invalid book numbers', () {
    expect(() => repo.assetPath(0), throwsRangeError);
    expect(() => repo.assetPath(67), throwsRangeError);
  });

  test('the LSS corpus sits beside the LSGS one, same filenames', () {
    final lss = LsgsRepository(directory: 'lss');
    expect(lss.assetPath(1), 'assets/bible/lss/01-Genèse.json');
    expect(lss.assetPath(66), 'assets/bible/lss/66-Apocalypse.json');
    expect(LsgsRepository().directory, 'lsgs');
  });

  test('the plain text leaves out the words the translation does not render',
      () {
    expect(LsgsRepository.joinTokens(verseSansMot), 'Béla mourut; et Jobab');
  });

  test('the interlinear rendering gives those words their code', () {
    expect(
      LsgsRepository.joinTokens(verseSansMot, includeStrong: true),
      'Béla H1106 mourut H4191 H8799; et Jobab',
    );
  });

  test('an excerpt shows the searched code even when it has no word', () {
    final cible = LsgsRepository.segments(verseSansMot, target: 'H8799');
    expect(cible.any((s) => s.isTarget && s.text.trim() == 'H8799'), isTrue);

    // Un code qui n'est pas celui cherché reste hors de l'extrait : le texte
    // lu ne se met pas à parsemer ses mots d'annotation.
    final autre = LsgsRepository.segments(verseSansMot, target: 'H4191');
    expect(autre.where((s) => s.text.trim() == 'H8799'), isEmpty);
    expect(autre.any((s) => s.isTarget), isTrue);
  });
}
