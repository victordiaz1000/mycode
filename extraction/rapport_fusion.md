# Fusion strong_fr.json + HEB/GRC → strong_fr_v2.json

- sortie : `extraction/strong_fr_v2.json`
- schéma : `bym.strong.v2`, inchangé — le chargeur Dart ne lit que les
  champs qu'il connaît : l'objet `biblia` par entrée est simplement
  ignoré en lecture
- source : CrossWire/SWORD FreStrongsHebrew + FreStrongsGreek ; sections supplémentaires : Biblia Universalis 3 (1.39) dictionnaires HEB/GRC
- copyright : Biblia Universalis — Laurent Soufflet © 2016–2026

## Chaîne de production

```
appCodebar/sword_zld_to_json.py  → assets/lexicon/strong_fr.json    (base, embarquée)
extraction/extract_heb_grc.py    → extraction/{HEB,GRC}/entries.json
extraction/fusion_strong_v2.py   → extraction/strong_fr_v2.json   (hors bundle)
```

Ce fichier fusionné n'est **pas embarqué** : l'application lit
`assets/lexicon/strong_fr.json`, la base SWORD. La sortie vit dans
`extraction/` parce que le `pubspec.yaml` liste `assets/lexicon/` en entier :
y déposer la fusion la remonterait dans le bundle. Pour la réintégrer —
`--sortie bible_app/assets/lexicon/strong_fr_v2.json`, déclarer ce fichier
dans le `pubspec.yaml` (à l'unité, jamais le dossier) et pointer `_assetPath`
de `strong_lexicon.dart` dessus.

## Contenu ajouté (objet `biblia`)

| champ | entrées | origine |
| --- | --- | --- |
| `biblia.occurrences` | 14175 | Occurrences (livres + total) |
| `biblia.nature` | 1318 | Nature du mot, seulement si ≠ `partOfSpeech` |
| `biblia.etymology` | 11571 | Étymologie, seulement si ≠ `etymology` (en-tête lemma retiré) |
| `biblia.synonyms` | 167 | Synonymes (GRC) |
| `biblia.spicq` | 2 | Définition approfondie Spicq (GRC) |

## Écartés

- **Définition Bailly** et **Définition Sander et Trenel** : rejetés à la
  demande. Ni ces textes, ni aucun HTML brut, ni les champs `sections`,
  `strongDefinition`, `strongLineNumber` et `source` au sein d'une entrée —
  contrôle inclus dans le générateur (`FORBIDDEN`).

## Créées

- G2994, G2995 : entrées complètes (lemma, nature, sens,
  plan, définition), citées par le LSGS mais absentes de `strong_fr.json`.

## Contrôles — exécutés à chaque génération

- base intacte : les 11 champs du schéma repris champ par champ ;
- clés bannies absentes, aucun balisage résiduel ;
- `python extraction/valider_v2.py` : relecture indépendante du fichier
  écrit (même contrôles, plus en-tête, entrées créées et compteurs
  `biblia`).

## Poids

- base : 9.25 Mo → fusion : 14.11 Mo
- entrées : 14195 + 2 créées = 14197

Régénérer : `python extraction/fusion_strong_v2.py` (ce fichier suit).
