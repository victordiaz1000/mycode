import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/data/theme_catalog.dart';
import 'package:bible_app/models/ati.dart';
import 'package:bible_app/models/chapter.dart';
import 'package:bible_app/models/verse.dart';
import 'package:bible_app/screens/settings_screen.dart';
import 'package:bible_app/widgets/ati_interlinear.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/fiche_text_settings.dart';
import 'package:bible_app/widgets/verse_tile.dart';

/// « Texte continu » sur l'ATI : l'option se désactive, le lecteur refuse
/// d'écrire une préférence qu'il ignorera, et le rendu — dernier rempart —
/// garde ses colonnes même si « Continu » arrive par ailleurs.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('le rendu', () {
    testWidgets(
      'un chapitre ATI garde ses colonnes, quelle que soit la disposition '
      'demandée',
      (tester) async {
        const mots = [
          AtiWord(
            translit: 'bə·rê·šîṯ',
            hebrew: 'רֵאשִׁית',
            gloss: 'En un commencement',
          ),
          AtiWord(translit: 'ĕ·lō·hîm', hebrew: 'אֱלֹהִים', gloss: 'Dieu'),
        ];
        const verset = Verse(
          verse: '1:1',
          text: 'En un commencement Dieu',
          textWithNotes: 'En un commencement Dieu',
          mots: mots,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: BibleThemeScope(
              child: Scaffold(
                body: ChapterVerseList(
                  chapter: const Chapter(chapter: 1, verses: [verset]),
                  showNotes: false,
                  // La disposition que la préférence dirait, avant coercion.
                  layout: ReadingLayout.paragraph,
                  theme: bibleThemes.first,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byType(AtiInterlinear),
          findsOneWidget,
          reason: 'une colonne de sept champs ne coule pas : elle reste debout',
        );
        final rendu = tester
            .widgetList<RichText>(find.byType(RichText))
            .map((rich) => rich.text.toPlainText())
            .join('\n');
        expect(
          rendu,
          isNot(contains('En un commencement Dieu')),
          reason:
              'la ligne jointe est une glose de recherche, pas un texte de '
              'lecture : chaque glose reste dans sa cellule',
        );
      },
    );

    testWidgets('une version sans mots garde son texte continu', (
      tester,
    ) async {
      const verset = Verse(
        verse: '1:1',
        text: 'Au commencement Dieu créa les cieux.',
        textWithNotes: 'Au commencement Dieu créa les cieux.',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BibleThemeScope(
            child: Scaffold(
              body: ChapterVerseList(
                chapter: const Chapter(chapter: 1, verses: [verset]),
                showNotes: false,
                layout: ReadingLayout.paragraph,
                theme: bibleThemes.first,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AtiInterlinear), findsNothing);
      final rendu = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((rich) => rich.text.toPlainText())
          .join('\n');
      expect(rendu, contains('Au commencement Dieu créa les cieux.'));
    });
  });

  group('la carte de disposition', () {
    Future<void> pumpCarte(
      WidgetTester tester, {
      required bool dispo,
      ReadingLayout layout = ReadingLayout.tiles,
      ValueChanged<ReadingLayout>? onChanged,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DisplayLayoutSection(
                layout: layout,
                paragraphAvailable: dispo,
                onChanged:
                    onChanged ??
                    (_) {
                      /* rien : la carte ne fait qu'annoncer le choix */
                    },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
      'sans texte continu, « Continu » se lit délavé et ne se prend pas',
      (tester) async {
        ReadingLayout? choisi;
        await pumpCarte(
          tester,
          dispo: false,
          layout: ReadingLayout.paragraph,
          onChanged: (value) => choisi = value,
        );

        expect(find.text('Versets séparés'), findsOneWidget);
        expect(
          tester
              .widgetList<Opacity>(
                find.ancestor(
                  of: find.text('Texte continu'),
                  matching: find.byType(Opacity),
                ),
              )
              .map((opacity) => opacity.opacity),
          contains(.45),
          reason: 'on voit que l\'option existe et ce qui la bloque',
        );

        await tester.tap(find.text('Texte continu'));
        await tester.pumpAndSettle();

        expect(
          choisi,
          isNull,
          reason: 'le tap ne passe pas sur une option qui ne s\'applique pas',
        );
        expect(
          find.text('Versets séparés'),
          findsOneWidget,
          reason: 'l\'écran annonce ce qu\'il montre, pas la préférence',
        );
      },
    );

    testWidgets('la version qui sait couler garde ses deux segments', (
      tester,
    ) async {
      ReadingLayout? choisi;
      await pumpCarte(
        tester,
        dispo: true,
        layout: ReadingLayout.tiles,
        onChanged: (value) => choisi = value,
      );

      await tester.tap(find.text('Texte continu'));
      await tester.pumpAndSettle();

      expect(choisi, ReadingLayout.paragraph);
    });
  });

  group('les réglages', () {
    /// Ouvre les réglages sur la version donnée, large et haut — le premier
    /// écran ne bâtit que ce que le viewport tient.
    Future<void> pumpReglages(WidgetTester tester, String code) async {
      SharedPreferences.setMockInitialValues({'reading.versionCode': code});
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Disposition du texte'), 120);
      await tester.pumpAndSettle();
    }

    testWidgets('sur l\'ATI, « Continu » est bloqué et la préférence intacte', (
      tester,
    ) async {
      await pumpReglages(tester, 'ATI');

      expect(find.text('Continu'), findsOneWidget);
      expect(
        tester
            .widgetList<Opacity>(
              find.ancestor(
                of: find.text('Continu'),
                matching: find.byType(Opacity),
              ),
            )
            .map((opacity) => opacity.opacity),
        contains(.45),
        reason: 'le segment se lit délavé plutôt que disparu',
      );
      expect(
        find.text('Versets séparés'),
        findsOneWidget,
        reason: 'le sous-titre dit ce qui est affiché',
      );

      await tester.tap(find.text('Continu'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('reading.layout'),
        isNull,
        reason:
            'la préférence n\'est jamais réécrite : elle attend une '
            'version qui sache s\'en servir',
      );
      expect(find.text('Versets séparés'), findsOneWidget);
    });

    testWidgets('sur une version ordinaire, « Continu » reste à portée', (
      tester,
    ) async {
      await pumpReglages(tester, 'LSGS');

      await tester.tap(find.text('Continu'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('reading.layout'), 'paragraph');
    });
  });
}
