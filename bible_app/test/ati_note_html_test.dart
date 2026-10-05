import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/ati_note_html.dart';
import 'package:bible_app/data/ati_notes.dart';

/// Le démontage se juge sur le glossaire réel : c'est lui qui porte les
/// tables non fermées, les `&nbsp;` par triplet et les liens de trois
/// sortes. Chaque test ouvre une page du `notes.json` embarqué, donc le
/// fichier du bundle est aussi contrôlé au passage.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AtiNoteDocument> parse(String id) async {
    final note = await AtiNotes.instance.lookup(id);
    expect(note, isNotNull, reason: 'page $id absente du glossaire embarqué');
    return AtiNoteDocument.parse(note!.html);
  }

  String textOf(Iterable<AtiNoteSpan> spans) => spans.map((span) {
    return switch (span) {
      AtiNoteText(:final text) => text,
      AtiNoteLink(:final label) => label,
      AtiNoteLineBreak() => '\n',
    };
  }).join();

  String allText(AtiNoteDocument doc) => doc.nodes
      .map((node) {
        return switch (node) {
          AtiNoteHeading(:final spans) => textOf(spans),
          AtiNoteParagraph(:final spans) => textOf(spans),
          AtiNoteList(:final items) => items.map(textOf).join('\n'),
          AtiNoteTable(:final rows) =>
            rows
                .map((row) => row.cells.map((c) => textOf(c.spans)).join('|'))
                .join('\n'),
          AtiNoteRule() => '',
          AtiNoteImage() => '',
        };
      })
      .join('\n');

  group('n12 — la page la plus simple', () {
    test('titre au niveau 1, un seul paragraphe, aucun lien', () async {
      final doc = await parse('n12');

      expect(doc.nodes, hasLength(2));
      final heading = doc.nodes.first as AtiNoteHeading;
      expect(heading.level, 1);
      expect(textOf(heading.spans), contains('Mot rare, hapax'));

      final body = doc.nodes.last as AtiNoteParagraph;
      expect(textOf(body.spans), contains('difficile à comprendre'));
      expect(body.quote, isFalse);
      expect(
        body.spans.whereType<AtiNoteLink>(),
        isEmpty,
        reason: 'la note 12 ne renvoie nulle part',
      );
    });

    test('le blanc de balisage ne contamine pas le texte', () async {
      final doc = await parse('n12');
      final body = doc.nodes.last as AtiNoteParagraph;
      final text = textOf(body.spans);
      expect(text, equals(text.trim()));
      expect(text, isNot(contains('  ')));
      expect(text, isNot(contains('&nbsp;')));
    });
  });

  group('d12 — tables, hébreu et références', () {
    test(
      'les références de verset restent des liens, identifiées OSIS',
      () async {
        final doc = await parse('d12');
        final table = doc.nodes.whereType<AtiNoteTable>().first;
        final first = table.rows.first.cells;

        expect(first, hasLength(2));
        final link = first[0].spans.whereType<AtiNoteLink>().single;
        expect(link.target, const AtiNoteVerseTarget('JDG1.28'));
        expect(link.label, 'Juges 1.28');
        expect(first[0].right, isTrue, reason: 'align="right" de la source');
        expect(first[0].width, 200, reason: 'width=200 sans guillemets');

        final hebrew = first[1].spans.whereType<AtiNoteText>().single;
        final source = (await AtiNotes.instance.lookup('d12'))!.html;
        expect(
          source,
          contains(hebrew.text),
          reason: 'l’hébreu doit être repris de la source, marque compris',
        );
        expect(hebrew.style.hebrew, isTrue);
        expect(hebrew.style.big, isTrue);
      },
    );

    test('la seconde ligne porte la traduction en italique', () async {
      final doc = await parse('d12');
      final table = doc.nodes.whereType<AtiNoteTable>().first;
      final second = table.rows[1].cells;

      expect(second, hasLength(2));
      expect(second[0].spans, isEmpty, reason: 'cellule de retrait vide');
      final gloss = second[1].spans.whereType<AtiNoteText>().single;
      expect(gloss.text, 'quand Israël fut fort');
      expect(gloss.style.italic, isTrue);
    });

    test('le titre de page contient l’hébreu de la racine', () async {
      final doc = await parse('d12');
      final source = (await AtiNotes.instance.lookup('d12'))!.html;
      final heading = doc.nodes.first as AtiNoteHeading;
      final hebrew = heading.spans.whereType<AtiNoteText>().last;

      expect(source, contains(hebrew.text));
      expect(hebrew.style.hebrew, isTrue);
      expect(hebrew.style.big, isTrue);
      expect(
        heading.spans.whereType<AtiNoteText>().length,
        greaterThan(1),
        reason: 'le titre mêle français et hébreu en fragments distincts',
      );
    });

    test('le premier paragraphe, lui, n’est pas en retrait', () async {
      final doc = await parse('d12');
      final paragraphs = doc.nodes.whereType<AtiNoteParagraph>().toList();
      expect(paragraphs, isNotEmpty);
      expect(
        paragraphs.first.quote,
        isFalse,
        reason: 'l’introduction n’est dans aucune citation',
      );
    });
  });

  group('les trois sortes de liens', () {
    test('vers une autre page du glossaire, par son nom', () async {
      final doc = await parse('d10');
      final links = doc.nodes
          .expand(
            (node) => switch (node) {
              AtiNoteParagraph(:final spans) => spans,
              AtiNoteHeading(:final spans) => spans,
              _ => const <AtiNoteSpan>[],
            },
          )
          .whereType<AtiNoteLink>()
          .where((link) => link.target is AtiNotePageTarget)
          .toList();

      expect(links, hasLength(1));
      expect(
        (links.single.target as AtiNotePageTarget).pageName,
        'Difficulté 7',
      );
      expect(links.single.label, '► difficulté n° 7');
    });

    test('vers le lexique Strong, code complet', () async {
      final doc = await parse('d2');
      final links = doc.nodes
          .expand(
            (node) => switch (node) {
              AtiNoteParagraph(:final spans) => spans,
              _ => const <AtiNoteSpan>[],
            },
          )
          .whereType<AtiNoteLink>()
          .where((link) => link.target is AtiNoteStrongTarget)
          .toList();

      expect(links, isNotEmpty);
      final link = links.firstWhere(
        (link) => (link.target as AtiNoteStrongTarget).strong == 'H8812',
      );
      expect(link.label, '►InCs');
      expect(link.style.bold, isTrue);
      expect(link.style.sup, isTrue);
    });
  });

  group('abr — la liste des abréviations', () {
    test(
      'cinq colonnes par ligne, la colonne d’espacement reste vide',
      () async {
        final doc = await parse('abr');
        final table = doc.nodes.whereType<AtiNoteTable>().first;

        expect(
          table.rows.length,
          greaterThanOrEqualTo(18),
          reason: '18 <tr> dans la source, plus la rangée de fin non fermée',
        );
        final first = table.rows.first.cells
            .map((c) => textOf(c.spans))
            .toList();
        expect(first, ['ab', '(infinitif) absolu', '', 'm', 'masculin']);
      },
    );
  });

  group('r2 — les schémas de la source', () {
    test('les deux images en base64 sont décodées', () async {
      final doc = await parse('r2');
      final images = doc.nodes.whereType<AtiNoteImage>().toList();

      expect(images, hasLength(2));
      for (final image in images) {
        expect(image.bytes, isNotEmpty);
        // Décodés, les deux schémas commencent par la signature PNG — la
        // source annonce `image/jpeg` mais écrit du PNG, et c'est elle qui
        // a raison.
        expect(image.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      }
    });
  });

  group('tolérance', () {
    test('un fragment vide se lit sans bloc', () {
      expect(AtiNoteDocument.parse('').isEmpty, isTrue);
      expect(AtiNoteDocument.parse('\n   \n').isEmpty, isTrue);
    });

    test('un paragraphe non fermé est refermé à la fin du flux', () {
      final doc = AtiNoteDocument.parse('<p>Une phrase coupée');
      expect(doc.nodes.single, isA<AtiNoteParagraph>());
      expect(
        textOf((doc.nodes.single as AtiNoteParagraph).spans),
        'Une phrase coupée',
      );
    });

    test('une cellule non fermée rend sa teneur', () {
      final doc = AtiNoteDocument.parse('<table><tr><td>réf</td><td><i>glose');
      final table = doc.nodes.single as AtiNoteTable;
      expect(table.rows.single.cells, hasLength(2));
      expect(textOf(table.rows.single.cells[1].spans), 'glose');
    });

    test('une balise inconnue est ignorée, le texte reste', () {
      final doc = AtiNoteDocument.parse(
        '<article><p>Texte utile</p>'
        '</article>',
      );
      expect(allText(doc), contains('Texte utile'));
    });

    test('un lien dont l’adresse est inconnue se lit en texte', () {
      final doc = AtiNoteDocument.parse(
        '<p>Voir <a class="ref" href="autre.php?x=1">ailleurs</a>.</p>',
      );
      final spans = (doc.nodes.single as AtiNoteParagraph).spans;
      expect(spans.whereType<AtiNoteLink>(), isEmpty);
      expect(textOf(spans), 'Voir ailleurs.');
    });
  });
}
