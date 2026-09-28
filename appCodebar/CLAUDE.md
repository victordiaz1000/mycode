# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Conversion des 66 livres de la Bible (version BYM, en français) du format Markdown vers JSON, en vue d'une application de lecture/étude biblique.

Ce dossier porte aussi un second convertisseur, `html_verses_to_json.py`, qui traite des corpus externes (Chouraqui, King James Française) au format HTML — voir « Corpus hébergés » plus bas : d'autres sources, d'autres règles, mais **le même invariant de comptes, 31 169 versets**.

## Commandes

```bash
python sync_bym_source.py --dry-run       # MàJ du texte : ce qui serait synchronisé
python sync_bym_source.py                 # applique (télécharge, convertit, écrit _source.json)
python sync_bym_source.py --all           # retélécharge et reconvertit les 66 livres
python md_to_json.py                      # convertit bym_md/ -> bym_json/ (sortie de travail)
python md_to_json.py <source> <dest>      # dossiers personnalisés
python html_verses_to_json.py <source> <dest> [nom] [abbr] [--bym <assets/bible/bym>]
                                           # corpus HTML (CHO, KJF) -> JSON getbible
```

> **MàJ du texte BYM depuis GitLab :** toute correction de texte suit `../MAJ_TEXTE_BYM.md` (doc
> canonique, écrite d'après le code livré). Phrase déclencheuse : `mets à jour le texte BYM` /
> `synchronise avec GitLab`.
> Source officielle = `https://gitlab.com/anjc/bjc-source` (public, 66 `.md`, branche `master`)
> → `sync_bym_source.py` → `bym_md/` + `bible_app/assets/bible/bym/*.json` + `_source.json`,
> ce dernier étant la référence que `bible_app/lib/data/bym_update_service.dart` compare à
> l'arbre distant. **Committer `_source.json` avec les JSON qu'il décrit.**
> Ne jamais éditer `bym_md/` (miroir de l'amont) ni `assets/bible/bym/` (généré) à la main.
> `--dry-run` d'abord, toujours.
> Le signal de changement est l'**empreinte de blob git** — `sha1("blob <len>\0" + octets)`,
> soit l'`id` que GitLab publie dans l'arbre. Elle porte sur les octets exacts : plus aucune
> normalisation de fin de ligne. `git_blob_id` (Python) et `gitBlobId` (Dart) doivent rester
> identiques.
> L'application convertit elle-même les `.md` (`lib/data/bym_markdown_converter.dart`, port de
> `md_to_json.py`) : toute correction de l'un doit être portée dans l'autre, et
> `test/bym_markdown_converter_golden_test.dart` échoue à la première divergence.
> Il n'y a plus de dépôt miroir, plus de manifest, plus de tag, plus de purge de cache :
> `publish_bym.py`, `generate_manifest.py` et `PUBLISH_Bym.md` ont été supprimés.

Python 3.12, aucune dépendance externe (stdlib uniquement).

## Structure

- `bym_md/` — miroir des 66 `NN-Livre.md` du dépôt GitLab (écrit par `sync_bym_source.py`, ne pas éditer)
- `md_to_json.py` — script de conversion, référence du format ; son port Dart est `bym_markdown_converter.dart`
- `sync_bym_source.py` — la seule commande du flux de mise à jour du texte
- `html_verses_to_json.py` — l'autre convertisseur : corpus HTML externes (CHO, KJF) → JSON getbible
- `bym_json/` — sortie de travail de `md_to_json.py` sans argument (regénérable, non embarquée)
- `../bible_app/assets/bible/bym/` — les JSON réellement embarqués, plus `_source.json`

## Format Markdown source

- `# Titre (Nom français) (Abrév.)` — titre du livre
- `<h>...</h>` — bloc de métadonnées (Signification, Auteur, Thème, Date de rédaction)
- Paragraphes avant le premier chapitre — introduction du livre
- `## Chapitre N` / `### Titre de section`
- Versets : `N:M<TAB>texte`, avec deux types d'annotations :
  - `<w lemma="strong:HXXXX">mot</w>` — codes Strong (supprimés à la conversion, seul le texte est gardé)
  - `<!--commentaire-->` collé au mot qu'il annote — extrait comme note

## Format JSON de sortie (choix validés par l'utilisateur)

```json
{
  "book": "Bereshit (Genèse)",
  "abbreviation": "Ge.",
  "metadata": { "signification": "...", "auteur": "...", "theme": "...", "date": "..." },
  "introduction": "...",
  "chapters": [{
    "chapter": 1,
    "verses": [{
      "verse": "1:2",
      "section": "Titre de section",
      "text": "texte propre sans balises",
      "textWithNotes": "texte avec chaque note inline entre [crochets] après son mot",
      "notes": [{ "word": "devint", "position": 9, "note": "Voir Es. 45:18." }]
    }]
  }]
}
```

Points importants :
- `section` n'est présent que sur le **premier verset** suivant un titre `###` (choix utilisateur — ne pas changer sans demander)
- `notes.position` = index de caractère du début du mot dans `text` ; invariant vérifié : `text[position : position+len(word)] == word`
- `textWithNotes` et `notes` ne sont présents que si le verset a des notes
- Sortie attendue : 66 livres, 31 169 versets au total (vérification de non-régression rapide)
- JSON en UTF-8 (`ensure_ascii=False`) — les `�` dans la console Windows sont un artefact d'affichage, pas un bug d'encodage

## Corpus hébergés (Chouraqui, King James Française)

L'app ne sert pas que la BYM : `version_catalog.dart` donne à `DownloadService` un `urlTemplate` vers `raw.githubusercontent.com/victordiaz1000/-bym-bibles/main/<sous-dossier>/{book}.json` — un JSON par livre, **ordre standard 1..66**. Ces JSON sont produits par `html_verses_to_json.py` puis poussés **à la main** dans le dépôt `victordiaz1000/-bym-bibles` (seul maillon manuel de la chaîne, décrit dans `../AGENTS.off.md` § 4.3).

- **Source** : archives HTML livrées par l'utilisateur, un dossier par livre au code OSIS (`GEN/`, `1CH/`…), un fichier `<NNN>.html` par chapitre, balisage `<v/>` + `<span class="cn|vn">`
- **Commande** : `python html_verses_to_json.py <source> <dest> "<Nom>" <ID> --bym ../bible_app/assets/bible/bym`
- **Retiré** : entêtes de livre, titres de section (`<h3>`), retours de ligne — le schéma getbible ne porte que du texte nu
- **Canon 66** : deutérocanoniques ignorés, chapitres supplémentaires d'Esther et de Daniel coupés (Daniel 14 → 12)
- **Les numéros imprimés ne font pas foi — la position fait foi** : les corpus impriment des fautes (`222`, `74` pour 174, un « 55 » hébreu en tête de Genèse 32) ; renumérotation 1…N par position, chaque écart listé en avertissement pour qu'un défaut du texte source reste visible
- **Aucune espace n'est retirée du texte** : les `&nbsp;` deviennent des espaces simples (typographie française, comme la BYM) — ne jamais réintroduire de suppression devant la ponctuation
- **`--bym`** compare les comptes chapitre par chapitre : **31 169 = BYM exact**. Écarts connus et acceptés (divisions de versets propres au texte, identiques des deux côtés) : Actes 19, 2 Corinthiens 13, 3 Jean 1, Apocalypse 12
- **Publication** : sortie poussée telle quelle dans `-bym-bibles` (sous `chouraqui/`, `kjf/`). La ligne `rights` de chaque version, dans `version_catalog.dart`, vient de l'index du corpus source et ne se raccourcit pas

> Le balisage exact, les fautes d'impression relevées et les règles de canon sont détaillés dans le **docstring de `html_verses_to_json.py`** — le lire avant d'y toucher. `KJF.zip` porte une correction à la main (Psaumes 44:24 manquait dans le fichier source) : repartir de l'archive corrigée, sinon une régénération réinstallerait le trou.

## Contexte utilisateur

L'utilisateur communique en français.
