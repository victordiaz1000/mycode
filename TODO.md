# TODO — restyle « Premium affirmé » : traité

Le lot est **clos** (commit `f38bf5f`, 2026-09-30). `flutter analyze` sans
remarque, **744 tests verts** depuis `bible_app/`.

Ce fichier ne contient plus de travail en attente : il garde **les règles du
restyle** — elles restent valables pour tout écran qu'on reprendra — et les
pièges de tests qu'on a déjà payés, pour ne pas les redécouvrir.

---

## Ce qui a été traité

### Les écrans ouverts depuis l'accueil
- **Favoris · Notes · Comparer** — le lot d'origine : cartes en
  `premiumSurface`, velours d'AppBar, filets d'intertitre.
- **Historique** (« Tout voir ») — non listé au départ, mais dans le même état
  que les trois (fond + ombres, pas de `premiumSurface`) ; rejoint le lot.
- **Bibliothèque** — ses deux dialogues de suppression (versions et
  dictionnaires) façonnés au `premiumCardBorder`.

### L'écran Lecture et ses annexes
- **`study_sheet.dart`** — panneau et cartes en `premiumSurface`, tuiles
  d'action au motif d'encrage (règle 5), pilule d'intertitre en dégradé.
- **`reader_screen.dart`** — `Scaffold` externe sur `premiumBackground` (le
  bandeau d'onglets est translucide à `.60`, il se posait sur le blanc du
  thème) et la carte « Reprendre » sortie du `Card` en aplat.
- **`tab_switcher.dart`** — dock d'actions en coque premium, velours d'AppBar,
  pastilles d'accent, vignette d'aperçu habillée, « Rouvrir » en dégradé.

### La barre de recherche (Notes, Historique)
- États de focus : `FocusNode` + `AnimatedContainer(180 ms)`, voile `.35` au
  repos → `.9` + liseré `.55`/1,4 px + halo d'accent + icône en accent au
  focus. `tooltip: 'Effacer'` sur le bouton ✕.
- **`filled: false`** : voir la règle 7 plus bas, et son origine dans
  `AGENTS.off.md` § 4.7.

---

## Pièges de tests — déjà payés, ne pas les redécouvrir

- **`study_sheet_test.dart`** exigeait `d.color == p.surface` sur la carte
  « Surligner » et des tuiles adossées à un `Material`. Réécrit : finder
  **structurel** (ancêtre de `find.byTooltip('Effacer le surlignage')`,
  `Container` + dégradé + `BorderRadius.circular(16)`), contraste mesuré sur
  `gradient.colors.first` (vérifié `== p.surface`) au seuil **> 1.2**, plus une
  vérification des six voiles d'icône posés dans un `Ink`.
  **Réécrire le test, pas contourner le style.**
- **`tab_switcher_test`** prend le **premier** `Container` dont la décoration
  porte un `Border` et attend l'or de la carte courante : la coque du dock du
  bas est donc un `DecoratedBox`, sinon elle vole cette première place.
- **`tab_strip_test`** verrouille la structure interne d'une puce
  (`Container` + `constraints: BoxConstraints(maxWidth: 116)`) : ne pas la
  réécrire en `Ink` sans réécrire le test.
- **`find.text` ne matche pas le message d'un `Tooltip`** (aucun `Text` n'est
  rendu tant qu'on ne le montre pas) : ajouter un `tooltip:` ne touche aucun
  verrou.
- `find.text('ACTIONS')` (×2), `find.byIcon(Icons.format_color_fill)`,
  `'2 favoris'`, `'2 versions affichées'`, `'BYM').first`, `'3 lectures'`,
  `'Sans groupe'` : libellés inchangés par le restyle — c'est le contrat de la
  règle 3.

---

## Règles du restyle (les garder sinon les tests cassent)

1. **Pas de couleurs en dur** : `premiumPalette`, `premiumCardBorder`,
   `premiumShadow`, `premiumBackground`, `BibleTheme` uniquement.
2. **Vocabulaire** : `premiumSurface(context, radius:, depth:)` = dégradé
   `surface → surfaceAlt` + liseré `premiumCardBorder(.18)` + deux ombres.
   L'accent (or/hébreu) uniquement en filets, pastilles, halos et marqueurs
   d'état — **jamais** en bordure de carte.
3. **Aucun texte, key, tooltip ni géométrie** modifié : les tests verrouillent
   les libellés exacts, les types de widgets et la disposition.
4. **Animations finies seulement** (`AnimatedContainer`), sinon
   `pumpAndSettle` ne se termine plus.
5. **Motif d'encrage** : `Material(color: Colors.transparent)` **sans** `shape`
   + `Ink(decoration)` pour que les ombres ne soient pas rognées ;
   `InkWell(borderRadius:)` découpe bien son propre ripple.
6. **Vérification obligatoire** : `flutter analyze` puis `flutter test`
   (**744 tests, 3 à 5 min**) depuis `bible_app/`.
7. **Un `TextField` logé dans une surface arrondie écrit `filled: false`.**
   `main.dart` pose `inputDecorationTheme(filled: true, fillColor: panelColor)`
   et tout `InputDecoration` qui ne redéfinit pas `filled` hérite de la valeur :
   l'`InputDecorator` peint alors un aplat **carré** par-dessus le voile rond de
   l'appelant. Les deux formes ont le même rectangle, donc le carré ne dépasse
   qu'aux quatre coins — « il a deux bordures, une ronde et une carrée ».
   Corrigé sur les cinq champs de Notes, Historique, index du lexique et
   éditeur de note ; `note_dialog` est laissé tel quel (pas de conteneur
   arrondi, l'applat y lit comme une zone de saisie).
