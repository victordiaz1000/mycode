import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/bible_sections.dart';
import 'package:bible_app/data/book_mapping.dart';

void main() {
  test('all 66 BYM indexes fall in exactly one section', () {
    for (var i = 1; i <= 66; i++) {
      final matches = bibleSections.where((s) => s.contains(i));
      expect(matches.length, 1, reason: 'index $i');
    }
  });

  test('section sizes match design', () {
    expect(bibleSections[0].name, 'Torah');
    expect(bibleSections[0].to - bibleSections[0].from + 1, 5);

    expect(bibleSections[1].name, contains('Nevi’im'));
    expect(bibleSections[1].to - bibleSections[1].from + 1, 21);

    expect(bibleSections[2].name, contains('Ketouvim'));
    expect(bibleSections[2].to - bibleSections[2].from + 1, 13);

    expect(bibleSections[3].name, 'Évangiles');
    expect(bibleSections[3].to - bibleSections[3].from + 1, 4);

    expect(bibleSections[4].name, 'Testament de Yehoshoua');
    expect(bibleSections[4].to - bibleSections[4].from + 1, 23);
  });

  test('BYM -> standard mapping round-trips', () {
    for (var i = 1; i <= 66; i++) {
      final standard = bymToStandard(i);
      expect(standardToBym(standard), i, reason: 'index $i');
    }
  });

  test('known mappings', () {
    expect(bymToStandard(27), 19); // Psaumes
    expect(bymToStandard(29), 18); // Job
    expect(bymToStandard(51), 45); // Romains
    expect(bymToStandard(62), 58); // Hébreux
    expect(bymToStandard(1), 1);
    expect(bymToStandard(66), 66);
  });
}
