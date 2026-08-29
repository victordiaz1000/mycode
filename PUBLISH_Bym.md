# PUBLISH_Bym.md — Procédure canonique MàJ BYM via GitHub

> **À lire par toute IA / humain avant de publier une correction BYM.**
> Phrase déclencheuse : `envoie le nouveau fichier sur GitHub`, `publie la MàJ BYM`, `mets à jour le texte BYM`.
> Ce fichier est la **source de vérité** du workflow. `AGENTS.md` et `appCodebar/CLAUDE.md` ne font que pointer ici.

## 1. Principe

- Le texte BYM embarqué (`bible_app/assets/bible/bym/`) est **figé à la release**.
- Les corrections post-release sont servies via un repo GitHub séparé `victordiaz1000/bym-text`.
- L'app vérifie un `manifest.json` distant et télécharge **uniquement les livres modifiés** (delta), stockés dans `<documents>/bym_updates/` (prioritaire sur l'asset).
- Code : `bible_app/lib/data/bym_update_service.dart` (vérif/apply), `bible_app/lib/data/bym_update_store.dart` (stockage), `bible_app/lib/data/local_repository.dart` (priorité), `bible_app/lib/screens/settings_screen.dart` (UI).

## 2. Repo GitHub `bym-text`

- URL : `https://github.com/victordiaz1000/bym-text` (branche `main`, public)
- Structure attendue :
  ```
  bym-text/
    manifest.json
    bym_json/
      01-Genese.json
      ...
      66-Apocalypse.json
  ```
- URL prod lue par l'app : `https://cdn.jsdelivr.net/gh/victordiaz1000/bym-text@main/manifest.json` (`bym_update_store.dart:22`) — mirror jsDelivr (évite blocage raw). Legacy `raw.githubusercontent.com/...` migrée auto.
- Format `manifest.json` :
  ```json
  {
    "version": "1.0.2",
    "updatedAt": "2026-08-22T14:00:00Z",
    "notes": "3 livres : Genèse, Exode +1 autre - abc123 corr orthographe",
    "files": ["01-Genese.json", "02-Exode.json"]
  }
  ```
  - `files` vide ou absent = les 66 livres (fallback `bym_update_service.dart:116`).
  - `version` = semver `x.y.z`, comparée par `BymUpdateService.isNewer()` (`bym_update_service.dart:62`).

## 3. Workflow complet (à suivre dans l'ordre)

### Étape A — Corriger la source markdown (OBLIGATOIRE)

```
appCodebar/bym_md/NN-Livre.md   ← SEULE source éditable
```

- **JAMAIS** éditer `bym_json/` ou `bible_app/assets/bible/bym/` à la main.
- Grammaire markdown : voir `appCodebar/CLAUDE.md` (`# Titre`, `<h>`, `## Chapitre`, `### Section`, `N:M<TAB>texte` + `<!--note-->`).
- Exemple : corriger `appCodebar/bym_md/01-Genese.md`.

### Étape B — Régénérer les JSON

```powershell
# Depuis la racine bym3/ ou appCodebar/
python appCodebar/md_to_json.py
# Défauts : appCodebar/bym_md/ -> bym_json/  (à la racine)
# Vérif : 66 fichiers, 31 169 versets
```

Puis synchroniser l'asset embarqué (pour la prochaine release APK) :

```powershell
Copy-Item bym_json\*.json bible_app\assets\bible\bym\ -Force
# Optionnel mais recommandé : vérifier
python -c "import json,glob; print(sum(len(json.load(open(f,encoding='utf-8'))['chapters']) for f in glob.glob('bym_json/*.json')))"
```

### Étape C — Générer le manifest (delta)

```powershell
# Dry-run : affiche diff vs distant, propose version
python appCodebar/generate_manifest.py

# Écrire manifest.json localement (dans bym3/manifest.json par défaut)
python appCodebar/generate_manifest.py --apply

# Forcer version/notes
python appCodebar/generate_manifest.py --apply --version 1.0.2 --notes "Corrections orthographe Ge 1:1"

# Lister les 66 (première publication ou refonte)
python appCodebar/generate_manifest.py --apply --full
```

- Le script compare les SHA256 locaux vs ceux du manifest distant (`generate_manifest.py:46`).
- Bump auto : `patch++` si ≤3 fichiers modifiés, sinon `minor++` (`generate_manifest.py:81`).

