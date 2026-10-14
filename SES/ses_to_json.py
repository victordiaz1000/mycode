# -*- coding: utf-8 -*-
"""
Extraction de la Septuaginta + Strong (SES) depuis Biblia Universalis 3.

Source : C:\\Users\\laptek\\Documents\\Bible\\Biblia Universalis 3 (1.39)\\Ressources\\bibles\\SES.xml
Sortie : SES/json/1.json … 39.json — un fichier par livre, numérotation
         standard 1=Genèse … 39=Malachie (jeton {book} de urlTemplate).

Ce qu'est le module : le texte grec de la Septante, mot à mot, chaque mot
avec son numéro Strong et son analyse morphologique — l'Ancien Testament
seul, sans un mot de français. Même famille que l'ATI (hébreu) et le NTI
(grec du Nouveau Testament) : la sortie reprend leur schéma
(`cg`/`ca` + mots `m`/`s`/`g`/`a`), sans les clés qu'ici la source ne porte
pas — ni lemme, ni koinè, ni glose française. L'app lit ce schéma tel quel
(`bookFromAti`, rendu interlinéaire) : les colonnes montrent le grec, le
Strong et l'analyse, la ligne de texte aplati restant vide.

Format source (constaté, non documenté) :
  <bible><files><number>931</number><file><size>S</size><data>…HTML…</data></file>…
  <toc><input><name>GEN/001.html</name><addr>offset</addr></input>…</toc>

- 931 blocs = 930 chapitres + index.html. Le canon compte 929 chapitres
  (39 livres) + le Psaume 151 (fichier PSA/151.html).
- Un chapitre = une suite de blocs `<v/>`, un par verset. Chaque bloc porte
  sa colonne de numérotation (`<span class="vn">N</span>`, sans `frame`) puis
  une table par mot (`<table align="left" dir="ltr" frame="lhs">`), trois
  `<td>` empilés, toujours dans cet ordre :
      1 grec     <td><big>Ἐν</big></td>            le mot tel qu'imprimé
      2 Strong   <td><a … href="h.php?c=STR&f=G1722"
                     title="εν • …">1722</a></td>
      3 analyse  <td …><small><a href=""><span title="Nature:&nbsp;…">
                     PREP</span></small></td>       code + développement
- Pas de table d'étiquettes (le NTI en a une), pas de premier marqueur `cn`
  en ouverture de chapitre : le premier bloc porte déjà `vn=1`.
- Deux sortes de mots sans Strong : `<td>absent</td>` (27 622 fois), et
  l'ancre `f=G0` au titre vide (noms propres indéclinables type Δαν) —
  Strong 0 ne veut dire aucun numéro : abandonné, compté à part. Les autres
  ancres au titre vide (547 fois, ex. G3996) gardent leur code : le numéro
  est valide, seule la glose d'infobulle manque — et les gloses Strong
  viennent du lexique embarqué, pas de ces infobulles.
- Un doublon éditorial, prouvé mot à mot (116 mots identiques) : les 7
  derniers blocs de PSA/150.html (un `cn=151` puis `vn` 2..7) rejouent le
  fichier PSA/151.html (`vn` 1..7). Comme le `MIC/001_caduque.html` de l'ATI,
  ils sont écartés — un chapitre 150 en versets 1..6,151,2..7 serait une
  numérotation cassée, et le Psaume 151 a son propre chapitre.

Usage :  C:\\Python312\\python.exe SES/ses_to_json.py
Python 3.12, stdlib uniquement.
"""

from __future__ import annotations

import gzip
import html as html_lib
import json
import re
import sys
from collections import Counter
from pathlib import Path

SOURCE = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\SES.xml")
RACINE = Path(__file__).resolve().parent
SORTIE = RACINE / "json"

# Code TOC -> osis_id de l'app.
TOC_TO_OSIS = {
    "GEN": "Gen", "EXO": "Exod", "LEV": "Lev", "NUM": "Num", "DEU": "Deut",
    "JOS": "Josh", "JDG": "Judg", "RUT": "Ruth", "1SA": "1Sam", "2SA": "2Sam",
    "1KI": "1Kgs", "2KI": "2Kgs", "1CH": "1Chr", "2CH": "2Chr", "EZR": "Ezra",
    "NEH": "Neh", "EST": "Esth", "JOB": "Job", "PSA": "Ps", "PRO": "Prov",
    "ECC": "Eccl", "SNG": "Song", "ISA": "Isa", "JER": "Jer", "LAM": "Lam",
    "EZK": "Ezek", "DAN": "Dan", "HOS": "Hos", "JOL": "Joel", "AMO": "Amos",
    "OBA": "Obad", "JON": "Jonah", "MIC": "Mic", "NAM": "Nah", "HAB": "Hab",
    "ZEP": "Zeph", "HAG": "Hag", "ZEC": "Zech", "MAL": "Mal",
}

