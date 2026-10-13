# Fluidité — lot traité, règles, et ce qui reste

Journal du 2026-10-13. Trois commits posés sur `0eb80a7`, base revenue
volontairement en arrière pour repartir propre.

| | |
|---|---|
| `faf6c11` | la position de lecture ne réveille plus l'application |
| `3612c49` | accueil paresseux, palette mémoïsée, futures hors du build |
| `a17884b` | retour sur le garde-fou fautif de la bibliothèque |

**État à la clôture** : `flutter analyze` à 2 infos (toutes deux préexistantes,
`test/highlight_wash_test.dart:51-52`, `.value` déprécié), **1031 tests verts**,
1 ignoré — `e2e_ati_reseau_test.dart`, réseau réel, opt-in `BYM_E2E=1`.

Aucun libellé, aucune géométrie, aucune couleur touchés : la règle 3 de
`TODO.md` tient, et l'audit de débordement sur 16 tailles d'écran le confirme.

---

## Ce qui a été corrigé

### La cascade par geste de lecture — le gros morceau

`TabManager.updateTabVerse` notifiait ses écouteurs. Chaîne déclenchée à chaque
fois que le défilement s'immobilisait sur un autre verset :

1. `chapter_reader` → debounce 400 ms → `onVerseChanged`
2. `updateTabVerse` → `_persist()` **et** `notifyListeners()`
3. `ReaderScreen` reconstruisait son `Scaffold`, la `TabStrip`, la bannière de
   mise à jour et l'`IndexedStack` de **tous** les onglets ouverts — donc chaque
   `ChapterReader` et ses tuiles visibles
4. `HomeScreen._reload` relisait l'historique puis reconstruisait **l'accueil
   entier**, ses vingt sections décoratives comprises, pendant que
   l'utilisateur regardait l'écran Lecture

La notification est supprimée. `_persist()` reste **immédiat** : c'est lui qui
fait survivre la position à un arrêt brutal du processus.

### Les préférences

`_onPreferencesChanged` adopte toujours le cliché, mais ne reconstruit que si
un champ réellement affiché a bougé. `AppPreferences.save()` incrémente la
révision à chaque écriture, y compris pour un thème ou la version par défaut.

### L'accueil

- `_Pal` était un doublon exact de `PremiumPalette`, champ pour champ, recalculé
  une vingtaine de fois par build. Supprimé au profit d'une délégation.
- `premiumPalette` garde sa dernière palette, indexée sur l'**identité** du
  thème. `premiumSurface` ne la demandait plus deux fois.
- Les trois futures de la carte « Reprendre » sortent du `build`, indexées sur
  la position.
- Les rangées passent en `ListView.builder`.
- `_EmptyReadingBody` (écran Lecture) retient sa lecture d'historique.

---

## Pièges déjà payés — ne pas les redécouvrir

### 1. Ne jamais figer `fontSize` / `panelOpacity` / `sidePadding`

Épingler ces trois champs sur la copie locale de `_prefs`, pour « protéger un
glissement en cours », casse `reader_paragraph_test.dart` « le titre de section
suit la taille du texte » — et surtout : une taille réglée dans Réglages
n'atteint plus un onglet déjà ouvert.

C'est **inutile** : pendant un glissement, `_setFontSize` et ses jumeaux
n'écrivent rien, donc n'incrémentent aucune révision. La seule écriture arrive
au relâcher, avec la valeur locale elle-même.

### 2. Toujours adopter le cliché des préférences

Conditionner l'**adoption** (et pas seulement le `setState`) laisserait au
lecteur une copie d'avant un choix de thème, que la prochaine sauvegarde
d'opacité réécrirait en entier — le thème choisi serait silencieusement annulé.
Verrouillé par `panel_opacity_test.dart`.

### 3. Aucun garde-fou possible sur `LibraryStore.revision` dans le lecteur

Tentative faite, et fausse. `ReaderActionsBar` reçoit la carte du registre en
**instantané de build** (`installedVersions:`), et c'est cet instantané que la
feuille « Version » photographie à l'ouverture. Rafraîchir le champ `_installed`
sans `setState` laisse la barre sur la carte du dernier build : pendant un
téléchargement, la progression reste figée sur son premier livre jusqu'à ce
qu'autre chose reconstruise le lecteur.

