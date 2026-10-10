# -*- coding: utf-8 -*-
"""
Identifie les codes Strong « étendus » de la LSS — H8675 et plus, G5625 et
plus — en l'alignant sur le texte hébreu de WLS (Westminster Leningrad).

Principe
--------
WLS écrit chaque mot hébreu suivi de son Strong standard, et laisse les
particules SANS ancre — elles sont là, en toutes lettres, juste avant le code
suivant :

    <big>וַֽיְהִי</big> <a f=H1961>1961</a>

La LSS, elle, découpe ce même mot en deux : `soit[H1961] [[H8799]]`. Entre
deux codes standard appariés des deux côtés, le mot WLS resté sans ancre et le
code étendu LSS se répondent donc 1 pour 1.

Sortie : extraction/strong_etendu.json
    {code: {"total": n, "attribues": n, "lemmes": {mot: n}, "exemples": [...]}}
"""
import difflib
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
from extract_lgs_lss import (  # noqa: E402
    CHAPTER_NAME_RE, MARK_RE, TOC_TO_OSIS,
)

WLS_SOURCE = r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\WLS.xml"
LSS_DIR = r"C:\Users\laptek\Desktop\bym3\extraction\LSS"
OUT_JSON = r"C:\Users\laptek\Desktop\bym3\extraction\strong_etendu.json"

# Un événement est soit un mot hébreu (<big>…</big>), soit une ancre Strong.
EVENT_RE = re.compile(
    r'<big>(?P<mot>.*?)</big>'
    r'|<a\b[^>]*href="h\.php\?c=STR&f=(?P<code>[HG]\d+)"[^>]*>',
    re.S,
)
HEB_RE = re.compile(r"[א-ת]")            # une lettre hébreue, ponctuation exclue
# Niqqud et accentuation : le lemme se retient aux consonnes (וַיְהִי → ויהי).
# Niqqud et accentuation : U+0591–U+05C7 seulement. Les lettres commencent à
# U+05D0 (א) — une plage comme [֑-ׇי-׿] avalerait י כ ל מ נ ע פ ר ש ת.
ACCENTS_RE = re.compile(r"[֑-ׇ]")
# ס et פ, seuls, sont les marques de paragraphe du codex, pas des mots.
PARAGRAPHE = {"ס", "פ"}
STRONG_RE = re.compile(r"^([HG])(\d+)$")


def est_etendu(code: str) -> bool:
    m = STRONG_RE.match(code or "")
    if not m:
        return False
    n = int(m.group(2))
    return n > (8674 if m.group(1) == "H" else 5624)


# --------------------------------------------------------------------------- #
# Programme principal                                                          #
# --------------------------------------------------------------------------- #

def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    # --- index osis_id -> bym_index, depuis les JSON de la LSS ---------------
    osis_vers_bym = {}
    bym_vers_json = {}
    for path in glob.glob(os.path.join(LSS_DIR, "*.json")):
        doc = json.load(open(path, encoding="utf-8"))
        osis_vers_bym[doc["osis_id"]] = doc["bym_index"]
        bym_vers_json[doc["bym_index"]] = doc

    # --- WLS, chapitre par chapitre -----------------------------------------
    raw = open(WLS_SOURCE, "rb").read()
    noms = [m.group(1).decode() for m in re.finditer(
        rb"<input><name>(.*?)</name><addr>\d+</addr></input>", raw)]
    datas = [m.group(1) for m in re.finditer(rb"<data>(.*?)</data>", raw, re.S)]
    print(f"WLS : {len(datas)} chapitres, {len(noms)} entrées TOC")

    wls: dict[tuple[int, int], list] = {}
    sautes = []
    for nom, data in zip(noms, datas):
        m = CHAPTER_NAME_RE.match(nom)
        if not m:
            continue
        code_toc, chapitre = m.group(1), int(m.group(2))
        osis = TOC_TO_OSIS.get(code_toc)
        bym = osis_vers_bym.get(osis)
        if bym is None:
            sautes.append(nom)
            continue
        texte = data.decode("utf-8", errors="replace")
        premier = True
        numero = 0
        for morceau in re.split(r"<v/>", texte):
            marqueur = MARK_RE.search(morceau)
            if not marqueur:
                continue
            if marqueur.group(1) == "cn" and premier:
                numero = 1
            elif marqueur.group(1) == "vn":
                numero = int(marqueur.group(2))
            else:
                continue
            premier = False
            wls[(bym, chapitre, numero)] = extraire_mots(morceau)
    print(f"  {len(wls)} versets hébreux, {len(sautes)} blocs sautés"
          + (f" ({', '.join(sautes[:5])})" if sautes else ""))

    # --- alignement ----------------------------------------------------------
    lemmes = defaultdict(Counter)
    total = Counter()
    attribues = Counter()
    exemples = defaultdict(list)

    for bym, doc in sorted(bym_vers_json.items()):
        nom = doc["book"]
        for ch in doc["chapters"]:
            for v in ch["verses"]:
                cibles = codes_etendus(v["tokens"])
                if not cibles:
                    continue
                hebreu = wls.get((bym, ch["chapter"], v["verse"]))
                if hebreu is None:
                    for c in cibles:
                        total[c] += 1
                    continue
                for c in cibles:
                    total[c] += 1
                for code, mot in apparier(hebreu, v["tokens"]):
                    if not est_etendu(code):
                        continue
                    lemmes[code][mot] += 1
                    attribues[code] += 1
                    if len(exemples[code]) < 3:
                        exemples[code].append(f"{nom} {ch['chapter']}.{v['verse']}")

    # --- rapport -------------------------------------------------------------
    result = {}
    for code, n in total.most_common():
        result[code] = {
            "total": n,
            "attribues": attribues[code],
            "lemmes": dict(lemmes[code].most_common(12)),
            "exemples": exemples[code],
        }
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)

    print(f"\n{len(total)} codes étendus, {sum(total.values())} occurrences, "
          f"{sum(attribues.values())} attribuées à un mot hébreu")
    print(f" écrit : {OUT_JSON}\n")
    for code, n in total.most_common(25):
        top = " ".join(f"{mot}×{k}" for mot, k in lemmes[code].most_common(3))
        part = 100 * attribues[code] / n if n else 0
        print(f"  {code}  ×{n:<6d} {part:5.1f}%  {top}")
    return 0


