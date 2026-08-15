# Plan : Source Française + Strong (Point 8)

## État des lieux

- **Données acquises** : `Sg1910-csv/Sg1910.csv` (LSG 1910 avec tags `<w strong="H0430">`) + script `sg1910_to_json.py` qui convertit en 66 JSON dans `sg1910_json/`. Le convertisseur `appCodebar/sword_zld_to_json.py` télécharge au besoin les modules CrossWire, lit directement les blocs zLD et régénère le lexique Strong structuré.
- **App Flutter** : LSGS est embarquée dans `assets/bible/lsgs/`, reconnue comme version lisible, et le rendu de lecture affiche les numéros Strong inline.
- **Duplication nettoyée** : `appCodebar/sg1910_json/` (sortie du script, régénérable) et `Sg1910-csv.zip` sont gitignorés — une seule copie des données vit dans le dépôt (`assets/bible/lsgs/`), comme pour `bym_json/`.
- **Avancement récent** : `lib/data/lsgs_repository.dart`, `lib/models/lsgs.dart`, `lib/data/version_catalog.dart`, `lib/data/version_repository.dart`, `lib/widgets/verse_tile.dart` et `lib/widgets/clickable_verse.dart` ont été ajoutés/ajustés. Le format LSGS est différencié du format BYM.
- **Écran cliquable finalisé d’après les maquettes v8** (`Qwen_maquette_lexique_suite.html`, `renduLexique/`) : bandeau d’aide, carte du verset LSG 1910 + Strong, mot sélectionné à fort contraste, fiche structurée (pastille Strong, définition, position), navigation « Mot préc. / Mot suiv. », pied source et action « Note complète dans la lecture ».
- **Audio supprimé (décision 2026-08)** : plus de `audioplayers`, de bouton « Écouter » ni de `audioUrl` — le squelette audio ne produisait que « Audio non disponible ». Le champ `hasAudio` du catalogue est retiré.
- **Validation** : `flutter analyze` sans erreur ; `flutter test` complet vert (**221 tests**). Le JSON v2 contient 14 195 entrées structurées (8 674 hébreu + 5 521 grec). La **recherche Strong est câblée** (catégorie `SearchCategory.strong`, classement par position).
- **Phase Strong terminée** : l’action « Note complète dans la lecture » revient au lecteur et remet le verset en évidence.
- **Catalogue** : LSGS est intégrée et affichée dans la feuille de version comme version embarquée correcte, sans panneau vide.

## Plan en 4 phases (mise à jour)

### Phase 1 — Héberger et lire LSGS offline ✅
**Objectif** : rendre le texte LSG+Strong disponible offline, comme BYM.
- Copier `sg1910_json/` dans `bible_app/assets/bible/lsgs/` (66 fichiers).
- Déclarer le dossier dans `pubspec.yaml` (assets).
- Ajouter `VersionEntry` LSGS avec `format: VersionFormat.getbible` car le schéma est plus pauvre que le BYM, sans intro/metadata/notes.
- Rendre LSGS `embedded` au lieu de `unavailable`.
- Adapter `VersionRepository.loadBook` pour lire ce schéma.

### Phase 2 — Parser le schéma LSGS ✅
**Objectif** : lire les JSON LSGS et en extraire les mots + numéros Strong.
- Créer `models/lsgs.dart` : `LsgsToken` (text + strong), `LsgsVerse`, `LsgsChapter`, `LsgsBook`.
- Créer `data/lsgs_repository.dart` : charge un livre depuis les assets, parse le JSON LSGS.
- Conserver les Strong dans le texte visible en réécriture du rendu de lecture.
- Cacher le header BYM et les notes quand la version ne porte pas ce schéma.

### Phase 3 — Définitions Strong (H#### / G####) ✅ SOURCE TROUVÉE
**Objectif** : avoir une base de définitions hébreu/grec en français.
- **Source retenue** : CrossWire/SWORD — modules **`FreStrongsHebrew`** et **`FreStrongsGreek`**.
- **Étape 3a** : télécharger les 2 ZIP dans `appCodebar/sword_modules/`.
- **Étape 3b** : convertir en JSON français via un script Python.
- **Étape 3c** : copier les JSON dans `bible_app/assets/lexicon/`.
- Créer `lib/data/strong_lexicon.dart` : `lookup(String strongNumber)`. Il accepte aussi le schéma structuré v2 (lemme, translittération, prononciation, catégorie, origine et sens).