### Étape D — Publier sur GitHub (bym-text)

```powershell
# 1ère fois : cloner le repo vide (créé sur github.com)
git clone https://github.com/victordiaz1000/bym-text.git C:\Temp\bym-text

# Copier
Copy-Item manifest.json C:\Temp\bym-text\manifest.json -Force
New-Item -ItemType Directory -Force -Path C:\Temp\bym-text\bym_json | Out-Null
Copy-Item bym_json\*.json C:\Temp\bym-text\bym_json\ -Force
# OU seulement les fichiers listés dans manifest.files pour un push léger

# Pousser
cd C:\Temp\bym-text
git add manifest.json bym_json/
git commit -m "BYM 1.0.2 - corrections"
git push origin main
# jsDelivr invalide en ~5 min. Tester via :
# https://cdn.jsdelivr.net/gh/victordiaz1000/bym-text@main/manifest.json
```

Alternative en 1 commande (script) :

```powershell
.\appCodebar\publish_bym.ps1 -Notes "correction Ge 1:1" -Version 1.0.2
# ou
python appCodebar/publish_bym.py --notes "correction Ge 1:1"
```

### Étape E — Vérifier côté app

1. Lancer l'app → `Réglages > MISE À JOUR DU TEXTE` (`settings_screen.dart:597`)
2. `Vérifier les mises à jour` → doit afficher `MàJ disponible : 1.0.2`
3. `Mettre à jour maintenant` → barre de progression (`BymUpdateService.apply()` `bym_update_service.dart:110`), puis `LocalRepository.clearCache()` + `FulltextIndex.forget()`
4. Rouvrir le chapitre corrigé → `LocalRepository.loadBook()` (`local_repository.dart:60`) sert `<documents>/bym_updates/NN-*.json` (prioritaire)
5. Rollback : `Revenir au texte embarqué` → `BymUpdateStore.clear()` (`bym_update_store.dart:122`)

### Test local sans GitHub (recommandé avant push prod)

```powershell
python -m http.server 8000
# Dans Réglages > Manifest GitHub, saisir :
#   http://10.0.2.2:8000/manifest.json  (émulateur Android)
#   http://localhost:8000/manifest.json (Windows)
# Puis Vérifier
```

## 4. Règles pour IA

1. **Toujours** partir de `appCodebar/bym_md/`, jamais du JSON.
2. **Toujours** passer par `md_to_json.py` puis `generate_manifest.py --apply`.
3. **Ne jamais** `git push` dans `bym3/` le dossier `bym_json/` (généré). Seul `bym-text` reçoit les JSON publiés.
4. Après génération, vérifier `flutter analyze` et `flutter test` (dans `bible_app/`).
5. Si l'utilisateur dit `envoie sur GitHub` sans préciser version/notes, faire dry-run, proposer la version bumpée et demander confirmation avant `git push`.
6. Documenter la modif dans `notes` du manifest (ex: `Ge 1:1 orthographe`).

## 5. Fichiers clés

| Fichier | Rôle |
|---------|------|
| `appCodebar/bym_md/*.md` | Source |
| `appCodebar/md_to_json.py` | Convertisseur |
| `appCodebar/generate_manifest.py` | Génère `manifest.json` |
| `appCodebar/publish_bym.ps1/.py` | Automatise A→D |
| `PUBLISH_Bym.md` (ce fichier) | Doc canonique |
| `bible_app/lib/data/bym_update_service.dart:79` | `check()` |
| `bible_app/lib/data/bym_update_service.dart:110` | `apply()` |
| `bible_app/lib/data/bym_update_store.dart:22` | URL manifest + stockage |
| `bible_app/lib/data/local_repository.dart:60` | Priorité MàJ > asset |

## 6. Erreurs courantes

- `404 manifest` → première publication, `generate_manifest.py` part de `1.0.0` et liste les 66.
- `Échec MàJ` dans l'app → JSON invalide (doit contenir `book`) ou `status != 200` → `apply()` renvoie `false` (`bym_update_service.dart:127`).
- `raw.githubusercontent.com` bloqué → l'app migre vers `cdn.jsdelivr.net` (`bym_update_store.dart:58`).
- Tests qui hang → ne pas lire `BymUpdateStore.fileFor` en `testWidgets` sans `useDirectory()` (`bym_update_store.dart:36`).
