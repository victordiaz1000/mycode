# -*- coding: utf-8 -*-
"""
Lecture des chapitres du NTI — le parseur, et lui seul.

Isolé ici pour la même raison que `ATI/ati_parse.py` : les règles de découpage
du HTML de Biblia sont le cœur fragile de la chaîne, et il n'en existe qu'une
définition. Deux choses seulement y sont empruntées à l'ATI, parce qu'elles ne
sont pas hébraïques mais génériques : `nu` (texte d'un fragment HTML) et
`groupe_versets` (regroupement des marqueurs et des mots en versets).

Le HTML d'un chapitre du NTI est une suite de blocs de verset, un par `<v/>`,
et **tous en gauche à droite** — l'ATI est de droite à gauche. Chaque bloc
contient trois sortes de `<table>`, toutes en `<table align="left" dir="ltr">` :

    table de numérotation   <table align="left" dir="ltr"> — un seul
                            `<span class="vn">3</span>` en troisième rangée,
                            les cinq autres rangées sont des `&nbsp;`
    table d'étiquettes      <table … frame="lhs"> — les six noms de rangée :
                            Moderne, Lemme, Koinè, Strong, Français, Analyse
    une table par mot       <table … frame="lhs"> — six `<td>` empilés, et
                            toujours exactement six, dans cet ordre :

      1 Moderne   <td><b><big>Βίβλος</big></b></td>   le mot tel qu'imprimé
      2 Lemme     <td>βίβλος</td>                     la forme-lemme
      3 Koinè     <td>βιβλοσ</td>                     sans accents, crases
                                                       abrégées (`=χυ`)
      4 Strong    <td><a … href="h.php?c=STR&f=G976"
                       title="βιβλος • …">976</a></td>
      5 Français  <td style="color:darkred"><big>
                       de genèse <small>/ <i>de généalogie</i></small>
                   </big></td>                        glose + variante
      6 Analyse   <td><small><a href="g*NTI*Analyses"
                       title="• Nature : Nom …">N-NMS</a></small></td>

Ce que le parseur suppose, **vérifié sur les 138 099 mots des 260 chapitres
avant d'être écrit** : chaque mot a ses six cellules, chaque bloc de verset a
sa table d'étiquettes, chaque numéro de verset va de 1 à N sans saut ni
doublon. Le contrôle reste dans `nti_to_json.py` — supposer n'est pas
prouver, et une source corrigée doit faire échouer la conversion.

Trois pièges, tous trois rencontrés en lecture :

**Les cellules se distinguent par leur rang, pas par leur balisage.** La
cellule Moderne et la cellule Français portent toutes deux un `<big>` ; chercher
le rouge (`style="color:darkred"`) ou le gras donnerait la glose quand il n'y
en a pas. Le rang fait foi, la balise ne fait que le confirmer.

**La variante française est dans la même cellule que la glose.** La source
l'écrit `<small>/ <i>…</i></small>` à la suite du texte principal — c'est la
ligne « de genèse / de généalogie » de la maquette. La découper avant de
retirer les balises, sinon `nu()` rend « de genèse / de généalogie » d'un seul
tenant et il est impossible de la mettre en italique ensuite.

**L'analyse développée est dans l'infobulle, pas dans le texte.** La cellule
n'affiche que `N-NMS` ; `title` porte « Nature : Nom / Déclinaison :
Nominatif / … », en `&nbsp;` et sautés à la ligne. C'est ce `title` qui devient
la `ca` du livre, exactement comme le `tiptt` de l'ATI — sans quoi la fiche du
mot ne dirait jamais ce qu'est un nominatif.

Les gloses Strong que le HTML porte en attribut `title` ne sont PAS extraites :
`StrongLexicon` les sert déjà depuis `assets/lexicon/`. Le `title` ne sert ici
qu'à distinguer le lien du mot d'un éventuel badge.
"""
import re
import sys
from pathlib import Path

# `nu` et `groupe_versets` sont génériques, pas hébraïques : on les lit chez
# l'ATI plutôt que d'en écrire une deuxième version ici. Le chemin se charge
# ici même pour que le module tienne debout tout seul.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "ATI"))
from ati_parse import groupe_versets, nu  # noqa: E402,F401

