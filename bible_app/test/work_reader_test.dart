import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/work_reader.dart';
import 'package:bible_app/data/work_store.dart';
import 'package:bible_app/widgets/reader_actions_bar.dart';
import 'package:bible_app/widgets/work_reader.dart';

/// Le texte noté de la convention BYM : `text` nu, `textWithNotes` avec la
/// marque `[mot]`, et l'invariant que `text` contient bien le mot à la
/// position déclarée. C'est ce que `pdf_book_to_json.py` produit, et ce que
/// `NoteAwareVerseText` exige pour situer une note.
const String _notedText = "Le ministère est d'abord une conséquence de l'appel.";
const String _notedWord = 'appel';

int get _notedPosition => _notedText.indexOf(_notedWord);

/// Deux chapitres : le premier sert de répertoire à tous les types de blocs,
/// le second est assez long pour déborder un téléphone et exercer le
/// défilement comme la reprise de position.
Map<String, dynamic> fakeWork({String code = 'MINISTERE'}) => {
      'code': code,
      'title': 'LE MINISTÈRE OU LE SEIGNEUR',
      'subtitle': 'QUE PRÉFÈRES-TU ?',
      'author': 'Trésor Koufounda',
      'publisher': 'Vases de Terre les Éditions',
      'isbn': '978-2-9578689-3-3',
      'rights': '© 2024 Vases de Terre les Éditions · diffusion gratuite '
          'autorisée · STRICTEMENT INTERDIT À LA VENTE',
      'toc': [
        {'title': 'INTRODUCTION', 'level': 0, 'chapter': 1},
        // Le chapitre 1 du livre tient son titre de cette ligne, et ses
        // sections lui sont subordonnées — la structure du sommaire imprimé,
        // celle que le double chevron replie sur le chapitre courant.
        {'title': 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR', 'level': 0, 'chapter': 2},
        {'title': "I. D'ABORD L'ADORATION", 'level': 1, 'chapter': 2},
        {'title': 'II. AIMER LE SEIGNEUR', 'level': 1, 'chapter': 2},
        // Section annoncée par le sommaire mais absente du corps : la feuille
        // doit la montrer sans faire semblant de pouvoir y conduire.
        {'title': 'III. FAIRE LA VOLONTÉ DU SEIGNEUR', 'level': 1, 'chapter': 2},
        // Section imprimée avant le premier chapitre : elle n'ouvre rien.
        {'title': 'Avant-propos de l\'éditeur', 'level': 0, 'chapter': 0},
      ],
      'chapters': [
        {
          'number': 1,
          'title': 'INTRODUCTION',
          'blocks': [
            {'type': 'p', 'text': _notedText, 'notes': [
              {
                'word': _notedWord,
                'position': _notedPosition,
                'note': 'Première note.',
              },
            ]},
            {
              'type': 'quote',
              'text': '« Oui, je serai avec toi. »',
              'reference': 'Genèse 1:1',
            },
            {'type': 'h2', 'text': "I. D'ABORD L'ADORATION"},
            {'type': 'li', 'text': 'La vie de prière,'},
            {'type': 'li', 'text': 'la communion fraternelle.'},
            {'type': 'pair', 'text': 'Bereshit', 'gloss': 'Genèse'},
            // Type qu'un convertisseur plus récent seul pourrait écrire :
            // il doit tomber en prose plutôt qu'en blanc.
            {'type': 'h9', 'text': 'Un titre d\'un rang inconnu'},
          ],
        },
        {
          'number': 2,
          'title': 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR',
          'blocks': [
            {'type': 'h2', 'text': "I. D'ABORD L'ADORATION"},
            for (var i = 1; i <= 7; i++)
              {
                'type': 'p',
                'text': 'Paragraphe $i : servir le Seigneur, c\'est d\'abord '
                    'obéir à son appel, puis y persévérer avec ceux qui '
                    'l\'ont déjà fait.',
              },
            {'type': 'h2', 'text': 'II. AIMER LE SEIGNEUR'},
            for (var i = 8; i <= 15; i++)
              {
                'type': 'p',
                'text': 'Paragraphe $i : servir le Seigneur, c\'est d\'abord '
                    'obéir à son appel, puis y persévérer avec ceux qui '
                    'l\'ont déjà fait.',
              },
          ],
        },
      ],
    };

/// Reads from memory instead of `dart:io`, which never answers inside the
/// fake-async zone of `testWidgets`.
class FakeWorkStore extends WorkStore {
  FakeWorkStore(this.payload);

  final Map<String, dynamic>? payload;

  @override
  Future<Map<String, dynamic>?> load(String code) async => payload;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ---- Le modèle, tel que l'extracteur l'écrit ----

  group('Work.parse', () {
    test('a stored payload becomes a readable work', () {
      final work = Work.parse(fakeWork())!;

      expect(work.code, 'MINISTERE');
      expect(work.title, 'LE MINISTÈRE OU LE SEIGNEUR');
      expect(work.subtitle, 'QUE PRÉFÈRES-TU ?');
      expect(work.author, 'Trésor Koufounda');
      expect(work.publisher, 'Vases de Terre les Éditions');
      expect(work.isbn, '978-2-9578689-3-3');
      expect(work.toc.length, 6);
      expect(work.toc.first.title, 'INTRODUCTION');
      expect(work.toc.first.level, 0);
      expect(work.toc.first.chapter, 1);
      // La structure que le sommaire du chapitre déplie : un titre de niveau
      // 0, puis ses sections à niveau 1, toutes portant le numéro du chapitre
      // qui les contient.
      expect(work.toc[1].title, 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR');
      expect(work.toc[1].chapter, 2);
      expect(work.toc[2].title, "I. D'ABORD L'ADORATION");
      expect(work.toc[2].level, 1);
      expect(work.toc[2].chapter, 2);
      expect(work.chapters.length, 2);
      expect(work.chapters.first.blocks.length, 7);
    });

    test('a payload without a title is not a book', () {
      final json = fakeWork()..remove('title');
      expect(Work.parse(json), isNull,
          reason: 'la pastille de l\'écran Lecture n\'aurait rien à porter');
    });

    test('a payload with a blank title is not a book either', () {
      final json = fakeWork()..['title'] = '   ';
      expect(Work.parse(json), isNull);
    });

    test('a payload without chapters is not a book', () {
      final json = fakeWork()..remove('chapters');
      expect(Work.parse(json), isNull,
          reason: 'un lien cassé sert souvent une page HTML en 200');
    });

    test('a payload with an empty chapter list is not a book', () {
      final json = fakeWork()..['chapters'] = <dynamic>[];
      expect(Work.parse(json), isNull);
    });

    test('an unknown block type degrades to a paragraph, never to a blank',
        () {
      final work = Work.parse(fakeWork())!;
      final last = work.chapters.first.blocks.last;
      expect(last.kind, WorkBlockKind.paragraph);
      expect(last.text, 'Un titre d\'un rang inconnu');
    });

    test('a note rides on the BYM verse convention', () {
      final work = Work.parse(fakeWork())!;
      final block = work.chapters.first.blocks.first;
      final verse = block.asVerse();

      expect(verse.text, _notedText);
      // Sans marque de crochet dans la version « textWithNotes » : c'est le
      // widget de notes qui la remet, à sa façon.
      expect(verse.textWithNotes, _notedText);
      expect(verse.notes.single.word, _notedWord);
      expect(
        verse.text.substring(
          verse.notes.single.position,
          verse.notes.single.position + _notedWord.length,
        ),
        _notedWord,
        reason: 'l\'invariant sans lequel aucune note ne se situe',
      );
    });
  });

  group('Work index de lecture', () {
    final work = Work.parse(fakeWork())!;

    test('the sommaire is index 0 and holds no chapter', () {
      expect(work.chapterAt(0), isNull);
      expect(work.labelAt(0), 'Sommaire');
    });

    test('chapters are numbered from 1, not from their own number', () {
      // Chapitre imprimé « CHAPITRE 1 » = deuxième index : le numéro du livre
      // et l'index de lecture sont deux comptes différents.
      expect(work.chapterAt(1)!.number, 1);
      expect(work.chapterAt(2)!.number, 2);
      expect(work.chapterAt(2)!.title, 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR');
    });

    test('an out-of-range index reads as nothing, not as the last chapter',
        () {
      expect(work.chapterAt(3), isNull);
      expect(work.chapterAt(-1), isNull);
    });

    test('the last index is the sommaire\'s mirror', () {
      expect(work.lastIndex, 2);
      expect(work.labelAt(work.lastIndex), 'CHAPITRE 1 : LE SERVICE DU SEIGNEUR');
    });

    test('a toc line opens a chapter only when it names one', () {
      expect(const WorkTocItem(title: 'I.', level: 1, chapter: 2).hasDestination,
          isTrue);
      expect(
        const WorkTocItem(title: 'Avant-propos', level: 0, chapter: 0)
            .hasDestination,
        isFalse,
      );
    });
  });

  // ---- Le lecteur ----

  group('WorkReader', () {
    /// Fait écouler le débounce (400 ms) du rapport de position, puis **force
    /// un frame**.
    ///
    /// Le rapport part d'un `addPostFrameCallback` lancé hors frame — le
    /// canal que `ChapterReader` utilise déjà, pour ne pas notifier le
    /// `TabManager` pendant le build. Or `tester.pump()` ne dessine un frame
    /// que s'il y en a un de planifié, et `addPostFrameCallback` n'en planifie
    /// aucun : sans cet appel, le rapport resterait en attente indéfiniment
    /// alors que l'appareil, lui, redessine sans arrêt.
    Future<void> settleDebounce(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 600));
      tester.binding.scheduleFrame();
      await tester.pump();
    }

    /// Rend [reader] sur une surface donnée. Haute par défaut : les tests de
    /// contenu veulent tout voir sans défiler.
    Future<void> pumpReader(
      WidgetTester tester, {
      required WorkReader reader,
      Size size = const Size(1000, 3600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: reader)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('le chapitre 0 rend le sommaire, pas un chapitre',
        (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.byKey(const Key('workSommaire')), findsOneWidget);
      expect(find.text('SOMMAIRE'), findsOneWidget);
      expect(find.text("I. D'ABORD L'ADORATION"), findsOneWidget);
      // Les métadonnées de garde sont à leur place : un sommaire de livre
      // imprimé porte le sous-titre, l'auteur et l'éditeur.
      expect(find.text('QUE PRÉFÈRES-TU ?'), findsOneWidget);
      expect(find.text('Trésor Koufounda'), findsOneWidget);
      expect(find.textContaining('ISBN 978-2-9578689-3-3'), findsOneWidget);
      expect(find.textContaining('STRICTEMENT INTERDIT'), findsOneWidget,
          reason: 'la licence du pilote doit rester lisible');
    });

    testWidgets('une ligne du sommaire ouvre son chapitre', (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      await tester.tap(find.byKey(const Key('work-toc-0')));
      await tester.pumpAndSettle();
      expect(opened, [1], reason: 'le niveau 0 mène au chapitre 1');

      await tester.tap(find.byKey(const Key('work-toc-1')));
      await tester.pumpAndSettle();
      expect(opened, [1, 2], reason: 'une ligne de titre ouvre son chapitre');

      await tester.tap(find.byKey(const Key('work-toc-2')));
      await tester.pumpAndSettle();
      expect(opened, [1, 2, 2],
          reason: 'le niveau 1 ouvre aussi le chapitre qui le contient');
    });

    testWidgets('une ligne sans destination ne fait pas semblant',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      // « Avant-propos de l'éditeur » : section imprimée, aucun chapitre.
      await tester.tap(find.text('Avant-propos de l\'éditeur'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(find.text('Avant-propos de l\'éditeur'), findsOneWidget,
          reason: 'elle reste du texte, pas un lien mort');
    });

    testWidgets('un chapitre rend ses blocs dans leur ordre', (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.byKey(const Key('workSommaire')), findsNothing);
      // L'en-tête du chapitre, puis les blocs.
      expect(find.text('INTRODUCTION'), findsOneWidget);
      expect(
        find.textContaining(_notedWord, findRichText: true),
        findsOneWidget,
        reason: 'le paragraphe noté est rendu dans le corps du texte',
      );
      expect(find.text('« Oui, je serai avec toi. »'), findsOneWidget);
      expect(find.text("I. D'ABORD L'ADORATION"), findsOneWidget,
          reason: 'l\'intertitre est rendu, pas avalé');
      expect(find.text('La vie de prière,'), findsOneWidget);
      expect(find.text('Bereshit'), findsOneWidget);
      expect(find.text('Genèse'), findsOneWidget,
          reason: 'la glose d\'un tableau des noms tient sa colonne');
    });

    testWidgets('la pastille porte le titre de l\'ouvrage, sans version',
        (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.text('LE MINISTÈRE OU LE SEIGNEUR'), findsOneWidget,
          reason: 'le titre remplace le nom de livre biblique');
      expect(find.byTooltip('Aller au verset'), findsNothing,
          reason: 'un ouvrage n\'a pas de numérotation de verset');
      expect(find.byTooltip('Chapitre précédent'), findsOneWidget);
      expect(find.byTooltip('Chapitre suivant'), findsOneWidget);
      // Le réglage de la taille du texte est la seule entrée de plus.
      expect(find.byTooltip('Affichage du texte'), findsOneWidget);
    });

    // ---- Le double chevron : aller à un chapitre ----

    testWidgets('la barre tient sur un écran étroit sans déborder',
        (tester) async {
      // Le titre partage désormais sa ligne avec un bouton de plus : sur un
      // téléphone étroit c'est sa place qui manque d'abord. Il doit raccourcir
      // (le libellé porte déjà l'ellipsis) et surtout ne pas faire déborder la
      // rangée — un débordement est une exception que le test attrape.
      await pumpReader(
        tester,
        size: const Size(360, 800),
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('LE MINISTÈRE OU LE SEIGNEUR'), findsOneWidget,
          reason: 'le titre reste porté par la pastille, tronqué si besoin');
      expect(find.byTooltip('Sommaire du chapitre'), findsOneWidget);
      expect(find.byTooltip('Chapitre suivant'), findsOneWidget);
    });

    testWidgets('le double chevron déplie les titres du chapitre courant',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      expect(find.byTooltip('Aller au verset'), findsNothing,
          reason: 'un ouvrage n\'a pas de numérotation de verset');
      expect(find.byTooltip('Sommaire du chapitre'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workChapterPicker')), findsOneWidget);
      expect(find.text('Sommaire du chapitre'), findsOneWidget,
          reason: 'même tête que les autres feuilles du lecteur');
      // Le titre du chapitre, puis ses sections, dans l'ordre du livre. Le
      // corps du texte, derrière la feuille, répète les mêmes intitulés :
      // on cherche dans la feuille, pas partout.
      final sheet = find.byKey(const Key('workChapterPicker'));
      for (var i = 0; i < 3; i++) {
        expect(
          find.descendant(
            of: sheet,
            matching: find.byKey(ValueKey('work-section-$i')),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: sheet,
          matching: find.text("I. D'ABORD L'ADORATION"),
        ),
        findsOneWidget,
        reason: 'la feuille nomme les sections, pas les chapitres',
      );

      await tester.tap(find.byKey(const ValueKey('work-section-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('workChapterPicker')), findsNothing,
          reason: 'la feuille se referme, la lecture reste sur le chapitre');
      expect(opened, isEmpty,
          reason: 'on ne change pas de chapitre : on va à une section');
    });

    testWidgets('une section y fait défiler jusqu\'à son bloc',
        (tester) async {
      await pumpReader(
        tester,
        size: const Size(390, 800),
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      final scroller = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final before = scroller.position.pixels;
      expect(before, 0, reason: 'le chapitre s\'ouvre en haut');

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
      await tester.pumpAndSettle();
      // « II. AIMER LE SEIGNEUR » ouvre la deuxième moitié du chapitre —
      // cherché dans la feuille, le corps du texte répète le même intitulé.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('workChapterPicker')),
          matching: find.text('II. AIMER LE SEIGNEUR'),
        ),
      );
      await settleDebounce(tester);
      await tester.pumpAndSettle();

      expect(scroller.position.pixels, greaterThan(before),
          reason: 'la section est plus bas que là où l\'on était');
    });

    testWidgets('un titre du chapitre ramène en haut', (tester) async {
      await pumpReader(
        tester,
        size: const Size(390, 800),
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('work-section-0')));
      await tester.pumpAndSettle();

      final scroller = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      expect(scroller.position.pixels, 0,
          reason: 'la ligne du titre du chapitre est un retour en haut, '
              'pas un bloc que l\'onglet lirait pour une position');
    });

    testWidgets('une section sans bloc ne fait pas semblant',
        (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
      await tester.pumpAndSettle();

      // Le sommaire annonce « III. FAIRE LA VOLONTÉ DU SEIGNEUR » ; ce titre
      // n'existe pas dans le corps du chapitre tel que l'extracteur l'a
      // découpé.
      final row = tester.widget<InkWell>(
        find.descendant(
          of: find.byKey(const Key('workChapterPicker')),
          matching: find.byKey(const ValueKey('work-section-3')),
        ),
      );
      expect(row.onTap, isNull,
          reason: 'une ligne qui ne mène nulle part ne doit pas se faire '
              'passer pour un lien');
    });

    testWidgets('le double chevron est inerte sur le sommaire', (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.keyboard_double_arrow_down),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull,
          reason: 'cette page n\'a pas de chapitre courant : il n\'y a rien '
              'à déplier, et le sommaire du livre est déjà à l\'écran');

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('workChapterPicker')), findsNothing);
    });

    // ---- Le bouton « Continuer » en pied de chapitre ----

    testWidgets('le pied « Continuer » mène au chapitre suivant',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      expect(find.text('Fin du chapitre'), findsOneWidget);
      expect(
        find.text('Continuer — CHAPITRE 1 : LE SERVICE DU SEIGNEUR'),
        findsOneWidget,
        reason: 'le titre du chapitre suivant dit où l\'on va',
      );

      await tester.tap(find.text('Continuer — CHAPITRE 1 : LE SERVICE DU SEIGNEUR'));
      await tester.pumpAndSettle();

      expect(opened, [2]);
    });

    testWidgets('le dernier chapitre ne propose pas de continuer',
        (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.textContaining('Continuer'), findsNothing);
      expect(find.text('Fin du chapitre'), findsNothing,
          reason: 'un bouton qui ne mène nulle part n\'a rien à faire en pied '
              'de livre');
    });

    testWidgets('le sommaire n\'a pas de pied non plus', (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.textContaining('Continuer'), findsNothing);
      expect(find.text('Fin du chapitre'), findsNothing);
    });

    testWidgets('en immersion le pied cède la place au texte, comme dans la '
        'Bible', (tester) async {
      final previous = AppPreferences.immersionNotifier.value;
      AppPreferences.immersionNotifier.value = true;
      addTearDown(() => AppPreferences.immersionNotifier.value = previous);

      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.textContaining('Continuer'), findsNothing,
          reason: 'l\'immersion efface toutes les commandes, et le pied en '
              'est une — c\'est la règle de ChapterReader');
      expect(find.byTooltip('Chapitre suivant'), findsNothing,
          reason: 'la barre a disparu avec');
      expect(find.text('INTRODUCTION'), findsOneWidget,
          reason: 'seul le texte reste');
    });

    testWidgets('une note de bas de page se lit dans le texte', (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      // Disposition inline : la note suit son mot, dans le même paragraphe,
      // sans geste supplémentaire.
      expect(
        find.textContaining('Première note', findRichText: true),
        findsOneWidget,
        reason: 'les notes d\'un ouvrage sont des notes de bas de page : '
            'les cacher couperait le texte de son appareil',
      );
    });

    testWidgets('une référence citée est tapable et ouvre la Bible',
        (tester) async {
      final opened = <(int, int, int)>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
          onOpenVerse: (b, c, v) => opened.add((b, c, v)),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('work-reference')));
      await tester.pumpAndSettle();

      expect(opened, [(1, 1, 1)],
          reason: 'Genèse 1:1 — index BYM 1-based, comme partout dans '
              'l\'application (catalogEntry(bymIndex) = bookCatalog[bymIndex '
              '- 1])');
    });

    testWidgets('sans la coquille, une référence reste du texte souligné',
        (tester) async {
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
        ),
      );

      expect(find.byKey(const ValueKey('work-reference')), findsNothing,
          reason: 'pas de bouton mort : le texte est rendu sans geste');
      expect(find.text('Genèse 1:1'), findsOneWidget);
    });

    testWidgets('l\'ouvrage effacé propose de retourner à la Bibliothèque',
        (tester) async {
      var openedLibrary = 0;
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(null),
          onOpenChapter: (_) {},
          onOpenLibrary: () => openedLibrary++,
        ),
      );

      expect(find.text('Ce livre n\'est plus sur l\'appareil'), findsOneWidget);

      await tester.tap(find.text('Bibliothèque'));
      await tester.pumpAndSettle();
      expect(openedLibrary, 1);
    });

    testWidgets('un chapitre hors du livre retombe sur le sommaire',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 9,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      expect(find.text('Chapitre introuvable'), findsOneWidget);
      expect(find.textContaining('2 chapitres'), findsOneWidget,
          reason: 'le lecteur dit d\'où il part, il ne se tait pas');

      await tester.tap(find.text('Sommaire'));
      await tester.pumpAndSettle();
      expect(opened, [0]);
    });

    testWidgets('les flèches feuillettent, la pastille revient au sommaire',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 1,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      await tester.tap(find.byTooltip('Chapitre suivant'));
      await tester.pumpAndSettle();
      expect(opened, [2]);

      await tester.tap(find.byTooltip('Chapitre précédent'));
      await tester.pumpAndSettle();
      expect(opened, [2, 0], reason: 'le précédent du premier est le sommaire');

      await tester.tap(find.text('LE MINISTÈRE OU LE SEIGNEUR'));
      await tester.pumpAndSettle();
      expect(opened, [2, 0, 0], reason: 'la pastille est le sommaire');
    });

    testWidgets('sur le sommaire, la pastille ne rouvre pas ce qui est à '
        'l\'écran', (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 0,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      // Le titre est à la fois dans la pastille et en tête du sommaire :
      // c'est la pastille qu'on interroge, pas la page.
      await tester.tap(
        find.descendant(
          of: find.byType(ReaderActionsBar),
          matching: find.text('LE MINISTÈRE OU LE SEIGNEUR'),
        ),
      );
      await tester.pumpAndSettle();

      expect(opened, isEmpty);
      expect(find.byTooltip('Chapitre précédent'), findsOneWidget);
    });

    testWidgets('la flèche suivante s\'arrête au dernier chapitre',
        (tester) async {
      final opened = <int>[];
      await pumpReader(
        tester,
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: opened.add,
        ),
      );

      await tester.tap(find.byTooltip('Chapitre suivant'));
      await tester.pumpAndSettle();

      expect(opened, isEmpty,
          reason: 'le dernier chapitre n\'a pas de suivant : la flèche '
              's\'arrête, elle ne mène nulle part');
    });

    testWidgets('une position restaurée est rapportée à l\'onglet',
        (tester) async {
      final reported = <int>[];
      await pumpReader(
        tester,
        size: const Size(390, 800),
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          initialBlock: 6,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
          onBlockChanged: reported.add,
        ),
      );

      // La reprise saute, puis le débounce (400 ms) finit son temps et le
      // rapport part hors frame.
      await settleDebounce(tester);

      expect(reported, contains(6),
          reason: 'le lecteur reprend au bloc qu\'il avait quitté');
    });

    testWidgets('le défilement déplace la position rapportée', (tester) async {
      final reported = <int>[];
      await pumpReader(
        tester,
        size: const Size(390, 800),
        reader: WorkReader(
          code: 'MINISTERE',
          chapter: 2,
          store: FakeWorkStore(fakeWork()),
          onOpenChapter: (_) {},
          onBlockChanged: reported.add,
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await settleDebounce(tester);

      expect(reported, isNotEmpty);
      expect(reported.last, greaterThan(1),
          reason: 'descendre dans le chapitre remonte l\'index de bloc');
    });
  });
}
