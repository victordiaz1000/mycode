import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/dictionary_catalog.dart';
import 'package:bible_app/data/dictionary_reader.dart';
import 'package:bible_app/screens/dictionary_entry_screen.dart';

/// La fiche dictionnaire est **paresseuse**.
///
/// C'est la garantie anti-régression du passage en slivers. Avant, la fiche
/// était une `Column` dans un `SingleChildScrollView` : tous les paragraphes
/// étaient construits et mis en page d'un coup, et un bouton « Lire la suite »
/// servait de digue. Mesuré sur le corpus Westphal, cette digue était
/// indispensable — « PROPHÈTE 6. » fait 140 121 caractères sur 705
/// paragraphes, et six autres articles dépassent 55 000 caractères.
///
/// Si quelqu'un remet un `SingleChildScrollView` ou une `Column` sur ce
/// chemin, le premier test ci-dessous passe de « une poignée de paragraphes
/// construits » à « 700 », et échoue.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const entry = DictionaryEntry(
    code: 'TEST',
    name: 'Dictionnaire test',
    rights: 'libre',
    description: 'Un dictionnaire de test.',
    availability: DictionaryAvailability.downloadable,
  );

  /// 700 paragraphes de prose, chacun identifiable et assez long pour ne pas
  /// tomber dans le régime « ligne courte » (qui resserre l'interligne).
  String longDefinition(int count) => [
    for (var i = 0; i < count; i++)
      'Paragraphe $i — du texte de remplissage suffisamment long pour que ce '
          'bloc compte comme de la prose et non comme un vers isolé, afin que '
          'la mise en page testée soit bien celle d\'un article ordinaire.',
  ].join('\n\n');

  Future<DictionaryArticle> pumpFiche(
    WidgetTester tester, {
    required int paragraphs,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final reader = DictionaryReader.fromJson({
      'entries': {
        'LONG': {'definition': longDefinition(paragraphs)},
      },
    });
    final article = reader.lookup('LONG')!;
    await tester.pumpWidget(
      MaterialApp(
        home: DictionaryEntryScreen(
          entry: entry,
          article: article,
          reader: reader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return article;
  }

  /// Le nombre de paragraphes réellement construits : les `RichText` dont le
  /// texte brut est l'un des nôtres. Le terme et le badge de l'en-tête en sont
  /// exclus par le préfixe.
  int builtParagraphs(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .where((w) => w.text.toPlainText().startsWith('Paragraphe '))
      .length;

  testWidgets('700 paragraphes : seul un écran est construit', (tester) async {
    await pumpFiche(tester, paragraphs: 700, size: const Size(390, 844));

    final built = builtParagraphs(tester);
    expect(built, greaterThan(0), reason: 'le début de l\'article est rendu');
    expect(
      built,
      // Mesuré : 5 paragraphes construits sur 700, à 390×844. La borne laisse
      // de la marge pour un viewport plus grand ou une police plus petite,
      // tout en restant très loin des 700 d'une construction gloutonne.
      lessThan(40),
      reason:
          'une fiche paresseuse ne construit qu\'un écran et ses marges ; '
          '$built paragraphes construits sur 700 trahit un retour à une '
          'Column / un SingleChildScrollView',
    );
  });

  testWidgets('« Lire la suite » a disparu, le compteur le remplace', (
    tester,
  ) async {
    await pumpFiche(tester, paragraphs: 700, size: const Size(390, 844));

    expect(
      find.textContaining('Lire la suite'),
      findsNothing,
      reason: 'le bouton n\'existait que pour contenir le coût de construction',
    );
    expect(find.textContaining('Réduire'), findsNothing);
    // Il informait aussi que l'entrée est un traité : ce service passe au
    // compteur de l'en-tête épinglée.
    expect(find.text('700 §'), findsOneWidget);
  });

  testWidgets('un article court n\'affiche pas de compteur', (tester) async {
    await pumpFiche(tester, paragraphs: 3, size: const Size(390, 844));

    expect(find.textContaining('§'), findsNothing);
    // Et il est rendu en entier : rien n'est caché.
    expect(builtParagraphs(tester), 3);
  });

  testWidgets('l’en-tête reste épinglée pendant le défilement', (
    tester,
  ) async {
    await pumpFiche(tester, paragraphs: 700, size: const Size(390, 844));

    expect(find.text('LONG'), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();

    expect(
      find.text('LONG'),
      findsOneWidget,
      reason: 'le terme accompagne la lecture ; la carte de tête, elle, '
          'disparaissait au premier geste',
    );
  });
}