### Phase 4 — Rendu cliquable + recherche Strong ✅
**Objectif** : aller au-delà du simple affichage et rendre le lexique réellement exploitable.
- ✅ Finaliser `widgets/clickable_verse.dart` (tap sur les mots Strong — ouvre `strong_lexique_screen.dart`).
- ✅ Ajouter un écran de lexique dédié Strong (`screens/strong_lexique_screen.dart`), aligné maquette v8.
- ✅ Brancher le bouton Lexique de la feuille d’étude selon le type de version.
- ✅ Dégriser `SearchCategory.strong` et permettre la recherche Strong (moteur + écran, classement corrigé, 6 tests `strong_lexicon_test`).
- ✅ **Fiche Strong au clic dans le chapitre** — tap dans le lecteur → `_StrongDefinitionSheet` (fiche rapide) + écran complet via le bouton « Lexique ».
- ✅ **Polish UI** — carte de verset, fiche Strong accessible, mot sélectionné à fort contraste et action « Note complète dans la lecture » (retour + flash du verset).
- ✅ **UI thématique cohérente** — le titre d’accueil `Bym classic` est textuel et suit la couleur active du thème, l’onglet actif du lecteur est rendu avec `accentColor` du thème.

## Prérequis / Dépendances
- ✅ **LSGS embarquée** : le texte est désormais accessible offline.
- ✅ **Strong visible dans la lecture** : affichage inline des codes `H####` / `G####`.
- ✅ **Masquage du header vide** : les versions sans métadonnées BYM ne montrent plus de bloc vide.
- ✅ **Lexique Strong complet** : dictionnaire bilingue FR intégré (14 195 entrées, `assets/lexicon/strong_fr.json`) et fiche au tap finalisée.
- ✅ **Recherche Strong** : câblée (moteur + écran), classement corrigé.

## Dictionnaires français complémentaires (CrossWire/SWORD)
| Module | Description |
|---|---|
| `FreStrongsHebrew` | Lexique hébreu des nombres de Strong |
| `FreStrongsGreek` | Dictionnaire grec des nombres de Strong |
| `FreBailly` | Dictionnaire Grec-Français abrégé |
| `FreDAW` | Dictionnaire encyclopédique de la Bible |
| `FreGBM` | Glossaire de la Bible David Martin |

## Risques / points restants
- Les dictionnaires Strong sont volumineux, il faut garder la taille d’APK raisonnable.
- La recherche Strong respecte le même comportement que les autres catégories (moteur `search_engine.dart` + écran), classement exact > préfixe > sous-chaîne > définition, puis position ; la normalisation est pré-calculée pour ne pas bloquer le thread UI.

## Fichiers déjà créés / modifiés
- `lib/models/lsgs.dart`
- `lib/data/lsgs_repository.dart`
- `lib/data/strong_lexicon.dart`
- `lib/widgets/clickable_verse.dart`
- `lib/screens/strong_lexique_screen.dart`
- `lib/data/version_catalog.dart`
- `lib/data/version_repository.dart`
- `lib/widgets/verse_tile.dart`
- `lib/widgets/chapter_reader.dart` (retour « Note complète » + flash du verset)
- `test/strong_lexique_screen_test.dart`

## Fichiers à modifier pour la suite
- Aucun pour la phase Strong. (Supprimé : `screens/strong_lexique_sheet.dart` fusionné dans le lecteur, audio retiré.)

## Ordre de priorité
1. **Comparaison multi-traductions** — plusieurs textes cohabitent désormais.

## Mise à jour — interface Strong et marque (2026-08)

- La fiche de l’écran **Lexique — verset mot à mot** affiche le lemme hébreu ou grec en grand à droite du mot français. L’hébreu est rendu de droite à gauche.
- Le tap direct sur un code `H####` / `G####` de la lecture LSGS ouvre une fiche rapide structurée : référence, code Strong, lemme original, translittération/prononciation/catégorie, définition défilable, origine et bouton « Ouvrir le lexique du verset ».
- Le bouton du lexique complet ferme d’abord la fiche rapide pour ne pas empiler deux modales.
- Les visuels de `logoBym/` sont intégrés : logo d’accueil sans déformation et écran de lancement affiché entièrement, sans rognage.