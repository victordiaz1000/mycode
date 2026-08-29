import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_app/data/local_repository.dart';
import 'package:bible_app/main.dart';

import 'support/fake_bible_bundle.dart';

/// Balayage anti-débordement de toute l'interface, sur un parc d'appareils.
///
/// Objet du test : aucun `RenderFlex` ne doit déborder, sur aucune taille
/// d'écran, à aucune taille de police système. En *release* un débordement ne
/// lève rien — il rogne silencieusement — donc seul un test le voit venir ; sur
/// l'appareil d'un testeur en debug, il s'affiche en bandes jaunes et noires.
///
/// Deux pièges ont coûté cher à écrire ce fichier, ne pas les réintroduire :
///
/// 1. Peindre le premier écran de chaque page ne suffit pas. Les sections de
///    l'Accueil vivent dans une `ListView` paresseuse : une section basse n'est
///    ni mise en page ni peinte avant d'entrer dans le viewport, donc son
///    débordement reste invisible. D'où [_paintWholeScroll].
/// 2. La page déjà sélectionnée porte l'icône *pleine* (`Icons.home`), pas
///    l'icône contour cherchée pour la taper. Sauter une destination dont
///    l'icône contour est absente laissait l'Accueil — la page la plus longue et
///    la plus riche — entièrement hors audit.
///
/// Vérifié en plantant un débordement volontaire bas dans l'Accueil : le test le
/// signale. Sans les deux points ci-dessus, il ne le voyait pas.
const _devices = <String, Size>{
  '320x568 mini': Size(320, 568),
  '360x640 budget': Size(360, 640),
  '360x800 android': Size(360, 800),
  '390x844 iphone14': Size(390, 844),
  '412x915 pixel7': Size(412, 915),
  '430x932 maxpro': Size(430, 932),
  '600x1024 tablette7': Size(600, 1024),
  '834x1112 ipadair': Size(834, 1112),
  '1024x768 tablette paysage': Size(1024, 768),
  '800x360 telephone paysage': Size(800, 360),
};

/// Icône *contour* de chaque destination du shell, celle de l'onglet inactif.
const _destinations = <String, IconData>{
  'Accueil': Icons.home_outlined,
  'Lecture': Icons.menu_book_outlined,
  'Recherche': Icons.search_outlined,
  'Bibliothèque': Icons.download_outlined,
  'Réglages': Icons.settings_outlined,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalRepository.useBundle(FakeBibleBundle(chapters: 3, verses: 12));
  });
  tearDown(LocalRepository.useRootBundle);

  /// 1.0 = police système par défaut. 2.0 = accessibilité poussée à fond : le
  /// `MediaQuery` de `main.dart` la borne à 1.18, et ce test garde cette borne
  /// honnête — c'est elle qui doit suffire à tenir la mise en page.
  for (final scale in const [1.0, 2.0]) {
    for (final device in _devices.entries) {
      testWidgets('aucun débordement — ${device.key} @x$scale', (tester) async {
        final overflows = <String>[];

        tester.view.physicalSize = device.value;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        /// Vide la file d'exceptions du binding. Un débordement y arrive à
        /// chaque peinture fautive, donc il faut la vider après chaque pump —
        /// sinon la première masque les suivantes.
        void collect(String where) {
          for (var i = 0; i < 40; i++) {
            final error = tester.takeException();
            if (error == null) break;
            overflows.add('$where :: ${error.toString().split('\n').first}');
          }
        }

        Future<void> settle() async {
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
        }

        /// Fait défiler chaque zone scrollable d'un bout à l'autre pour forcer
        /// la mise en page et la peinture de tout son contenu.
        ///
        /// Pilote `ScrollPosition` directement plutôt que `tester.drag` : un
        /// drag atterrit sur le widget au centre du finder (une bande
        /// horizontale interne, une carte qui avale le geste) et ne déplace
        /// parfois rien du tout, silencieusement.
        Future<void> paintWholeScroll(String where) async {
          for (var index = 0; index < 8; index++) {
            final scrollables = tester
                .stateList<ScrollableState>(find.byType(Scrollable))
                .toList();
            if (index >= scrollables.length) break;
            final position = scrollables[index].position;
            if (!position.hasContentDimensions) continue;
            final viewport = position.viewportDimension;
            if (viewport <= 0) continue;

            // `maxScrollExtent` d'une sliver paresseuse est une *estimation* qui
            // s'affine à mesure qu'on descend : la condition se réévalue à
            // chaque tour, le garde-fou borne les cas pathologiques.
            var guard = 0;
            while (position.pixels < position.maxScrollExtent && guard++ < 60) {
              position.jumpTo(
                (position.pixels + viewport * 0.8).clamp(
                  position.minScrollExtent,
                  position.maxScrollExtent,
                ),
              );
              await settle();
              collect('$where défilé à ${position.pixels.toStringAsFixed(0)}');
            }
          }
        }

        await tester.pumpWidget(const BymApp());
        await settle();
        collect('démarrage');

        for (final destination in _destinations.entries) {
          final tab = find.byIcon(destination.value);
          if (tab.evaluate().isNotEmpty) {
            await tester.tap(tab.first, warnIfMissed: false);
            await settle();
          }
          collect(destination.key);
          await paintWholeScroll(destination.key);

          // La Recherche n'a de mise en page à éprouver qu'avec des résultats :
          // l'état vide ne dit rien des lignes de versets.
          if (destination.key == 'Recherche') {
            final field = find.byType(TextField);
            if (field.evaluate().isNotEmpty) {
              await tester.enterText(field.first, 'Dieu');
              await tester.testTextInput.receiveAction(TextInputAction.search);
              await settle();
              collect('Recherche résultats');
              await paintWholeScroll('Recherche résultats');
            }
          }
        }

        expect(
          overflows.toSet(),
          isEmpty,
          reason:
              'Débordements sur ${device.key} à x$scale :\n'
              '${overflows.toSet().join('\n')}',
        );
      });
    }
  }
}
