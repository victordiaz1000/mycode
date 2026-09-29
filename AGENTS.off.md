# AGENTS.md — Projet BYM (App de Bible Flutter)

> **État vérifié le 2026-09-29.** `flutter analyze` : **No issues found** (29 s). `flutter test` : **739 tests verts** en **~3 min 40**. 76 fichiers de test + 4 faux bundles dans `test/support/`. 90 fichiers Dart dans `lib/` (8 models · 34 data · 22 screens · 23 widgets · 2 utils · `main.dart`). Dépôt sous git à la racine `bym3/` (`build/`, `.dart_tool/`, `android/.gradle` exclus). Le lot du 29/09 est en 7 commits (`250b39b`…`ce1fd9c`) ; ce qui reste du registre premium est listé dans `TODO.md`.
>
> **Ce document décrit l'état courant, pas une chronologie.** Il est réorganisé par domaine : une décision est écrite une fois, à sa place, avec sa raison. Les journaux d'itération (« étape 1, étape 2, c'est fait ») ont été retirés — ils sont la raison pour laquelle ce fichier était en retard. **Ne pas y ajouter de récit : ajouter ou corriger une règle.**

## Documents canoniques

| Fichier | Domaine | Quand le lire |
|---|---|---|
| `MAJ_TEXTE_BYM.md` | Le texte BYM : source amont, empreintes, mise à jour dans l'app | **Avant toute correction du texte BYM.** Phrases déclencheuses : `mets à jour le texte BYM`, `synchronise avec GitLab` |
| `regles-liens-references-bibliques.md` | Contrat de la liaison des références dans les notes | Avant de toucher `note_reference_linker.dart` |
| `abbreviations.txt` | Source de vérité des abréviations **des notes** (≠ `book_catalog.dart`) | Avant de toucher au parseur de références |
| `appCodebar/CLAUDE.md` | Grammaire markdown BYM + chaîne des corpus hébergés (CHO, KJF) | Avant de toucher à `md_to_json.py`, `bym_markdown_converter.dart` ou `html_verses_to_json.py` |
| `bible_app/plan-strong-fr.md` | Origine du lexique Strong FR | ⚠️ **partiellement périmé** (cite des écrans supprimés) |
| `TODO.md` | Ce qui reste du registre premium (Favoris, Notes, Comparer, feuille d'étude) et les tests qui le verrouillent | Avant de reprendre le restyle |

## Vue d'ensemble

Application **mobile Flutter** de Bible nommée **BYM — Bible de Yehoshoua Ha Mashiah**.
- Texte principal **BYM**, embarqué dans l'APK (66 livres, hors ligne), **corrigible sans republier l'app** (§ 1).
- **15 versions** au catalogue : 2 embarquées, 7 téléchargeables, 5 sous droits.
- **6 dictionnaires / lexiques** : 4 embarqués, 1 téléchargeable, 1 indisponible.
- **14 thèmes** nommés + un fond photo choisi par le lecteur.
- Persistance : SQLite (`sqflite`) pour les annotations, `shared_preferences` pour les préférences et les registres.
- Flutter 3.44.1 · Dart 3.12.1 · Android + iOS.

### Dépendances réelles

`http` (seule pile HTTP) · `sqflite` · `shared_preferences` · `path_provider` · `path` · `crypto` (empreintes SHA-1) · `share_plus` · `image_picker` (fond de thème uniquement).
**`dio` et `provider` sont déclarés dans `pubspec.yaml` mais importés nulle part** — supprimables. `assets/fonts/` n'est **pas** listé dans `assets:` (la section `fonts:` l'embarque déjà) ; `assets/brand/` **n'existe plus** (voir § 7, « Périmés »).

---

## 1. Le texte BYM

> Détail complet dans **`MAJ_TEXTE_BYM.md`**. Résumé des invariants qu'il faut avoir en tête ailleurs.

- **Source de vérité** : `appCodebar/bym_md/` (66 `.md`, 5,1 Mo), **miroir** du dépôt public GitLab `anjc/bjc-source`, branche `master`. Le dépôt est la source de production, pas une copie de confort.
- **Une seule commande** : `python appCodebar/sync_bym_source.py [--dry-run|--all]`. Elle enchaîne commit → arbre → diff → téléchargement épinglé au sha → conversion → `_source.json`. `--dry-run` d'abord, toujours.
- **Le JSON ne s'édite jamais à la main.** Corriger un verset = corriger le `.md` amont et relancer le script.
- `bible_app/assets/bible/bym/` = 66 JSON **+ `_source.json`** (67 fichiers), ~9,1 Mo. **`_source.json` se commite avec les JSON qu'il décrit** (sinon l'app propose une mise à jour déjà-possée, ou masque une correction réelle).
- **Le signal est l'empreinte, pas un numéro de version** : `sha1("blob <taille>\0" + octets)`, écrit deux fois — `git_blob_id` en Python, `gitBlobId` en Dart — et les deux se vérifient l'une l'autre sur le même corpus. Cinq `.md` amont contiennent des CRLF : **ne pas les normaliser**, `.gitattributes` les épingle en `-text`.
- **L'app convertit elle-même** : `lib/data/bym_markdown_converter.dart` est un port fidèle de `md_to_json.py`, verrouillé par `test/bym_markdown_converter_golden_test.dart` (**octet pour octet**). Toute correction d'un convertisseur doit être portée dans l'autre.
- **Invariant du corpus** : 66 livres, **31 169 versets**, **5 753 notes** (et pour chaque note `text[position : position+word.length] == word`). Le compte de notes suit le corpus : le remesurer après un `sync`, **jamais** le remplacer par un `greaterThan`.
- Dans l'app, un livre corrigé est téléchargé dans `<documents>/bym_updates/` et **prend la priorité** sur l'asset. Bascule atomique via `.staging/`, registre écrit en dernier, invalidation des **quatre** caches (`LocalRepository`, `VersionRepository`, `FulltextIndex`, `LexiconIndex` — le dernier est bâti sur les *notes*, il servirait l'ancien texte). `BymUpdateService.textRevision` est incrémenté **en dernier**, et c'est lui que le lecteur écoute.
- **Aucun livre n'arrive sans accord** : trois surfaces d'annonce (pastille Bibliothèque, section Réglages, bandeau défilant de la lecture) écoutent `BymUpdateChecker.available`, **aucune n'installe** ; seul Réglages décide.
- `publish_bym.py`, `generate_manifest.py`, `victordiaz1000/bym-text` et `PUBLISH_Bym.md` **ont été supprimés** (commit `796de5c`). Le `bym_json/` de la racine aussi. Ne pas les ressusciter.

### Structure d'un livre BYM

```json
{
  "book": "Bereshit (Genèse)", "abbreviation": "Ge.",
  "metadata": { "signification": "…", "auteur": "…", "theme": "…", "date": "…" },
  "introduction": "…",
  "chapters": [ { "chapter": 1, "verses": [
    { "verse": "1:1", "section": "…", "text": "…", "textWithNotes": "…",
      "notes": [ { "word": "…", "position": 0, "note": "…" } ] } ] } ]
}
```
- `section` : **optionnel**, uniquement sur le premier verset d'une nouvelle section (choix utilisateur, ne pas changer sans demander).
- `textWithNotes` / `notes` : uniquement sur les versets qui ont des notes.

---

## 2. Décisions de conception verrouillées

1. **Navigation** : 5 sections, **PAS** d'Ancien/Nouveau Testament. `lib/data/bible_sections.dart` : Torah (1–5) · Nevi'im (6–26) · Ketouvim (27–39) · Évangiles (40–43) · Testament de Yehoshoua (44–66). 66 livres, index BYM 1–66.
2. **Version par défaut** : BYM embarquée.
3. **Notes** : OFF → `verse.text` ; ON → `verse.textWithNotes`. Le prédicat est **`carriesNotes` (= format BYM)**, jamais `code == 'BYM'`.
4. **Stockage** : dossier app (`path_provider`) + `shared_preferences`. Aucun secret Filebase dans l'APK.
5. **Hébergement des contenus téléchargeables** : **GitHub** (`victordiaz1000/-bym-dictionaries`, `victordiaz1000/-bym-bibles`), plus Filebase. Le catalogue est **configurable par code** (constantes compilées), pas par un champ URL dans l'app.
6. **Audio retiré** (décision 2026-08) : pas d'`audioplayers`, pas de marque 🔊. L'entrée correspondante de la feuille d'étude est un stub assumé.
7. **Cibles de build** : Android (`assembleRelease`) et iOS (`flutter build ios --release --no-codesign` + IPA non signé assemblé à la main), vérifiés par `.github/workflows/ios-check.yml`, qui contrôle aussi que **les icônes iOS sont opaques et carrées** (App Store Connect refuse un canal alpha, et le refus n'arrive qu'après paiement).
8. **Nom de l'app, deux longueurs.** Sous l'icône : **`Bym classic`**, 11 caractères — un libellé de lanceur tronque, et le nom complet serait coupé à « BYM — Bible de… ». Le nom long **« BYM — Bible de Yehoshoua Ha Mashiah »** vit dans l'app (`MaterialApp.title`, section « À propos », pied de l'export des notes). Le tiret y est un **U+2014**, pas un trait d'union — PowerShell affiche les deux comme `-`, donc vérifier les octets avant de conclure à une divergence.
   - **Le même nom sous l'icône sur les deux plateformes** : `android:label` et iOS `CFBundleDisplayName` portent `Bym classic`, comme le mot de marque de l'accueil (`home_screen.dart`, `brand_test.dart`). iOS portait **`Bible App`** — le placeholder de `flutter create`, jamais corrigé — c'est le seul écart qu'il fallait réparer. `CFBundleName` reste `bible_app` : c'est le nom interne du bundle, 15 caractères max et sans espace, jamais vu par le lecteur.
