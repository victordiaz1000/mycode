#!/usr/bin/env python3
"""Validation indépendante de strong_fr_v2.json (hors check() du générateur).

Fichier attendu dans extraction/, régénérable par fusion_strong_v2.py ; il
n'est pas embarqué — l'application lit assets/lexicon/strong_fr.json.
"""
import json
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = r"C:\Users\laptek\Desktop\bym3"
V1 = os.path.join(ROOT, "bible_app", "assets", "lexicon", "strong_fr.json")
V2 = os.path.join(ROOT, "extraction", "strong_fr_v2.json")

v1 = json.load(open(V1, encoding="utf-8"))
v2 = json.load(open(V2, encoding="utf-8"))
e1, e2 = v1["entries"], v2["entries"]

print("=== Entetes ===")
print("  v1 header:", {k: v for k, v in v1.items() if k != "entries"})
print("  v2 header:", {k: v for k, v in v2.items() if k != "entries"})
print("  schema v2:", v2.get("schema"), "| entries:", len(e2))

print("=== Structure ===")
print("  cles v2 (racine):", sorted(v2.keys()))
nouveaux = sorted(set(e2) - set(e1))
manquants = sorted(set(e1) - set(e2))
print("  ajoutes:", nouveaux, "| perdus:", manquants)

print("=== Base intacte (champ par champ) ===")
champs = (
    "strong", "language", "lemma", "transliteration", "pronunciation",
    "partOfSpeech", "etymology", "signification", "senses", "outline",
    "definition",
)
ecarts = []
for key, base in e1.items():
    entry = e2.get(key)
    if entry is None:
        ecarts.append(f"{key}: absent")
        continue
    for f in champs:
        if base.get(f) != entry.get(f):
            ecarts.append(f"{key}.{f} modifie")
print("  ecarts:", len(ecarts), ecarts[:5])

print("=== Cles bannies / HTML ===")
bannies = {"bailly", "sanderTrenel", "sections", "strongDefinition",
           "strongLineNumber", "source"}
trouvees = []
for key, entry in e2.items():
    for f in entry.keys():
        if f in bannies:
            trouvees.append(f"{key}.{f}")
print("  cles bannies:", len(trouvees), trouvees[:5])
tag = re.compile(r"</?[a-zA-Z!][^>]*>|&#\d+;")
html = []
for key, entry in e2.items():
    block = entry.get("biblia", {})
    for f, val in block.items():
        texts = val if isinstance(val, list) else [val]
        if isinstance(texts[0], dict):
            texts = list(texts[0].values())
        for t in texts:
            if tag.search(str(t)):
                html.append(f"{key}.{f}")
                break
print("  vrai HTML:", len(html), html[:5])

print("=== Compteurs biblia ===")
compteurs = {}
for key, entry in e2.items():
    for f in entry.get("biblia", {}):
        compteurs[f] = compteurs.get(f, 0) + 1
print(" ", compteurs)
occ_vide = sum(
    1 for entry in e2.values()
    if "occurrences" in entry.get("biblia", {})
    and not entry["biblia"]["occurrences"]["books"]
    and not entry["biblia"]["occurrences"]["summary"]
)
print("  occurrences vides:", occ_vide)

print("=== Echantillons ===")
for key in ("H0001", "H0005", "H0010", "G2994", "G2995"):
    entry = e2.get(key)
    if entry is None:
        print(f"  {key}: ABSENT")
        continue
    print(f"  --- {key} (pose={key in e1}):")
    for f in ("lemma", "partOfSpeech", "etymology", "senses", "outline",
              "definition", "signification"):
        if entry.get(f) is not None:
            v = entry[f]
            v = v if not isinstance(v, list) else v[:4]
            print(f"      {f}: {str(v)[:150]}")
    block = entry.get("biblia", {})
    for f, v in block.items():
        print(f"      biblia.{f}: {str(v)[:150]}")

print("=== Taille ===")
raw = open(V2, "rb").read()
print("  octets:", len(raw), f"({len(raw)/1024/1024:.2f} Mo)")
compact = json.dumps(v2, ensure_ascii=False, separators=(",", ":"))
indent = json.dumps(v2, ensure_ascii=False, indent=2)
print("  compact:", len(compact.encode("utf-8")) / 1024 / 1024, "Mo")
print("  indent2:", len(indent.encode("utf-8")) / 1024 / 1024, "Mo")
v1raw = open(V1, "rb").read()
print("  v1 sur disque:", len(v1raw) / 1024 / 1024, "Mo")