# (code OSIS, numéro standard, index BYM, nom français, chapitres attendus)
#
# Les chapitres attendus sont ceux du canon ; ils servent de contrôle, pas de
# consigne — un écart est signalé, jamais corrigé en silence. Mêmes 39 livres
# que l'ATI (même ordre BYM hébreu), avec le Psaume 151 en plus : 151
# chapitres aux Psaumes, pas 150.
LIVRES = [
    ("GEN", 1, 1, "Genèse", 50),
    ("EXO", 2, 2, "Exode", 40),
    ("LEV", 3, 3, "Lévitique", 27),
    ("NUM", 4, 4, "Nombres", 36),
    ("DEU", 5, 5, "Deutéronome", 34),
    ("JOS", 6, 6, "Josué", 24),
    ("JDG", 7, 7, "Juges", 21),
    ("RUT", 8, 31, "Ruth", 4),
    ("1SA", 9, 8, "1 Samuel", 31),
    ("2SA", 10, 9, "2 Samuel", 24),
    ("1KI", 11, 10, "1 Rois", 22),
    ("2KI", 12, 11, "2 Rois", 25),
    ("1CH", 13, 38, "1 Chroniques", 29),
    ("2CH", 14, 39, "2 Chroniques", 36),
    ("EZR", 15, 36, "Esdras", 10),
    ("NEH", 16, 37, "Néhémie", 13),
    ("EST", 17, 34, "Esther", 10),
    ("JOB", 18, 29, "Job", 42),
    ("PSA", 19, 27, "Psaumes", 151),
    ("PRO", 20, 28, "Proverbes", 31),
    ("ECC", 21, 33, "Ecclésiaste", 12),
    ("SNG", 22, 30, "Cantique des cantiques", 8),
    ("ISA", 23, 12, "Ésaïe", 66),
    ("JER", 24, 13, "Jérémie", 52),
    ("LAM", 25, 32, "Lamentations", 5),
    ("EZK", 26, 14, "Ézéchiel", 48),
    ("DAN", 27, 35, "Daniel", 12),
    ("HOS", 28, 15, "Osée", 14),
    ("JOL", 29, 16, "Joël", 4),
    ("AMO", 30, 17, "Amos", 9),
    ("OBA", 31, 18, "Abdias", 1),
    ("JON", 32, 19, "Jonas", 4),
    ("MIC", 33, 20, "Michée", 7),
    ("NAM", 34, 21, "Nahum", 3),
    ("HAB", 35, 22, "Habakuk", 3),
    ("ZEP", 36, 23, "Sophonie", 3),
    ("HAG", 37, 24, "Aggée", 2),
    ("ZEC", 38, 25, "Zacharie", 14),
    ("MAL", 39, 26, "Malachie", 3),
]

STANDARD_NUMBER = {code: i + 1 for i, code in enumerate(
    [l[0] for l in LIVRES])}

FILE_RE = re.compile(rb"<file>\s*<size>(\d+)</size>\s*<data>")
TOC_RE = re.compile(rb"<toc>(.*?)</toc>", re.S)
TOC_ENTRY_RE = re.compile(rb"<input><name>(.*?)</name><addr>(\d+)</addr></input>")
CHAPTER_NAME_RE = re.compile(r"^([A-Za-z0-9]{2,5})/(\d{3})\.html$")
BLOC_RE = re.compile(r"<v/>")
# Un mot = une colonne `frame="lhs"` ; la colonne de numérotation n'a pas de
# `frame` et ne passe pas ce filtre.
# Un mot = une ouverture de colonne `frame="lhs"`. Le découpage se fait sur
# les ouvertures, pas sur les fermetures : 4 tables du corpus ne sont jamais
# refermées (le mot suivant commence dans la foulée), et une fermeture
# manquante avalerait sinon le mot d'après.
OUVERTURE_RE = re.compile(r'<table align="left" dir="ltr" frame="lhs">')
CELLULE_RE = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
MARQUEUR_RE = re.compile(r'<span class="(?:cn|vn)">(\d+)(-[a-z])?</span>')
STRONG_RE = re.compile(r'href="h\.php\?c=STR&f=([HG])(\d+)"')
ANALYSE_RE = re.compile(r'<span title="([^"]*)">(.*?)</span>', re.S)
# Variante textuelle : le libellé préfixe le mot (`Variante A : Καιβαισελεηλ`,
# Jos 18) ou tient lieu de colonne (`Variante A :` seul). Le mot est gardé
# sans son préfixe, l'en-tête seul est écarté.
VARIANTE_RE = re.compile(r"^Variante [A-Z] :\s*")


