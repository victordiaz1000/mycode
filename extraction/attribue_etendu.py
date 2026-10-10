# -*- coding: utf-8 -*-
"""
Quelle racine hébreue porte un code étendu de la LSS ?

Deux règles d'attachement sont testées, chacune sur les seuls cas NON AMBIGUS
(le code standard encadrant ne doit figurer qu'une fois dans le verset) :

  règle A : le code étendu suit le code standard du mot qu'il porte
            (`mourut[H4191] ⟨H8799⟩` = וַיָּמָת : racine puis waw)
  règle B : il précède le code standard du mot qu'il porte

On retient la règle qui donne la distribution de préfixes la plus concentrée,
puis on affiche les préfixes (avec niqqud) de la racine associée.

Sortie : extraction/strong_etendu.json
"""
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from analyse_etendu import lire_wls  # noqa: E402

LSS = Path(r"C:\Users\laptek\Desktop\bym3\extraction\LSS")
OUT = r"C:\Users\laptek\Desktop\bym3\extraction\strong_etendu.json"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def etendu(c):
    m = re.fullmatch(r"([HG])(\d+)", c or "")
    return bool(m) and int(m.group(2)) > (8674 if m.group(1) == "H" else 5624)


def std(c):
    m = re.fullmatch(r"([HG])(\d+)", c or "")
    return bool(m) and int(m.group(2)) <= (8674 if m.group(1) == "H" else 5624)


def sequences():
    """{(bym, chap, v): [codes dans l'ordre d'émission]}"""
    out = {}
    for p in sorted(LSS.glob("*.json")):
        doc = json.load(open(p, encoding="utf-8"))
        bym = doc["bym_index"]
        for ch in doc["chapters"]:
            for v in ch["verses"]:
                seq = []
                for t in v["tokens"]:
                    s = (t.get("strong") or "").strip()
                    if s:
                        seq.extend(s.split())
                if any(etendu(c) for c in seq):
                    out[(bym, ch["chapter"], v["verse"])] = seq
    return out


def main():
    wls = lire_wls()
    seqs = sequences()

    # règle -> code -> Counter(préfixe brut de la racine) + formes complètes
    regles = {"A": defaultdict(Counter), "B": defaultdict(Counter)}
    formes = {"A": defaultdict(Counter), "B": defaultdict(Counter)}
    retenus = Counter()
    ambigus = Counter()

    for cle, seq in sorted(seqs.items()):
        if cle not in wls:
            continue
        mots = wls[cle]
        # index code standard -> positions (doit être unique)
        pos = defaultdict(list)
        for i, m in enumerate(mots):
            if m["code"]:
                pos[m["code"]].append(i)

        std_lss = [(i, c) for i, c in enumerate(seq) if std(c)]
        for i, code in enumerate(seq):
            if not etendu(code):
                continue
            retenus[code] += 1
            k = sum(1 for j in range(i) if std(seq[j]))   # nb de std avant
            # règle A : dernier standard avant
            if k > 0:
                s = std_lss[k - 1][1]
                if len(pos.get(s, [])) == 1:
                    w = mots[pos[s][0]]
                    regles["A"][code][w["brut"][:5]] += 1
                    formes["A"][code][w["brut"]] += 1
                    continue
            # règle B : premier standard après
            if k < len(std_lss):
                s = std_lss[k][1]
                if len(pos.get(s, [])) == 1:
                    w = mots[pos[s][0]]
                    regles["B"][code][w["brut"][:5]] += 1
                    formes["B"][code][w["brut"]] += 1
                    continue
            ambigus[code] += 1

    # concentration = part du préfixe dominant
    def concentration(cnt):
        n = sum(cnt.values())
        return (cnt.most_common(1)[0][1] / n if n else 0), n

    print(f"{'code':8s} {'occ':>6s} {'A':>12s} {'B':>12s}   règle retenue")
    print("-" * 78)
    result = {}
    for code, n in sorted(retenus.items(), key=lambda kv: -kv[1])[:60]:
        ca, na = concentration(regles["A"][code])
        cb, nb = concentration(regles["B"][code])
        regle = "A" if ca >= cb else "B"
        cnt = regles[regle][code]
        tot = sum(cnt.values())
        top = "  ".join(f"{k}×{v} ({100*v/tot:.0f}%)"
                        for k, v in cnt.most_common(4))
        print(f"{code:8s} {n:6d} {ca:5.2f}/{na:<5d} {cb:5.2f}/{nb:<5d}  {regle}")
        print(f"         préfixes : {top}")
        fm = "  ".join(f"{k}({v})" for k, v in
                       list(formes[regle][code].most_common(8)))
        print(f"         formes   : {fm}")
        result[code] = {"total": n, "regle": regle,
                        "concentration": round(max(ca, cb), 3),
                        "couverts": tot,
                        "prefixes": dict(cnt.most_common(20)),
                        "formes": dict(formes[regle][code].most_common(20))}

    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)
    print(f"\nécrit : {OUT}")


if __name__ == "__main__":
    main()
