# -*- coding: utf-8 -*-
"""
Identifie les codes Strong étendus de la LSS (H8675+, G5625+) sans deviner la
règle d'émission : on cherche, pour chaque code, la propriété morphologique du
texte hébreu (WLS) qui a le MÊME effectif, verset par verset.

Si un code a 3 occurrences dans un verset, il faut exactement 3 mots hébreux
présentant la propriété — et ce, dans chacun des 2 000 versets concernés.
Une correspondance à 99 % est une identification, pas une hypothèse.

Sortie : extraction/strong_etendu.json
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from aligne_etendu import EVENT_RE, HEB_RE, PARAGRAPHE  # noqa: E402
from extract_lgs_lss import CHAPTER_NAME_RE, MARK_RE, TOC_TO_OSIS  # noqa: E402

WLS = (r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)"
       r"\Ressources\bibles\WLS.xml")
LSS = r"C:\Users\laptek\Desktop\bym3\extraction\LSS"
OUT = r"C:\Users\laptek\Desktop\bym3\extraction\strong_etendu.json"

# Niqqud et accentuation (U+0591–U+05C7). Les lettres sont en U+05D0–U+05EA :
# la plage doit S'ARRÊTER avant, sinon elle avale י כ ל מ נ ס ע פ צ ק ר ש ת.
ACCENTS = re.compile(r"[֑-ׇ]")

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


# --------------------------------------------------------------------------- #
# Lecture                                                                      #
# --------------------------------------------------------------------------- #
def lire_wls() -> dict:
    """{(bym, chapitre, verset): [{'brut': …, 'cons': …, 'code': …}, …]}"""
    raw = open(WLS, "rb").read()
    noms = [m.group(1).decode() for m in re.finditer(
        rb"<input><name>(.*?)</name><addr>\d+</addr></input>", raw)]
    datas = [m.group(1) for m in re.finditer(rb"<data>(.*?)</data>", raw, re.S)]

    osis_vers_bym = {}
    for p in Path(LSS).glob("*.json"):
        doc = json.load(open(p, encoding="utf-8"))
        osis_vers_bym[doc["osis_id"]] = doc["bym_index"]

    wls = {}
    for nom, data in zip(noms, datas):
        m = CHAPTER_NAME_RE.match(nom)
        if not m:
            continue
        bym = osis_vers_bym.get(TOC_TO_OSIS.get(m.group(1)))
        if bym is None:
            continue
        chapitre, numero, premier = int(m.group(2)), 0, True
        texte = data.decode("utf-8", errors="replace")
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
            wls[(bym, chapitre, numero)] = extraire(morceau)
    return wls


def extraire(bloc: str) -> list:
    mots, attente = [], False
    for m in EVENT_RE.finditer(bloc):
        if m.group("mot") is not None:
            brut = m.group("mot").strip()
            if not HEB_RE.search(brut):
                continue
            cons = ACCENTS.sub("", brut)
            if not cons or cons in PARAGRAPHE:
                continue
            mots.append({"brut": brut, "cons": cons, "code": None})
            attente = True
        elif attente:
            mots[-1]["code"] = m.group("code")
            attente = False
    return mots


def lire_lss() -> dict:
    """{(bym, chapitre, verset): Counter des codes étendus}"""
    out = {}
    for p in sorted(Path(LSS).glob("*.json")):
        doc = json.load(open(p, encoding="utf-8"))
        bym = doc["bym_index"]
        for ch in doc["chapters"]:
            for v in ch["verses"]:
                c = Counter()
                for t in v["tokens"]:
                    s = (t.get("strong") or "").strip()
                    if s:
                        for code in s.split():
                            m = re.fullmatch(r"([HG])(\d+)", code)
                            if m and int(m.group(2)) > (8674 if m.group(1) == "H"
                                                        else 5624):
                                c[code] += 1
                if c:
                    out[(bym, ch["chapter"], v["verse"])] = c
    return out


# --------------------------------------------------------------------------- #
# Propriétés morphologiques                                                    #
# --------------------------------------------------------------------------- #
NIQ = {
    "sheva": "ְ", "patah": "ַ", "qamats": "ָ", "hiriq": "ִ",
    "holam": "ֹ", "shuruq": "ּ", "qamats_hatuf": "ֻ", "tsere": "ֵ",
    "segol": "ֶ",
}
# Les préfixes contractés des particules
PREFIXES = "ואבלהכמשג"


def construire_features() -> list:
    feats = []

    def ajoute(nom, fn):
        feats.append((nom, fn))

    # --- préfixes : première consonne ------------------------------------
    for l in PREFIXES:
        ajoute(f"init_{l}", lambda mots, l=l: sum(1 for m in mots
                                                  if m["cons"].startswith(l)))
        ajoute(f"seul_{l}", lambda mots, l=l: sum(1 for m in mots
                                                  if m["cons"] == l))
        for nv, car in NIQ.items():
            ajoute(f"init_{l}+{nv}",
                   lambda mots, l=l, car=car: sum(
                       1 for m in mots
                       if m["brut"].startswith(l + car)))
        # préfixe contracté (dagesh / pas de dagesh)
        ajoute(f"init_{l}_dagesh",
               lambda mots, l=l: sum(1 for m in mots
                                     if m["brut"].startswith(l + NIQ["shuruq"])))
        ajoute(f"init_{l}_sans_dagesh",
               lambda mots, l=l: sum(
                   1 for m in mots
                   if m["brut"].startswith(l + NIQ["sheva"])))

    # --- suffixes pronominaux ---------------------------------------------
    for l in "םהוךןףץתיכ":
        ajoute(f"fin_{l}", lambda mots, l=l: sum(1 for m in mots
                                                 if m["cons"].endswith(l)))
        for nv, car in NIQ.items():
            ajoute(f"fin_{l}+{nv}",
                   lambda mots, l=l, car=car: sum(
                       1 for m in mots if m["brut"].endswith(car + l)))

    # --- article ------------------------------------------------------------
    for nv, car in NIQ.items():
        ajoute(f"art_{nv}", lambda mots, car=car: sum(
            1 for m in mots if m["brut"].startswith("ה" + car)))

    # --- globaux ------------------------------------------------------------
    ajoute("nb_mots", lambda mots: len(mots))
    ajoute("nb_codes", lambda mots: sum(1 for m in mots if m["code"]))
    ajoute("nb_sans_code", lambda mots: sum(1 for m in mots if not m["code"]))
    return feats


# --------------------------------------------------------------------------- #
# Appariement                                                                  #
# --------------------------------------------------------------------------- #
def main() -> int:
    wls = lire_wls()
    lss = lire_lss()
    print(f"WLS {len(wls)} versets · LSS {len(lss)} versets portant un code étendu")

    feats = construire_features()
    print(f"{len(feats)} propriétés testées\n")

    # effectifs par verset pour chaque propriété
    vues = {nom: {} for nom, _ in feats}
    for cle, mots in wls.items():
        for nom, fn in feats:
            vues[nom][cle] = fn(mots)

    # effectifs des codes
    codes = defaultdict(dict)          # code -> {verset: n}
    for cle, c in lss.items():
        for code, n in c.items():
            codes[code][cle] = n

    # chaque code : quelle propriété colle ?
    resultats = {}
    for code, par_verse in sorted(
            codes.items(),
            key=lambda kv: -sum(kv[1].values())):
        cles = set(par_verse)
        cibles = {c: par_verse[c] for c in cles if c in wls}
        if not cibles:
            continue
        total = sum(cibles.values())
        notes = []
        for nom, _ in feats:
            v = vues[nom]
            ecart = sum(abs(cibles[k] - v.get(k, 0)) for k in cibles)
            notes.append((1 - ecart / total, nom))
        notes.sort(reverse=True)
        resultats[code] = {
            "total": total,
            "versets": len(cibles),
            "meilleures": [{"prop": n, "score": round(s, 4)}
                           for s, n in notes[:5]],
        }

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(resultats, fh, ensure_ascii=False, indent=1)
    print(f"écrit : {OUT}\n")

    print(f"{'code':8s} {'occ':>7s} {'v':>5s}  meilleures propriétés")
    print("-" * 78)
    for code, r in sorted(resultats.items(), key=lambda kv: -kv[1]["total"])[:40]:
        props = "  ".join(f"{p['prop']}={p['score']:.3f}"
                          for p in r["meilleures"][:3])
        print(f"{code:8s} {r['total']:7d} {r['versets']:5d}  {props}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
