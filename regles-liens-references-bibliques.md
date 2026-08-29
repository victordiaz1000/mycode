# Règles pour détecter et lier les références bibliques dans les notes

## Contexte
Les notes/commentaires (`notes[].note` dans les fichiers JSON comme `01-Genese.json`) contiennent des références bibliques en abrégé, du type :
`Es. 7:14` · `Jos. 22:22 ; 2 S. 22:32 ; Es. 9:5, 10:21, 43:12` · `De. 6:13, 10:20`

Objectif : rendre **uniquement** les références bibliques cliquables, sans jamais transformer un nombre isolé (année, numéro de note, etc.) en lien.

---

## 1. Table des abréviations (source de vérité)

Utiliser exclusivement la table fournie (`abbreviations.txt`, format `numéro;abréviation`), 66 entrées, ex. :
```
01;Ge.
08;1 S.
09;2 S.
38;1 Ch.
66;Ap.
```
Ne jamais deviner ou générer une abréviation par ailleurs : si un texte ne matche aucune entrée de cette table, ce n'est **pas** une référence.

### ⚠️ Cas critique : abréviations à préfixe numérique
16 livres commencent par un chiffre + espace : `1 S.`, `2 S.`, `1 R.`, `2 R.`, `1 Ch.`, `2 Ch.`, `1 Co.`, `2 Co.`, `1 Th.`, `2 Th.`, `1 Ti.`, `2 Ti.`, `1 Pi.`, `2 Pi.`, `1 Jn.`, `2 Jn.`, `3 Jn.`

**C'est la source du bug observé** (capture 1 : `2 S. 22:32` où le `2` se retrouvait traité à part). Ces abréviations doivent être matchées comme **un seul bloc atomique** (`chiffre + espace + lettres + point`), jamais découpées sur l'espace. Lors du parsing, toujours tester en premier si les 2 tokens `\d\s[A-Za-zÀ-ÿ]+\.` correspondent à une entrée de la table AVANT d'interpréter le chiffre isolé comme un chapitre ou un numéro de note.

---

## 2. Grammaire d'une référence

Structure générale d'un groupe de références :
```
<Livre>. <chapitre>:<verset>[-<verset_fin>][,<verset_ou_chapitre:verset>...] [ ; <nouveau groupe> ...]
```

### Règle du point-virgule `;`
Sépare des **références indépendantes**. Après un `;`, on repart de zéro : il faut chercher une nouvelle abréviation de livre. Le livre PEUT changer, mais peut aussi rester identique si aucune nouvelle abréviation n'apparaît juste après (cas rare — à vérifier au cas par cas, ne pas supposer).

### Règle de la virgule `,`
Signifie qu'on **reste dans le même livre** que la référence qui précède dans le même groupe (depuis le dernier `;` ou le début). Deux sous-cas selon ce qui suit la virgule :
- **Contient un `:`** → nouveau chapitre:verset du même livre.
  `Es. 9:5, 10:21, 43:12` → Es. 9:5 · **Es. 10:21** · **Es. 43:12**
- **Ne contient pas de `:`** → nouveau verset, même chapitre que la référence précédente.
  `Ex. 26:20,26-27,35` → Ex. 26:20 · **Ex. 26:26-27** · **Ex. 26:35**

### Règle du tiret `-`
Indique un **intervalle de versets** dans le même chapitre : `1:26-27` = versets 26 à 27 du chapitre 1. Le chapitre ne change jamais à l'intérieur d'un tiret (aucun cas contraire observé dans le corpus).