def nu(fragment: str) -> str:
    """Texte d'un fragment HTML : balises retirées, entités décodées."""
    fragment = re.sub(r"<[^>]+>", "", fragment)
    return html_lib.unescape(fragment).replace("\xa0", " ").strip()


def analyse_developpee(brut: str) -> str:
    """Le `title` d'analyse réduit à une ligne — même format `·` que le NTI.

    Ici les membres sont séparés par des sauts de ligne, pas par des puces
    `•` : on découpe sur les deux.
    """
    texte = nu(brut)
    if not texte:
        return ""
    membres = [
        re.sub(r"\s+", " ", m).strip()
        for m in re.split(r"[•\r\n]+", texte)
    ]
    return " · ".join(m for m in membres if m)


def parse_mot(morceau: str, stats: Counter) -> dict | None:
    """Les rangées d'un mot -> {"m","s"?,"g"?,"a"?} ou None (pas un mot).

    Les rangées se lisent par rôle, pas par compte : la source porte des
    tables à 2 rangées (grec + morphologie `non renseigné`), à 4 (grec +
    Strong + `absent` + morphologie `non renseigné`), et une colonne
    `Variante A :` seule. Seules comptent la rangée grecque, la première
    ancre Strong et la première analyse.
    """
    cellules = CELLULE_RE.findall(morceau)
    if not cellules:
        return None
    if "</table>" not in morceau:
        stats["tables_non_fermees"] += 1
    # La cellule grecque lue en entier, comme le NTI lit sa Moderne : le Nom
    # divin y est en italique (`<big><i>ΚΥΡΙΟΣ</i></big>`, 6 575 fois), une
    # variante textuelle en préfixe (`Variante A : …`), une coquille en
    # `<big>` mal fermé — `nu` rend le mot ou rien, jamais un bout de balise.
    mot = nu(cellules[0])
    mot, reste = VARIANTE_RE.subn("", mot)
    if reste:
        if mot:
            stats["mots_variante"] += 1
        else:
            stats["entetes_variante"] += 1
            return None
    if not mot:
        stats["mots_sans_grec"] += 1
        return None
    sortie: dict = {"m": mot}
    fort = STRONG_RE.search(cellules[1]) if len(cellules) > 1 else None
    if fort is not None:
        numero = int(fort.group(2))
        if numero == 0:
            # Strong 0 (noms propres indéclinables type Δαν) : aucun numéro,
            # pas un code — abandonné, compté à part.
            stats["strong_zero"] += 1
        else:
            sortie["s"] = f"{fort.group(1)}{numero}"
    else:
        stats["mots_sans_strong"] += 1
    for cellule in cellules[1:]:
        if (a := ANALYSE_RE.search(cellule)) is not None:
            code, analyse = nu(a.group(2)), analyse_developpee(a.group(1))
            if code:
                sortie["g"] = code
            if analyse:
                sortie["a"] = analyse
            break
    else:
        stats["mots_sans_analyse"] += 1
    return sortie


# Les 7 blocs dupliqués en fin de PSA/150.html (le Psaume 151 rejoué, avec son
# propre chapitre PSA/151.html) : écartés par leur position, vérifiés par
# leurs numéros de tête — jamais corrigés en silence.
DOUBLON_PSAUME_151_TETES = [151, 2, 3, 4, 5, 6, 7]


