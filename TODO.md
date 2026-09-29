# TODO — suite du restyle « Premium affirmé »

Lot en attente, mis de côté volontairement (demande du 29/09) : les autres écrans
sont traités et la suite complète est verte (**739 tests**, `flutter analyze`
zéro issue, depuis `bible_app/`).

---

## 1. Les trois interfaces ouvertes depuis l'accueil

### Favoris — `bible_app/lib/screens/favoris_screen.dart`
- **Déjà là** : `premiumBackground` sur le Scaffold, `premiumShadow` (×2).
- **Manque** : les cartes de favoris sont en aplat — elles passent par
  `premiumSurface(context, radius: …, depth: …)` avec le liseré
  `premiumCardBorder`, plus le velours d'AppBar et le filet de section comme
  sur les écrans déjà traités.

### Notes — `bible_app/lib/screens/notes_screen.dart`
- **Déjà là** : `premiumBackground`, `premiumShadow(p.primaryDark)` (×2).
- **Manque** : mêmes cartes en `premiumSurface`, listes de notes et en-tête
  remontés au vocabulaire premium.

### Comparer — `bible_app/lib/screens/ecran_comparer.dart`
- **Aucun** import `premium_style` : `theme.scaffoldBackgroundColor`,
  `Colors.black.withValues(alpha: .03/.04)` sur les fonds de cartes.
- **Travail complet** : fond `premiumBackground`, cartes `premiumSurface`,
  liserés `premiumCardBorder`, ombres `premiumShadow`, AppBar voilée — et
  sortie des `Colors.*` au profit des tokens.

> À confirmer : `historique_screen.dart` (aussi ouvert depuis l'accueil, via
> « Tout voir ») est dans le même état que Favoris/Notes — fond + ombres, pas
> de `premiumSurface`. Non listé dans les 3, donc non touché.

---

## 2. La feuille d'étude de l'écran Lecture — `bible_app/lib/widgets/study_sheet.dart`

- Importe déjà `premium_style` mais a été **laissé tel quel au round 3** :
  un test mesure sa couleur actuelle (voir ci-dessous).
- **Manque** : fond des feuilles, cartes d'action (Surligner, Note, Copier…)
  en `premiumSurface`, pastilles d'icônes et séparateurs en dégradé, dialogues
  de suppression façonnés au `premiumCardBorder`.

### Point de vigilance — ce qui bloque aujourd'hui
- `test/study_sheet_test.dart` exige `d.color == p.surface` sur la carte
  « Surligner » et que les tuiles d'action restent adossées à un `Material`
  (les ripples en dépendent). Passer la carte en dégradé `premiumSurface`
  fait échouer cette assertion : il faut alors **réécrire le test**, pas
  contourner le style — c'est une décision d'aujourd'hui, pas une loi.
- `test/responsive_pushed_screens_test.dart` pompe la feuille en ×1.0 et
  ×2.0 (« feuille d'étude » et « feuille d'étude — lexique grisé ») :
  l'ajustement du fond ne doit rien faire déborder.

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
   (739 tests ≈ 2 min 45) depuis `bible_app/`.