9. **La BYM nomme ses livres en hébreu, et elle seule.** `Bereshit`, `Shemot`, `Shir Hashirim`, `Apokalupsis` : c'est le nom que **le texte** donne à ses livres, et c'est la seule chose à l'écran qui réponde à « quel texte je lis ? ». Toutes les traductions sont françaises. Passé par **`bookDisplayName` / `bookDisplayLabel`** (`data/book_catalog.dart`), qui prennent le `code` de la version — jamais une chaîne écrite au site d'appel.
   - **Pas de version ne vaut BYM** : `isBymVersion(null, …) == false`. Favoris, notes, recherche, historique, occurrences Strong, comparateur : ces surfaces-là **n'ont pas de version** (un favori peut venir d'une lecture Darby) et doivent rester en français, sinon on renomme un surlignage Darby en `Bereshit` et le lecteur ne le retrouve plus en tapant « Genèse ». La feuille des livres, elle, affiche `name` complet (`Bereshit (Genèse)`) : c'est la table des matières de la Bible, pas le chapitre courant.
   - **Les 66 noms** viennent de `appCodebar/bym_md/*.md` — le markdown qui *est* la BYM. Les 36 livres déjà bilingues se déduisent de `name` ; les 18 que le catalogue avait réduits à leur nom français sont restitués ; les **12 derniers ne sont pas nommés en amont** (Actes · Galates · les deux Thessaloniciens · les deux Corinthiens · Romains · Éphésiens · Philippiens · Colossiens · Philémon · Hébreux) et sont translittérés de la Septante, **marqués comme tels dans le catalogue**. Si `bjc-source` les nomme un jour, prendre le nom de là et supprimer la note.
   - **La pastille a une seule largeur**, et les noms hébreu ne sont pas les noms français raccourcis : `Divrei Hayamim 1` est plus large que « 1 Chroniques ». C'est donc **la BYM**, la version que l'app ouvre, qui doit ne pas déborder — vérifié à 360 px.

---

## 3. Architecture réelle

```
bible_app/
  assets/
    bible/bym/     66 JSON + _source.json   (généré, jamais à la main)
    bible/lsgs/    66 JSON Segond 1910 + Strong (accents dans les noms)
    lexicon/       strong_fr.json (14 195) · fredaw.json (Westphal 1932)
    themes/        14 PNG
    fonts/         32 TTF / 12 familles
  lib/
    main.dart            BymApp (cycle de vie, ThemeData) + HomeShell (5 destinations)
    models/        (8)   bible_book, chapter, verse, lsgs, study_tab, tab_group,
                          translation, user_data
    data/          (34)  dépôts, registres, index, catalogues, convertisseurs
    screens/       (22)  destinations + écrans poussés
    widgets/       (21)  chrome partagé, feuilles, tuiles
    utils/         (2)   hex_color, date_format
  test/            (74 fichiers) + test/support/ (4 faux AssetBundle)
```

**`lib/data` est le cœur du projet** (34 fichiers) : c'est là que vivent les coutures de test (`useBundle`, `useRoot`, `useRepository`, `debugServiceFactory`, `ambientDatabase: false`). Presque tout écran qui lit des données ou le disque a un point d'injection.

---

## 4. Domaines

### 4.1 Onglets

`models/study_tab.dart` · `models/tab_group.dart` · `data/tab_manager.dart` · `widgets/tab_strip.dart` · `widgets/tab_switcher.dart` · `widgets/tab_context_menu.dart` · `screens/reader_screen.dart`

