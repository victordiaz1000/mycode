import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lsgs_repository.dart';

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
}
