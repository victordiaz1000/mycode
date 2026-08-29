# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projet

Conversion des 66 livres de la Bible (version BYM, en français) du format Markdown vers JSON, en vue d'une application de lecture/étude biblique.

## Commandes

```bash
python md_to_json.py                      # convertit bym_md/ -> bym_json/
python md_to_json.py <source> <dest>      # dossiers personnalisés
python generate_manifest.py --apply       # génère manifest.json (voir PUBLISH_Bym.md)
python publish_bym.py --notes "corr Ge 1:1"  # publie MàJ BYM sur GitHub (bym-text)
```

> **MàJ BYM via GitHub :** toute correction de texte suit `../PUBLISH_Bym.md` (doc canonique).
> Source = `bym_md/` → `md_to_json.py` → `generate_manifest.py` → `publish_bym.py` → repo `victordiaz1000/bym-text`.
> Ne jamais éditer `bym_json/` à la main. Phrase déclencheuse : `envoie sur GitHub` / `publie la MàJ BYM`.

Python 3.12, aucune dépendance externe (stdlib uniquement).

## Structure

- `bym_md/` — source : 66 fichiers `NN-Livre.md` (ne pas modifier, c'est la donnée d'origine)
- `md_to_json.py` — script de conversion
- `bym_json/` — sortie générée : un JSON par livre (regénérable à volonté, ne pas éditer à la main)

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

## Contexte utilisateur

L'utilisateur communique en français.
