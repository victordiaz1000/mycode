# Rendu ATI — choix en attente

> Écrit pour reprendre la discussion. Le prototype visuel est ici :
> **`ATI/prototype_rendu.html`** (double-clic, trois maquettes côte à côte sur
> Genèse 1:1-3, données réelles, clic sur les pastilles de note).

## 1. Où on en est

- **Étape 2 terminée** : `notes.json` lu dans l'app, chaque renvoi s'ouvre, un
  mot du rendu A donne sa fiche (sept champs, Strong cliquable), et **« Texte
  continu » est désactivé avec l'ATI**. Détail en §7 :
  `flutter analyze` sans remarque, **858 tests verts** (1 sauté), E2E vert.
- **Étape 1 terminée** : convertisseur, publication, bout en bout.
  - `ATI/ati_parse.py` corrigé — `CELLULE_RE` accepte `<td[^>]*>` ; les cellules
    de glose/analyse du dernier verset de chaque chapitre étaient en
    `<td align="right" dir="ltr">` et sautaient : **929 versets sortaient blancs**
    (12 964 mots, 4,2 % du corpus).
  - `ATI/ati_to_json.py` : nouveau contrôle — **un verset sans aucune glose =
    anomalie = code 1 = publication bloquée**. Sur l'ancien corpus, 929 anomalies.
  - Rapport relu, propre : 39/39 livres · 929 chapitres · 23 212 versets ·
    309 972 mots · 4 lacunes de source · 10 246 marqueurs · 333 184 colonnes
    sur 333 185 · **aucune anomalie**.
  - Publié : `victordiaz1000/-bym-bibles`, `6982296..16913f9` sur `main`,
    **40/40 URL en 200 et identiques** à `ATI/json/`, `notes.json` intact.
  - Vérifs : `ca`/`cg` sans dérive hors des derniers versets (+397 analyses,
    0 indice invalide), 0 verset vide.
  - App : `flutter analyze` sans remarque, **804 tests verts** (1 sauté :
    l'E2E réseau, opt-in `BYM_E2E=1`), E2E vert avec **Genèse 1:31** lisible.

**Ce que l'app affiche aujourd'hui** = l'interlinéaire en colonnes (§6), avec
les notes résolues et le tap sur un mot (§7). Le plan décrivait l'étape 2
comme *« une tuile de verset en colonnes de mots, hébreu droite-à-gauche,
sept champs empilés, pilotée par un drapeau sur `VersionEntry` comme
`hasStrong` pilote `strong_code_text.dart` »*
(`staged-imagining-pnueli.md:163`) — c'est fait, mais **piloté par
`verse.mots`** plutôt que par un drapeau : voir §6, « Décisions prises en
route ». La ligne jointe (`joinAtiGlosses`) reste dans `Verse.text` pour la
recherche, le partage et Comparer, mais ne se lit plus nulle part : la
colonne la remplace, et « Texte continu » est désactivé sur cette version
(§7).

## 2. Les trois rendus proposés

### A. Interlinéaire en colonnes — le rendu prévu au plan

```
      אֱלֹהִ֑ים        בָּרָ֣א       בְּרֵאשִׁ֖ית
      ’ĕ·lō·hîm;      bā·rā        bə·rê·šîṯ
      Dieu            créa         En un commencement
      Nom             Verbe        Nom · n12
```

Colonnes de droite à gauche, gloses en `ltr` isolé à l'intérieur de chaque
colonne, quatre à cinq niveaux (hébreu, translittération, glose, catégorie
`cg`, pastille de note).

- **Coût** : nouveau widget de tuile de verset + drapeau `VersionEntry`.
  Le plus de travail, le plus riche.
- **Déjà là** : police **Cardo** embarquée (hébreu + points-voyelles,
  `pubspec.yaml:203`), `strong_lemma.dart:50` gère `TextDirection.rtl`.
- **Point d'attention** : versets très longs (Exode 34:6 ≈ 40 colonnes) —
  combien de colonnes avant retour à la ligne, taille plancher de la glose.

### B. Bilingue : hébreu au-dessus, français en dessous

```
 1   בְּרֵאשִׁית בָּרָ֣א אֱלֹהִים אֵת הַשָּׁמַ֖יִם וְאֵת הָאָֽרֶץ׃
     En un commencement créa Dieu les cieux et la terre.
```

- **Coût** : moyen. Deux lignes par verset, aucun alignement mot à mot.
- **Contre** : on perd la correspondance mot à mot, qui est tout l'intérêt d'un
  interlinéaire.

### C. Texte actuel + notes résolues

```
 1   En un commencement créa Dieu les cieux et la terre. ⁽ⁿ¹²⁾
     H7225 Nom commun·féminin·état absolu—Préposition · H1254 Verbe qal…
```

- **Coût** : le plus rapide — pas de changement de mise en page, il suffit de
  **consommer `notes.json`** (publié, mais jamais lu : les mots ne portent que
  l'id `n`).
- **Contre** : ça ne répond pas à la demande d'interligne.

## 3. Les données sont prêtes

Sept champs par mot, tous présents dans les 39 fichiers : `s` Strong,
`t` translittération, `h` hébreu vocalisé, `d` découpage morphologique,
`f` glose française, `g`/`a` index vers `cg` (23 catégories) et `ca` (analyses
par livre), `n` id de note résolu par `notes.json` (37 pages : `n…`, `d…`, `r…`,
`abr`).

Couverture : 309 968 / 309 972 mots avec glose (4 lacunes de la source :
Genèse 9:11, Lévitique 14:27, Nombres 1:18 et 1:52), 298 876 avec analyse,
10 246 gloses réduites à un marqueur (`*` ou `-`, à sauter comme aujourd'hui).

## 4. En attente de décision

1. ~~**Quel rendu ?**~~ **→ A choisi, et réalisé.** Voir §6 pour le détail et
   ce qui reste à décider (flux continu, notes, tap sur un mot).
2. ~~**Défaut antérieur** : les versions AT-only affichent `bookCatalog.length`~~
   **→ corrigé.** Cinq endroits, pas trois : `library_screen.dart:135` (barre
   initiale) et `:530`, `reader_actions_bar.dart:823`, `search_screen.dart:925`,
   plus `search_engine.dart:436` — sans ce dernier, une ATI complète restait
   signalée comme partielle (« la recherche ne couvre que 39/66 livres »).
   Tous passent par `entry.bookCount` / `version.bookCount`, le canon de la
   version. Import de `book_catalog.dart` retiré de `library_screen.dart` (devenu
   inutile) et import de `version_catalog.dart` ajouté à `search_engine.dart`.
   Test de non-régression ajouté : `an OT-only version counts its own books, not
   66` (`library_screen_test.dart`), et le fake de service prend son total dans
   `entry.bookCount` comme le vrai. **`flutter analyze` sans remarque, 805 tests
   verts** (1 sauté : E2E réseau). Touche aussi SEF au passage, qui était dans le
   même cas.
3. ~~**`bym3` rien commité**~~ **→ fait, dépôt propre** (`git status` vide).
   Quatre commits posés sur `42918e6`, locaux seulement, rien poussé :

   | Hash | Sujet |
   |---|---|
   | `eb6e7fb` | Icônes : la barre et le rail passent aux cinq glyphes bibliques |
   | `c9c5cbd` | ATI : extraction Biblia et conversion des 39 livres en JSON publié |
   | `66c8e10` | ATI : téléchargement, lecture et rendu interlinéaire en colonnes |
   | `fa1d746` | Bibliothèque : une version Ancien Testament compte 39 livres, pas 66 |

   Les 36 Mo de `ATI/json/` sont versionnés (décision prise), `ATI/extrait/` et
   `ATI/__pycache__/` sont ignorés dans le même commit. Les icônes sont un
   sujet à part, le correctif 39/66 aussi : quatre features, quatre commits, et
   aucun fichier partagé entre deux.

## 5. Reprendre par ici

- Prototype : `ATI/prototype_rendu.html` — régénérer avec
  `python ATI/genere_prototype.py` si les données changent.
- Re-vérifier après tout changement de rendu :
  `flutter analyze` puis `flutter test` puis
  `BYM_E2E=1 flutter test test/e2e_ati_reseau_test.dart`.
- Le rapport du convertisseur (`python ATI/ati_to_json.py`) doit toujours
  finir par « Anomalies — aucune ».

## 6. Rendu A — interlinéaire en colonnes : fait

**À voir tout de suite :** `bible_app\test\goldens\ati_interlinear.png` —
Genèse 1:1-2 rendus par les vrais widgets, sur un cadre de 390 px, hébreu en
Cardo. Se régénère par
`flutter test --update-goldens test/ati_interlinear_golden_test.dart`.

### Ce qui est en place

| Fichier | Rôle |
|---|---|
| `lib/models/verse.dart` | champ `mots` (`List<AtiWord>?`) — les sept champs voyagent avec le verset |
| `lib/models/ati.dart` | `AtiWord.readableGloss` — le nettoyage des marqueurs vit **là**, une seule fois |
| `lib/data/version_repository.dart` | `bookFromAti` remplit `mots` **et** `text` (la ligne jointe reste pour recherche / partage / Comparer) |
| `lib/widgets/ati_interlinear.dart` | le widget : `Wrap` en `TextDirection.rtl`, une colonne par mot — hébreu Cardo ×1,5, translittération, glose, étiquette `cg`, renvoi de glossaire |
| `lib/widgets/verse_tile.dart` | le portail : `verse.mots` non vide → colonnes, sinon la ligne comme avant |
| `test/ati_render_test.dart` | 5 tests : ordre RTL, Cardo + `textDirection`, marqueur jamais affiché, repli sur la ligne (null **et** liste vide) |
| `test/ati_interlinear_golden_test.dart` | le golden |
| `test/ati_format_test.dart` | + 1 test : `bookFromAti` porte bien les mots, glose brute incluse |

`flutter analyze` sans remarque, **812 tests verts** (1 sauté : E2E réseau).

### Décisions prises en route

- **Piloté par la donnée, pas par un drapeau sur `VersionEntry`.** Le plan
  prévoyait un drapeau « comme `hasStrong` » ; le précédent de la SEF
  (`verse.grec != null`) fait la même chose sans qu'aucun écran ait à savoir
  quelle version est active, et un favori relu depuis son JSON (sans mots)
  retombe seul sur sa ligne. Le commentaire du catalogue ATI sur `hasStrong`
  annonçait déjà « le rendu interlinéaire lira les mots directement ».
- **Pas de tap sur un mot pour l'instant.** Voir ci-dessous.
- **Pas d'alignement de texte** sur ce rendu : `textAlign` règle la ligne
  courante, un flux de colonnes a un sens de lecture, pas une justification.

### Ce qui reste à décider / à faire

1. ~~**Le renvoi de glossaire affiché mais muet**~~ — **soldé, §7 : les 37
   pages sont lues et le tap donne la fiche.**
2. ~~**« Texte continu » garde la ligne jointe**~~ — **tranché, §7 : l'option
   se désactive avec l'ATI.**
3. **Lecture parallèle** (`parallel_reading_screen.dart`) passe par
   `VerseTile` : l'interlinéaire y apparaît aussi, colonnes comprimées dans
   chaque volet — à juger sur un écran réel.
4. **Vérification réelle** : aucun émulateur, aucune cible desktop, le web est
   exclu (`dart:io`) — le golden est la seule image obtenable ici.

## 7. Étape 2 — notes résolues + tap sur un mot : fait

`notes.json` est lu pour de vrai, chaque renvoi s'ouvre, et un mot du rendu A
donne sa fiche. Contrôles : `flutter analyze` sans remarque, **858 tests
verts** (1 sauté), et `BYM_E2E=1 flutter test test/e2e_ati_reseau_test.dart`
vert (39/39 téléchargés, réseau réel).

### Ce qui est en place

| Fichier | Rôle |
|---|---|
| `assets/ati/notes.json` | les 37 pages, **embarquées** (306 168 o, copié depuis `ATI/json/notes.json`) |
| `pubspec.yaml` | l'asset + le commentaire qui dit pourquoi il est embarqué |
| `lib/data/ati_notes.dart` | chargeur : `load` (bundle), `lookup(page, ancre)`, `lookupByName` (glossaire), `headingOf`, `useBundle` pour les tests |
| `lib/data/ati_note_html.dart` | démontage : `AtiNoteDocument.parse` — blocs (paragraphe, titre, liste, tableau, image) et liens (Strong, page de glossaire, verset), tolérants à ce que le HTML réserve |
| `lib/widgets/ati_note_view.dart` | les blocs → widgets, tableaux à colonnes fixées ou flexibles |
| `lib/screens/ati_note_screen.dart` | l'écran de page + la mention de droits |
| `lib/widgets/ati_word_sheet.dart` | la fiche des sept champs : tous les champs présents sont montrés, le Strong n'est cliquable que si `StrongLexicon` le connaît |
| `lib/widgets/ati_interlinear.dart` | `onWordTap` sur chaque cellule (l'ancien `TapGestureRecognizer` à libérer est sorti du jeu : `InkWell` + `WidgetSpan`) |
| `lib/widgets/verse_tile.dart` → `chapter_reader.dart` | la chaîne `onAtiWordTap` jusqu'au lecteur, qui ouvre la fiche puis `AtiNoteScreen.push` |
| `test/support/fake_ati_notes_bundle.dart` | le vrai fichier lu depuis le disque : dans `testWidgets`, `rootBundle` ne complète pas (zone fake-async) |
| tests | `ati_note_html_test.dart` (15), `ati_notes_test.dart` (8), `ati_note_screen_test.dart` (8), `ati_word_sheet_test.dart` (5), `ati_texte_continu_test.dart` (6) |

### Décisions prises en route

- **`notes.json` est embarqué, pas téléchargé.** Un asset ne dépend d'aucune
  panne réseau, se vérifie au démarrage et pèse 0,3 Mo dans un binaire qui en
  pèse bien plus ; aller chercher un fichier de notes au milieu d'une lecture
  pour devoir gérer l'échec par-dessus n'avait rien à y gagner. Le rationale
  est écrit dans le commentaire du `pubspec.yaml`.
- **Liens** : Strong → fiche, page de glossaire → `AtiNoteScreen`, renvoi de
  verset (`r.php`) affiché en texte simple — le lecteur ne fournit pas
  `onVerseTap` (v1 : situer une autre référence demanderait une recherche que
  le lecteur ne fait pas encore). Liens en `WidgetSpan` + `GestureDetector`
  (rien à libérer), et la fiche **ferme la feuille avant** de pousser la
  route.
- **Assertions hébreu** : on compare au `html` source, pas à l'affiché — les
  cantillations ne survivent pas au copier-coller du test, elles passent par
  `html`.
- **`Uri.decodeQueryComponent` refuse les accents bruts** (`Illegal percent
  encoding in URI`) : `_pageOf` garde la chaîne brute et ne décode que si elle
  contient un `%`, en `try/catch`.
- **Texte continu désactivé avec l'ATI.** L'option ne disparaît pas : elle se
  lit délavée avec le rappel « Indisponible avec l'interlinéaire ATI »,
  `enabledOf` rendant le tap muet et `selected` affichant « Séparés » — le
  même traitement que « Sous » en texte continu. Trois niveaux le tiennent :
  le réglage n'offre plus le choix (écran Réglages **et** feuille
  « Affichage »), `_setLayout` refuse de l'écrire, et `ChapterVerseList`
  force les colonnes dès qu'un verset porte `mots` — le contrat vaut pour
  n'importe quel appelant. La préférence globale **n'est jamais réécrite** :
  « Continu » revient tout seul en sortant de l'ATI. La sémantique vit dans
  `VersionEntry.interlinear`.

### Ce qui reste à décider / à faire

1. **Lecture parallèle** (`parallel_reading_screen.dart`) passe par
   `VerseTile` : l'interlinéaire y apparaît aussi, colonnes comprimées dans
   chaque volet — à juger sur un écran réel.
2. **Vérification réelle** : aucun émulateur, aucune cible desktop, le web est
   exclu (`dart:io`) — le golden reste la seule image obtenable ici.
