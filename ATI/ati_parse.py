# -*- coding: utf-8 -*-
"""
Lecture des chapitres de l'ATI — le parseur, et lui seul.

Isolé ici parce que trois outils s'en servent (`mesure_taille.py`,
`cout_par_champ.py`, `ati_to_json.py`) et que les règles de découpage du HTML de
Biblia sont le cœur fragile de la chaîne : une seule définition, pas trois.

Le HTML d'un chapitre est une suite de colonnes, une par mot hébreu, dans un
conteneur `direction: rtl`. Chaque colonne est une `<table style="display:
inline-table; …">` dont les `<td>` empilés portent, de haut en bas :

    numéro Strong      <a href="h.php?c=STR&f=H3588" title="• kiy ➔ que…">3588</a>
                       suivi, s'il y a lieu, du renvoi au glossaire :
                       <a class="glossaire" href="g*ATI*Difficulté 12">►d12</a>
    translittération   <font color="grey">kî-</font>
    hébreu vocalisé    <font face="Ezra SIL">כִּֽי<span class="tiptt">כִּֽי • י</span>
    glose française    <font color="red">car</font>
    analyse            <font color="green">Accusatif</font>
                       <span class="tiptt">Particule marqueur d'objet direct</span>

Trois pièges, tous trois rencontrés pour de vrai dans le corpus :

**L'infobulle appartient à sa cellule, pas au rang.** Deux cellules portent un
`<span class="tiptt">` : l'hébreu (découpage morphologique) et l'analyse
grammaticale. Les repérer par leur ordre d'apparition se trompe sur les mots d'un
seul morphème, qui n'ont pas d'infobulle hébraïque : leur analyse se retrouve
rangée en découpage. Mesuré à 9 colonnes sur 3 330 de l'échantillon, soit près de
900 mots à l'échelle du corpus. On lit donc cellule par cellule.

**Les renvois au glossaire ne sont pas tous des « notes ».** Trois familles s'y
mêlent — `Note N`, `Difficulté N`, `Remarque N` — plus la page `Abréviations`,
et les deux dernières sont les plus fréquentes. Les chercher par le mot « note »
en perdrait les deux tiers. On lit le `href="g*ATI*…"`, qui donne le nom exact de
la page de glossaire, et on le réduit à l'identifiant court que Biblia affiche
lui-même (`►d12` → `d12`).

**Le dernier verset d'un chapitre aligne ses cellules.** Partout ailleurs la glose
et l'analyse sont en `<td>` nu ; sur le dernier verset de chaque chapitre Biblia les
écrit en `<td align="right" dir="ltr">` — 26 218 cellules, toutes rouges ou vertes,
et pas une de plus dans tout le corpus. Une regex qui n'accepte que `<td>` littéral
laisse donc ces deux champs de côté : le mot garde Strong, translittération, hébreu
et découpage, mais perd sa glose, et le verset sort **blanc** dans le lecteur.
929 versets, 12 964 mots, 4,2 % du corpus — l'équivalent d'un chapitre sur
vingt-quatre qui s'efface. On lit donc `<td[^>]*>`, attributs acceptés.

Les gloses Strong que le HTML porte en attribut `title` ne sont PAS extraites :
`StrongLexicon` les sert déjà depuis `assets/lexicon/`.
"""
import html
import re
import unicodedata

# Un mot = une colonne.
COLONNE_RE = re.compile(r'<table style="display: inline-table;.*?</table>', re.S)
# `<td[^>]*>` et non `<td>` : les cellules de glose et d'analyse du dernier verset
# de chaque chapitre portent `align="right" dir="ltr"` (voir le troisième piège).
CELLULE_RE = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
STRONG_RE = re.compile(r'f=([HG]\d+)"')
GRIS_RE = re.compile(r'<font color="grey">(.*?)</font>', re.S)
ROUGE_RE = re.compile(r'<font color="red">(.*?)</font>', re.S)
VERT_RE = re.compile(r'<font color="green">(.*?)</font>', re.S)
TIP_RE = re.compile(r'<span class="tiptt">(.*?)</span>', re.S)
EZRA_RE = re.compile(
    r'face="Ezra SIL">(.*?)(?:<span class="tiptt">|</span>|</font>)', re.S)
GLOSSAIRE_RE = re.compile(r'href="g\*ATI\*([^"]+)"')
VERSET_RE = re.compile(r'<span class="cn">(?:<[^>]+>)*(\d+)')
BALISE_RE = re.compile(r"<[^>]+>")

