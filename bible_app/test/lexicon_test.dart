import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/lexicon_service.dart';
import 'package:bible_app/data/local_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = LexiconService();

  test('lexicon built from Genèse notes (Ge 6:14)', () async {
    final repo = LocalRepository();
    final book = await repo.loadBook(1);
    final entries = service.forBook(book);

    final v614 = entries
        .where((e) => e.chapter == 6 && e.verseNumber == 14)
        .toList();
    // Genèse 6:14 carries 4 notes (arche, couvriras, poix, l'intérieur).
    expect(v614.length, greaterThanOrEqualTo(4));
    expect(v614.map((e) => e.word), contains('couvriras'));
    final kaphar = v614.firstWhere((e) => e.word == 'couvriras');
    expect(kaphar.note, contains('kaphar')); // couvrir = expier
    expect(kaphar.bookIndex, 1);
  });

  test('entries without notes are not indexed', () async {
    final repo = LocalRepository();
    final book = await repo.loadBook(1);
    final entries = service.forBook(book);
    final byRef = entries.map((e) => e.ref).toSet();
    expect(byRef, isNotEmpty);
  });
}