# Un mot = une colonne (`frame="lhs"`), la table d'étiquettes comprise : elle
# se reconnaît à son premier rang, pas à sa balise.
COLONNE_RE = re.compile(r'<table align="left" dir="ltr" frame="lhs">(.*?)</table>', re.S)
# `<td[^>]*>` : la cellule de glose porte `style="color:darkred"`, celle de
# l'analyse aucun attribut du tout.
CELLULE_RE = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
# Le numéro de verset : unique par bloc, toujours en troisième rangée, mais on
# le cherche dans tout le bloc — son rang n'est pas une garantie de source.
VERSET_RE = re.compile(r'class="vn">(\d+)')
# La table d'étiquettes : ses six noms, et aucun mot du corpus ne les porte.
ETIQUETTE = '<small>Moderne</small>'
# Le numéro Strong : le lien qui porte un `title`, comme dans l'ATI.
STRONG_RE = re.compile(r'<a [^>]*f=([HG]\d+)"[^>]*title="')
# La cellule de glose : le `<big>` entoure le texte, variante comprise.
GLOSE_RE = re.compile(r"<big>(.*?)</big>", re.S)
# La variante : `<small>/ texte</small>` à la suite de la glose. L'italique de
# la source n'est qu'une exception (1 occurrence sur 39 375 dans le corpus) —
# c'est le « / » qui la signale, pas la balise, donc on la lit avec ou sans.
VARIANTE_RE = re.compile(r"<small>\s*/\s*(.*?)</small>", re.S)
# L'analyse : le lien vers la page « Analyses » porte le code *et* son
# développement dans `title`.
ANALYSE_RE = re.compile(r'<a href="g\*NTI\*Analyses" title="([^"]*)">(.*?)</a>', re.S)
# Le marqueur de verset — un `<v/>` par verset, 7 957 dans tout le corpus.
BLOC_RE = re.compile(r"<v/>")

# L'infobulle d'analyse : « •&nbsp;Nature&nbsp;:&nbsp;Nom » → « Nature : Nom »,
# les puces séparant les membres d'une même analyse. Reprise du format `·` de
# l'ATI (« Nom commun · féminin singulier ») pour que la fiche ne change pas de
# voix selon le corpus.
SEP_ANALYSE = " · "


def analyse_developpee(brut):
    """Le `title` d'analyse réduit à une ligne lisible.

    « •&nbsp;Nature&nbsp;:&nbsp;Nom • Déclinaison&nbsp;:&nbsp;Nominatif » →
    « Nature : Nom · Déclinaison : Nominatif ». `nu` a déjà décodé les
    `&nbsp;` et écrasé les sauts de ligne en espaces simples.
    """
    texte = nu(brut)
    if not texte:
        return ""
    membres = [m.strip() for m in texte.split("•") if m.strip()]
    return SEP_ANALYSE.join(membres)


def _glose(cellule):
    """(glose principale, variante) de la cellule française.

    La variante n'est détachée qu'ici, **avant** de retirer les balises :
    une fois `nu()` appliqué il ne reste plus rien qui la distingue.
    """
    m = GLOSE_RE.search(cellule)
    interieur = m.group(1) if m else cellule
    v = VARIANTE_RE.search(interieur)
    if v:
        return nu(interieur[: v.start()]), nu(v.group(1))
    return nu(interieur), ""


def parse_chapitre(html, anomalies=None):
    """Colonnes d'un chapitre, dans l'ordre du document.

    Retourne une liste mêlant deux sortes d'entrées :
      {"v": 3}                      marqueur : les mots qui suivent sont au v. 3
      {"m": …, "l": …, "k": …, …}   un mot, avec les seuls champs qu'il porte

    `anomalies`, si fourni, reçoit ce que la source s'écarte de la règle des
    six cellules — jamais corrigé en silence, toujours nommé.
    """
    sorties = []
    for position, bloc in enumerate(BLOC_RE.split(html)):
        # Le premier morceau est l'en-tête du fichier, avant le premier <v/> :
        # il ne porte ni numéro ni mot.
        if position == 0:
            if COLONNE_RE.search(bloc) and anomalies is not None:
                anomalies.append(
                    f"colonne avant le premier verset ({len(COLONNE_RE.findall(bloc))})")
            continue

        m = VERSET_RE.search(bloc)
        if not m:
            if anomalies is not None:
                anomalies.append(f"bloc de verset sans numéro (position {position})")
            continue
        sorties.append({"v": int(m.group(1))})

        for colonne in COLONNE_RE.findall(bloc):
            # La table d'étiquettes nomme les rangées, elle ne porte pas de mot.
            if ETIQUETTE in colonne:
                continue
            cellules = CELLULE_RE.findall(colonne)
            if len(cellules) != 6:
                if anomalies is not None:
                    anomalies.append(
                        f"verset {m.group(1)} : colonne à {len(cellules)} cellule(s)")
                continue

            glose, variante = _glose(cellules[4])
            mot = {
                "m": nu(cellules[0]),
                "l": nu(cellules[1]),
                "k": nu(cellules[2]),
                "f": glose,
            }
            if s := STRONG_RE.search(cellules[3]):
                mot["s"] = s.group(1)
            if variante:
                mot["f2"] = variante
            if a := ANALYSE_RE.search(cellules[5]):
                code, analyse = nu(a.group(2)), analyse_developpee(a.group(1))
                if code:
                    mot["g"] = code
                if analyse:
                    mot["a"] = analyse
            if mot.get("m") or mot.get("l") or mot.get("k") or mot.get("s"):
                sorties.append(mot)
    return sorties
