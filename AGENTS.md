# AGENTS.md — Projet BYM (App de Bible Flutter)

Ce fichier documente le projet, ses décisions et la feuille de route. À lire avant toute modification.

## Vue d'ensemble

> **État actuel du dépôt.** Le projet Flutter `bible_app/` existe et compile. Données sources : `bym_json/` (66 livres, copiés dans `bible_app/assets/bible/bym/`), `thème/` (10 fonds, copiés+convertis en PNG dans `bible_app/assets/themes/`) et le lexique Français+Strong `bible_app/assets/lexicon/strong_fr.json` (14 195 définitions). Les maquettes UI de référence sont dans `maquettes/` (9 fichiers HTML, versions v1–v8) ; les itérations plus récentes s'appuient sur des captures : `modif/` (barre d'actions, feuille des versions) et `rech/` (4 captures de la recherche unifiée). Syntaxe : `flutter analyze` + `flutter test` avant validation. **`flutter test` complet passe : 220 tests, ~70 s, `flutter analyze` à zéro.** Le dépôt est sous **git** (`git init` à la racine `bym3/` ; `build/`, `.dart_tool/`, `android/.gradle` exclus — 28 Mo suivis, pas 1,4 Go).

Application **mobile Flutter** de Bible nommée **BYM — Bible de Yehoshoua Ha Mashiah**.
- Version principale **BYM** (contenu de l'utilisateur), embarquée dans l'app (offline).
- Autres versions de traduction et dictionnaires **téléchargeables** (getbible.net + hébergement Filebase + catalogue configurable).
- Thèmes personnalisables : 4 thèmes nommés (Vitrail, Oliveraie, Désert, Nuit étoilée) combinant palette + fond issus des 10 images.

## Données sources

- `appCodebar/bym_md/` : **la source de vérité** — les 66 livres BYM en markdown (5,1 Mo), tels qu'ils sont rédigés et corrigés.
- `appCodebar/md_to_json.py` : le convertisseur markdown → JSON (Python 3.12, stdlib seule). `python md_to_json.py [dossier_md] [dossier_sortie]`, défauts `./bym_md` → `./bym_json`. Toute correction de texte passe par lui ; le JSON ne s'édite pas à la main.
- `bym_json/` : les 66 livres BYM (un fichier JSON UTF-8 par livre, numéroté `01-Genese.json` … `66-Apocalypse.json`) — **sortie du script**, recopiée dans `bible_app/assets/bible/bym/`. `appCodebar/bym_json/` est la même chose et reste hors de git (voir `.gitignore`) : trois copies de 9,3 Mo suffisaient déjà.
- `thème/` : 10 images de fond utilisées par les thèmes.

### Structure d'un fichier livre BYM
```json
{
  "book": "Bereshit (Genèse)",
  "abbreviation": "Ge.",
  "metadata": { "signification": "...", "auteur": "...", "theme": "...", "date": "..." },
  "introduction": "...",
  "chapters": [
    {
      "chapter": 1,
      "verses": [
        {
          "verse": "1:1",
          "section": "Titre de section (optionnel, coloré différemment)",
          "text": "Texte simple.",
          "textWithNotes": "Texte avec le contenu des notes entre crochets.",
          "notes": [ { "word": "...", "position": 0, "note": "..." } ]
        }
      ]
    }
  ]
}
```
- `section` est **optionnel**, présent uniquement sur le premier verset d'une nouvelle section.
- `text` = texte simple ; `textWithNotes` = texte + notes ; `notes[]` = notes structurées.

## Décisions de conception (verrouillées)

1. **Frameworks** : Flutter 3.44.1 (dispo), Dart 3.12.1.
2. **Navigation** : 5 sections (PAS d'Ancien/Nouveau Testament) :
   - **Torah** (5) : Genèse→Deutéronome (01–05)
   - **Nevi'im / Prophètes** (21) : Josué→Malachie (06–26)
   - **Ketouvim / Écrits** (13) : Psaumes→2 Chroniques (27–39)
   - **Évangiles** (4) : Matthieu→Jean (40–43)
   - **Testament de Yehoshoua** (23) : Actes→Apocalypse (44–66)
3. **Version par défaut** : BYM embarquée.
4. **Bouton Notes** (AppBar du chapitre) : OFF → `verse.text` ; ON → `verse.textWithNotes`.
5. **Titres de section** : rendre `verse.section` comme un titre coloré différemment au-dessus du verset.
6. **Bibliothèque** : 2 onglets (Bibles + Dictionnaires), chaque item = bouton ⬇ Télécharger / 🗑 Supprimer, stockage offline sur l'appareil.
7. **Sources** : chacune `source: "getbible"` (getbible.net) OU `url:` (lien direct, ex. Filebase). Catalogue **configurable** (URL externe).
8. **Hébergement** : Filebase (S3-compatible `s3.filebase.io`, noeud `region: auto`). Publication manuelle via console (pas de script pour l'instant).
9. **Bibles getbible dispo** : `ls1910` (Louis Segond 1910), `darby`, `martin` (français) ; KJV, WEB… (anglais). Note : ls1910 « with Strong » n'embarque PAS les numéros Strong dans le JSON texte (vérifié).
10. **Lexique (mots cliquables)** : clic sur un verset BYM → bouton « Lexique » → même livre/chapitre/verset affiché dans une **version Française + Strong**, mots cliquables → définition Strong (hébreu `H####` / grec `G####`).
    - **Source retenue** : CrossWire/SWORD — `FreStrongsHebrew` + `FreStrongsGreek` (convertis par `appCodebar/sword_zld_to_json.py` en `assets/lexicon/strong_fr.json`, 14 195 définitions FR). Voir `bible_app/plan-strong-fr.md`.
11. **Thèmes** : galerie des 10 fonds ; texte sur **panneau semi-transparent** ; couleur de texte déduite de la luminosité ; GIF → convertir en PNG ; thème BYM par défaut ; préférence mémorisée.
12. **Stockage** : dossier app `path_provider` + registre `shared_preferences`.

## Dépendances prévues (Flutter)

`http` · `dio` (téléchargements + progression) · `path_provider` · `shared_preferences` · `provider`.

## Fonds de thème (analyse luminosité → couleur de texte)

| Fichier | Dim. | Lum | Texte conseillé |
|---|---|---|---|
| assyriens.png | 640×480 | 219 | sombre |
| beige.gif | 300×225 | 238 | sombre |
| bg.gif | 590×480 | 247 | sombre |
| blanc.png | 32×32 | 162 | sombre |
| bleu.png | 130×129 | 93 | clair (blanc) |
| bois.png | 300×225 | 178 | sombre |
| chocolat.png | 300×200 | 218 | sombre |
| gris.png | 100×100 | 243 | sombre |
| metal.png | 300×198 | 190 | sombre |
| sable_gris.png | 208×207 | 210 | sombre |

La plupart sont de petits motifs → tuiles (`ImageRepeat.repeat`). `beige.gif`, `bg.gif` → convertir en PNG.

## Architecture projet cible

```
bible_app/
  assets/
    bible/bym/          # copie des 66 JSON de bym_json/
    themes/             # fonds convertis (PNG)
  lib/
    models/             # BibleBook/Chapter/Verse/Note, Translation, Dictionary, Catalog
    data/
      local_repository.dart    # BYM embarqué (chargement paresseux par livre)
      read_repository.dart     # lit BYM local OU fichier téléchargé (par livre/chapitre)
      catalog_service.dart     # fetch catalogue configurable
      download_service.dart    # http + progression (66 requêtes, reprise par livre)
      library_store.dart       # registre installé + dossier stockage
      version_repository.dart  # lecture dans la version active (BYM ou téléchargée)
      fulltext_index.dart      # index plein texte, un par version (of/forget, 2 téléchargés max)
      strong_source.dart       # version FR+Strong (source configurable)
      strong_lexicon.dart      # définitions Strong
      book_mapping.dart        # BYM (ordre hébraïque) <-> numéros standard (1=Genèse...66=Apocalypse)
    screens/
      books_screen.dart        # 5 sections -> livre -> chapitre
      chapter_screen.dart      # lecture + bouton Notes + bouton Lexique
      library_screen.dart      # Bibles & Dictionnaires (+/-)
      dictionary_screen.dart
      settings_screen.dart     # URL catalogue, version/lexique par défaut
      themes_screen.dart       # sélection de thème
    widgets/
      verse_tile.dart
      clickable_verse.dart     # RichText, mots Strong cliquables
      translation_bar.dart
  test/
    book_parsing_test.dart
    sections_mapping_test.dart
    catalog_test.dart
```

## Avancement (itérations en cours)

> Les **maquettes de référence** sont dans `maquettes/` (9 HTML, v1–v8). Priorité validée : **lecture d'abord**, persistance **SQLite (sqflite)**, thèmes **4 nommés combinant les 10 fonds**, périmètre « socle lecture + feuille d'étude ».

Fait dans `bible_app/` :
- **Lecture v4** : en-tête de livre repliable au chapitre 1 (titre `book`, abréviation + traduction, grille 2×2 métadonnées, intro), bascule « Texte seul / Texte + notes » sous la référence (**BYM seule** — voir `_supportsNotes`), **disposition mémorisée** (À la suite / Sous le verset), marqueur ✦, titres de section, surlignage des mots notés via `word`+`position`.
- **Feuille d'étude v5** (`widgets/study_sheet.dart`) : au clic sur un verset → surlignage **4 couleurs + gomme**, actions Note · Favori · Comparer(stub) · Références(stub) · Écouter(stub) · Copier · Partager(stub), **bouton doré Lexique** (grisé sans notes), **appui long = multi-sélection**. **Surlignage et favori sont des bascules appliquées au tap** (`onHighlight` / `onFavorite`), pas des valeurs rendues à la fermeture : `showStudySheet` ne renvoie qu'un `StudyAction?`. Retaper la couleur active l'efface ; la gomme est inerte quand il n'y a rien à effacer. Couvert par `test/study_sheet_test.dart` (9 tests).
- **Lexique v8** : verset **mot à mot cliquable**, fiche, navigation, index construit depuis `lexicon_service.dart` (notes → entrées), sans module externe. **Supercédé par le lexique Strong** (`strong_lexique_screen.dart`) pour l'écran « Lexique » de la lecture (voir § LSGS ci-dessous) ; `lexique_screen.dart` a été supprimé (orphelin).
- **LSGS (Segond 1910 + Strong) embarquée** (`data/lsgs_repository.dart`, `models/lsgs.dart`) : corpus construit par `appCodebar/sg1910_to_json.py` depuis `Sg1910-csv/`, copié dans `assets/bible/lsgs/` (66 JSON). Version `embedded`, format `getbible`, `hasStrong`. Lecture : codes Strong inline (`_StrongAwareText`), tap → fiche de définition ; bouton « Lexique » de la feuille d'étude → **`screens/strong_lexique_screen.dart`** aligné maquette v8 (« Lexique — {livre} {ch}.{v} » + « verset mot à mot », bandeau d'aide doré, fiche Strong avec navigation « Mot préc./suiv. »). Définitions FR : `assets/lexicon/strong_fr.json` (14 195, `data/strong_lexicon.dart`). **Audio retiré** (décision 2026-08) : pas d'`audioplayers`, pas de marque 🔊.
- **Persistance SQLite** (`data/app_database.dart`, tables highlights/notes/favorites/prefs, factory injectable, `useInMemory()` pour tests), préférences via `shared_preferences` (`data/app_preferences.dart`).
- **Thèmes** : `data/theme_catalog.dart` = 4 thèmes nommés (palette + fond des 10 images `assets/themes/`), 2 GIF convertis en PNG (beige, bg).

### Itération onglets façon Chrome (maquette `Qwen_maquette_gestion d'onglet.html`)

**Implémenté (analyse propre, 39 tests verts dont 10 unitaires TabManager + 11 widgets onglets) :**
- `models/study_tab.dart` — `StudyTab` (kind `reading`|`home`, book/chapter, `title`, `pinned`), sérialisation JSON.
- `data/tab_manager.dart` — `TabManager extends ChangeNotifier` : `openReading` (reuse/focus si déjà ouvert), `openHome`, `activate`, `close` (file **Fermés récemment** de 8 max), `reopen`, `closeAll`, `reopen`, `duplicate`, `togglePin`, `clearRecentlyClosed` ; **persistance `shared_preferences`** (restauration au lancement).
- `widgets/chapter_reader.dart` — corps de lecture (toggle texte/notes + liste + interactions) extrait de `chapter_screen.dart`, **indépendant du Scaffold** (multi-sélection = barre basse interne). `chapter_screen.dart` : devenu un simple wrapper.
- `widgets/tab_strip.dart` — barre : onglets scrollables (actif liseré doré, épingle, ✕) + bouton **＋** (ouvre un onglet accueil) + **compteur doré** (ouvre le sélecteur).
- `widgets/tab_switcher.dart` — overlay plein écran : grille d'onglets (cartes), onglet actif bordé d'or, **Fermés récemment** (Rouvrir / Vider), bas : Accueil ⌂ / **＋** / **Tout fermer**.
- `screens/reader_screen.dart` — coquille onglets : `TabStrip` + `IndexedStack` du contenu + page d'accueil Chrome-like (intègre `BooksScreen`). **Paramètre injectable `initialManager`** pour les tests. `main.dart` : destination « Livre » = `ReaderScreen`.
- `books_screen.dart` / `chapter_list_screen.dart` : callback `onOpenChapter` → ouvre un onglet (au lieu de pousser `ChapterScreen`).
- `data/local_repository.dart` : **cache désormais statique** (partagé entre instances) + `clearCache()`.

**Test d'intégration `test/reader_tab_test.dart` — RÉSOLU.** Le test `Reading a chapter opens it in a tab` partait en timeout (~7 min, « did not complete »). Cause réelle : `rootBundle` fait de l'**I/O réelle**, qui ne peut jamais se terminer dans la zone `fakeAsync` de `testWidgets` → tout `pumpAndSettle` attend indéfiniment (le `CircularProgressIndicator` n'était que le symptôme). `tester.runAsync` ne suffit pas : y imbriquer `pumpAndSettle` ne débloque rien.

Correctif :
- `LocalRepository` expose une **source d'assets injectable** : `static AssetBundle get bundle`, `useBundle(AssetBundle)` (vide aussi le cache) et `useRootBundle()`. Le code de production est inchangé (défaut = `rootBundle`).
- `test/support/fake_bible_bundle.dart` — `FakeBibleBundle extends AssetBundle` sert des livres **synthétiques** pour n'importe lequel des 66 fichiers du catalogue (nom + abréviation réels conservés, N chapitres × N versets paramétrables, section + note sur le verset 1).
- Le test installe le faux bundle en `setUp` et restaure `useRootBundle` en `tearDown`, puis utilise des `pumpAndSettle` normaux (plus de `runAsync`).
- Assertions durcies : le compteur doré se cherche via `find.descendant(of: find.byType(TabStrip), matching: find.text('N'))` (l'ancien `find.text('1')` était ambigu), et les chapitres via `find.widgetWithText(OutlinedButton, '1')`.
- Un 4ᵉ cas a été ajouté : ouvrir un 2ᵉ chapitre crée bien un 2ᵉ onglet, et rouvrir un chapitre déjà ouvert **focalise** l'onglet existant sans le dupliquer.

Résultat : **4/4 en ~2 s** sur ce fichier, **43/43 sur `flutter test` complet en ~5 s**, `flutter analyze` sans issue. Les tests widget qui rendent un chapitre ne doivent plus jamais lire les assets réels — passer par `FakeBibleBundle` (les tests purs `test()`, eux, peuvent : ils tournent hors fake-async, cf. `book_parsing_test.dart`).

Attendu (maquette v1.1) : menu ⋯ par carte (Épingler ★ / Dupliquer / Fermer), groupes v2 (hors périmètre v1 du cahier des charges), aperçu réel de carte (thème + position).

### Itération Bibliothèque (décision 6) — faite

**Objectif** : la feuille « Version » de la lecture promet « à télécharger depuis la Bibliothèque », et `library_screen.dart` n'était qu'un `Center` de 18 lignes. C'est le seul cul-de-sac que l'utilisateur peut atteindre. Débloque ensuite la recherche full-text sur versions téléchargées et la comparaison multi-traductions, qui ne peuvent pas commencer avant qu'un fichier existe sur l'appareil.

**Découvertes en sondant l'API getbible** (vérifié en direct, pas supposé) :
- L'id de la Darby est **`darby`**, pas `darbyfr`. `read_repository.dart:49` force `final quirk = t.id == 'darby' ? 'darbyfr' : t.id` → **404 systématique aujourd'hui**. Bug latent jamais vu parce que `ReadRepository` n'est instancié nulle part dans `lib/`.
- Endpoints réels : `v2/<id>.json` (Bible entière), `v2/<id>/<nr>.json` (**un livre**), `v2/<id>/<nr>/<ch>.json` (un chapitre). `v2/<id>/books.json` n'existe pas.
- Poids : `darby.json` = **10,1 Mo** contre **8 Ko** pour Jude par livre — confirme la décision 9 (télécharger par livre, jamais le fichier entier). Un téléchargement complet = **66 requêtes**.
- Schéma d'un livre : `{translation, abbreviation, lang, language, direction, encoding, nr, name, chapters: [{chapter: int, name, verses: [{chapter: "1", verse: "1", name, text}]}]}`. **Attention aux types mixtes** : `chapter` est un `int` au niveau chapitre mais une `String` au niveau verset — parser en tolérant les deux.

**Décision de conception : reprise par livre.** 66 requêtes sur un réseau mobile, une qui échoue en cours de route est le cas normal, pas l'exception. Le registre stocke donc **la liste des livres obtenus** par version, pas un booléen « installé » : un téléchargement mort au livre 40 garde ses 39 fichiers et la reprise ne va chercher que le manquant.

**Étape 1 — `data/library_store.dart` (fait, 10 tests).** Fichiers et registre.
- Un livre = un fichier `<documents>/versions/<code>/<bymIndex>.json` ; le registre `shared_preferences` (clé `library.installed`, JSON `{code: [indexes]}`) dit lesquels sont arrivés (décision 12).
- `InstalledVersion` : `bookCount`, `isComplete`, `isPartial`, `progress` (0..1), `has(book)`.
- API : `installed()`, `versionState(code)`, `missingBooks(code)` (dans l'ordre de lecture — c'est la liste de reprise), `saveBook`, `loadBook`, `remove(code)` (🗑 : fichiers + registre), `sizeOnDisk(code)`.
- **Ordre d'écriture volontaire** : le fichier d'abord, le registre ensuite. Une coupure peut donc laisser un fichier non enregistré (inoffensif : il sera refetché) mais **jamais** un livre enregistré sans fichier, qui se lirait comme installé et planterait à l'ouverture.
- **Racine injectable** `LibraryStore.useRoot(Directory)` / `useAppDirectory()`, sur le modèle de `LocalRepository.useBundle` : `path_provider` répond via canal de plateforme, muet dans la zone fake-async de `testWidgets`.
- Un registre corrompu dégrade vers « rien d'installé » au lieu de lever : les fichiers sont toujours là et retélécharger reste possible — un JSON abîmé ne doit pas condamner l'écran.
- Tests `test/library_store_test.dart` en `test()` réel (le disque est vraiment accessible hors fake-async) sur un `Directory.systemTemp.createTemp`.

**Étape 2 — `data/download_service.dart` (fait, 9 tests).** Les 66 requêtes.
- `install(VersionEntry, onProgress:)` → `DownloadOutcome`. Ne demande que `missingBooks`, donc **relancer = reprendre** ; l'appelant n'a rien à orchestrer.
- Quatre fins possibles (`DownloadStatus`) : `complete`, `failed` (+ `failedBook`), `cancelled`, `unavailable` (pas de source libre, décision 9 — refusé **sans aucune requête**). `outcome.message` porte la phrase du snackbar, française et chiffrée (« Échec sur Lévitique — 2/66 livres conservés »).
- **Tout échec renvoie `null` depuis `_fetchBook`** au lieu de lever : statut ≠ 200, JSON illisible, timeout 20 s, ou **200 avec `chapters` vide** (un livre vide enregistré comme installé serait un trou invisible dans la version). La logique de reprise reste ainsi en un seul endroit.
- `client` et `store` injectables. Tests avec `MockClient` (`package:http/testing.dart`) : reprise après échec au 3ᵉ livre, annulation en vol, corps UTF-8 accentué relu depuis le disque, et le `bookUri` qui traduit **BYM 27 → standard 19** (Psaumes).
- Corrigé au passage : le `darbyfr` de `read_repository.dart`.

**Étape 3 — `screens/library_screen.dart` (fait, 9 tests).** L'écran, 18 lignes → 2 onglets.
- Onglet **Bibles** : `versionCatalog` dans ses trois groupes (mêmes intitulés que la feuille « Version »), chaque ligne = pastille du code + nom + droits + action. Cinq états : intégrée (BYM, ✓ sans bouton) · rien (⬇ Télécharger) · en cours (barre + « 12/66 livres · Genèse » + Annuler) · partielle (↻ **Reprendre** + 🗑) · complète (« 66 livres · 2,5 Mo » + 🗑). Les versions sans source restent grisées, cadenassées, et répondent « bientôt disponible » au tap — même phrase que la feuille « Version ».
- **Reprendre n'est pas une action à part** : c'est le même bouton, la même méthode, seule l'étiquette change. `DownloadService.install` saute déjà les livres présents, donc l'écran n'a aucune reprise à orchestrer.
- **Un seul téléchargement à la fois** (`_activeCode`) : deux versions en parallèle, ce sont 132 requêtes en vol sur un réseau de téléphone. Les autres boutons restent visibles mais inertes plutôt que de disparaître.
- La barre s'affiche **dès le tap**, avant la première réponse (`done` = ce qui est déjà là) : la première requête peut mettre plusieurs secondes et une ligne muette se lit comme un bouton mort. 🗑 passe par une confirmation, y compris sur une version partielle.
- Onglet **Dictionnaires** : vide assumé. Le lexique est dérivé des notes BYM, donc déjà embarqué — mieux vaut l'écrire que d'inventer des entrées qui ne se téléchargeraient nulle part.
- `store` et `service` injectables (même couture qu'aux étapes 1–2) : `test/library_screen_test.dart` sous-classe les deux en mémoire, un `Completer` retient l'install en vol pour observer la barre, et la surface est agrandie (`tester.view.physicalSize`) puisque la `ListView` ne construit que le visible.
- **Reste à câbler** : rien — la feuille « Version » navigue vers la Bibliothèque depuis l'étape 5.

**Étape 4 — lire les versions téléchargées (fait, 14 tests).** `data/version_repository.dart` + `widgets/chapter_reader.dart`.
- `VersionRepository` est **la seule couture de lecture** : `loadBook(code, bymIndex)` sert la BYM par `LocalRepository` et tout autre code par `LibraryStore`. `ChapterReader` n'a plus deux chemins à connaître, il a un code de version en tête d'appel.
- `bookFromGetbible` convertit le JSON getbible vers le modèle de l'app. **Types mixtes assumés** : `chapter` est un int au niveau chapitre mais une String au niveau verset. Le **nom vient du catalogue BYM, pas du JSON** — getbible répond dans la langue de la traduction (« Psalms » pour la KJV) alors que toute la navigation est en français et dans l'ordre BYM (décision 2). La version fournit le texte, pas le vocabulaire. `textWithNotes` = le texte nu : les notes et le lexique sont des fichiers BYM, une traduction téléchargée n'en a aucune.
- **Un livre absent lève `BookNotDownloaded`, il ne retombe pas sur la BYM.** Afficher un texte BYM sous l'étiquette « DBY » serait un mensonge silencieux, invisible pour le lecteur. L'exception remonte jusqu'au `FutureBuilder` et devient un état d'écran à part entière (`_MissingBookPanel` : quel livre, quelle version, et « Lire en BYM » qui marche toujours) — un téléchargement partiel est le cas **normal**, pas une erreur.
- Nuance : les chemins qui n'ont besoin que d'un **compte** de versets (saut au verset, sélecteur) passent par `_activeChapter()`, qui avale l'exception en chapitre vide — le corps de l'écran dit déjà ce qui manque, inutile de le répéter deux fois.
- **Flèches ⏴⏵ calculées sur la BYM** quelle que soit la version lue : le découpage en chapitres est le même d'une traduction protestante à l'autre, et on peut ainsi continuer d'avancer **au-dessus d'un livre non téléchargé** — c'est justement là qu'il faut pouvoir sortir.
- Cache `code|index` des livres parsés (même raison que celui de `LocalRepository` : un chapitre est relu 3–4 fois), avec `forget(code)` quand la Bibliothèque supprime une version — sinon elle resterait lisible en mémoire alors que les fichiers ont disparu.
- Le choix persiste (`AppPreferences.versionCode`), et `_bootstrap()` lit **les préférences avant le livre** : charger la BYM d'abord ferait clignoter la mauvaise traduction pendant une frame. Une version supprimée entre deux lancements retombe sur BYM plutôt que d'ouvrir sur un panneau d'erreur.
- La feuille « Version » **choisit** au lieu d'annoncer : une version avec des livres sur l'appareil est sélectionnable (une partielle aussi, avec « Téléchargée en partie · 1/66 livres »), les autres gardent leur snackbar.
- `store` injectable sur `ChapterReader` (même couture qu'aux étapes 1–3) : `test/reader_version_test.dart` sous-classe `LibraryStore` en mémoire — `installed()` et `loadBook()` suffisent au chemin de lecture — et `test/version_repository_test.dart` fait le vrai disque en `test()`.

**Étape 5 — sortir du cul-de-sac et chercher dans les versions téléchargées (fait, 19 tests).** `reader_actions_bar.dart` + `fulltext_index.dart` + `search_engine.dart` + `search_screen.dart`.

*Navigation.* Le callback `onOpenLibrary` remonte de la ligne de la feuille « Version » jusqu'à `HomeShell`, qui bascule la destination. **Deux points de sortie, volontairement différents** :
- feuille « Version » → un **snackbar avec action « Ouvrir »**, pas un saut immédiat : parcourir la liste des versions ne doit pas éjecter le lecteur de son chapitre ;
- `_MissingBookPanel` → un vrai bouton « Bibliothèque » à côté de « Lire en BYM » : là l'intention de réparer le téléchargement est sans ambiguïté.
- Hors coquille (écran isolé, tests), le callback est nul et le bouton **absent** plutôt que mort.

*Recherche.* `FulltextIndex` passe d'un index statique unique à un **registre par version** (`FulltextIndex.of(code)`, `instance` = la BYM).
- **Question centrale : que veut dire chercher dans une version partielle ?** Réponse retenue : **indexer ce que l'appareil détient** (refuser tant que le 66ᵉ livre n'est pas là rendrait le téléchargement inutile pendant une heure), et **dire ce qui est couvert** plutôt que de laisser croire à une absence. `BookNotDownloaded` est un trou dans la boucle d'indexation, pas un arrêt ; le compte remonte par `FulltextResults.indexedBooks` → `SearchOutcome.coverageNote` → un bandeau `_CoverageNote` au-dessus des résultats. Sans lui, « 3 résultats » se lit « ce mot n'est presque pas dans la Bible » alors qu'il veut dire « pas dans les livres présents ».
- **Deux index téléchargés en mémoire au maximum** (`_maxDownloadedIndexes`), le plus ancien évincé. Chacun pèse ~31 000 versets normalisés : laisser s'empiler toutes les versions essayées croîtrait sans borne. La BYM ne compte jamais dans le plafond — c'est la source par défaut de toute recherche.
- La **carte de référence** (« Jean 3:16 ») retombe sur la BYM quand le livre n'est pas téléchargé, **mais rebadge en `BYM`** : refuser un verset qu'on sait servir serait bête, le servir sous l'étiquette « DBY » serait le mensonge de l'étape 4.
- Le menu « Version » de la recherche n'active que l'indexable hors ligne (BYM, ou une version avec des livres sur l'appareil, partielle comprise) et affiche « Bible Darby · 2/66 livres ». `_loadInstalled()` était rejoué **à chaque recherche** faute de mieux ; l'écran **écoute désormais `LibraryStore.revision`** (voir la règle « Registre de bibliothèque = source unique observable » plus bas) : il apprend un téléchargement ou une suppression au moment où ils arrivent, sans les lier à une frappe au clavier. Une version supprimée qui restait sélectionnée est ramenée à BYM.
- **Supprimer une version purge les deux caches** (`_invalidate` dans `library_screen.dart` : `VersionRepository.forget` + `FulltextIndex.forget`). Oublier l'index seul ne suffit pas — il se reconstruirait depuis les livres que `VersionRepository` garde parsés, et une version effacée du disque continuerait de répondre. Un téléchargement qui complète une version partielle purge aussi, sinon l'index resterait bâti sur les seuls livres d'avant.
- `versions` injectable sur `SearchEngine`, `store` sur `SearchScreen`, `FulltextIndex.useVersions(...)` / `useAmbientVersions()` (même couture qu'aux étapes 1–4) : `test/search_version_test.dart` réutilise le `FakeStore` de `reader_version_test.dart`.

**Bilan** : 103 tests avant l'itération → **167**, `flutter analyze` à zéro. L'itération Bibliothèque est bouclée de bout en bout : télécharger → lire → chercher → supprimer. Reste ouvert : la **comparaison multi-traductions** (deux versions côte à côte), désormais débloquée puisque plusieurs textes cohabitent sur l'appareil.

## Correspondance des livres BYM ↔ numéros standard (getbible/ordre 1-66)

L'ordre des fichiers BYM (01–66) correspond à l'ordre « canon hébraïque » pour l'AT, puis NT dans l'ordre standard.
- Psaumes = 19, Proverbes = 20, Job = 18 (ex.)… **Nécessite une table de mapping explicite** dans `book_mapping.dart` (BYM ↔ index numérique utilisé par l'API getbible), to reconstruct during implementation.
- getbible utilise des nombres de livres standards. Trois granularités, toutes vérifiées en direct : chapitre `v2/<id>/<book_nr>/<chapter>.json`, **livre `v2/<id>/<book_nr>.json`**, Bible entière `v2/<id>.json`. `v2/<id>/books.json` n'existe pas (404).
- Fichier entier = 10,1 Mo (mesuré sur `darby.json`) contre 8 Ko pour un petit livre : le téléchargement se fait **par livre**, 66 requêtes (décision 9).

## API / sources en ligne

- **getbible.net** : gratuit, sans clé, CORS. Français : **`ls1910`, `darby`, `martin`** — ce sont les ids exacts de `v2/checksum.json`, qui liste toutes les traductions servies. ⚠️ `darbyfr` **n'existe pas** (404) : `read_repository.dart` le force encore, à corriger.
- **bible-api.com** : écarté (aucune traduction française).
- **bolls.life** : candidat pour du texte FR riche tagué Strong (à vérifier à l'implémentation).

## Actions en attente

- [x] Créer le projet Flutter `bible_app/`, copier `bym_json/` dans `assets/bible/bym/` et les 10 fonds (GIF→PNG via System.Drawing) dans `assets/themes/`.
- [x] Socle lecture + feuille d'étude (v4/v5) + lexique v8 (voir « Avancement »).
- [x] **Système d'onglets façon Chrome** (barre, compteur, sélecteur de cartes, « Fermés récemment », duplication, épingle) — implémenté, test d'intégration `test/reader_tab_test.dart` **stabilisé**.
- [x] **Accueil à la Chrome + nav à 5** (Accueil · Lecture · Recherche · Bibliothèque · Réglages) — câblé dans `main.dart` : `HomeShell` possède un `TabManager` unique partagé (compteur doré synchronisé avec les onglets), `HomeScreen` (`screens/home_screen.dart`, enum `BymDestination`) et `SearchScreen` (`screens/search_screen.dart`, refs + livres) sont branchés ; Thèmes retiré de la nav basse (accessible depuis l'Accueil). Correctif overflow du chip raccourcis dans `home_screen.dart`.
- [x] **Recherche plein texte BYM (offline)** — `data/fulltext_index.dart` (index en mémoire sur les 66 livres, construit paresseusement, insensible aux accents/casse), `SearchScreen` enrichi d'une section « Résultats dans le texte » (debounce 300 ms, surlignage or du terme, cap 60) ; un résultat ouvre l'onglet Lecture **et saute au verset** (notifier `VerseTarget` → `ChapterReader` scroll + flash doré 900 ms). Tests : `test/fulltext_search_test.dart` (pur `test()`, ≥ 30 000 versets indexés) + `test/search_screen_test.dart` (FakeBibleBundle). Total : **51 tests**, `flutter analyze` à zéro. Bandeau DEBUG retiré (`debugShowCheckedModeBanner: false`).
- [x] **Barre d'actions de lecture (maquette `modif/3boutons.jpg`)** — `widgets/reader_actions_bar.dart` : 3 boutons en haut de la lecture (📖 **Livres** → navigation `BooksScreen`/`ChapterListScreen`, **Version** → bottom sheet des traductions, ⬇⬇ **Versets** → bottom sheet des versets du chapitre courant avec saut/flash). **0 onglet** : la barre s'affiche au-dessus du listing livres (Versets désactivé) ; **≥1 onglet** : en haut du texte dans `ChapterReader` (`onOpenChapter` → `manager.openReading`). Tests : `test/reader_actions_test.dart`. Total : **55 tests**, `flutter analyze` à zéro.
- [x] **Épuration de l'état vide (0 onglet)** — la pilule « Livres » ouvre désormais un bottom sheet (accordéon des 5 sections + grilles de chapitres en ligne) qui **remplace** l'ancien listing plein écran ; `BooksScreen` est sorti de ce flux. Dans la foulée, `_NewTabHome` (`screens/reader_screen.dart`) **n'a plus d'`AppBar`** : la `ReaderActionsBar` (dans un `SafeArea`) est la seule surface de navigation quand aucun onglet n'est ouvert. Le bouton « Nouvel onglet » de cette AppBar faisait doublon avec le ＋ de `TabStrip`, et le titre « BYM » avec la pilule de version juste en dessous. L'onglet accueil `_HomeTab`, lui, **garde son AppBar**. Test mis à jour : `reader_tab_test.dart` attend `find.byType(AppBar), findsNothing` sur l'état vide. Total : **62 tests**, `flutter analyze` à zéro.
- [x] **Contrôle de la taille du texte** — 6 crans dans le menu ⋯ (`_DisplayMenu`, `widgets/chapter_reader.dart`), présentés sous un séparateur comme une **rangée compacte de pastilles « A »** (`_TextSizeRow` / `_SizeChip`, titrée « Taille du texte »), chacune dessinée à la taille qu'elle sélectionne (plafonnée à 24 pt) et étiquetée pour les lecteurs d'écran. Six entrées de menu pleine hauteur avaient été essayées d'abord : elles poussaient la plus grande taille à 709 px sur un écran de 600, soit hors écran — exactement l'option que les lecteurs qui en ont besoin auraient dû aller chercher en scrollant. Un test garde cette contrainte (`getBottomLeft(...).dy < hauteur d'écran`). Enum `ReadingTextSize` (`data/app_preferences.dart`) : `small 14`, `medium 16`, `large 19`, `extraLarge 22`, `huge 26`, `giant 30` (les deux derniers pour les vues fatiguées : 30 pt ≈ le double du corps par défaut), + `ReadingTextSize.nearest(double)` pour cocher le cran courant à partir de la valeur stockée. **Le défaut de `AppPreferences.fontSize` passe de 19.0 à 16.0** (`ReadingTextSize.medium`) : 19 était une valeur dormante jamais lue par le rendu, et 16 est le `bodyLarge` Material que le lecteur affichait réellement — « moyen » reproduit donc l'apparence d'avant. Application : `ChapterVerseList` (`widgets/verse_tile.dart`) enveloppe sa `ListView` dans un `Theme` qui met `bodyLarge` à la taille choisie **et multiplie `bodySmall` (numéro de verset) et `titleMedium` (intertitres) par le même ratio** — un corps à 30 pt à côté d'un numéro resté à 12 pt se lit comme un bug. Dans `VerseTile`, le ✦ et les icônes étoile/note, jadis à 11 et 14 pt en dur, sont exprimés en ratios de `bodySmall` et suivent. Un seul point d'insertion, et **le `textScaler` d'accessibilité de l'OS reste actif** (contrairement à l'option `MediaQuery(textScaler:)` envisagée). Idem pour `note_aware_text.dart` : exposant, note en ligne et carte de note sont des ratios du corps via `_noteScaled(body, factor)` (.56 / .81 / .78). Persistance inchangée (clé `reading.fontSize`). Tests : `reader_actions_test.dart` — défaut à 16, choix « grand » → 19 conservé après remontage, présence des 6 pastilles, « géant » → 30 avec le numéro de verset au même ratio, et ladder entièrement visible sans scroll.
- [x] **Navigation chapitre précédent / suivant + pilule « Livres » in-place** — deux besoins qui partagent le même code, livrés ensemble. **(a)** `TabManager.replaceActiveReading(int bookIndex, int chapter)` (`data/tab_manager.dart`) reconstruit un `StudyTab` en place (`copyWith` ne peut pas changer `bookIndex`/`chapter`), **conserve l'`id` et le drapeau `pinned`** (c'est le même onglet, déplacé), fait `history.record` + `_persist()` + `notifyListeners()`, et retombe sur `openReading` si aucun onglet n'est actif. Un onglet accueil devient un onglet lecture. **(b)** Dans `screens/reader_screen.dart`, le `onOpenChapter` **de tout onglet** (lecture *et* accueil `_HomeTab`) appelle désormais `replaceActiveReading` : la pilule « Livres » et les flèches déplacent l'onglet courant au lieu d'en ouvrir un, et l'onglet vide « Nouvel onglet » créé par le ＋ **se remplit lui-même** au lieu de rester en plan pendant que le livre s'ouvre ailleurs (comportement d'un onglet vierge Chrome où l'on tape une URL). Seul `_NewTabHome` (état 0 onglet, rien à remplacer) garde `openReading`. Le ＋ de `TabStrip` (`openHome`) reste le **seul** créateur d'onglet ; `openReading` sert aux ouvertures depuis l'écran Accueil et la recherche. **(c)** `LocalRepository.previousChapter` / `nextChapter` renvoient un `Future<(int book, int chapter)?>` (records Dart 3) : ± 1 dans le livre, sinon traversée vers le livre voisin via `chapterCount`, `null` aux bornes (Ge. 1 / dernier chapitre d'Apocalypse). `ChapterReader` les précharge dans `initState` ; `ReaderActionsBar` reçoit `onPreviousChapter` / `onNextChapter` (deux `IconButton` `chevron_left` / `chevron_right` après le `Spacer`), `null` = flèche grisée. Ordre BYM à 5 sections (décision 2) respecté. Tests : `tab_manager_test.dart` (4 cas : déplacement sans création, épingle + accueil→lecture, aucun onglet actif, chapitre déjà ouvert ailleurs), `reader_tab_test.dart` (pilule et flèches in-place : `count` reste à 1, `id` inchangé), `reader_actions_test.dart` (bornes, traversée de livre dans les deux sens, flèches grisées sans onglet). Total : **73 tests**, `flutter analyze` à zéro.
- [x] **Catalogue des versions** — `data/version_catalog.dart` : trois états réels, **embedded** (BYM, décision 3, + **LSGS**, le texte Segond 1910 avec codes Strong, décision 10) ; **downloadable** (les traductions du domaine public réellement servables via getbible.net — ls1910, Darby, Martin, KJV, décision 9) ; **unavailable** (sous droits ou sans source : NBS, NEG79, NVS78P, S21, INT, KJF). Le JSON ls1910 de getbible ne porte pas les numéros Strong (décision 9), d'où le corpus LSGS embarqué construit séparément (voir § LSGS). **Axe indépendant : `VersionFormat`** (`bym` / `getbible`, défaut `getbible`) — le schéma que portent les fichiers, distinct de l'endroit où ils vivent ; `VersionRepository.loadBook` y choisit son parseur, et `carriesNotes` en découle. Le catalogue entier est affiché **dans la Bibliothèque** (5 états, cadenas, ⬇ / ↻ / 🗑) ; la feuille « Version » de la lecture et le menu « Version » de la recherche, eux, ne listent que ce qui est lisible — voir les entrées suivantes.
- [x] **La feuille « Version » ne liste que les versions installées** — BYM (embarquée) + ce que `LibraryStore.installed()` porte, groupé comme la maquette `modif/resultat_vers_les_versions.jpg` (Version intégrée · Versions Louis Segond · Autres versions) ; un groupe vidé de ses lignes disparaît avec son intertitre. Auparavant les 12 entrées du catalogue y figuraient, grisées, et répondaient « à télécharger depuis la Bibliothèque » ou « bientôt disponible » au tap : onze lignes intappables dans une feuille dont le seul rôle est de **choisir**, et un second endroit où les téléchargements étaient à moitié gérés. Choisir une version appartient à la feuille, en obtenir une appartient à la Bibliothèque. Ce qui manque reste atteignable par une **ligne de pied** `_LibraryFooter` (« Bibliothèque · N autres versions à télécharger ») qui ferme la feuille et bascule sur l'onglet ; sans `onOpenLibrary` (usage autonome) la ligne nomme la Bibliothèque sans être cliquable, plutôt que d'être un bouton mort. Conséquences dans `_VersionRow` : plus de `onOpenLibrary`, plus de `_readable`, plus d'état grisé (`VersionAvailability.unavailable` ne peut plus apparaître ici), et `_select` se réduit à « bascule, ou dit qu'il n'y a pas de chapitre à basculer ». Tests : `reader_actions_test.dart`, `reader_version_test.dart`, `home_tab_version_test.dart`. **Le menu Version de la recherche a reçu le même traitement** — voir l'entrée « Recherche unifiée v2 ».
- [x] **Recherche unifiée v2 (captures `rech/`)** — un champ interroge toutes les sources d'un coup et **groupe les résultats par catégorie**. Moteur extrait dans `data/search_engine.dart` (l'écran ne fait plus que de l'affichage), `screens/search_screen.dart` refondu (~1175 l.).
  - **7 familles** (`SearchCategory`) : Passages · Notes · Liens · Études · Strong · Dictionnaire · Nave. Deux n'ont **aucune source** dans l'app (`available == false` : Liens, Nave) : leurs puces restent affichées pour coller au design mais sont grisées et expliquent leur absence en snackbar (`unavailableReason`) au lieu de basculer. `SearchCategory.searchable` = les 5 réellement câblées, et une catégorie indisponible n'est **jamais** interrogée même si on la passe explicitement.
  - **Sources**, une par famille disponible : Passages → `FulltextIndex` (66 livres embarqués) · Notes → table `notes` de `AppDatabase` · Études → `ReadingHistory` (les chapitres déjà ouverts, faute d'études rédigées) · Strong → `StrongLexicon` (les définitions FR+Strong, code ou mot) · Dictionnaire → `LexiconIndex` (ancres de notes BYM). Interrogées **en parallèle** (`Future.wait`), avec l'échec **avalé par source** : pas de base (premier lancement, tests widget) ⇒ les passages et le dictionnaire passent quand même.
  - **Filtres** `SearchFilters` (Version · Section · Livre · Ordre) : `allows(book)` où `bookIndex` gagne sur `sectionIndex` ; `copyWith` prend `clearSection` / `clearBook` parce que passer `null` ne peut pas distinguer « inchangé » de « remettre à Tout ». « Livre » ouvre une feuille scrollable (66 entrées + Tout, groupées par les 5 sections de la décision 2) là où les trois autres tiennent dans un `PopupMenu`.
  - **Le menu « Version » ne liste que le cherchable** — BYM + ce que `LibraryStore.installed()` porte, aligné sur la feuille de lecture. Il affichait les 12 entrées, dix grisées répondant « à télécharger depuis la Bibliothèque pour la chercher hors ligne » : `_FilterOption` a donc perdu `enabled` / `disabledReason`, et `_FilterMenu` son `Opacity` et son snackbar. Le reste reste atteignable par un `_FilterFooter` (« Bibliothèque · N autres versions à télécharger ») que `SearchScreen.onOpenLibrary` — câblé depuis `main.dart` — branche sur l'onglet. **Ce pied ne sélectionne pas** : son `PopupMenuItem` ne porte pas de `value`, seulement un `onTap`, sinon le taper changerait la version filtrée en sortant. Sans `onOpenLibrary` (tests, usage isolé) la ligne énonce le fait. Un téléchargement partiel reste listé avec sa couverture (« Bible Darby · 2/66 livres »), qui explique une liste de résultats courte.
  - **Pagination** : `pageSize = 5` lignes par groupe, chip « Voir plus » dès que `total > hits.length` (le badge du en-tête montre le total **non tronqué**), `sourceLimit = 60` par source, `minQueryLength = 2`, debounce 300 ms. `SearchOutcome.query` garde contre un résultat asynchrone périmé qui écraserait un plus récent.
  - **Carte de référence** : une requête qui se lit comme une référence (« Jean 3:16 », « Psaume 23 ») est résolue en verset et imprimée **au-dessus** des groupes. Un nom de livre nu (« psaumes ») ne qualifie **pas** : sinon toute recherche de mot ressemblant à un livre pousserait une carte devant ses propres résultats. Une référence hors filtres, ou vers un verset inexistant, est abandonnée.
  - **État vide** : 5 groupes de requêtes-exemples cliquables, dont « Chercher un mot Strong » (H0430, G2316, agapao).
  - **Deux coutures de test** que le code de production porte exprès. (a) `SearchScreen` accepte un `engine` injectable et `SearchEngine` un drapeau `ambientDatabase` : `AppDatabase.instance` ouvre via path_provider, dont le canal de plateforme ne répond **jamais** dans la zone fake-async de `testWidgets` — le futur reste pendu au lieu de lever, `_searching` reste vrai, et le `LinearProgressIndicator` indéterminé programme des frames à l'infini (9 tests en timeout avant le correctif). Les tests widget passent `ambientDatabase: false`. (b) `categoryRowKey` / `resultListKey` : la rangée de puces et la liste de résultats sont paresseuses, donc les tests doivent les scroller pour atteindre la 7ᵉ puce et les dernières lignes — et un `TextField` possède **son propre** scrollable horizontal, donc les désigner par axe ne suffit pas.
  - Tests : `search_engine_test.dart` (21 cas : filtres, disponibilité, groupage, pagination, références) + `search_screen_test.dart` (11 cas, `FakeBibleBundle` + moteur sans base).
- [x] **Saut au verset : les versets lointains** — deux symptômes, **un seul défaut**. « Jean 3:16 » depuis la recherche ouvrait Jean 3 sans jamais descendre au verset, et le sélecteur ⬇⬇ ne fonctionnait que pour les versets déjà collés à l'écran. Cause : `ChapterVerseList` est une `ListView.builder` paresseuse et la `GlobalKey` de saut n'est posée **que** sur le verset visé (`widgets/verse_tile.dart`) ; au-delà du *cache extent* la tuile n'est jamais construite, `currentContext` est nul, `Scrollable.ensureVisible` n'a rien à viser et le saut s'annulait **en silence**. Correctif dans `widgets/chapter_reader.dart` : `_scrollToTarget` pilote d'abord la liste vers l'offset **estimé** du verset (`maxScrollExtent × itemIndex/(itemCount-1)`) — estimation qu'une liste paresseuse affine à mesure qu'elle mesure des tuiles, d'où la **boucle de convergence** (12 essais max, `await endOfFrame` entre chacun) qui s'arrête dès que `_jumpKey.currentContext` existe ; `ensureVisible` fait alors le placement fin (350 ms). Le flash doré de 900 ms n'est armé **qu'une fois le verset atteint** : un timer lancé au départ détacherait la clé en plein scroll sur un long chapitre. L'index du verset se calcule par une boucle sur son numéro et non un `indexOf` (comparaison d'identité, et quadratique). Les deux chemins d'entrée (résultat de recherche, sélecteur de versets) passent par le même `_beginJump`. Effet de bord corrigé dans `main.dart` : sans verset demandé, `_jumpToVerse` est **remis à null** — la cible périmée était sinon rejouée par le chapitre suivant ouvert à neuf, `ChapterReader` lisant la valeur courante dans `initState`. Tests : `reader_actions_test.dart` (60 versets, saut au 55 — on vérifie que la tuile est **dans le viewport**, pas seulement construite dans le cache extent) et `search_engine_test.dart` (Jean 3:16 conserve le verset 16). Total : **103 tests**, `flutter analyze` à zéro.
- [ ] **Plages de références** (dette) — `splitReference` (`data/reference_parser.dart`) ne lit qu'un `chapitre[:verset]` en fin de requête (`_trailingNumbers`) : « Exode 4:5-10 » ne matche pas, retombe en recherche de livre et ne renvoie **rien**. La puce d'exemple de la maquette a été ramenée à « Exode 4:5 » en attendant. Ajouter les plages = étendre le regex **et** décider ce qu'affiche la carte de référence pour une plage (le premier verset ? les N versets ?).
- [x] **Recherche Strong câblée** — `SearchCategory.strong` passe d'indisponible à cherchable : la source `StrongLexicon` répond à un code (« H0430 » → sa définition) ou à un mot français (« père » → les définitions qui le mentionnent). **Classement corrigé** : un mot courant renvoyait les 50 premières entrées toutes grecques (ordre lexicographique `G… < H…`) ; désormais exact > préfixe > sous-chaîne du code > définition, puis **position de la correspondance** et hébreu avant grec (`strong_lexicon.dart`). Couture de test : `StrongLexicon.useBundle` / `useRootBundle` (même find que `LocalRepository`), faux lexique dans `test/support/fake_strong_lexicon_bundle.dart`, installé dans les `testWidgets` qui interrogent le moteur (`search_screen_test.dart`, `search_version_test.dart`). Tests : `strong_lexicon_test.dart` (6 cas), `search_engine_test.dart` + `search_screen_test.dart` mis à jour (Nave reste l'indisponible de référence).
- [ ] **`SearchCategory.nave`** (dette) — index thématique sans aucune source identifiée à ce jour, contrairement à Liens qui a une piste. Décider : le laisser grisé indéfiniment, ou le retirer de la rangée de puces.
- [x] Recherche full-text sur les **versions téléchargées** — un index plein texte par version (`FulltextIndex.of(code)`), qui indexe ce que l'appareil détient et annonce sa couverture (`SearchFilters.versionCode` route l'index à interroger). Détail dans « Itération Bibliothèque » (étape 5) ci-dessus.
- [ ] Comparaison multi-traductions.
- [x] **Audio retiré (décision 2026-08)** — le squelette audio de Copilot ne produisait que « Audio non disponible » : suppression de `audioplayers`, du bouton « Écouter », de `audioUrl` et des marques 🔊 du catalogue (`hasAudio`). L'entrée de la feuille d'étude reste un stub « bientôt disponible ».
- [ ] Partage d'image.
- [x] **Bibliothèque à la demande** — `data/library_store.dart` + `data/download_service.dart` + `screens/library_screen.dart` + `data/version_repository.dart` (61 tests). Téléchargement réel par livre depuis getbible (66 requêtes, jamais le fichier entier de 10 Mo), registre des livres obtenus, reprise après coupure, suppression, **lecture** (la feuille « Version » choisit une version téléchargée, un livre manquant le dit au lieu de servir la BYM sous une autre étiquette) **et recherche** (un index plein texte par version, qui indexe ce que l'appareil détient et annonce sa couverture). Fait avec `http` et non `dio` : `read_repository.dart` utilisait déjà `http` et `dio` n'était importé nulle part — une seule pile HTTP, et `MockClient` donne la couture de test. Détail dans « Itération Bibliothèque » plus haut.
- [ ] Export / synchronisation.
- [x] Rechercher et valider une **source Française + Strong** — retenue : CrossWire/SWORD `FreStrongsHebrew` + `FreStrongsGreek`, converties en `assets/lexicon/strong_fr.json` (14 195 définitions, `appCodebar/sword_zld_to_json.py`). Voir `bible_app/plan-strong-fr.md`.
- [ ] Publier (à la main, console Filebase) les dictionnaires/versions propres quand le contenu sera prêt.

## Notes utiles pour travailler

- Outillage : cette machine est Windows. Le shell peut être PowerShell 5.1 **ou** Git Bash selon la session — vérifier avant d'écrire des commandes (`rm -f` vs `Remove-Item`, `/dev/null` vs `$null`). Dans les deux cas, mettre les chemins entre guillemets.
- **Nom de dossier accentué** : la source des fonds s'appelle `thème/` (accent `é`). Si des outils ou scripts échouent à trouver ce dossier, le chemin en dur est `C:\Users\laptek\Desktop\bym3\thème` ; utiliser `-LiteralPath` (ou `Get-ChildItem -LiteralPath`/`Test-Path -LiteralPath`) plutôt qu'un chemin global avec wildcards. Au moment du copier dans `assets/themes/`, renommer en ASCII (`themes`).
- Les JSON BYM sont en UTF-8 ; ne pas les réécrire en changeant l'encodage.
- `flutter analyze` + `flutter test` avant de considérer une tâche terminée.
- **Travailler dans `bible_app/`** (workdir), jamais à la racine du repo.
- **Tests SQLite** : utilisent `sqflite_common_ffi` (factory FFI) + `useInMemory()` ; requêtes SQL → utiliser des `?` placeholders, jamais de guillemets doubles (`text != ?`).
- Ne jamais embarquer de secret Filebase dans l'app (lecture seule via URLs publiques).
- Ne pas modifier/committer la source `bym_json/` inutilement ; l'app exploite une copie dans `assets/`.

## À faire / points d'attention (reprise)

- **Registre de bibliothèque = source unique observable.** `LibraryStore.revision` est un `ValueNotifier<int>` **statique** que `saveBook` et `remove` incrémentent. Tout écran qui dépend de ce qui est installé doit l'**écouter**, jamais copier `installed()` dans un champ au `initState`. Raison : les écrans vivent dans l'`IndexedStack` du shell d'onglets, donc `initState` ne rejoue pas quand on revient de la Bibliothèque — la copie reste périmée, la feuille « Version » répond « à télécharger » pour une version présente, et l'utilisateur fait la navette entre les deux écrans sans fin. Le lecteur (`chapter_reader.dart`) s'y abonne et, sur signal, revalide la version courante (repli sur BYM si elle a été supprimée) et recharge le livre **seulement** s'il vient d'arriver — un téléchargement complet émet 66 signaux, relire le disque à chacun est inutile.
  - **Corollaire : `installedVersions` n'a pas de défaut acceptable.** `ReaderActionsBar` le laisse à `const {}`, et les deux pages d'accueil d'onglet prenaient ce défaut — la feuille lisait *toute* version téléchargée comme absente et renvoyait à la Bibliothèque chercher ce qui était déjà là. `_HomeActionsBar` (`reader_screen.dart`) porte maintenant cet état, écoute la révision comme le lecteur, et **enregistre** la version choisie dans `reading.versionCode` : sans chapitre à basculer, le sens du geste est « la prochaine lecture sera dans cette version », ce que `ChapterReader._bootstrap` relit. Couvert par `test/home_tab_version_test.dart`. `installed()` ne lit que shared_preferences (pas de `dart:io`) — c'est ce qui rend ces tests possibles sous `testWidgets` là où `loadBook` bloquerait. Depuis que la feuille filtre sur ce registre, ce défaut ne dégrade plus le message mais **la liste** : une carte vide laisserait une feuille à une seule ligne, BYM.
- **Les feuilles doivent rendre l'encoche système.** Elles sont dimensionnées en fraction de l'écran (`MediaQuery.sizeOf(...).height * .8`), barre de gestes Android comprise : avec une marge basse fixe, la dernière ligne (le pied « Bibliothèque » dans « Version », la dernière tuile de chapitre dans « Livres ») était dessinée **sous** la barre et intappable. Utiliser `sheetBottomInset(context)` (`reader_actions_bar.dart`) = `24 + MediaQuery.viewPaddingOf(context).bottom`. `viewPadding` et non `padding` : dans une feuille, `padding` est déjà consommé par la route et vaut 0.
- **Deux axes à ne plus confondre : `availability` et `format`.** *Où* vit le fichier (assets embarqués / `<documents>/versions/<code>/<n>.json`) et *quel* schéma il porte sont indépendants ; la BYM les confondait, étant seule à porter le format riche. `VersionEntry.format` (`VersionFormat.bym` / `.getbible`, défaut `.getbible`) tranche la seconde question, et `VersionRepository.loadBook` choisit son parseur dessus : `BibleBook.fromJson` ou `bookFromGetbible`. Conséquence : une version au **format BYM téléchargée** d'ailleurs garde son en-tête, ses sections et ses notes — c'est ce qui rend possible d'héberger un second texte BYM sans le mettre dans l'APK. Le défaut est volontairement le schéma **pauvre** : un code inconnu doit lire du texte nu, pas chercher des champs absents. `carriesNotes` (= format BYM) est le seul prédicat que l'interface doit interroger ; ne pas retomber sur `code == 'BYM'`.
- **L'en-tête de livre et les notes suivent le format, pas le code.** `bookFromGetbible` laisse `metadata` et `introduction` vides, recopie le texte nu dans `textWithNotes` et laisse `notes` vide : getbible ne sert que du texte. D'où deux gardes dans `chapter_reader.dart`, tous deux adossés à `versionByCode(_versionCode)?.carriesNotes` :
  - `_showsBookHeader` — sinon on rend un titre au-dessus de quatre cellules vides sous une mention « Traduction BYM » mensongère. Attention : `itemCount` et `_scrollToTarget` comptent tous deux cet en-tête, la condition doit passer par ce getter unique sans quoi le saut au verset se décale d'un cran.
  - `_supportsNotes` — « Texte + notes » basculait entre deux rendus identiques et les deux dispositions ne commandaient rien. Il verrouille `showNotes: _prefs.notesMode && _supportsNotes` sur `ChapterVerseList` et `notesAvailable` sur `_DisplayMenu`, dont l'`itemBuilder` remplace alors les quatre entrées de notes par **une** ligne désactivée « Notes — BYM uniquement » (l'échelle de taille reste : elle ne parle pas de notes).

  Deux choix à ne pas défaire : (1) garde d'**affichage**, jamais d'écriture dans `reading.notesMode` — sinon un aller-retour par une version téléchargée coûte son réglage au lecteur ; (2) une ligne qui s'explique plutôt que cinq grisées, même critique que pour la feuille « Version ». Couvert par le groupe « the notes menu » de `test/reader_version_test.dart`. Le bouton Lexique de la feuille d'étude se désactive déjà seul : il teste `verse.notes.isNotEmpty`.
- **Un menu de choix ne liste que ce qui est choisissable.** Vaut pour la feuille « Version » de la lecture **et** pour le menu « Version » de la recherche (`_FilterBar`) : les deux affichaient les douze entrées du catalogue, dix d'entre elles grisées répondant par un snackbar « à télécharger » ou « bientôt disponible ». Filtrer sur `version.embedded || installed[code]?.isEmpty == false`, puis fermer la liste par un `_FilterFooter` / une ligne de pied « Bibliothèque · N autres versions à télécharger » — sans quoi rien sur l'écran ne dit que les autres traductions existent. Ce pied **ne sélectionne pas** : son `PopupMenuItem` ne porte pas de valeur, seulement un `onTap`, sinon taper « Bibliothèque » changerait le filtre au passage. `onOpenLibrary` nul (écran isolé, tests) → la ligne énonce le fait sans prétendre être un bouton. Le catalogue entier reste affiché **dans la Bibliothèque**, dont c'est le métier.
- **La source des données est le markdown, pas le JSON.** `appCodebar/` porte `bym_md/` (66 fichiers) et `md_to_json.py` (Python 3.12, stdlib seule) ; `bym_json/` en est la sortie, régénérable par `python md_to_json.py`, et donc **ignorée par git** dans `appCodebar/` — les mêmes 9,3 Mo existent déjà dans `bym_json/` à la racine et dans `bible_app/assets/bible/bym/`. Corriger un verset = corriger le `.md` et relancer le script, jamais éditer le JSON à la main. Invariants vérifiés par le script : 66 livres, 31 169 versets, et `text[position : position+len(word)] == word` pour chaque note. `section` n'est présent que sur le **premier verset** suivant un titre `###` (choix utilisateur, ne pas changer sans demander) ; `textWithNotes` et `notes` seulement sur les versets qui ont des notes. Voir `appCodebar/CLAUDE.md` pour la grammaire markdown complète.
- **Règle de test** : tout `testWidgets` qui rend un écran lisant un livre doit installer `LocalRepository.useBundle(FakeBibleBundle())` (`test/support/fake_bible_bundle.dart`) et restaurer `LocalRepository.useRootBundle()` en `tearDown`. Lire les assets réels sous `testWidgets` = `pumpAndSettle` bloqué à l'infini.
- **Corollaire path_provider** : même piège pour `AppDatabase.instance` (SQLite s'ouvre via path_provider). Un `testWidgets` qui construit un `SearchEngine` doit passer `ambientDatabase: false`, sinon le futur reste pendu — il ne lève pas, il ne répond jamais. Symptôme trompeur : le timeout est signalé sur le `pumpAndSettle`, pas sur la base.
- **`pumpAndSettle` n'attend pas une chaîne `await`** : il rend la main dès qu'aucune frame n'est programmée, ce qui arrive **entre** deux `await` d'une même fonction asynchrone. Pour un enchaînement comme le saut au verset (délai → chargement → convergence), pomper explicitement (`for (var i = 0; i < 20; i++) await tester.pump(const Duration(milliseconds: 60));`) avant le `pumpAndSettle` final.
- **Widgets paresseux dans les tests** : une `ListView`/`SingleChildScrollView` ne construit pas ce qui est hors du cache extent — un `find` sur un élément lointain renvoie 0 sans que rien ne soit cassé. Scroller d'abord (`scrollUntilVisible` + un `pumpAndSettle` derrière, car son `ensureVisible` final ne se matérialise qu'à la frame suivante), et cibler le scrollable par une `Key` de production : un `TextField` embarque son propre scrollable et le choix par axe attrape le mauvais.
- Vérifier que `flutter analyze` reste à zéro après toute modification.
- L'ordre d'exécution avant validation : `flutter analyze`, puis `flutter test` (l'exécution globale passe désormais en ~5 s ; plus besoin de lancer fichier par fichier).