- **Onglet** : `id`, `kind` (`reading` | `home`), `title`, `bookIndex`, `chapter`, **`verse`** (dernier verset lu → position restaurée), **`versionCode` (propre à chaque onglet)**, `pinned`, `groupId`. `copyWith` **ne peut pas** remettre `groupId` à `null` — d'où la reconstruction manuelle dans `assignTabToGroup`.
- **Persistance** : `tabs.open`, `tabs.active`, `tabs.groups`. La file « Fermés récemment » (8 max) est **volontairement non persistée**.
- **`TabManager`** : `openReading` / `replaceActiveReading` / `openHome` / `activate` / `close` / `reopen` / `closeAll` / `duplicate` / `togglePin` / `updateTabVerse` / `updateTabVersion` + les groupes (`createGroup`, `renameGroup`, `setGroupColor`, `toggleGroupCollapsed`, `assignTabToGroup`, `closeGroup`).
  - `openReading` **focalise** un chapitre déjà ouvert ; si un `verse` explicite est fourni, il **remplace** la position enregistrée (sinon la référence ressuscite à l'ancien endroit).
  - `replaceActiveReading` déplace l'onglet **actif en place** (même `id`, `pinned` et `groupId`) et **tolère le doublon** : revenir à un chapitre déjà ouvert ailleurs duplique la position au lieu de sauter d'onglet.
  - Règle de vie d'un groupe : il existe tant qu'un onglet **ouvert ou fermé récemment** le référence. `_pruneGroups` n'est appelé que par `clearRecentlyClosed`, `assignTabToGroup` et `closeGroup`.
- **Rendu** : `TabStrip` (56 px, ＋ à gauche, puces scrollables, liseré `accentColor` 2 px + fond à 12 % sur l'onglet actif, épingle, pastille de groupe, ✕, révélation automatique de la puce active) et `TabSwitcher` (**route poussée sur le `rootNavigator`**, pas un overlay : `AppBar` « N onglet(s) / mémorisés en local » + « Terminé », sections de groupes puis « Sans groupe », « Fermés récemment » avec « Vider », barre basse Accueil / ＋ doré / Tout fermer).
- **Menu contextuel** (`tab_context_menu.dart`) : partagé par les puces de la barre **et** les cartes du sélecteur — Épingler · Dupliquer · Ajouter au groupe… · Fermer. `showGroupPicker` puis `showGroupEditor` (nom + 6 couleurs stockées **par index**, pour que la palette puisse évoluer).
- `ReaderScreen` **ne rappelle pas** `load()` sur un `initialManager` injecté : le gestionnaire est possédé et restauré par `HomeShell`.

### 4.2 Lecture

`widgets/chapter_reader.dart` (~2 500 l.) · `widgets/verse_tile.dart` · `widgets/reader_actions_bar.dart` · `widgets/note_aware_text.dart` · `screens/chapter_screen.dart` (wrapper)

- `ChapterReader` est un corps **sans `Scaffold`** (le mode multi-sélection rend sa propre barre basse). `ChapterScreen` n'est plus qu'un wrapper.
- **Gestes** : glissement horizontal = pagination de chapitre (flick `|v|>400 && |dx|>70`, ou glissement long `|dx|>140` ; **inerte en multi-sélection**) · appui long = multi-sélection · tap = feuille d'étude. Un `ScrollStartNotification` **avec `dragDetails`** marque que l'utilisateur a pris la main, et le rapporteur de position redevient une estimation honnête.
- **Barre de sélection** (`_SelectionBar`) : **cinq actions**, icônes seules — surligner · favoris · copier · **partager** · ✕. Les libellés ont été retirés parce qu'un « Terminer » écrit à côté de trois actions débordait de 42 px un écran de 360 px ; les cinq boutons sont donc à `minWidth: 40` (48 px × 5 débordaient de 320 px) et `visualDensity.compact`, et un test vérifie la barre à **320 px**. C'est le seul endroit du lecteur où un débordement est une **erreur dure** et pas cosmétique : la barre est au-dessus de la zone sûre, tout en bas. Partager **ne ferme pas** la sélection (la feuille système *est* le retour visible) ; copier la ferme (le presse-papiers est invisible, il lui faut un message et un terme).
- **Saut au verset** : `_beginJump` → estimation d'offset sur `maxScrollExtent × index/(count-1)` puis **boucle de convergence** (12 essais) parce que la liste est paresseuse et affine son extent à mesure qu'elle mesure ses tuiles ; `ensureVisible` (350 ms) fait le placement fin. Le flash doré n'est armé **qu'une fois le verset à l'écran** (1 700 ms de tenue + 520 ms de fonte ; `_targetVerse` n'est libéré qu'**après** la fonte, sinon le lavis disparaît en une frame).
- **Ne jamais mettre de `ValueKey` incluant l'affichage** sur `ChapterVerseList` : il recréerait le `ListView` et son `ScrollController` à chaque changement d'alignement et ramènerait le lecteur au verset 1.
- **Deux dispositions** (`ReadingLayout.tiles` / `.paragraph`) doivent rendre **la même taille, déclarée et peinte** — verrouillé par `reader_layout_size_parity_test.dart` sous `textScaler` 0.9 / 1.0 / 1.18. Un `RichText` nu retombe sur `TextScaler.noScaling` : le flux continu perdait ~14 % par rapport aux tuiles.
- **Un seul objet de style partagé** (`flowBodyStyle`) pour les blocs de paragraphe, l'override `bodyLarge` des tuiles **et** l'introduction de l'en-tête de livre : le corps et son introduction ne peuvent pas dériver.
- **« Trouver dans le chapitre »** (debounce 300 ms, compteur `3/12`, ▲▼) et **mode immersion** (`AppPreferences.immersionNotifier` : barre d'actions, barre de recherche, `TabStrip`, bandeau de mise à jour et chrome du shell disparaissent ; une pastille flottante reste).
- **Feuille d'affichage `⋯`** (`_showDisplaySheet`) : immersion · opacité du panneau · disposition · notes · taille · couleur du texte · alignement · graisse · aération · police · **bouton « Lecture parallèle — deux versions »** en bas. Chaque changement est **live derrière la feuille ouverte**, persisté au relâchement.
- **L'index de verset se calcule par une boucle** sur son numéro, jamais par `indexOf` (comparaison d'identité, et quadratique).
- Un livre absent **lève** `BookNotDownloaded` et ne retombe **jamais** sur la BYM : `_MissingBookPanel` dit quel livre, quelle version, et propose « Lire en BYM » + « Bibliothèque » si le callback existe.

### 4.3 Bibliothèque, versions, téléchargements

`data/version_catalog.dart` · `data/download_service.dart` · `data/library_store.dart` · `data/version_repository.dart` · `screens/library_screen.dart`

- **15 versions** : `BYM` (embedded, format bym) · `LSGS` (embedded, Strong) · `LSG` `DBY` `MAR` `OST` `NCL` `KJV` `CHO` `KJF` (downloadable) · `NBS` `NEG79` `NVS78P` `S21` `INT` (unavailable). Seules `LSGS` a `hasStrong` et `KJV` a `languageCode: 'EN'`.
- **Les deux axes à ne pas confondre** : `availability` (**où** vit le fichier : assets / `<documents>/versions/`) et `format` (**quel** schéma il porte). `VersionEntry.format` (`bym` | `getbible`, **défaut `getbible`**) choisit le parseur dans `VersionRepository.loadBook`. Le défaut est le schéma **pauvre** : un code inconnu doit lire du texte nu.
- **Deux modes de source** dans `DownloadService.bookUri` : `getbibleId` (`https://api.getbible.net/v2/<id>/<n>.json`) ou `urlTemplate` (`{book}` ← **numéro standard**, pas index BYM). Le template gagne. `OST` / `NCL` (Ostervald, néo-Crampon Libre) viennent de `raw.githubusercontent.com` et sont produits par `appCodebar/ostervald_to_json.py` ; `CHO` / `KJF` (Chouraqui, King James Française) par `appCodebar/html_verses_to_json.py`, à partir des archives HTML `<livre>/<chapitre>.html`.
- **Chaîne manuelle des corpus hébergés** (le seul maillon manuel, § 7) : script de conversion → dépôt public **`victordiaz1000/-bym-bibles`**, sous-dossier propre (`ostervald/`, `neocrampon/`, `chouraqui/`, `kjf/`), fichiers `1.json` … `66.json` en **ordre standard** → `urlTemplate` de `version_catalog.dart`. Le dépôt n'est pas cloné dans `bym3/` : la poussée se fait à la main. Les deux scripts retirent les deutérocanoniques, **renumérotent les versets par position** (les corpus impriment des numéros faux : `222`, `74` pour `174`, un « 55 » hébreu en tête de Genèse 32) et comparent les comptes à la BYM avec `--bym assets/bible/bym`. Le nettoyage du texte ne retire **aucune espace** : les `&nbsp;` du corpus deviennent des espaces simples (typographie française, comme la BYM) — jamais l'inverse. La source KJF.zip a reçu une correction à la main : Psaumes 44:24 y manquait (un `<v/><v/>` vide entre les versets 23 et 25), rétabli avant conversion — les deux corpus totalisent ainsi 31 169 versets, le compte exact de la BYM.
- **Une version sous droits affiche son copyright** : la ligne `rights` de CHO (`© 1987 Desclée de Brouwer`) et de KJF (`© 2006 Nadine L. Stratford`) vient de l'index du corpus source et n'est jamais raccourcie pour faire joli.
- `bookUri` prend le **numéro standard** : l'appelant fait `bymToStandard(bymIndex)` (BYM 27 → standard 19, Psaumes).
- **6 états de fin** : `complete` · `failed` · `noConnection` · `serverError` · `cancelled` · `unavailable` (refusé **sans aucune requête**). `_fetchBook` **ne lève jamais**. Un lien mort n'est pas retenté ; le réseau l'est (3 tentatives, backoff).
- **Reprise** : `install()` ne demande que `missingBooks` → relancer = reprendre. Le premier livre fautif arrête le tir ; les livres déjà en vol qui reviennent bons sont **quand même enregistrés** (la reprise ne referait pas ce travail). Parallélisme `maxInFlight = 4`.
- **Ordre d'écriture involontairement protégé** : le **fichier d'abord**, le registre ensuite. Une coupure peut laisser un fichier non enregistré (inoffensif) mais **jamais** un livre enregistré sans fichier.
- **Le nom du livre vient du catalogue BYM**, jamais du JSON téléchargé : getbible répond dans la langue de sa traduction (« Psalms » pour la KJV) alors que toute la navigation est française et dans l'ordre BYM. La version fournit le texte, pas le vocabulaire.
- **Les flèches ⏴⏵ sont calculées sur la BYM** quelle que soit la version lue (le découpage en chapitres est le même) : on peut ainsi avancer **au-dessus d'un livre non téléchargé**.
- `LibraryStore.revision` est un `ValueNotifier<int>` **statique** : voir § 5, règle « registre = source unique observable ».

### 4.4 Dictionnaires et lexiques

`data/dictionary_catalog.dart` (5 entrées : `STRONG_FR`, `SWORD`, `FREDAW` embarqués · `GBM` téléchargeable · `NAVE` indisponible — `BYM` retiré du catalogue le 2026-09-29, § 7) · `data/dictionary_store.dart` · `data/dictionary_download_service.dart` · `data/dictionary_reader.dart` · `data/lexicon_index.dart` · `data/strong_lexicon.dart` · `data/strong_occurrences.dart` · `data/fredaw_lexicon.dart`

- **Trois écrans d'index embarqués** : `StrongIndexScreen` (14 195 définitions FR CrossWire/SWORD), `FredawIndexScreen` (Westphal 1932) et `BymLexiconIndexScreen` (dérivé des **notes** BYM) — ce dernier **n'est plus exposé par l'UI** : ni la Bibliothèque, ni la recherche (demande utilisateur), il ne s'ouvre plus que par son test. `SWORD` est déclaré `embedded` mais son écran est le stub statique `_DictionaryDetailScreen` — **dette connue**.
- **La « Définition complète » du Strong est un arbre.** Le champ `outline` (`{level, kind, text[, label]}`, kinds `sense` / `number` / `header` / `label`) est posé par l'exportateur `appCodebar/sword_zld_to_json.py` sur **1 765 des 14 195** entrées ; absent ⇒ `outline == []` en Dart et les puces servent de repli. `StrongSenses` dessine l'arbre indenté (stèmes puis numérotation), `StrongLemma` écrit le mot (serif, `w700`, RTL pour l'hébreu, **26 en carte / 34 en fiche**) — **la carte d'étude du verset est la référence**, la fiche détail s'y aligne.
- **`BAILLY` a été retiré du catalogue** alors que `appCodebar/dictionaries_json/bailly.json` (50 493 entrées, 11 Mo) est toujours sur le disque et suivi par git : le fichier est donc **inatteignable depuis l'app**. Décision en attente (§ 7).
- Un dictionnaire téléchargé = **un seul fichier** (`<documents>/dictionaries/<CODE>.json`) : pas de granularité par livre, pas de reprise. `DictionaryDownloadService` lit le corps **en flux** (point de contrôle de l'annulation + progression), et **valide `entries` non vide** avant d'écrire — un 200 mal formé est un `invalidPayload`, pas un trou installé.
- `DictionaryArticleView` est le widget **générique** de fiche (badge, sous-titre, mention de source, « Lire la suite / Réduire », mots du dictionnaire + références bibliques cliquables). `FredawArticleView` n'en est plus qu'une **mince enveloppe** de valeurs Westphal.
- Dans `_LinkifiedText`, une **référence biblique gagne sur un mot de dictionnaire** au même endroit : « Jean 3:16 » lie toute la référence, pas seulement « Jean ».

### 4.5 Notes, étude, favoris, historique

`data/app_database.dart` (SQLite v2) · `widgets/note_editor_sheet.dart` · `screens/notes_screen.dart` · `data/note_reference_linker.dart` · `widgets/study_sheet.dart` · `screens/favoris_screen.dart` · `data/reading_history.dart` · `screens/historique_screen.dart` · `screens/etude_verset_screen.dart` · `data/share_text.dart`

- **Schéma** : `highlights(book, chapter, verse, color)` · `notes(id, book, chapter, verse, title, text, updated_at, created_at)` · `favorites(book, chapter, verse)` · `prefs(key, value)` (**dormante**, aucun appelant). `notes` a **`title` + `id` auto-incrémenté** depuis la v2 ⇒ **plusieurs notes par verset** ; la migration v1→v2 est jouée pour de vrai dans `database_test.dart`.
- **`highlightColors` = 16 couleurs** (pas 4).
- **Feuille d'étude** : surlignage (16 pastilles + gomme, **retaper la couleur active l'efface**) et favori sont des **bascules appliquées au tap**, pas des valeurs de retour ; `showStudySheet` ne renvoie qu'un `StudyAction?` (`note`, `compare`, `references`, `copy`, `share`, `lexicon`). Le bouton Lexique est **doré**, désactivé sans notes, et son désactivé **s'explique** (« Disponible depuis le texte BYM. ») au lieu d'être un bouton mort.
- **Éditeur de notes** : une feuille qui **possède la persistance** — elle enregistre à la fermeture (✕, glissé vers le bas, bouton retour via `PopScope`), un corps vide sur une note neuve n'écrit rien, et le pied annonce « Enregistré à la fermeture ». `viewInsets.bottom` est réservé : une feuille modale ne monte jamais au-dessus du clavier par elle-même. Plusieurs notes sur un verset ⇒ `showVerseNotesPicker` d'abord.
- **Deux parseurs de références, volontairement distincts** : `note_reference_linker.dart` (spécifique aux notes BYM, abréviations de `abbreviations.txt` — « Lu. » = Luc, « Jud. » = Jude) et `reference_parser.dart` (tolérant, pour les dictionnaires — abréviations Westphal sans points). Un lien n'existe **que si `onTap` n'est pas nul** : « un recognizer qui ne répond à rien est un mensonge en forme de bouton ».
- `lib/widgets/note_dialog.dart` est **mort** (zéro appelant) — l'éditeur en feuille l'a remplacé. À supprimer.
- **Copier / partager : une seule mise en forme, dans `share_text.dart`.** Les chaînes vivaient en dur dans `chapter_reader.dart`, à deux endroits, donc ni testables sans monter un lecteur ni libres de diverger — **et elles avaient divergé** : « Partager » nommait la version traduite, « Copier » non. Cinq fonctions pures, testées seules dans `share_format_test.dart` : `versionTag` (le BYM embarqué ne se nomme pas, une version téléchargée donne ` (DBY)`), `formatCitation` (la forme **copier** : nom de l'app en tête, puis référence, `BYM — Bible de Yehoshoua Ha Mashiah\nGenèse 1:1 (DBY) texte` — on *scanne* ce qu'on colle), `formatCitations` (une sélection à copier : le nom **une fois**, puis une ligne par verset), `formatPassage` (la forme **partager** d'un verset : nom, puis `« texte »` puis `— Genèse 1:1 (DBY)` — on *lit* ce qu'on transmet), `formatSelection` (1..N : nom, `« … »` par ligne, puis `— Genèse 1:1-3` si la suite est contiguë, `— Genèse 1:1, 3, 5` si elle est trouée — écrire `1:1-5` pour des versets 1, 3 et 5 attribuerait des mots à un verset que personne n'a choisi).
  - **Règle** : la version se nomme **partout**, copier comprise. Coller un texte de la Darby dans une note sans dire d'où il vient est une affirmation que le BYM n'a pas faite. Aucun de ces appels ne doit réécrire sa chaîne à la main.
  - **Règle** : le nom de l'app ouvre **chaque** bloc copié ou partagé, un verset comme une sélection. Un texte qui circule sans sa source se lit comme une parole venue de nulle part. La constante `appName` (dans `share_text.dart`) sert aussi de titre à l'écran (`MaterialApp.title`), de ligne À PROPOS et de pied de l'export des notes : **une seule adresse**, et dix littéraux en moins. Éprouvé en retirant l'en-tête de `formatCitations` — le seul des quatre chemins qui assemblait sa chaîne à part : **3 tests tombent**.
  - **Deux coutures** : `shareText(String, {Rect? origin})` et `shareTextFile(path, {String? subject})` (export `.txt` des notes, seul appelant : `NotesScreen`). `origin` est passé depuis `_originOf(context)` — sans ancrage, `share_plus` n'a rien contre quoi poser la feuille, la cause classique du partage mal placé ou débordant sur tablette.
  - **Le partage d'image n'existe pas** — `image_picker` ne sert qu'au fond de thème, et ni capture ni `RepaintBoundary` n'existent (§ 7).
- **Étude du verset : les cartes se comptent en colonnes, pas en pixels.** La bande des cartes swipables (`etude_verset_screen.dart`) tient **1** carte en portrait de téléphone (viewport à 0.9, l'arête de la suivante servant d'invite au glissement), **2** dès 600 px — paysage de téléphone comme petite tablette —, **3** dès 900 et **4** dès 1200, le pas des Thèmes. Une carte étirée sur toute la largeur vide les côtés et n'est pas une mise en page. Deux pièges, tous deux vérifiés : un `PageController` **ne change pas** de `viewportFraction` après coup (il faut en réallouer un dans `didChangeDependencies`, seul endroit où `MediaQuery` est lisible, et libérer l'ancien après la frame) ; et `PageView.padEnds`, **vrai par défaut**, centre la première et la dernière carte — juste en colonne unique, mais un demi-écran de vide avant la première dès deux colonnes.
  - **Règle** : la largeur grandit, les colonnes suivent. Ancrage : « les cartes se multiplient quand la largeur grandit » (`etude_verset_screen_test.dart`) — il échoue sur la version à colonne unique.
- `AppDatabase.notesRevision` existe mais **personne ne l'écoute** : `NotesScreen` et `FavorisScreen` ne chargent qu'en `initState` et renvoient périmés depuis l'`IndexedStack` (§ 7).

### 4.6 Recherche

`data/search_engine.dart` (le moteur, l'écran ne fait que l'affichage) · `screens/search_screen.dart`

- Un champ interroge **toutes** les sources en parallèle (`Future.wait`), l'échec **avalé par source** : pas de base (premier lancement, test widget) ⇒ les passages et le dictionnaire passent quand même.
- **7 familles** : Passages (`FulltextIndex`) · Notes (table `notes`) · Liens (indisponible) · Études (`ReadingHistory`) · Strong (`StrongLexicon`) · Dictionnaire (`FreDawLexicon` embarqué **et les dictionnaires téléchargés** de `DictionaryStore`) · Nave (indisponible). Le lexique « Notes BYM Lexique » en a été **débranché** le 2026-09-29. `SearchCategory.searchable` = les 5 câblées ; **une catégorie indisponible n'est jamais interrogée**, même passée explicitement.
- **Dans la famille Dictionnaire, chaque source garde ses lignes** : `_spread()` les entrelace sur les 5 rangées de la première page, sinon le Westphal — qui répond à un mot courant par des dizaines d'articles — noyait le dictionnaire téléchargé derrière « Voir plus ». L'écran écoute en plus `DictionaryStore.revision` : un téléchargement (ou une suppression) fait depuis la Bibliothèque rejoint la requête déjà posée, sans retaper le mot.
- **Classement Strong** : exact > préfixe > sous-chaîne du code > définition, puis position de la correspondance et hébreu avant grec. Un mot courant renvoyait les 50 premières entrées toutes grecques avant que ce classement soit corrigé.
- **Carte de référence** : « Jean 3:16 » est résolu en verset et imprimé **au-dessus** des groupes. Un nom de livre nu (« psaumes ») **ne qualifie pas** — sinon toute recherche de mot ressemblant à un livre pousserait une carte devant ses propres résultats. Une référence hors filtres, ou vers un verset inexistant, est abandonnée.
- **Un index plein texte par version** (`FulltextIndex.of(code)`), max **2** versions téléchargées en mémoire. Une version partielle est **indexée sur ce que l'appareil détient** et **annonce sa couverture** (`coverageNote`) : sans elle, « 3 résultats » se lit « ce mot n'est presque pas dans la Bible ».
- Un menu de choix **ne liste que ce qui estchoosable** : Version (feuille de lecture **et** recherche) filtre sur `embedded || installed`, et se ferme par un pied « Bibliothèque · N autres versions à télécharger » qui **ne sélectionne pas** (`PopupMenuItem` sans `value`).
- **Test seams** : `SearchScreen` accepte un `engine` injectable et `SearchEngine` un `ambientDatabase: false`. Sans ce drapeau, `AppDatabase.instance` ouvre via `path_provider` et le futur **reste pendu** (il ne lève pas) — `_searching` reste vrai, l'indicateur indéterminé programme des frames à l'infini.

### 4.7 Design system, thèmes, typographie

`widgets/premium_style.dart` · `widgets/bible_theme_scope.dart` · `data/theme_catalog.dart` · `data/custom_background.dart` · `widgets/responsive_text_scaling.dart` · `widgets/loading_skeleton.dart` · `widgets/fiche_text_settings.dart` · `utils/`

- **La couleur du thème est `BibleTheme`** (`data/theme_catalog.dart`) et rien d'autre. La chaîne : `AppPreferences.themeNotifier` → `BibleThemeScope` (posé dans **`MaterialApp.builder`**, donc autour du **Navigator entier** — une route poussée est une sœur de `home`) → `premiumPalette(context)` dérive 14 rôles (`primary`, `surface`, `heroGradient`, `greek`, `hebrew`…) → `ThemeData` dans `main.dart`.
- `premiumCardBorder` est un liseré **`textGrey`**, pas d'accent : mesuré, un liseré d'accent tourne au cerne coloré sur les thèmes chauds (rapports 1,015 à 1,084).
- **14 thèmes** : Bas-relief · Oliveraie · Papier clair · Mosaïque grise · **Bois doré (`forest`, défaut)** · Cacao · Brume · Acier · Sable minéral · Azur profond · Nuit étoilée · Sinaï · Lin blanc · Veillée. `usesLightText` est vrai pour exactement 3 : `azur`, `nuit`, `veillee`.
  - Les **ids sont persistés et ne disent plus rien du fond affiché** : ne pas les renommer (une clé orpheline retomberait en silence sur le premier thème).
  - `backgroundTone` doit valoir **la moyenne de la texture** : toutes les surfaces opaques en dérivent, sinon les cartes « jurent » avec le fond.
  - `BackgroundFit.tile` pour les textures, `.cover` pour les deux scènes (`vitrail`, `parchemin`).
- **Polices** : `google_fonts` **supprimé** — 12 familles nommées dans `pubspec.yaml`, 32 fichiers, aucune variante synthétique. `kUiFontFamily = 'Plus Jakarta Sans'` pour toute l'interface, **Crimson Pro** pour la lecture. **Cardo est la seule famille embarquée couvrant l'hébreu** (vérifié sur la table `cmap`) : sans elle, les lemmes hébreux des fiches Strong s'affichent en carrés vides. Chaque famille doit déclarer au moins un italique, sinon Skia penche le romain.
  - Charger les polices en test **explicitement** et seulement pour `{'Plus Jakarta Sans', 'Lora'}` (`test/flutter_test_config.dart`) : le dossier complet pèse ~15 Mo et serait payé à chaque fichier.
- **Valeurs par défaut de lecture** : `fontSize` = **`extraLarge` = 22 pt** (⚠️ pas 16), `readingFont` = **`crimson` (Crimson Pro)**, `layout` = tiles, `fontWeight` = normal, `spacing` = normal, `textAlign` = left, `panelOpacity` = **.80** (le rendu historique), `themeId` = `forest`. Les 6 crans : 14 / 16 / 19 / 22 / 26 / 30.
  - Le défaut est écrit à **deux endroits** qui doivent dire la même chose : le constructeur `AppPreferences` et le `fallback:` de `AppPreferences.load`. Le second gagne toujours — c'est lui qui répond à une installation neuve. Les deux sont épinglés par `reading_fonts_test.dart`, avec le test qui compte le plus : un `literata` **déjà stocké** survit au changement de défaut, parce que changer la police par défaut ne doit pas réécrire le choix d'un lecteur qui en a fait un.
- **Trois familles de préférences, délibérément séparées** : `reading.*` (14 clés) · `fiche.*` · `etude.*` (`DisplayGroup`), chacune avec sa propre révision. `reading.fontFamily` a migré `'modern'` → `'jakarta'` **avant** le repli du `caller`.
- **L'échelle « écran étroit » vit dans `ResponsiveTextScaling`** (plafond système **1.18**, `deviceFactor` : <360 → .90 · <400 → .95 · <480 → .98), posée une fois dans `main.dart`. **Une seule fois** : la réduction a existé en double (une échelle sur l'enum + le `deviceFactor`, mêmes seuils) et composait une coupe de 19 % là où 10 % était voulu. `ReadingTextSize.fontSize` **ne** réduit pas. Un test d'unicité verrouille le facteur lu sur la classe, jamais recopié.
- **Chrome partagé** : `DisplaySettingsSheetLayout` (titre + ✕ `ValueKey('display-sheet-close')` + `SingleChildScrollView` + `SafeArea`/`viewPadding`), `DisplaySizeSection`, `DisplayAlignSection`, `DisplayFontSection`, `DisplayCard`, `DisplayToggleCard` (bascule sur **toute** la carte), `premiumText`, `premiumBadge`, `premiumShadow`, `premiumBackground`, `premiumSurface` — la carte habillée du registre « premium affirmé » (dégradé `surface → surfaceAlt`, liseré `premiumCardBorder(.18)`, deux ombres modulées par `depth`) — et `kPremiumCoeur`.
- **Un choix à 2–6 valeurs est une barre segmentée**, jamais des pastilles libres ni des boutons empilés : `ReadingChoiceBar` est le mécanisme (segments égaux par `Expanded`, gouttière commune, segment courant plein d'accent, `FittedBox` qui rétrécit au lieu de saigner, **plafond 460 px** — au-delà la barre se lit comme un curseur) et ses trois visages `ReadingSizeChips` (les « A » **dessinés à la taille qu'ils sélectionnent**, plafonnés à 24 pt) · `ReadingOptionBar` (disposition, graisse, aération, disposition des notes) · `ReadingAlignChips` (4 icônes **teintées à la palette** — l'`IconButton` les teintait au bleu du `colorScheme`). La feuille ⋯ monte `ReadingChoiceBar` elle-même pour ses **deux décisions de notes** (`<bool>` « Texte seul / Texte + notes » puis `<NoteDisposition>`, cette dernière **n'apparaissant qu'une fois qu'il y a des notes à placer**). Réglages et feuilles n'ont que ces widgets : une préférence ne peut pas avoir deux implémentations qui divergent.
  - Le piège précis, et il a coupé l'écran Réglages en trois : un `Container` avec `alignment` posé dans un `Wrap` reçoit la largeur **maximale** du wrap, chaque pastille remplit donc la ligne et le `Wrap` l'empile sous la suivante — six tailles en 4 + 2, « Séparés / Continu » sur deux écrans. Ancrage : « les choix du texte se lisent en une barre, jamais en pile » et « sur un grand écran, la barre garde la taille d'un contrôle » (`settings_screen_test`).
- **Squelettes** (`loading_skeleton.dart`) : 6 formes qui imitent la forme du contenu réel, plus `InterfaceLoadingGate` (une frame). **Rogner vaut mieux que déborder**, et rien ne saute à l'arrivée. Les hauteurs figées dépassaient de 9 px à 217 px selon la taille — d'où des hauteurs calculées, pas des valeurs qui « tombent juste ».
- **Fond photo** (`data/custom_background.dart`) : `image_picker` → copie dans `getApplicationDocumentsDirectory()` sous un **nom unique par choix** (le `FileImage` cache par chemin ; réécrire un nom fixe laisserait la photo précédente à l'écran) → palette dérivée de la **teinte HSL** de la moyenne 32×32 (les anciennes palettes brun/or fixes lisaient comme des restes du thème par défaut sur une photo bleue) → `reading.customTheme`. Créneau global `customBibleTheme`, id `'custom'`. L'ancien fichier est supprimé **juste après** la copie.
- Changer de thème **remet `panelOpacity` à .80** ; re-taper le thème courant est un no-op silencieux.
- Le liseré de carte « Surligner » et l'anneau de la pastille choisie ont un **contraste WCAG mesuré** sur les 12 palettes (`study_sheet_test.dart`).

### 4.8 Réglages

`screens/settings_screen.dart` — 5 sections : **LECTURE** (version par défaut · taille · disposition · graisse · aération · alignement · police · couleur du texte · opacité du panneau · notes, et la disposition des notes quand elles sont actives) · **APPARENCE** (thème de lecture) · **DONNÉES** (versions téléchargées, vider le cache, effacer l'historique) · **MISE À JOUR DU TEXTE** (date, taille, vérifier / mettre à jour, revenir à l'embarqué) · **À PROPOS**.
- `_pickDefaultVersion` filtre sur `embedded || installed` : **un menu de choix ne liste que ce qui estchoosable**.
- « Vider le cache » itère `LocalRepository` + `VersionRepository` + `FulltextIndex.forget` pour **chaque** version installée.
- Il écoute `LibraryStore.revision` **et** `BymUpdateStore.revision`, et `_loadTextVersion()` est **détaché** de `_load()` : passer par les assets / `path_provider` laisserait tout l'écran sur son squelette sous fake-async.
- `appVersion = '1.0.0'` est à tenir en phase avec `pubspec.yaml`.
- **Réglages et feuille `⋯` partagent les contrôles, pas les lignes.** La feuille du lecteur garde l'immersion, la disposition, la taille, les notes, l'opacité, la lecture parallèle **et une ligne qui ouvre Réglages** (« le reste vit à un seul endroit ») ; la graisse, l'aération, l'alignement, la police et la couleur ne vivent plus que dans Réglages. **L'immersion n'a de ligne que dans la feuille** : c'est une action de lecture (elle referme la feuille en s'activant), retirée de Réglages le 2026-09-29 — une préférence, une adresse. Le point qui compte : les deux surfaces montent les **mêmes** widgets (`ReadingSizeChips`, `ReadingOptionBar`, `ReadingAlignChips`…), donc la même préférence ne peut pas se régler d'une manière qui contredit l'autre.

---

## 5. Règles transverses

1. **Registre = source unique observable.** Tout écran qui dépend de ce qui est installé écoute `LibraryStore.revision`, **jamais** `installed()` copié dans un champ à l'`initState`. Les écrans vivent dans l'`IndexedStack` du shell : `initState` ne rejoue pas, la copie reste périmée, et l'utilisateur fait la navette entre Bibliothèque et lecture sans fin. Même règle pour `AppPreferences.revision`, `BymUpdateStore.revision` et `BymUpdateService.textRevision` (émis **après** l'invalidation des caches, jamais avant).
2. **Les feuilles doivent rendre l'encoche système.** `sheetBottomInset(context)` = `24 + MediaQuery.viewPaddingOf(context).bottom` — `viewPadding` et non `padding`, qu'une feuille a déjà consommé. Une marge basse fixe dessinait la dernière ligne **sous** la barre de gestes.
3. **Un lien n'existe que si le tap est câblé.** `onTap == null` ⇒ pas de span, pas de `Recognizer`, pas de bouton mort.
4. **Une feuille modale est un sous-arbre à part : rebuildir le lecteur ne rebuild pas la feuille.** `showModalBottomSheet` monte une route ; son `StatefulBuilder` a son propre `setSheet`, et le `setState` du lecteur en dessous ne l'atteint pas. Tout contrôle **vivant** de la feuille `⋯` doit donc appeler les deux — c'est ce que font `_setLayout` / `_setFontSize` / `_setNotesMode` / `_setDisposition`. L'opacité ne le faisait pas : le panneau s'estompait derrière la feuille pendant que le pouce et son étiquette restaient sur « 80 % », jusqu'au prochain `setSheet` d'un autre contrôle qui les remettait d'un coup. Le test qui aurait vu le défaut regardait **le modèle** (`prefs.panelOpacity`), qui était juste, et son commentaire affirmait déjà « the label follows live » sans le vérifier. Un commentaire d'intention n'est pas une assertion.
5. **Un menu ne liste que ce qui est choosable ; un menu qui ouvre la commande dit pourquoi.** Griser onze lignes et répondre par un snackbar est pire que de ne pas les montrer — le catalogue complet a un écran qui est fait pour ça.
6. **Une ligne qui s'explique plutôt que cinq lignes grisées.** Même règle pour les fonctions indisponibles.
7. **`VersionFormat` ≠ `availability`.** Où vit le fichier et quel schéma il porte sont deux axes. `carriesNotes` est le seul prédicat que l'interface doit interroger.
8. **La source des données est le markdown, jamais le JSON.**
9. **`main.dart` est le seul endroit** qui applique la règle d'échelle et pose le thème, et c'est le **Navigator entier** qu'elles enveloppent.
10. **Réduire une entrée de menu n'est jamais cosmosétique.** Six entrées pleine hauteur avaient été essayées : la plus grande taille sortait de l'écran, précisément pour ceux qui la cherchaient. D'où la rangée compacte de pastilles.
11. **`flutter analyze` à zéro, `flutter test` vert.** Dans cet ordre, en global. Ne pas lancer fichier par fichier.
12. **Ne jamais embarquer de secret** ni laisser une URL distante rediriger l'application : hôtes et chemins sont des constantes compilées.
13. **En paysage, la barre Android vit sur le côté : c'est le corps de l'écran qui doit l'écouter.** Les insets sont dans `MediaQuery.padding`, et l'`AppBar` les applique déjà — d'où le titre et le⋮ toujours lisibles pendant que le contenu, lui, passait sous les boutons. Un corps nu (`TabBarView`, `SingleChildScrollView`) les ignore et file jusqu'au bord : c'est ce qui coupait la Bibliothèque et l'étude du verset, les deux seuls écrans sans `SafeArea` (les onglets de la lecture sont eux enveloppés par la coquille, `reader_screen`). Règle : **tout corps d'écran passe par `SafeArea`**. Ancrage : « en paysage, le corps reste dans la zone sûre » (`library_screen_test`, `etude_verset_screen_test`).

14. **Un choix, une barre.** Une préférence à 2–6 valeurs se dessine en segments égaux dans une gouttière commune (`ReadingChoiceBar`, `fiche_text_settings.dart`), jamais en boutons empilés pleine largeur ni en pastilles qui se rangent au hasard. La cause du défaut est précise : un `Container` avec `alignment` posé dans un `Wrap` reçoit la largeur **maximale** du wrap, chaque pastille remplit la ligne, le `Wrap` l'empile sous la suivante — six tailles en 4 + 2, « Séparés / Continu » qui occupait trois écrans de réglages. Segments égaux + plafond : le même contrôle tient de 320 px à la tablette. Ancrage : « les choix du texte se lisent en une barre, jamais en pile » (`settings_screen_test`).

---

## 6. Règles de test

> `flutter analyze` puis `flutter test`. 739 tests, ~3 min 40. Les tests qui lisent les assets réels doivent être des `test()` purs, **jamais** des `testWidgets`.

1. **`rootBundle` et `path_provider` ne répondent pas dans la zone fake-async de `testWidgets`.** I/O réel ⇒ `pumpAndSettle` attend pour toujours. Le symptôme est trompeur : le timeout est signalé sur le `pumpAndSettle`, pas sur la lecture.
   - `LocalRepository.useBundle(...)` / `useRootBundle()` — `test/support/fake_bible_bundle.dart` sert n'importe lequel des 66 fichiers.
   - `LibraryStore.useRoot(temp)`, `CustomBackgroundStore.useRoot(temp)`, `DictionaryStore.useRoot(temp)`, `StrongOccurrenceIndex.useRepository(...)`, `StrongLexicon.useBundle(...)`, `FreDawLexicon.useBundle(...)`, `LsgsRepository` (faux bundle), `BymUpdateStore.useRoot(temp)`, `BymUpdateChecker.debugServiceFactory`, `SearchEngine(ambientDatabase: false)`.
   - **Rétablir la production en `tearDown`** : un faux bundle laissé en place rend le test suivant vert pour la mauvaise raison.
2. **`pumpAndSettle` n'attend pas une chaîne `await`** : il rend la main entre deux `await` d'une même fonction asynchrone. Pour un enchaînement (délai → chargement → convergence), pomper explicitement (`for (…) await tester.pump(60 ms)`) avant le `pumpAndSettle` final.
3. **Widgets paresseux** : une `ListView` ne construit pas hors du cache extent — un `find` lointain renvoie 0 sans que rien ne soit cassé. `scrollUntilVisible` **puis** `pumpAndSettle` (`ensureVisible` ne se matérialise qu'à la frame suivante), et cibler le scrollable par une `Key` de production (un `TextField` a son propre scrollable ; le choix par axe attrape le mauvais).
4. **Faux-async serré : microtâches, pas `sqflite_common_ffi`.** Le FFI fait de vraies I/O qui ne se résolvent jamais. Pour un vrai disque : un `test()` pur hors fake-async (`LibraryStore`, `AppDatabase.testOpen`).
5. **Un écran affiché doit avoir été audité au canari.** Les deux balayages anti-débordement (`responsive_overflow_test`, `responsive_pushed_screens_test`) ont été vérifiés en injectant un débordement volontaire : un test qui n'a jamais détecté de défaut n'est pas encore un test.
   - `paintWholeScroll` pilote `jumpTo` par paliers (un `tester.drag` atterrit sur le widget central et peut ne rien déplacer) ; la page **déjà sélectionnée** porte l'icône *pleine*, donc sauter une destination dont l'icône contour est absente laissait l'Accueil hors audit.
   - Une **`Row` de 5000 px** enfouie derrière 3000 px n'est visible que par les entrées « défilé à … », jamais par « montage ».
   - `responsive_pushed_screens_test` monte **directement** chaque écran : une chaîne de taps échoue *en silence*.
6. **Notifiers statiques : remettre à zéro en `tearDown`** (`AppPreferences.revision`, `LibraryStore.revision`, `LexiconIndex.instance.clearIndex()` — l'index est statique).
7. **`TabStrip` ne s'écoute pas elle-même** (elle ne se redessine que si l'appelant la reconstruit) ; `TabSwitcher` n'écoute le manager que via le `ListenableBuilder` de son hôte. Sans cela, `activate()` n'atteint jamais le widget en test.
8. **Un test qui vérifie une promesse non tenue est un test qui ment.** Exemple réel : `EtudeVersetScreen` ne pope jamais avec `true`, donc le « retour au verset et flash » du lecteur est du code mort — ne pas le tester comme s'il fonctionnait.
9. **Le test doré est le premier à regarder** après une modification du convertisseur : il échoue à la première divergence entre `md_to_json.py` et `bym_markdown_converter.dart`, en pointant le premier octet fautif.
10. **Le compte de notes du corpus (5 753) est un invariant, pas un plancher.** Le remplacer par `greaterThan` rendrait vert un bug qui viderait toutes les notes.
11. **Un test d'ancrage doit mordre, et viser le bon chemin.** Écrire « la version se nomme au site d'appel » ne prouve rien tant que le test reste vert quand on rend la chaîne en dur. Vérifié cette fois en réintroduisant la faute : le test que j'avais écrit **passait**, parce qu'il tapait le bouton *copier de la barre de sélection* — déjà corrigé — au lieu du bouton *copier de la feuille d'étude*, qui ne l'était pas. Reintroduire la faute, voir le test échouer, puis remettre.
12. **Un `snackBar` avale le geste suivant.** « 1 verset copié. » reste ~4 s au-dessus du bas de l'écran : un appui long ou un tap qui suit dans le même test atterrit sur lui, et l'action demandée n'arrive jamais — le test échoue alors sur l'assertion d'après, à un endroit qui ne raconte pas la cause. Faire le partage **avant** la copie, ou vider la file, ou fermer la sélection d'abord.

---

## 7. Dettes ouvertes

- [ ] **Plages de références** dans `reference_parser.dart` — `splitReference` ne lit qu'un `chapitre[:verset]` en fin de requête, donc « Exode 4:5-10 » retombe en recherche de livre et ne rend rien. `BibleReference.verseEnd` **existe et est câblé dans `label`** ; rien ne le produit. Décider en plus ce qu'affiche la carte de référence pour une plage.
- [ ] **`SearchCategory.nave`** — indisponible des deux côtés (`search_engine.dart` **et** `dictionary_catalog.dart`). Retirer la puce et l'entrée, ou trouver une source.
- [ ] **`BAILLY`** — retiré du catalogue, `bailly.json` (11 Mo) toujours sur le disque et suivi par git, donc **inatteignable**. Le remettre en `downloadable` avec son URL GitHub, ou le supprimer du dépôt.
- [ ] **`onOpenVerse` non câblé** de la Bibliothèque vers un dictionnaire téléchargé : `_openScreen` ne le passe pas, donc les références d'une fiche GBM sont du texte plat. Le chemin de la recherche le passe bien.
- [ ] **`NotesScreen` / `FavorisScreen` ne se rafraîchissent pas** — ils ne chargent qu'en `initState` et vivent dans l'`IndexedStack`. `AppDatabase.notesRevision` existe et n'est écouté par personne. Une note écrite depuis la lecture n'apparaît pas dans « Mes notes ».
- [ ] **Code mort** : `widgets/note_dialog.dart` (zéro appelant) · `data/lexicon_service.dart` (seul `lexicon_test.dart` l'utilise ; `LexiconIndex` fait le travail) · `AppDatabase.prefs` + `setPref`/`getPref` · `UserHighlight.legacyNote` · `TypeFavori.strong` / `.dictionnaire` (modélisés, aucune fabrique ne les crée — la table `favorites` ne peut pas les porter).
- [ ] **Duplication d'index** — en partie soldée : le champ, l'état vide et la carte sont partagés depuis `lexicon_index_widgets` (`LexiconSearchField`, `LexiconEmptyState`, `LexiconEntryCard`). Reste le groupement par lettre recopié dans `FredawIndexScreen`, `BymLexiconIndexScreen` et `DictionaryBrowseScreen` (`_groupLetter` + `_filtered` + `_letters`, sur trois types d'entrée distincts) ; `StrongIndexScreen` garde sa propre liste.
- [ ] **Partage d'image** — aucun code. Ni capture, ni image du verset, ni `RepaintBoundary`. L'ancrage est résolu (§ 4.5) ; seule l'image manque.
- [ ] **Favoris Strong / dictionnaire** — `Favori.badge` / `.langue` attendent une table dédiée et une troisième action dans la fiche Strong et dans `DictionaryEntryScreen`.
- [ ] **`sword_zld_to_json.py --download` est cassé** : `download_modules()` référence `tempfile`, `urllib.request` et `MODULE_URLS`, aucun des trois n'existe dans le module. L'export normal fonctionne.
- [ ] **`appCodebar/CLAUDE.md` est incomplet** : il ne mentionne ni `ostervald_to_json.py`, ni `sg1910_to_json.py`, ni `sword_dict_to_json.py`, ni `sword_zld_to_json_fredaw.py`, ni `generate_theme_textures.py`, ni `generate_splash.py`, ni les 4 scripts `inspect_fredaw_*.py`. Il affirme aussi que `sync_bym_source.py` vérifie les invariants 66 / 31 169 — **il ne le fait plus** (c'est le test doré qui les porte).
- [ ] **L'accueil ne suit pas la version de l'onglet** — « Reprendre la lecture — Bereshit (Genèse) 5 » charge son aperçu par `LocalRepository`, donc **toujours le texte BYM**, même pour un onglet réglé sur la Darby. Le nom affiché est donc honnête aujourd'hui (c'est bien la BYM qui est prévisualisée) ; c'est l'aperçu qui ment, pas l'étiquette. Corriger ⇒ passer par `VersionRepository.loadChapter(code, …)` avec `StudyTab.versionCode`. Ne pas « corriger » le nom en le rendant sensible à la version avant d'avoir corrigé l'aperçu : on afficherait « Genèse » au-dessus d'un texte BYM.
- [ ] **Les 12 noms BYM que l'amont ne donne pas** (Actes · Galates · Thessaloniciens ×2 · Corinthiens ×2 · Romains · Éphésiens · Philippiens · Colossiens · Philémon · Hébreux) sont translittérés de la Septante dans `book_catalog.dart`, pas tirés de `bym_md/*.md`. Marqués dans le fichier. À reprendre depuis `bjc-source` s'il les nomme.
- [ ] **Aucun test** ne couvre `SWORD` ni `_DictionaryDetailScreen`, ni un téléchargement `urlTemplate` de bout en bout depuis l'écran Bibliothèque.
- [ ] **Nettoyage** : retirer `dio` et `provider` de `pubspec.yaml` (importés nulle part) ; corriger le commentaire périmé de la ligne `GBM` dans `dictionary_catalog.dart`.
- [ ] **Restyle premium restant** — `TODO.md` à la racine : les trois écrans ouverts depuis l'accueil (Favoris, Notes, Comparer) et la feuille d'étude du lecteur, avec leurs pièges de tests. En particulier `study_sheet_test` mesure `d.color == p.surface` sur la carte « Surligner » : **réécrire le test**, pas contourner le style.
- [ ] **Signature release** : `android/app/build.gradle.kts` signe encore le `buildType.release` avec la **clé debug** (TODO du template). Keystore à câbler avant toute distribution — et le passage debug → release impose une désinstallation de l'app installée.

### Périmés — ne pas réintroduire

- `PUBLISH_Bym.md`, `publish_bym.py`, `generate_manifest.py`, `victordiaz1000/bym-text` : supprimés (commit `796de5c`). `MAJ_TEXTE_BYM.md` les remplace.
- `bym_json/` à la racine : supprimé. Il ne reste que `appCodebar/bym_json/`, gitignoré.
- `assets/brand/` : supprimé. L'accueil affiche un **intitulé textuel** `Bym classic`, pas une image ; la seule marque embarquée est `android/.../drawable-<densité>/splash_logo.png` (× 5, produit par `appCodebar/generate_splash.py`). `logoBym/` est à la racine du dépôt, pas embarqué.
- `screens/strong_lexique_screen.dart` et `screens/lexique_screen.dart` : supprimés. L'écran « Lexique » de la feuille d'étude est **`screens/etude_verset_screen.dart`** (« Lexique & Dictionnaire »), adossé à la LSGS embarquée.
- `ReadingFont 'modern'` (la seule famille non embarquée) : retirée, `'modern'` migre vers `'jakarta'`.
- `dio` : jamais utilisé, `http` fait tout le réseau.

---

## 8. Notes de travail

- **Outillage** : Windows. Le shell est PowerShell 5.1 **ou** Git Bash selon la session — vérifier avant d'écrire (`Remove-Item` vs `rm -f`). Toujours mettre les chemins entre guillemets.
- **Dossier accentué** : la source des fonds s'appelle `thème/`. Si un outil échoue, chemin en dur `C:\Users\laptek\Desktop\bym3\thème` et `-LiteralPath` / `Get-ChildItem -LiteralPath` / `Test-Path -LiteralPath` — un chemin global avec wildcards échoue. Au moment de la copie dans `assets/themes/`, renommer en ASCII.
- **Les JSON BYM sont en UTF-8** ; ne jamais les réécrire en changeant l'encodage (`.gitattributes` épingle `bym_md/*.md` et `assets/bible/bym/*.json` en `-text`).
- **Travailler dans `bible_app/`**, jamais à la racine du dépôt.
- **Deux vocabulaires de nommage d'asset** pour le même canon : `bym/06-Josue.json` vs `lsgs/06-Josué.json`, `30-Cantiques.json` vs `30-Cantine.json`. Toute fusion future des deux corpus devra traiter ça.
- `generate_theme_textures.py` est le **seul** producteur de `lin.png` et `veillee.png` (bruit filtré dans le domaine de Fourier donc périodique, moyenne recentrée exactement sur le `backgroundTone` cible). Il lui faut `numpy` + `Pillow` — les autres scripts sont en stdlib seule.
- `generate_splash.py` lit `logoBym/splash_logo_hd.png`, recadre sur la **masse d'encre** (le recadrage par pixel prenait les taches de compression pour du contenu) et borne la **diagonale** de la marque, pas sa largeur, parce qu'Android 12+ masque l'icône en cercle.
