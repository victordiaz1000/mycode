# -*- coding: utf-8 -*-
"""Vérification de l'extraction SEF."""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
OUT = Path(r"C:\Users\laptek\Desktop\bym3\sef\extrait")

def load(code):
    return json.loads((OUT / "livres" / f"{code}.json").read_text(encoding="utf-8"))

def vlivre(obj, chap, verset, groupe=None):
    for ch in obj["chapitres"]:
        if ch["chapitre"] == chap and (groupe is None or ch["groupe"] == groupe):
            for v in ch["versets"]:
                if v["verset"] == verset:
                    return ch, v
    return None, None

def show(t, s, n=220):
    s = (s or "").replace("\n", " ")
    print(f"  {t}: {s[:n]}{'…' if len(s) > n else ''}")

print("=== GEN 1:1 ===")
gen = load("GEN")
ch, v = vlivre(gen, 1, "1")
show("grec", v["grec"]); show("giguet", v["giguet"]); show("alex", v["alexandrie"])
print("  intro:", [t[:60] for t in ch["introduction"]])

print("\n=== 1CH 1:1 (1er livre du fichier, Giguet seul) ===")
c1 = load("1CH")
ch, v = vlivre(c1, 1, "1")
show("grec", v["grec"]); show("giguet", v["giguet"]); print("  alex:", repr(v["alexandrie"]))
print("  intro:", [t[:80] for t in ch["introduction"]])
print("  v11 (verset vide):", [v["verset"] for v in ch["versets"][:16]])

print("\n=== PSA 1:1 (2 traductions) ===")
psa = load("PSA")
ch, v = vlivre(psa, 1, "1")
show("grec", v["grec"]); show("giguet", v["giguet"]); show("alex", v["alexandrie"])
print("  nb chapitres PSA:", len(psa["chapitres"]),
      " numeros:", [c["chapitre"] for c in psa["chapitres"]][:5], "…",
      [c["chapitre"] for c in psa["chapitres"]][-3:])
print("  doublons:", [(c["fichierToc"], c.get("doublon_de")) for c in psa["chapitres"] if c.get("doublon_de")])

print("\n=== JER (livre sans Alexandrie) ===")
jer = load("JER")
n = sum(1 for c in jer["chapitres"] for vv in c["versets"] if vv["alexandrie"].strip())
print("  versets avec alexandrie:", n)
ch, v = vlivre(jer, 10, "7")
print("  JER 10:7 (verset vide) :", v)
ch, v = vlivre(jer, 11, "1")
show("intro", " | ".join(ch["introduction"]))

print("\n=== 1KI chap. 20 (variante 020b) ===")
ki = load("1KI")
for c in ki["chapitres"]:
    if c["chapitre"] == 20:
        print(f"  {c['fichierToc']} libelle={c['libelle']!r} versets={len(c['versets'])} doublon_de={c.get('doublon_de')}")

print("\n=== EZR (Esdras B + groupe Esdras A) ===")
ezr = load("EZR")
for c in ezr["chapitres"]:
    has_tx = any(vv["giguet"].strip() for vv in c["versets"])
    print(f"  {c['fichierToc']} chap={c['chapitre']} grp={c['groupe']!r} "
          f"lib={c['libelle']!r} v={len(c['versets'])} giguet={'oui' if has_tx else 'NON'}")

print("\n=== SIR prologue ===")
sir = load("SIR")
for c in sir["chapitres"]:
    if c["chapitre"] in (51, 52):
        print(f"  {c['fichierToc']} chap={c['chapitre']} intro={c['introduction']} "
              f"doublon_de={c.get('doublon_de')} v={len(c['versets'])}")

print("\n=== DEU titres de péricope ===")
deu = load("DEU")
for c in deu["chapitres"]:
    if c["chapitre"] == 5:
        for vv in c["versets"][:3]:
            if vv["titres"]:
                print(f"  avant {vv['verset']}: {vv['titres']}")

print("\n=== JDG variante mixte (darkblue + green dans le même <p>) ===")
jdg = load("JDG")
for c in jdg["chapitres"]:
    if c["chapitre"] == 12:
        for vv in c["versets"]:
            if vv["autres"]:
                print(f"  {vv['verset']} autres={vv['autres']}")
                show("   giguet", vv["giguet"], 100)
                show("   alex", vv["alexandrie"], 100)
                break

print("\n=== versets sans grec mais avec traduction / sans aucun texte ===")
tot_no_grec_tx = []
empty = []
labels_bad = {}
for f in sorted((OUT / "livres").glob("*.json")):
    obj = json.loads(f.read_text(encoding="utf-8"))
    for c in obj["chapitres"]:
        for vv in c["versets"]:
            if not vv["grec"].strip() and (vv["giguet"].strip() or vv["alexandrie"].strip()):
                tot_no_grec_tx.append((f.stem, c["libelle"], vv["verset"], vv["giguet"][:60]))
            if not any((vv["grec"].strip(), vv["giguet"].strip(), vv["alexandrie"].strip())):
                empty.append((f.stem, c["libelle"], vv["verset"]))
            lab = vv["verset"]
            if lab and not lab.isdigit():
                labels_bad.setdefault(f.stem, []).append(lab)
print("  sans grec mais avec traduction:", tot_no_grec_tx)
print("  sans aucun texte:", empty)
print("  libellés non numériques par livre (extraits):")
for k, v in labels_bad.items():
    print(f"    {k}: {len(v)} -> {v[:8]}")

print("\n=== tailles ===")
tot = sum(p.stat().st_size for p in OUT.rglob("*") if p.is_file())
print(f"  total extrait: {tot/1e6:.1f} Mo, fichiers: {sum(1 for _ in OUT.rglob('*') if _.is_file())}")