def parse_chapitre(html: str, ref: str, stats: Counter):
    """Un chapitre HTML -> [(numéro de tête, [mots])], un par bloc `<v/>`.

    Les marqueurs vont dans l'ordre du document : les répétitions d'un même
    numéro (longs versets découpés en plusieurs groupes de colonnes) comme
    les sous-versets (`46-a`, `46-b` — 198 marqueurs) alimentent le même
    numéro de tête, fusionnés comme la SEF fusionne ses « 46a » (`sef/`).
    """
    sorties: list = []
    parties = BLOC_RE.split(html)
    if OUVERTURE_RE.search(parties[0]):
        stats["colonnes_avant_premier_verset"] += len(
            OUVERTURE_RE.findall(parties[0]))
    for position, bloc in enumerate(parties[1:], 1):
        marques = list(MARQUEUR_RE.finditer(bloc))
        if not marques:
            stats["blocs_sans_marqueur"] += 1
            if stats["blocs_sans_marqueur"] <= 3:
                print(f"  ! {ref} bloc {position} : sans marqueur, écarté")
            continue
        for i, mq in enumerate(marques):
            tete = int(mq.group(1))
            if mq.group(2):
                stats["sous_versets"] += 1
            fin = marques[i + 1].start() if i + 1 < len(marques) else len(bloc)
            mots = []
            morceaux = OUVERTURE_RE.split(bloc[mq.end():fin])
            for morceau in morceaux[1:]:
                if (mot := parse_mot(morceau, stats)) is not None:
                    mots.append(mot)
            sorties.append((tete, mots))
    return sorties


