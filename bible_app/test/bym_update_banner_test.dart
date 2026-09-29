import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/data/bym_update_service.dart';
import 'package:bible_app/widgets/bible_theme_scope.dart';
import 'package:bible_app/widgets/bym_update_banner.dart';

/// Le bandeau de l'écran de lecture : troisième surface d'annonce, avec la
/// pastille de la Bibliothèque et la section de Réglages.
///
/// **Jamais `pumpAndSettle` ici.** Le défilement est une animation en boucle :
/// elle programme des frames sans fin, donc l'attente de stabilisation ne finit
/// jamais — et depuis que le bandeau défile sur **toutes** les largeurs, il n'y a
/// plus d'exception liée à la taille de l'écran. Tous les tests ci-dessous
/// pompent des durées explicites, sauf les deux qui vérifient précisément que
/// rien ne bouge : aucune mise à jour disponible, et « réduire les animations ».
/// Le premier est d'ailleurs indispensable pour que les tests widget des écrans
/// hôtes, eux, continuent de se stabiliser.
void main() {
  /// Ce que la vérification de démarrage aurait posé.
  BymUpdateCheck available({int books = 21}) => BymUpdateCheck(
    BymUpdateStatus.available,
    commit: 'cb535d4a3c9f1e2b7d8a4c5e6f708192a3b4c5d6',
    committedAt: DateTime.utc(2026, 8, 29),
    books: [for (var i = 1; i <= books; i++) 'livre-$i.md'],
    notes: 'Pr. 6:16 qu\'Elohîm -> que YHWH',
  );

  Widget host(
    Widget child, {
    bool disableAnimations = false,
    double width = 360,
  }) => MediaQuery(
    data: MediaQueryData(
      size: Size(width, 640),
      disableAnimations: disableAnimations,
    ),
    // Le bandeau lit `premiumPalette`, donc il lui faut le thème BYM ambiant.
    child: BibleThemeScope(
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [SizedBox(width: width, child: child)]),
        ),
      ),
    ),
  );

  // Le notificateur est statique : sans ce nettoyage, un test laisserait une
  // mise à jour « disponible » à toute la suite, y compris aux écrans hôtes.
  tearDown(BymUpdateChecker.clear);

  testWidgets('rien du tout sans mise à jour disponible', (tester) async {
    BymUpdateChecker.available.value = null;

    await tester.pumpWidget(host(const BymUpdateBanner()));

    expect(find.byKey(const Key('bymUpdateBanner')), findsNothing);
    expect(find.textContaining('Mettre à jour'), findsNothing);
    // Le seul `pumpAndSettle` de ce fichier, et il est l'assertion : sans mise
    // à jour, aucune animation ne tourne, donc l'écran se stabilise. C'est ce
    // qui protège les tests widget des écrans hôtes, où le bandeau est présent
    // en permanence et où un défilement en boucle ferait attendre sans fin.
    await tester.pumpAndSettle();
  });

  testWidgets('rien non plus quand la vérification ne trouve rien', (
    tester,
  ) async {
    // `hasUpdate` est faux avec zéro livre, même en statut `available`.
    BymUpdateChecker.available.value = available(books: 0);

    await tester.pumpWidget(host(const BymUpdateBanner()));

    expect(find.byKey(const Key('bymUpdateBanner')), findsNothing);
  });

  testWidgets('la phrase dit où aller et combien de livres', (tester) async {
    BymUpdateChecker.available.value = available();

    await tester.pumpWidget(host(const BymUpdateBanner()));

    // Deux copies : c'est la boucle du défilement, pas un doublon.
    expect(
      find.text('Mettre à jour le texte BYM dans les Réglages · 21 livres'),
      findsNWidgets(2),
    );
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('« 1 livre » au singulier', (tester) async {
    BymUpdateChecker.available.value = available(books: 1);

    await tester.pumpWidget(host(const BymUpdateBanner()));

    expect(find.textContaining('· 1 livre'), findsNWidgets(2));
  });

  testWidgets('le texte défile vers la gauche', (tester) async {
    BymUpdateChecker.available.value = available();
    await tester.pumpWidget(host(const BymUpdateBanner()));

    double offset() => tester
        .widget<Transform>(find.byKey(const Key('bymUpdateMarquee')))
        .transform
        .getTranslation()
        .x;

    // Le défilement ne démarre qu'après la première mise en page — c'est elle
    // qui dit si la phrase déborde — et un `Ticker` relève son origine de temps
    // à sa toute première frame, sans rien rapporter. Donc on pompe une fois
    // avant de mesurer, sinon on comparerait deux zéros.
    await tester.pump(const Duration(milliseconds: 16));

    final start = offset();
    await tester.pump(const Duration(milliseconds: 600));
    final moved = offset();

    expect(moved, lessThan(start), reason: 'le défilement va de droite à gauche');
    // Le tour reprend à zéro : sans la seconde copie, la boucle se verrait.
    await tester.pump(const Duration(milliseconds: 600));
    expect(offset(), lessThan(moved));
  });

  testWidgets('le bandeau apparaît et disparaît avec la vérification', (
    tester,
  ) async {
    BymUpdateChecker.available.value = null;
    await tester.pumpWidget(host(const BymUpdateBanner()));
    expect(find.byKey(const Key('bymUpdateBanner')), findsNothing);

    // Ce que fait `maybeCheck` au démarrage.
    BymUpdateChecker.available.value = available();
    await tester.pump();
    expect(find.byKey(const Key('bymUpdateBanner')), findsOneWidget);

    // Ce que fait `clear()` après une installation : le bandeau s'efface de
    // lui-même, personne n'a à le fermer.
    BymUpdateChecker.clear();
    await tester.pump();
    expect(find.byKey(const Key('bymUpdateBanner')), findsNothing);
  });

  testWidgets('sur une largeur de tablette, la phrase défile quand même', (
    tester,
  ) async {
    BymUpdateChecker.available.value = available();

    // Assez large pour la phrase entière. Elle défile pourtant : c'est le
    // mouvement qui fait remarquer l'annonce, et une tablette n'a pas moins
    // besoin qu'on la voie qu'un téléphone.
    await tester.pumpWidget(host(const BymUpdateBanner(), width: 780));

    double offset() => tester
        .widget<Transform>(find.byKey(const Key('bymUpdateMarquee')))
        .transform
        .getTranslation()
        .x;

    // Même amorce que sur téléphone : un `Ticker` ne rapporte rien à sa toute
    // première frame.
    await tester.pump(const Duration(milliseconds: 16));
    final start = offset();
    await tester.pump(const Duration(milliseconds: 600));

    expect(offset(), lessThan(start));
    // Deux copies ici aussi : sans la seconde, la reprise de boucle laisserait un
    // blanc traverser toute la largeur de la tablette.
    expect(
      find.text('Mettre à jour le texte BYM dans les Réglages · 21 livres'),
      findsNWidgets(2),
    );
  });

  testWidgets('un appui conduit à Réglages', (tester) async {
    BymUpdateChecker.available.value = available();
    var taps = 0;

    await tester.pumpWidget(host(BymUpdateBanner(onOpenSettings: () => taps++)));
    await tester.tap(find.byKey(const Key('bymUpdateBanner')));

    expect(taps, 1);
  });

  testWidgets('sans route vers Réglages, le bandeau reste une annonce', (
    tester,
  ) async {
    BymUpdateChecker.available.value = available();

    await tester.pumpWidget(host(const BymUpdateBanner()));

    // Tappable mais inerte serait un faux bouton : `onTap` est null, donc
    // l'appui n'allume même pas l'encre.
    final inkWell = tester.widget<InkWell>(
      find.byKey(const Key('bymUpdateBanner')),
    );
    expect(inkWell.onTap, isNull);
    // La phrase, elle, dit toujours où aller.
    expect(find.textContaining('dans les Réglages'), findsNWidgets(2));
  });

  testWidgets('« réduire les animations » arrête le défilement', (tester) async {
    BymUpdateChecker.available.value = available();

    await tester.pumpWidget(
      host(const BymUpdateBanner(), disableAnimations: true),
    );

    // Une seule copie, tronquée, immobile : un défilement perpétuel qu'on ne
    // peut pas arrêter est exactement ce que ce réglage demande d'éviter.
    expect(find.byKey(const Key('bymUpdateMarquee')), findsNothing);
    final text = tester.widget<Text>(
      find.textContaining('Mettre à jour le texte BYM'),
    );
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.maxLines, 1);
    // Immobile pour de bon : l'écran se stabilise comme sans bandeau.
    await tester.pumpAndSettle();
  });
}
