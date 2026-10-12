# chatiment.json — Suppression des en-têtes de page (note de passation)

## Contexte

- **Fichier** : `appCodebar/chatiment.json`
- **Dépôt GitHub** : `victordiaz1000/pdf-bym` (public, servi par raw.githubusercontent)
- **Livre** : *Le châtiment du Père* — ouvrage d'édification lu par l'app BYM.
- **App** : `bible_app/` (Flutter). Le JSON est lu par `lib/data/work_reader.dart`,
  rendu par `lib/widgets/work_reader.dart` + `note_aware_text.dart`.

## État actuel (après restauration)

Version poussée sur `pdf-bym` : commit `88cc8978` (identique au local, bit à bit).

- Texte des paragraphes **intact**.
- **172 en-têtes de page** encore présents dans le corps (c'est la tâche à traiter).
- Correction **Hébreux 12:5-8** déjà appliquée et validée (à ne pas casser) :
  - `"reference": "Hébreux 12: 5-8"` (et non plus `5-81`).
  - La note « Les versets bibliques… » est rattachée au mot **`fils`**
    (`notes:[{word:"fils",position:336,note:"…"}]`), bloc `quote` de l'AVANT-PROPOS.
  - Le paragraphe brut « 1 Les versets bibliques… » a été retiré (redondant).
- **45 notes**, invariant `text[position:position+len(word)] == word` : **0 violation**.

## La tâche

Supprimer les **en-têtes de page** (running headers) : le titre du chapitre répété
en tête de chaque page de la section, qu pdftotext a extrait comme du contenu.

Exemple (chapitre « 1. ELOHÎM : POSITION ET RÔLE ») : le titre apparaît **17 fois**
dans le corps, alors que l'app affiche déjà `chapter.title` via `_chapterHeader`
(`work_reader.dart` ~ligne 1058). Donc ces répétitions sont du doubling.

### Chapitres concernés (nombre approximatif d'en-têtes)

| ch | Titre | En-têtes |
|----|-------|---------|
| 3 | 1. ELOHÎM : POSITION ET RÔLE | ~17 |
| 4 | 2. LE CHÂTIMENT | ~31 |
| 5 | 3. LE CHÂTIMENT DU PÈRE : RAISONS ET CAUSES | ~58 |
| 6 | 4. LE CHÂTIMENT DU SEIGNEUR : COMMENT ELOHÎM CHÂTIE-T-IL ? | ~43 |
| 7 | 5. LES CONSÉQUENCES DU CHÂTIMENT DU PÈRE : L'ÉPREUVE DE LA FOI | ~22 |
| 9, 10 | annexes | ~1 chacun |

AVANT-PROPOS, NOTE DE L'AUTEUR, INTRODUCTION, CONCLUSION : nets, ne pas y toucher.

## ⚠️ Cause racine d'un bug déjà rencontré (À NE PAS REPRODUIRE)

Une tentative de suppression a **détruit le texte**. Voici pourquoi, pour l'éviter :

1. pdftotext ne met **pas toujours** l'en-tête dans un bloc isolé. Parfois le titre
   est **glué en fin ou au milieu d'un paragraphe**, par ex. :
   - `« …les saints commandements de notre LE CHÂTIMENT »`
   - `« …ceux qui se rendent coupables LE CHÂTIMENT DU PÈRE : RAISONS ET CAUSES »`
2. La tentative précédente ne détectait comme « en-tête » que les blocs dont le
   texte **entier** égalait le titre (`text == titre`, court). Elle a donc **raté**
   les en-têtes incrustés, puis a « recousu » deux blocs en faisant entrer le titre
   dans le paragraphe → texte corrompu.

**Conséquence** : il faut traiter **deux formes** d'en-tête :
- (a) les **blocs isolés** dont le texte est exactement le titre ;
- (b) les occurrences du titre **incrustées dans le texte** d'un paragraphe
  (retrait par expression régulière, en conservant le reste du paragraphe).

## Recommandations de traitement

- Détecter le titre avec normalisation souple (casse, accents, espaces, numéro de
  chapitre « N. » optionnel devant ou derrière).
- Pour les en-têtes **incrustés** : retirer uniquement la sous-chaîne du titre,
  **sans** recoudre deux blocs différents (le paragraphe garde son texte).
- Pour les **blocs isolés** : supprimer le bloc. Si le paragraphe précédent se
  termine **sans ponctuation de fin** (phrase coupée par la page) ET que le bloc
  suivant est un vrai `p`, recoudre les deux en **décalant les `position` des notes**
  du bloc suivant de `len(prev)+1` (sinon l'invariant de note casse).
- Ne jamais recoudre si l'un des deux blocs porte des notes sans appliquer ce décalage.
- Ne pas toucher aux blocs `h2/h3/h4` (vrais sous-titres de section) ni aux `quote`.

## Schéma des notes (convention BYM) — à respecter

Un bloc note porte :
```json
{
  "type": "p",
  "text": "… texte nu …",
  "notes": [ { "word": "mot", "position": 42, "note": "texte de la note" } ],
  "textWithNotes": "… texte nu avec la note entre [crochets] après le mot …"
}
```
- **Invariant obligatoire** : `text[position : position+len(word)] == word`.
- `textWithNotes` = `with_notes(text, notes)` : pour chaque note (triée par
  position), `text[cursor : position+len(word)] + " [" + note + "]"`.
- Vérifier après traitement : **0 invariant violé**, aucun titre résiduel,
  JSON valide. Le script ne doit écrire le fichier qu'après validation.

## Référence utile

La logique officielle d'attachement/détachement des notes est dans
`appCodebar/pdf_book_to_json.py` : fonctions `attach_notes`, `glued_notes`,
`with_notes`, `marker_patterns`, `WORD_BEFORE` (~lignes 1099-1231).