def ecrit(chemin, obj):
    texte = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    chemin.write_text(texte, encoding="utf-8")
    brut = texte.encode("utf-8")
    return len(brut), len(gzip.compress(brut, 9))


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not SOURCE.exists():
        print(f"Source introuvable : {SOURCE}")
        return 1

    raw = SOURCE.read_bytes()
    blocs = []
    for m in FILE_RE.finditer(raw):
        start = m.end()
        size = int(m.group(1))
        end = raw.find(b"</data>", start)
        while end != -1 and end - start != size:
            end = raw.find(b"</data>", end + 1)
        if end == -1:
            print(f"bloc @{m.start()} : pas de </data> à <size>={size}")
            return 1
        blocs.append((m.start(), raw[start:end]))
    toc_m = TOC_RE.search(raw)
    entries = [(n.decode("utf-8"), int(a))
               for n, a in TOC_ENTRY_RE.findall(toc_m.group(1))]
    if len(entries) != len(blocs):
        print(f"{len(entries)} TOC != {len(blocs)} blocs")
        return 1
    for (_, addr), (off, _) in zip(entries, blocs):
        if addr != off:
            print("TOC addr != offset")
            return 1

    stats: Counter = Counter()
    chapitres: dict = {}
    ecartes: list = []
    for (_, data), (name, _) in zip(blocs, entries):
        m = CHAPTER_NAME_RE.match(name)
        if not m:
            ecartes.append(name)
            continue
        toc_code, toc_chapitre = m.group(1), int(m.group(2))
        if toc_code not in TOC_TO_OSIS:
            print(f"code livre inconnu : {name}")
            return 1
        texte = data.decode("utf-8", errors="replace")
        blocs_versets = parse_chapitre(texte, name, stats)
        # Doublon éditorial : les 7 derniers blocs de PSA/150 rejouent le
        # Psaume 151 (116 mots identiques au fichier PSA/151.html) — écartés
        # par position, vérifiés par numéros de tête.
        if (toc_code, toc_chapitre) == ("PSA", 150):
            tetes = [h for h, _ in blocs_versets[-7:]]
            if tetes != DOUBLON_PSAUME_151_TETES:
                print(f"{name} : doublon attendu introuvable ({tetes})")
                return 1
            stats["doublon_psaume_151"] += 7
            blocs_versets = blocs_versets[:-7]
        # Fusion des blocs sur leur numéro de tête (sous-versets `46-a`…).
        fusionnes: dict = {}
        for tete, mots in blocs_versets:
            fusionnes.setdefault(tete, []).extend(mots)
        versets = sorted(fusionnes.items())
        numeros = [n for n, _ in versets]
        if numeros != list(range(1, len(numeros) + 1)):
            stats["chapitres_numerotation"] += 1
            print(f"  ! {name} : numéros {numeros[:8]}… ({len(numeros)} v.)")
        chapitres[(toc_code, toc_chapitre)] = versets
        stats["blocs"] += 1

    by_book: dict = {}
    for (osis_code, chapitre), versets in chapitres.items():
        osis = TOC_TO_OSIS[osis_code]
        by_book.setdefault(osis, []).append((chapitre, versets))

    # La table elle-même, avant de produire : une collision rendrait deux
    # livres indiscernables côté app.
    for champ, i in (("standard", 1), ("bym", 2)):
        vus = [l[i] for l in LIVRES]
        if len(set(vus)) != len(vus):
            print(f"Table LIVRES : doublon sur {champ}")
            return 1

    SORTIE.mkdir(parents=True, exist_ok=True)
    for old in SORTIE.glob("*.json"):
        old.unlink()

    osis_to_toc = {v: k for k, v in TOC_TO_OSIS.items()}
    lignes = []
    # LIVRES porte les codes TOC ; `by_book` est rangé par osis_id.
    for toc, standard, bym, nom, attendus in LIVRES:
        osis = TOC_TO_OSIS[toc]
        items = sorted(by_book.get(osis, []), key=lambda kv: kv[0])
        if len(items) != attendus:
            print(f"{toc} : {len(items)} chapitres, {attendus} attendus")
            return 1
        ca, cg = {}, {}
        chapitres_json = []
        nb_mots = nb_versets = nb_forts = 0
        for chapitre, versets in items:
            versets_json = []
            for numero, mots in versets:
                mots_json = []
                for mot in mots:
                    w = dict(mot)
                    if "a" in w:
                        w["a"] = ca.setdefault(w["a"], len(ca))
                    if "g" in w:
                        w["g"] = cg.setdefault(w["g"], len(cg))
                    if "s" in w:
                        nb_forts += 1
                    mots_json.append(w)
                nb_mots += len(mots_json)
                versets_json.append({"verse": numero, "words": mots_json})
            nb_versets += len(versets_json)
            chapitres_json.append({"chapter": chapitre, "verses": versets_json})
        octets, gz = ecrit(SORTIE / f"{standard}.json", {
            "bym_index": bym,
            "standard": standard,
            "book": nom,
            "osis_id": osis,
            "ca": list(ca),
            "cg": list(cg),
            "chapters": chapitres_json,
        })
        lignes.append((toc, nom, standard, bym, len(items), attendus,
                       nb_versets, nb_mots, len(ca), octets, gz))

    tot_v = sum(r[6] for r in lignes)
    tot_m = sum(r[7] for r in lignes)
    tot_o = sum(r[9] for r in lignes)
    tot_g = sum(r[10] for r in lignes)
    print(f"SES : {stats['blocs']} chapitres, {len(lignes)} livres, "
          f"{tot_v} versets, {tot_m} mots")
    print(f"  forts : {stats.get('mots_sans_strong', 0)} sans Strong, "
          f"{stats.get('strong_zero', 0)} Strong 0 écartés, "
          f"{stats.get('mots_sans_analyse', 0)} sans analyse, "
          f"{stats.get('mots_sans_grec', 0)} sans grec, "
          f"{stats.get('tables_non_fermees', 0)} tables non fermées, "
          f"{stats.get('mots_variante', 0)} mots de variante, "
          f"{stats.get('entetes_variante', 0)} en-têtes de variante")
    print(f"  doublon Psaume 151 écarté : {stats.get('doublon_psaume_151', 0)} blocs")
    print(f"  blocs sans marqueur : {stats.get('blocs_sans_marqueur', 0)}, "
          f"multi-numéros : {stats.get('blocs_multi_numeros', 0)}, "
          f"numerotation HS : {stats.get('chapitres_numerotation', 0)}")
    print(f"  écartés : {len(ecartes)} ({', '.join(ecartes)})")
    print(f"  sortie : {SORTIE} — {tot_o / 1048576:.1f} Mo clair, "
          f"{tot_g / 1048576:.1f} Mo gzip")

    # Résidus de balisage dans les JSON.
    residus = 0
    for f in SORTIE.glob("*.json"):
        t = f.read_text(encoding="utf-8")
        if re.search(r"</?(table|td|tr|span|a|big|small|div|p)[ >]", t):
            residus += 1
            print(f"  ! résidu HTML dans {f.name}")
    if residus:
        return 1
    if stats.get("chapitres_numerotation", 0):
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