> Toute économie ici suppose **d'abord** que la feuille lise le registre au
> moment du tap, pas au build. Tant que c'est un instantané, aucun changement
> du registre ne peut être ignoré sans mentir.

Le coût assumé : `saveBook` incrémente la révision une fois par livre, soit 66
reconstructions par version téléchargée et par onglet ouvert. C'est le prix
d'un affichage juste, pendant une opération rare.

### 4. Un faux magasin mute de façon synchrone — le test peut passer à tort

Poser les 66 livres d'affilée puis `pumpAndSettle()` une seule fois **ne
reproduit pas** un téléchargement : la carte du `FakeStore` est mutée
synchroniquement, donc le premier écouteur asynchrone réveillé y voit déjà les
66 livres et prend le chemin complet. Le test est vert pour la mauvaise raison.

Il faut faire arriver les livres **un par un, avec une frame entre chacun**, et
relire la feuille à `1/66`, puis `2/66`, puis `66 livres`. Le cas `2/66` est
celui qu'un garde-fou croit pouvoir ignorer.

**Et vérifier qu'un test neuf échoue bien sans le correctif** : c'est la seule
preuve qu'il garde quelque chose.

---

## Ce qui reste

### Fluidité — le morceau suivant

`verse_tile.dart:1006` : la clé de `VerseTile` embarque les préférences —

```dart
ValueKey('${textAlign}_${fontSize}_${readingFont.name}_…_$vn')
```

Donc le moindre réglage change toutes les clés, et chaque tuile visible est
**détruite puis reconstruite** au lieu d'être mise à jour. Gain réel sur le
défilement, mais c'est le seul point qui touche au rendu, et un commentaire du
code documente un vrai défaut que cette clé corrige (sans elle, un `textAlign`
neuf n'atteignait pas le `Text`). `VerseTile` étant un `StatelessWidget`, ce
diagnostic mérite d'être réinstruit. **À traiter seul, avec son propre test.**

### Les autres écouteurs de `LibraryStore.revision`

`library_screen` (doit reconstruire : il montre la progression),
`search_screen`, `settings_screen`, `reader_screen._HomeActionsBar`. Jamais
instruits. Le piège 3 s'applique à chacun : vérifier d'abord ce qui est un
instantané de build.

### Hors fluidité, constats de l'audit du 2026-10-13

- **Accueil, rendu cassé sur 3 thèmes.** 29 couleurs en dur dans
  `home_screen.dart`, contre la règle 1 de `TODO.md`. Les tuiles pastel restent
  claires sur **Azur profond**, **Nuit étoilée** et **Veillée**
  (`usesLightText`). Aucun test ne couvre ça.
- **Accueil, 17 zones tactiles muettes** réparties sur 9 sections, toutes en
  `_soon()` → « bientôt disponible » : alphabets, Bible et histoire, les deux
  pavés de mesures, dénominations, conciles, empereurs, fausses divinités,
  fêtes/mois/temps, jours de la semaine. À construire ou à retirer — dix-sept
  boutons qui s'excusent, c'est pire que leur absence.
- **`appCodebar/chatiment.json`** : 172 blocs d'en-tête isolés + 109 occurrences
  incrustées = 281 répétitions du titre de chapitre dans le corps. Vérifié
  présent. La note de passation `CHATIMENT_en-tetes_TODO.md` décrit la méthode
  **et** pourquoi une première tentative a détruit le texte — la lire avant.
- **Recherche** : `liens` (références croisées) et `nave` (index thématique)
  désactivées faute de données. Assumé et documenté dans `search_engine.dart`.

---

## Vérification, à chaque fois

Depuis `bible_app/` :

```
flutter analyze     # doit rester à 2 infos, dans test/highlight_wash_test.dart
flutter test        # 1031 passés, 0 échec, 1 ignoré — compter 4 à 5 min
```

Et le contrôle que les tests ne savent pas faire : ouvrir trois ou quatre
onglets, défiler un chapitre long (Psaume 119), vérifier que le hoquet après
l'arrêt du geste a disparu. Puis régler la taille du texte dans Réglages et
revenir en Lecture : la taille doit avoir suivi.
