import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/main.dart';
import 'package:bible_app/utils/breakpoints.dart';

import 'support/fake_bible_bundle.dart';

/// Les deux décisions que le shell prend sur la taille de l'écran, et qu'il
/// ne faut **pas** reconfondre — c'était le bug d'origine.
///
///  * le **châssis** (`chassisFor`) : rail ou barre du bas, décidé sur la
///    **largeur réelle**, comme depuis toujours. Un écran large mérite un
///    rail, téléphone couché compris.
///  * la **classe d'appareil** (`isTablet` et ses dérivés) : grilles,
///    master/detail, panneau d'étude épinglé, plafond de contenu — décidés sur
///    le **côté court**, donc stables en rotation.
///
/// Avant, une seule comparaison de largeur gouvernait les deux : un iPhone 14
/// en paysage mesure 844 px, au-dessus du palier `expanded` de 840, et
/// recevait donc l'accueil en grille deux colonnes et le master/detail comme
/// un petit desktop. Le rail, lui, n'était pas le problème.
///
/// Pourquoi ce fichier existe à côté de `responsive_overflow_test.dart` : cet
/// audit-là ne pouvait rien voir de tout cela. Un `NavigationRail` est
/// `scrollable: true` et fait défiler ses destinations au lieu de déborder, et
/// une grille à deux colonnes ne déborde pas non plus — zéro `RenderFlex
/// overflow`, test vert, mise en page inadaptée.
void main() {
  group('AppBreakpoints — la règle, sans interface', () {
    test('un téléphone reste un téléphone dans les deux orientations', () {
      for (final phone in const [
        Size(390, 844), // iPhone 14
        Size(844, 390), // le même, couché : 844 px de large
        Size(430, 932), // iPhone 14 Pro Max
        Size(932, 430), // couché
        Size(412, 915), // Pixel 7
        Size(915, 412), // couché
        Size(360, 640),
        Size(800, 360),
      ]) {
        expect(AppBreakpoints.isTablet(phone), isFalse, reason: '$phone');
        // Le point du correctif : sans la garde de classe d'appareil, 844 et
        // 932 franchissaient `expanded` et ouvraient grilles et master/detail.
        expect(AppBreakpoints.isExpanded(phone), isFalse, reason: '$phone');
        expect(AppBreakpoints.isDesktop(phone), isFalse, reason: '$phone');
        expect(AppBreakpoints.contentMaxWidth(phone), isNull, reason: '$phone');
      }
    });

    test('le châssis, lui, ne regarde que la largeur', () {
      // Debout, le téléphone est trop étroit : barre du bas.
      expect(
        AppBreakpoints.chassisFor(const Size(390, 844)),
        AppChassis.bottomBar,
      );
      expect(
        AppBreakpoints.chassisFor(const Size(360, 640)),
        AppChassis.bottomBar,
      );
      // Couché, il est large : il garde son rail, comme avant le correctif.
      // C'est voulu — seule la mise en page du contenu avait à changer.
      expect(
        AppBreakpoints.chassisFor(const Size(800, 360)),
        AppChassis.rail,
      );
      expect(
        AppBreakpoints.chassisFor(const Size(844, 390)),
        AppChassis.extendedRail,
      );
      expect(
        AppBreakpoints.chassisFor(const Size(932, 430)),
        AppChassis.extendedRail,
      );
      // Et une tablette a son rail dans les deux sens.
      expect(AppBreakpoints.chassisFor(const Size(834, 1112)), AppChassis.rail);
      expect(
        AppBreakpoints.chassisFor(const Size(1112, 834)),
        AppChassis.extendedRail,
      );
    });

    test('une tablette garde son rail debout comme couchée', () {
      const portrait = Size(834, 1112); // iPad Air
      const landscape = Size(1112, 834);
      expect(AppBreakpoints.isTablet(portrait), isTrue);
      expect(AppBreakpoints.isTablet(landscape), isTrue);
      // Debout, l'iPad Air rate `expanded` de 6 px : colonne unique centrée,
      // plafonnée à 720 — choix assumé, un split à 834 px serait à l'étroit.
      expect(AppBreakpoints.isExpanded(portrait), isFalse);
      expect(AppBreakpoints.contentMaxWidth(portrait), AppBreakpoints.maxNarrow);
      // Couché, il passe en master/detail.
      expect(AppBreakpoints.isExpanded(landscape), isTrue);
      expect(AppBreakpoints.contentMaxWidth(landscape), AppBreakpoints.maxWide);
    });

    test('les paliers desktop et XL', () {
      // 1040 et non 1200 : une fenêtre sur la moitié d'un 13 pouces a la
      // place du panneau d'étude.
      expect(AppBreakpoints.isDesktop(const Size(1100, 800)), isTrue);
      expect(AppBreakpoints.isDesktop(const Size(1000, 800)), isFalse);
      expect(AppBreakpoints.isXl(const Size(1600, 900)), isTrue);
      expect(AppBreakpoints.isXl(const Size(1599, 900)), isFalse);
      // Un téléphone très large en paysage n'est jamais desktop.
      expect(AppBreakpoints.isDesktop(const Size(1200, 420)), isFalse);
    });

    test('le panneau latéral suit la fenêtre, borné aux deux bouts', () {
      expect(AppBreakpoints.sidePanelWidth(1040), 320); // plancher
      expect(AppBreakpoints.sidePanelWidth(1400), 420); // 30 % = 420
      expect(AppBreakpoints.sidePanelWidth(1920), 420); // plafond
    });
  });

  group('le shell choisit son châssis', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LocalRepository.useBundle(FakeBibleBundle(chapters: 2, verses: 4));
    });
    tearDown(LocalRepository.useRootBundle);

    /// `pumpAndSettle` ne convient pas : le shell porte des animations qui ne
    /// se terminent pas toujours dans le temps du test. Même boucle que
    /// `responsive_overflow_test`.
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    /// Les exceptions de peinture appartiennent au balayage anti-débordement ;
    /// ici on ne juge que le châssis, donc on vide la file pour qu'une
    /// exception étrangère ne fasse pas échouer ce test sur un autre sujet.
    void drain(WidgetTester tester) {
      for (var i = 0; i < 40; i++) {
        if (tester.takeException() == null) break;
      }
    }

    Future<void> pumpAt(WidgetTester tester, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const BymApp());
      await settle(tester);
    }

    for (final device in const <String, Size>{
      '390x844 iphone14 debout': Size(390, 844),
      '360x640 budget debout': Size(360, 640),
    }.entries) {
      testWidgets('${device.key} → barre du bas', (tester) async {
        await pumpAt(tester, device.value);
        expect(find.byType(NavigationRail), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        drain(tester);
      });
    }

    for (final device in const <String, (Size, bool)>{
      '844x390 iphone14 couché': (Size(844, 390), true),
      '932x430 maxpro couché': (Size(932, 430), true),
      '800x360 telephone couché': (Size(800, 360), false),
    }.entries) {
      final (size, extended) = device.value;
      testWidgets('${device.key} → garde son rail', (tester) async {
        await pumpAt(tester, size);
        final rail = find.byType(NavigationRail);
        expect(
          rail,
          findsOneWidget,
          reason:
              'le rail d\'un téléphone couché n\'a jamais été le problème : '
              'seule la mise en page du contenu avait à changer',
        );
        expect(find.byType(NavigationBar), findsNothing);
        expect(tester.widget<NavigationRail>(rail).extended, extended);
        drain(tester);
      });
    }

    for (final device in const <String, (Size, bool)>{
      '600x1024 tablette7': (Size(600, 1024), false),
      '834x1112 ipadair debout': (Size(834, 1112), false),
      '1112x834 ipadair couché': (Size(1112, 834), true),
      '1280x800 desktop': (Size(1280, 800), true),
      '1600x900 xl': (Size(1600, 900), true),
    }.entries) {
      final (size, extended) = device.value;
      testWidgets(
        '${device.key} → rail ${extended ? 'étendu' : 'compact'}',
        (tester) async {
          await pumpAt(tester, size);
          final rail = find.byType(NavigationRail);
          expect(rail, findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
          expect(
            tester.widget<NavigationRail>(rail).extended,
            extended,
            reason: 'les libellés du rail ne tiennent que si la largeur suit',
          );
          drain(tester);
        },
      );
    }
  });
}