### Règle du mot « et »
Repéré dans le corpus : `Voir Ge. 5:32 et 7:11.` → **synonyme strict de la virgule** (formulation naturelle du dernier élément d'une énumération). Même logique :
- suivi d'un `chapitre:verset` → nouveau chapitre, même livre
- suivi d'un simple numéro → nouveau verset, même chapitre

⚠️ « et » est un mot très courant en français : ne le traiter comme séparateur de référence **que si** il est immédiatement suivi d'un pattern numérique qui résout en référence valide (`\d+:\d+` ou `\d+` dans le contexte livre/chapitre courant). Sinon, l'ignorer complètement (ex. « Adam et Ève » ne doit jamais être touché).

---

## 3. Algorithme de parsing (pseudo-code)

```
pour chaque note.note (texte) :
  extraire tous les blocs candidats avec la regex :
    (?:\d\s)?[A-ZÀ-Ö][a-zà-ÿ]{0,4}\.\s?\d{1,3}:\d{1,3}(-\d{1,3})?(?:\s*[,;]\s*\d{1,3}(:\d{1,3})?(-\d{1,3})?)*

  découper le bloc en groupes sur ";"
  livre_courant = null
  chapitre_courant = null

  pour chaque groupe (séparé par ";") :
    découper le groupe en sous-tokens sur "," ET sur " et " (uniquement si " et " est suivi d'un motif numérique valide \d+:\d+ ou \d+ ; sinon ne pas découper à cet endroit)
    pour chaque sous-token :
      si sous-token commence par une abréviation valide de la table (test du cas 2-mots EN PREMIER) :
          livre_courant = cette abréviation
          chapitre_courant = chapitre extrait
          verset(s) = verset(s) extrait(s)
      sinon si sous-token contient ":" :
          # reste dans livre_courant, nouveau chapitre
          chapitre_courant = chapitre extrait
          verset(s) = verset(s) extrait(s)
      sinon :
          # reste dans livre_courant ET chapitre_courant, nouveau(x) verset(s)
          verset(s) = sous-token (potentiellement avec "-")

      construire la référence complète = livre_courant + chapitre_courant + verset(s)
      créer le lien UNIQUEMENT sur le texte affiché de ce sous-token
      (jamais sur un chiffre isolé qui n'a pas été résolu via ce processus)
```

## 4. Garde-fous obligatoires

1. **Ne jamais lier un nombre qui n'appartient pas à un bloc validé par la regex ci-dessus.** Un numéro de note (`1 ·`, `2 ·`), une année, un numéro de verset affiché en exposant (`23` dans l'image 1) ne sont jamais des cibles de lien.
2. **Ne jamais découper une abréviation à préfixe numérique** (`1 S.`, `2 Co.`, etc.) — la valider comme un tout via la table avant tout traitement du chiffre.
3. **Chaque sous-token séparé par `,` ou `;` doit produire un lien indépendant**, avec sa propre cible (livre/chapitre/verset), y compris les continuations implicites (bug de la capture 2 : `10:20` doit être lié en `De. 10:20`).
4. **Le texte visible du lien = exactement le sous-token d'origine** (ex. `10:21`, pas `Es. 10:21`) — seule la donnée de destination (href/route) porte le livre+chapitre+verset complets reconstitués.
5. Si un sous-token ne peut pas être résolu avec certitude (ambiguïté, format inconnu), **ne pas créer de lien** plutôt que de deviner.

## 5. Cas de test à valider avant mise en prod

- `Es. 7:14` → 1 lien : Es. 7:14
- `Jos. 22:22 ; 2 S. 22:32 ; Es. 9:5, 10:21, 43:12` → 5 liens : Jos. 22:22 / 2 S. 22:32 / Es. 9:5 / Es. 10:21 / Es. 43:12
- `De. 6:13, 10:20` → 2 liens : De. 6:13 / De. 10:20
- `Ex. 25:12,14, 26:20,26-27,35, 27:7, 30:4, 36:25,31-32, 37:3,5,27, 38:7` → tous les segments doivent résoudre vers le livre Ex., en changeant de chapitre uniquement quand un `:` apparaît
- `Ge. 5:32 et 7:11` → 2 liens : Ge. 5:32 / Ge. 7:11
- `Adam et Ève` → 0 lien (« et » non suivi d'un motif numérique, ignoré)
