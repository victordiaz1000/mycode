# -*- coding: utf-8 -*-
"""Récupère les définitions de la numérotation étendue hébreue et grecque.

Le lexique Strong d'emcitv (ex-enseignemoi.com) couvre la plage que Biblia
annonce dans son aide (« codes hébreu 1 à 8853, grecs 1 à 5799 ») mais que ni
le lexique embarqué ni les dictionnaires de Biblia ne peuplent. Chaque entrée
y est une combinaison grammaticale — « Radical - Qal », « Mode - Imparfait »,
« Temps - Présent » — et non une lexie, ce qui correspond à ce que l'on
observe dans la LSS.

Déjà-fait conservé : une entrée lue à un tour précédent n'est pas relu. Les
deux plages peuvent donc partir en parallèle sur des sorties différentes
(`--sortie`) qui se fusionnent ensuite.

Usage :
    python recupere_etendu_emcitv.py [--langues hebreu grec]
                                     [--sortie fichier.json]

Sortie : extraction/strong_etendu_glosses.json
"""
import argparse
import json
import re
import time
import unicodedata
from datetime import date
from html import unescape as html_unescape
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "https://emcitv.com"
RECHERCHE = BASE + "/bible/strong/search-bible-strong.php?search={n}&type={langue}"

# La borne haute vient de l'aide de Biblia, pas de la source : la sonder
# au-delà sert à vérifier qu'on n'a rien laissé tomber, pas à l'explorer.
PLAGES = {
    "hebreu": ("H", 8675, 8853),
    "grec": ("G", 5625, 5799),
}

SORTIE = Path(__file__).with_name("strong_etendu_glosses.json")
UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)
PAUSE = 0.15
ESSAIS = 3


def get(url):
    """HTML de [url], ou None si la page n'existe pas (404 compris)."""
    for tentative in range(ESSAIS):
        try:
            req = Request(url, headers={"User-Agent": UA, "Accept-Language": "fr"})
            with urlopen(req, timeout=30) as r:
                return r.read().decode("utf-8", "replace")
        except HTTPError as e:
            if e.code == 404:
                return None
            if tentative == ESSAIS - 1:
                raise
        except URLError:
            if tentative == ESSAIS - 1:
                raise
        time.sleep(1.5 * (tentative + 1))
        time.sleep(PAUSE)
    return None


def nom_et_lien(html, num):
    """Le nom de l'entrée et son lien tels que la recherche les rend.

    Seules les pages finissant par `-{num}.html` comptent : le reste est la
    navigation du site (« Strong grec & hébreu ») ou l'index général. La
    première ancre est le code lui-même, la suivante porte le libellé.
    """
    queue = f"-{num}.html"
    for href, texte in re.findall(r'<a href="([^"]+)"[^>]*>(.*?)</a>', html, re.S):
        if "strong-biblique" not in href or not href.endswith(queue):
            continue
        brut = re.sub(r"<[^>]+>", "", texte)
        brut = brut.replace("\\-", "-").replace("&nbsp;", " ").strip()
        if not brut or brut.isdigit():
            continue
        return brut, href
    return None, None


def slug(nom):
    """« Radical - Qal » → « radical-qal »."""
    nettoye = unicodedata.normalize("NFKD", nom)
    nettoye = "".join(c for c in nettoye if not unicodedata.combining(c))
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", nettoye.lower())).strip("-")