def extraire_mots(bloc: str) -> list:
    """[(mot hébreu, code|None)] d'un verset WLS, ponctuation écartée."""
    mots: list = []
    attente = False          # un mot vient d'être vu sans son ancre
    for m in EVENT_RE.finditer(bloc):
        if m.group("mot") is not None:
            mot = m.group("mot").strip()
            if not HEB_RE.search(mot):
                continue                      # ׃ ־ etc.
            mot = ACCENTS_RE.sub("", mot)
            if not mot or mot in PARAGRAPHE:
                continue                      # marque de paragraphe
            mots.append([mot, None])
            attente = True
        elif attente:
            mots[-1][1] = m.group("code")
            attente = False
    return [(m, c) for m, c in mots]


def codes_etendus(tokens) -> list:
    """Les seuls codes au-delà de la numérotation standard, dans l'ordre."""
    out = []
    for t in tokens:
        s = (t.get("strong") or "").strip()
        if not s:
            continue
        out.extend(c for c in s.split() if est_etendu(c))
    return out


def apparier(hebreu: list, tokens) -> list:
    """Code étendu -> mot WLS, par alignement sur les codes standard communs."""
    pos_wls = [i for i, (_, c) in enumerate(hebreu) if c]
    std_wls = [hebreu[i][1] for i in pos_wls]

    pos_lss, std_lss, etendus = [], [], []
    for i, t in enumerate(tokens):
        s = (t.get("strong") or "").strip()
        if not s:
            continue
        for code in s.split():
            if est_etendu(code):
                etendus.append((i, code))
            else:
                pos_lss.append(i)
                std_lss.append(code)

    sortie = []
    sm = difflib.SequenceMatcher(None, std_wls, std_lss, autojunk=False)
    bornes = [(0, 0)]          # (index WLS, index LSS) de départ
    for bloc in sm.get_matching_blocks():
        bornes.append((bloc.a, bloc.b))
    bornes.append((len(std_wls), len(std_lss)))

    for (i0, j0), (i1, j1) in zip(bornes, bornes[1:]):
        # Mot WLS sans ancre entre les deux bornes…
        debut_w = pos_wls[i0 - 1] + 1 if i0 else 0
        fin_w = pos_wls[i1] if i1 < len(pos_wls) else len(hebreu)
        trous_w = [hebreu[k][0] for k in range(debut_w, fin_w)
                   if hebreu[k][1] is None]
        # …et code étendu LSS entre les deux mêmes bornes.
        debut_l = pos_lss[j0 - 1] + 1 if j0 else 0
        fin_l = pos_lss[j1] if j1 < len(pos_lss) else 10 ** 9
        trous_l = [c for i, c in etendus if debut_l <= i < fin_l]
        if len(trous_w) == len(trous_l):
            sortie.extend(zip(trous_l, trous_w))
    return sortie


if __name__ == "__main__":
    raise SystemExit(main())
