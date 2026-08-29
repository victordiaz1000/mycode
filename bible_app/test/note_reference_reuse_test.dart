import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/data/lsgs_repository.dart';
import 'package:bible_app/data/note_reference_linker.dart';
import 'package:bible_app/data/tab_manager.dart';
import 'package:bible_app/screens/reader_screen.dart';
import 'package:bible_app/widgets/chapter_reader.dart';

import 'support/fake_bible_bundle.dart';
import 'support/fake_lsgs_bundle.dart';

/// Le signalement : la note d'Exode 3:6 porte « … Ac. 7:32. » ; le tap du lien
/// conduit à Actes 7 **35** quand un onglet était déjà posé sur Actes 7 (lu
/// jusqu'au v. 35 lors d'un passage précédent).
///
/// Deux maillons vérifiés ici :
/// 1. le parser produit bien Actes 7:32 depuis le texte réel de la note ;
/// 2. réouvrir un chapitre DÉJÀ ouvert dans un onglet doit déplacer la position
///    de cet onglet au verset demandé — l'ancienne branche « réutilisation » de
///    `TabManager.openReading` ignorait le verset, laissant l'onglet à sa
///    vieille position (35), que la restauration rejouait.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 8, verses: 40));
    LsgsRepository.useBundle(FakeLsgsBundle());
  });

  tearDown(() {
    LocalRepository.useRootBundle();
    LsgsRepository.useRootBundle();
  });

  test('the Exode 3:6 note parses to Acts 7:32, not 35', () {
    // Texte exact de la note (02-Exode.json, 3:6, mot « Yaacov »).
    const note = 'Mt. 22:32 ; Mc. 12:26 ; Lu. 20:37 ; Ac. 7:32.';
    final refs = findNoteReferences(note);
    final acts = refs.last.reference;
    expect(acts.bookIndex, 44);
    expect(acts.chapter, 7);
    expect(acts.verse, 32);
  });

  testWidgets(
    'a note reference onto an already-open chapter moves that tab to the verse',
    (tester) async {
      final m = TabManager();
      // Un onglet sur Actes 7, lu jusqu'au verset 35.
      m.openReading(44, 7);
      m.updateTabVerse(m.active!.id, 35);
      // Puis l'onglet actif passe sur Exode 3 — Actes 7 reste ouvert derrière.
      m.openReading(2, 3);

      final jump = ValueNotifier<VerseTarget?>(null);
      await tester.pumpWidget(MaterialApp(
        home: ReaderScreen(initialManager: m, jumpToVerse: jump),
      ));
      await tester.pumpAndSettle();

      // Le tap du lien « Ac. 7:32 » : ce que fait HomeShell._openReading
      // désormais — le verset demandé suit JUSQU'AU MANAGER (il ne doit plus
      // se perdre entre le shell et l'onglet).
      m.openReading(44, 7, verse: 32);
      jump.value = const VerseTarget(bookIndex: 44, chapter: 7, verse: 32);

      // La position enregistrée est celle qui a été DEMANDÉE : un onglet
      // réutilisé ne garde pas sa vieille position (sinon elle ressuscite au
      // prochain montage/restauration de l'onglet).
      expect(m.active!.bookIndex, 44);
      expect(m.active!.chapter, 7);
      expect(m.active!.verse, 32,
          reason: 'réutiliser un onglet doit y porter le verset demandé');

      // Le saut visuel reste vert : le lecteur rejoint le verset.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ac. 7:32.'), findsOneWidget);
    },
  );

  testWidgets(
    'fresh tab: the reader settles on the requested verse, not past it',
    (tester) async {
      // Aucun onglet sur Actes : le tap crée un onglet à neuf. C'est le cas
      // où main._openReading perd le `verse:` (il ne le passe pas au
      // manager) et où seul le mécanisme de saut place l'écran.
      final m = TabManager();
      m.openReading(2, 3); // onglet actif : Exode 3.

      final jump = ValueNotifier<VerseTarget?>(null);
      await tester.pumpWidget(MaterialApp(
        home: ReaderScreen(initialManager: m, jumpToVerse: jump),
      ));
      await tester.pumpAndSettle();

      m.openReading(44, 7);
      jump.value = const VerseTarget(bookIndex: 44, chapter: 7, verse: 32);

      // Le saut attend la liste, converge, puis place précisément : pomper
      // largement pour laisser toute la chaîne asynchrone finir.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.pumpAndSettle();

      expect(m.active!.bookIndex, 44);
      expect(m.active!.chapter, 7);

      // Où est posé le verset 32 à l'écran ? Sa tuile doit être DANS le
      // viewport — pas seulement construite dans le cache extent.
      const viewHeight = 600.0;
      final rect = tester.getRect(find.text('Verset de test Ac. 7:32.'));
      expect(rect.top, greaterThan(-60),
          reason: 'le verset demandé doit être atteint, pas survolé');
      expect(rect.top, lessThan(viewHeight),
          reason: 'le verset demandé doit être visible');

      // Et la position enregistrée colle à ce qui est affiché : si elle
      // dérive plusieurs versets plus loin, l'écran remontera là-au
      // prochain montage de l'onglet.
      expect(m.active!.verse, inInclusiveRange(28, 35),
          reason: 'position finale ${m.active!.verse} : dérive du rapporteur');
    },
  );
}