def detail(html):
    """Le bloc « Définition de … » : libellé, radical, mode, champs annexes.

    Le site écrit un seul `<p>` découpé par `<br>`, de la forme
    `Voir <a>Hifil (8818)</a>` puis `Mode - Imparfait Voir <a>Imparfait
    (8811)</a>` puis `Nombre - …`. La première ligne est toujours le radical ;
    les suivantes portent un libellé. On garde aussi le texte nu : certaines
    entrées (les termes seuls, « Qal », « Imparfait ») ne suivent pas ce plan.
    """
    i = html.find("Définition de")
    if i < 0:
        i = html.find("D&eacute;finition de")
    if i < 0:
        return {}
    p, q = html.find("<p>", i), html.find("</p>", i)
    if p < 0 or q < 0:
        return {}
    champs, brut = {}, []
    for ligne in re.split(r"<br\s*/?>", html[p + 3:q]):
        lien = re.search(r">([^<>]+)\((\d+)\)</a>", ligne)
        nom_lien = lien.group(1).strip() if lien else None
        code_lien = lien.group(2) if lien else None
        ligne = re.sub(r"<a[^>]*>.*?</a>", "", ligne, flags=re.S)
        ligne = html_unescape(re.sub(r"<[^>]+>", "", ligne))
        ligne = re.sub(r"\s+", " ", ligne).replace("\xa0", " ").strip()
        ligne = re.sub(r"^Voir\s+", "", ligne).strip()
        ligne = re.sub(r"\s*Voir\s*$", "", ligne).strip()
        if not ligne and not code_lien:
            continue
        brut.append(ligne)
        if " - " in ligne:
            cle, valeur = ligne.split(" - ", 1)
            cle, valeur = cle.strip().lower(), valeur.strip()
            if valeur:
                champs[cle] = valeur
            if code_lien:
                champs[cle + "_code"] = code_lien
        elif code_lien:
            cle = "radical" if "radical" not in champs else "terme"
            champs[cle] = nom_lien or ligne
            champs[cle + "_code"] = code_lien
        elif ligne:
            champs["texte"] = (champs.get("texte", "") + " " + ligne).strip()
    if brut:
        champs["brut"] = " / ".join(brut)
    return champs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--langues",
        nargs="+",
        default=list(PLAGES),
        choices=list(PLAGES),
        help="quelles plages lire (les entrées déjà lues sont conservées)",
    )
    ap.add_argument(
        "--sortie",
        default=str(SORTIE),
        help="fichier d'écriture : une plage en cours peut partir sur la "
             "sienne, les deux se fusionnent ensuite",
    )
    args = ap.parse_args()
    sortie = Path(args.sortie)

    # Ce qu'un tour précédent a déjà lu n'est pas relu : la récupération des
    # H ne repart pas de zéro quand on vient chercher les G.
    entrees = {}
    if sortie.exists():
        ancien = json.loads(sortie.read_text(encoding="utf-8"))
        entrees = ancien.get("entrees", {}) or {}

    manquants = []
    for langue in args.langues:
        lettre, debut, fin = PLAGES[langue]
        for num in range(debut, fin + 1):
            code = f"{lettre}{num}"
            if code in entrees:
                continue
            html = get(RECHERCHE.format(n=num, langue=langue))
            nom, lien = (nom_et_lien(html, num) if html else (None, None))
            if not nom:
                manquants.append(code)
                continue
            corps = get(BASE + lien) if lien else None
            if corps is None:
                # lien cassé : on reconstruit depuis le libellé (« Radical - Qal »)
                corps = get(
                    f"{BASE}/bible/strong-biblique-{langue}"
                    f"-{slug(nom)}-{num}.html"
                )
            champs = detail(corps) if corps else {}
            entrees[code] = {"nom": nom, **champs}
            radical = champs.get("radical")
            print(
                f"{code:<7s} {nom:<28s} {champs.get('mode', '')} "
                + (f"(radical {radical})" if radical else "")
            )
            time.sleep(PAUSE)

    tri = sorted(entrees, key=lambda c: (c[:1], int(c[1:]) if c[1:].isdigit() else 0))
    couvertes = {
        langue: f"{lettre}{debut}-{lettre}{fin}"
        for langue, (lettre, debut, fin) in PLAGES.items()
        if any(c.startswith(lettre) for c in tri)
    }
    sortie.write_text(
        json.dumps(
            {
                "_source": "https://emcitv.com/bible/strong/ — lexique Strong "
                           "français, numérotation étendue (peuplée, contrairement "
                           "au lexique embarqué de Biblia)",
                "_recupere": date.today().isoformat(),
                "_plages": couvertes,
                "_manquants": manquants,
                "entrees": {code: entrees[code] for code in tri},
            },
            ensure_ascii=False,
            indent=1,
        ),
        encoding="utf-8",
    )
    print(f"\n{len(entrees)} entrées dont {len(manquants)} manquantes → {sortie}")
    if manquants:
        print("manquants :", manquants)


if __name__ == "__main__":
    main()
