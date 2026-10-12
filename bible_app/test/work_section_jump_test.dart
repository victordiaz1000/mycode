import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/work_store.dart';
import 'package:bible_app/widgets/work_reader.dart';

/// Le double chevron ouvre les sections du chapitre : un tap doit **amener au
/// bloc visé**, dans les deux ouvrages réels.
///
/// Ce test mesure sur un téléphone (390 × 844). Sur la hauteur énorme des
/// tests de contenu, tout tient sans défiler et le saut n'a rien à faire — le
/// défaut ne s'y voit pas.
///
/// Deux pièges de mesure, tous deux déjà tombés :
///
///  - la feuille se dimensionne sur son contenu mais se borne à 0,6 de
///    l'écran : au-delà, les lignes ne sont pas construites et `find` ne les
///    voit pas. Il faut les faire défiler jusqu'à elles ;
///  - la ligne du sommaire et le titre du corps ne portent pas toujours le
///    même texte. C'est le corps qui fait foi : on cherche le **bloc** que la
///    section désigne, pas un widget égal à la ligne du sommaire.

class _FakeStore extends WorkStore {
  _FakeStore(this.payload);

  final Map<String, dynamic> payload;

  @override
  Future<Map<String, dynamic>?> load(String code) async => payload;
}

String _norm(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

Map<String, dynamic> _load(String name) =>
    jsonDecode(File('../appCodebar/$name.json').readAsStringSync())
        as Map<String, dynamic>;

/// Le texte que ce widget affiche réellement, `Text` comme `Text.rich`.
///
/// Les paragraphes passent par `NoteAwareVerseText`, qui compose un
/// `Text.rich` : leur `data` est nul, et chercher un `Text` simple ne les
/// verrait jamais.
String _shown(Widget widget) {
  if (widget is Text) return widget.data ?? widget.textSpan?.toPlainText() ?? '';
  if (widget is RichText) return widget.text.toPlainText();
  return '';
}

/// Réplique de `_WorkReaderState._blockForSection`, sur les blocs d'un
/// chapitre : l'index 1-basis du bloc visé, ou null si le sommaire annonce
/// une section que le corps ne porte pas.
///
/// Les trois passes sont dans le même ordre que dans l'app : égalité stricte,
/// égalité à séparateur près, inclusion — avec les blocs-titres prioritaires
/// sur les paragraphes qui les citent. Un écart entre les deux versions se
/// verrait immédiatement : le test chercherait un bloc que l'app n'a pas
/// sauté.
int? _targetBlock(List<dynamic> blocks, String title) {
  final wanted = _norm(title);
  if (wanted.isEmpty) return null;
  String kind(int i) => (blocks[i] as Map<String, dynamic>)['type'] as String;
  bool isHeading(int i) =>
      const {'h1', 'h2', 'h3', 'h4'}.contains(kind(i));
  String text(int i) =>
      _norm((blocks[i] as Map<String, dynamic>)['text'] as String);

  for (var i = 0; i < blocks.length; i++) {
    if (text(i) == wanted) return i + 1;
  }

  final loose = wanted.replaceAll(RegExp(r'\s+-\s+'), ' ');
  var anywhere = -1;
  for (var i = 0; i < blocks.length; i++) {
    if (text(i).replaceAll(RegExp(r'\s+-\s+'), ' ') != loose) continue;
    if (isHeading(i)) return i + 1;
    if (anywhere < 0) anywhere = i;
  }
  if (anywhere >= 0) return anywhere + 1;

  var inHeadings = -1;
  anywhere = -1;
  for (var i = 0; i < blocks.length; i++) {
    final t = text(i);
    if (t.length < 8) continue;
    if (!(t.contains(wanted) || wanted.contains(t))) continue;
    if (isHeading(i) && inHeadings < 0) inHeadings = i;
    if (anywhere < 0) anywhere = i;
  }
  final found = inHeadings >= 0 ? inHeadings : anywhere;
  return found < 0 ? null : found + 1;
}

/// La feuille est bornée : une ligne du bas n'existe pas encore dans
/// l'arbre. On la fait défiler jusqu'à elle.
Future<void> _revealRow(
  WidgetTester tester,
  Finder picker,
  Finder row,
) async {
  final sheet = find.descendant(of: picker, matching: find.byType(Scrollable));
  for (var attempt = 0; attempt < 40 && row.evaluate().isEmpty; attempt++) {
    await tester.drag(sheet, const Offset(0, -280));
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final name in ['ministere', 'animalite']) {
    final json = _load(name);
    final toc = (json['toc'] as List).cast<Map<String, dynamic>>();
    final chapters = (json['chapters'] as List).cast<Map<String, dynamic>>();
    final chapterCount = chapters.length;

    for (var chapter = 1; chapter <= chapterCount; chapter++) {
      // Les clés `work-section-N` sont numérotées dans la feuille, donc
      // localement au chapitre — pas par leur rang dans le sommaire.
      final rows = <({int index, String title, int level})>[
        for (var local = 0, i = 0; i < toc.length; i++)
          if (toc[i]['chapter'] == chapter)
            (
              index: local++,
              title: toc[i]['title'] as String,
              level: toc[i]['level'] as int,
            )
      ];
      if (rows.isEmpty) continue;

      final blocks = (chapters[chapter - 1]['blocks'] as List).cast<dynamic>();
      final chapterTitle = chapters[chapter - 1]['title'] as String;

      testWidgets('$name ch$chapter : chaque section y amène', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WorkReader(
                key: ValueKey('reader-$name-$chapter'),
                code: name.toUpperCase(),
                chapter: chapter,
                store: _FakeStore(json),
                onOpenChapter: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final faults = <String>[];
        final screen = Offset.zero & const Size(390, 844);

        Future<void> openSheet() async {
          await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down));
          await tester.pumpAndSettle();
        }

        await openSheet();
        final picker = find.byKey(const Key('workChapterPicker'));
        if (picker.evaluate().isEmpty) {
          expect(faults, isEmpty, reason: 'la feuille de sections ne s’ouvre pas');
          return;
        }

        /// Les rectangles où l'écran montre ce texte, à son premier tiers de
        /// ligne près. Vide si rien ne le porte.
        List<Rect> rectsShowing(String text) {
          final rects = <Rect>[];
          final wanted = _norm(text);
          if (wanted.isEmpty) return rects;
          final sample = wanted.length > 40 ? wanted.substring(0, 40) : wanted;
          for (final element in find.byWidgetPredicate(
            (w) => _shown(w).isNotEmpty,
          ).evaluate()) {
            if (!_norm(_shown(element.widget)).contains(sample)) continue;
            rects.add(tester.getRect(find.byWidget(element.widget)));
          }
          return rects;
        }

        Future<void> tapRow(Finder rowFinder) async {
          await tester.ensureVisible(rowFinder);
          await tester.pump();
          await tester.tap(rowFinder);
          // `_restore` boucle : saut, fin de frame, jusqu'à ce que la tuile
          // soit bâtie, puis `ensureVisible` anime 250 ms.
          await tester.pump();
          for (var i = 0; i < 25; i++) {
            await tester.pump(const Duration(milliseconds: 40));
          }
          await tester.pumpAndSettle();
        }

        for (final row in rows) {
          final rowFinder = find.byKey(ValueKey('work-section-${row.index}'));
          await _revealRow(tester, picker, rowFinder);

          if (rowFinder.evaluate().isEmpty) {
            faults.add('ligne jamais construite : ${row.title}');
            await tester.tap(picker);
            await tester.pumpAndSettle();
            continue;
          }

          // Le titre du chapitre n'est pas une section : l'app le traite à
          // part (`level0 ? 0 : _blockForSection`) et remonte en haut de page,
          // sans lui chercher de bloc de corps. Lui en réclamer un faisait
          // échouer les 22 chapitres **sur leur propre titre**, alors que le
          // saut était juste. On vérifie donc ce que la ligne promet : le
          // titre du chapitre est de retour à l'écran.
          if (row.level == 0) {
            await tapRow(rowFinder);
            if (!rectsShowing(chapterTitle).any((r) => r.overlaps(screen))) {
              faults.add('niveau 0 ne ramène pas au titre : ${row.title}');
            }
            if (row != rows.last) await openSheet();
            continue;
          }

          final target = _targetBlock(blocks, row.title);
          final inkwell = tester.widget<InkWell>(rowFinder);
          if (target == null || inkwell.onTap == null) {
            faults.add(target == null
                ? 'section sans cible dans le corps : ${row.title}'
                : 'ligne INERTE (tap sans effet) : ${row.title}');
            await tester.tap(rowFinder);
            await tester.pumpAndSettle();
            await openSheet();
            continue;
          }

          final before = tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .pixels;

          await tapRow(rowFinder);

          final after = tester
              .state<ScrollableState>(find.byType(Scrollable).last)
              .position
              .pixels;

          // Ce qui fait foi est le bloc que la section désigne : c'est son
          // texte que l'écran doit montrer.
          final rects = rectsShowing(blocks[target - 1]['text'] as String);
          if (!rects.any((r) => r.overlaps(screen))) {
            faults.add('PAS AU BON ENDROIT : ${row.title} '
                '[${before.toStringAsFixed(0)} \u2192 '
                '${after.toStringAsFixed(0)}] '
                '${rects.isEmpty ? '(bloc non rendu)' : 'rect=$rects'}');
          }

          if (row != rows.last) await openSheet();
        }

        expect(faults, isEmpty, reason: '${faults.length} défaut(s) — '
            '${faults.take(6).join(' ; ')}');
      });
    }
  }
}