# Nom de page de glossaire -> identifiant court, celui que Biblia affiche.
FAMILLES = (("note", "n"), ("difficult", "d"), ("remarque", "r"))


def nu(fragment):
    """Texte d'un fragment HTML : balises retirées, entités décodées, espaces
    normalisés.

    Les trois opérations dans cet ordre, et pas un autre. Décoder avant de
    retirer les balises ferait passer un `&lt;b&gt;` échappé — du texte — pour du
    balisage. Normaliser avant de décoder laisserait les 41 000 `&nbsp;` du
    corpus : `\\s` couvre l'espace insécable que produit le décodage, pas sa
    forme échappée. Sans quoi les analyses grammaticales arrivent dans l'app en
    « Nom commun&#183;&nbsp;féminin singulier ».
    """
    return re.sub(r"\s+", " ",
                  html.unescape(BALISE_RE.sub("", fragment or ""))).strip()


def ref_glossaire(nom):
    """« Difficulté 12 » -> « d12 ». « Abréviations » -> « abr ».

    Retourne None sur un nom inconnu, pour que l'appelant le signale plutôt que
    de le ranger sous une famille arbitraire.
    """
    plat = unicodedata.normalize("NFKD", nom).encode("ascii", "ignore").decode().lower()
    num = re.search(r"\d+", plat)
    for prefixe, lettre in FAMILLES:
        if plat.startswith(prefixe):
            return f"{lettre}{num.group(0)}" if num else lettre
    if plat.startswith("abrev"):
        return "abr"
    return None


def parse_chapitre(html, inconnus=None):
    """Colonnes d'un chapitre, dans l'ordre du document.

    Retourne une liste mêlant deux sortes d'entrées :
      {"v": 3}                      marqueur : les mots qui suivent sont au v. 3
      {"s": …, "t": …, "h": …, …}   un mot, avec les seuls champs qu'il porte

    `inconnus`, si fourni, reçoit les noms de pages de glossaire non reconnus.
    """
    sorties = []
    for colonne in COLONNE_RE.findall(html):
        cellules = CELLULE_RE.findall(colonne)
        if not cellules:
            continue

        # Colonne de numérotation : un numéro de verset, pas de mot. Le test
        # exige l'absence de translittération — un mot peut porter un `cn` sans
        # être une colonne de numéro.
        bloc = " ".join(cellules)
        if VERSET_RE.search(bloc) and not GRIS_RE.search(bloc):
            sorties.append({"v": int(VERSET_RE.search(bloc).group(1))})
            continue

        mot = {}
        for cellule in cellules:
            if m := STRONG_RE.search(cellule):
                mot["s"] = m.group(1)
            if m := GRIS_RE.search(cellule):
                mot["t"] = nu(m.group(1))
            if m := ROUGE_RE.search(cellule):
                mot["f"] = nu(m.group(1))
            if m := GLOSSAIRE_RE.search(cellule):
                if ref := ref_glossaire(m.group(1)):
                    mot["n"] = ref
                elif inconnus is not None:
                    inconnus.append(m.group(1))

            # Les deux cellules à infobulle. Chacune garde la sienne : l'ordre
            # d'apparition ne suffit pas (voir l'en-tête du module).
            if m := EZRA_RE.search(cellule):
                mot["h"] = nu(m.group(1))
                if t := TIP_RE.search(cellule):
                    mot["d"] = nu(t.group(1))
            if m := VERT_RE.search(cellule):
                mot["g"] = nu(m.group(1))
                if t := TIP_RE.search(cellule):
                    mot["a"] = nu(t.group(1))
        if mot:
            sorties.append(mot)
    return sorties


def est_mot(entree):
    return "v" not in entree


def groupe_versets(colonnes):
    """Regroupe la sortie de [parse_chapitre] en versets.

    Retourne (versets, orphelins) où `versets` est une liste de
    {"verse": n, "words": [...]} dans l'ordre rencontré, et `orphelins` le
    nombre de mots apparus avant tout marqueur de verset — une anomalie que
    l'appelant signale plutôt que de l'absorber en silence.
    """
    versets = []
    courant = None
    orphelins = 0
    for entree in colonnes:
        if not est_mot(entree):
            courant = {"verse": entree["v"], "words": []}
            versets.append(courant)
        elif courant is None:
            orphelins += 1
        else:
            courant["words"].append(entree)
    return versets, orphelins
