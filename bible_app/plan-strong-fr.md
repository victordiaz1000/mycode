# Plan : Source Française + Strong (Point 8)

## État des lieux

- **Données acquises** : `Sg1910-csv/Sg1910.csv` (LSG 1910 avec tags `<w strong="H0430">`) + script `sg1910_to_json.py` qui convertit en 66 JSON dans `sg1910_json/`.
- **App Flutter** : LSGS est embarquée dans `assets/bible/lsgs/`, reconnue comme version lisible, et le rendu de lecture affiche les numéros Strong inline.
- **Duplication nettoyée** : `appCodebar/sg1910_json/` (sortie du script, régénérable) et `Sg1910-csv.zip` sont gitignorés — une seule copie des données vit dans le dépôt (`assets/bible/lsgs/`), comme pour `bym_json/`.
- **Avancement récent** : `lib/data/lsgs_repository.dart`, `lib/models/lsgs.dart`, `lib/data/version_catalog.dart`, `lib/data/version_repository.dart`, `lib/widgets/verse_tile.dart` et `lib/widgets/clickable_verse.dart` ont été ajoutés/ajustés. Le format LSGS est différencié du format BYM.
- **Écran cliquable aligné sur la maquette v8** (`Qwen_maquette_lexique_suite.html`) : en-tête « Lexique — {livre} {ch}.{v} » + « Verset mot à mot », bandeau doré « ☞ Touchez un mot souligné du verset pour afficher sa fiche », fiche avec navigation « Mot préc. / Mot X / N du verset / Mot suiv. », pied source.
- **Audio supprimé (décision 2026-08)** : plus de `audioplayers`, de bouton « Écouter » ni de `audioUrl` — le squelette audio ne produisait que « Audio non disponible ». Le champ `hasAudio` du catalogue est retiré.
- **Validation** : `flutter analyze` sans erreur ; `flutter test` complet vert (220 tests). La **recherche Strong est câblée** (catégorie `SearchCategory.strong`, classement par position).
- **Restant** : polish UI de la fiche et « Note complète ↗ » de la maquette v8 (ouvre le verset dans la lecture).
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
- Créer `lib/data/strong_lexicon.dart` : `lookup(String strongNumber)`.

### Phase 4 — Rendu cliquable + recherche Strong
**Objectif** : aller au-delà du simple affichage et rendre le lexique réellement exploitable.
- ✅ Finaliser `widgets/clickable_verse.dart` (tap sur les mots Strong — ouvre `strong_lexique_screen.dart`).
- ✅ Ajouter un écran de lexique dédié Strong (`screens/strong_lexique_screen.dart`), aligné maquette v8.
- ✅ Brancher le bouton Lexique de la feuille d’étude selon le type de version.
- ✅ Dégriser `SearchCategory.strong` et permettre la recherche Strong (moteur + écran, classement corrigé, 6 tests `strong_lexicon_test`).
- ✅ **Fiche Strong au clic dans le chapitre** — tap dans le lecteur → `_StrongDefinitionSheet` (fiche rapide) + écran complet via le bouton « Lexique ».
- ⏳ **Polish UI** — couleur, taille, style d’affichage, accessibilité de la fiche, « Note complète ↗ ».

## Prérequis / Dépendances
- ✅ **LSGS embarquée** : le texte est désormais accessible offline.
- ✅ **Strong visible dans la lecture** : affichage inline des codes `H####` / `G####`.
- ✅ **Masquage du header vide** : les versions sans métadonnées BYM ne montrent plus de bloc vide.
- ⚠️ **Lexique Strong complet** : le dictionnaire bilingue FR est intégré (14 195 entrées, `assets/lexicon/strong_fr.json`) — solde : fiche au tap à peaufiner.
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

## Fichiers à modifier pour la suite
- `lib/screens/strong_lexique_screen.dart` — polish UI + « Note complète ↗ ».
- (Supprimé : `screens/strong_lexique_sheet.dart` fusionné dans le lecteur, audio retiré.)

## Ordre de priorité
1. **Polish UI de la fiche** — couleur, taille, style d’affichage, accessibilité, « Note complète ↗ ».
2. **Comparaison multi-traductions** — plusieurs textes cohabitent désormais.
