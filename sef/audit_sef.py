# -*- coding: utf-8 -*-
"""Audit d'intégrité : source vs extraction."""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
SRC = r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\SEF.xml"
OUT = Path(r"C:\Users\laptek\Desktop\bym3\sef\extrait")

data = open(SRC, encoding="utf-8", errors="replace").read()
files_sec = data[: data.index("</files>")]
toc = re.search(r"<toc>(.*?)</toc>", data, re.S).group(1)
names = re.findall(r"<input><name>([^<]+)</name>", toc)
blocks = re.findall(r"<file>\s*<size>(\d+)</size>\s*<data>(.*?)</data>\s*</file>", files_sec, re.S)

HDR = re.compile(
    r"<font color=darkblue>Traduction fran\xe7aise de Giguet.*?</font><br/>\s*"
    r"<font color=green>Traduction fran\xe7aise d'Alexandrie.*?</font>",
    re.S,
)

src_db = src_gr = 0
src_db_n = src_gr_n = 0
for n, (sz, b) in zip(names, blocks):
    if n.startswith("glossaire") or n in ("header.xml", "index.html"):
        continue
    b = HDR.sub("", b)
    for m in re.finditer(r"<font color=darkblue>(.*?)</font>", b, re.S):
        src_db += len(m.group(1))
        src_db_n += 1
    for m in re.finditer(r"<font color=green>(.*?)</font>", b, re.S):
        src_gr += len(m.group(1))
        src_gr_n += 1

ext_db = ext_gr = ext_au = 0
n_vers = 0
brut_non_vide = 0
intro_n = 0
for f in (OUT / "livres").glob("*.json"):
    obj = json.loads(f.read_text(encoding="utf-8"))
    for c in obj["chapitres"]:
        if c["brut"]:
            brut_non_vide += 1
        if c["introduction"]:
            intro_n += 1
        for v in c["versets"]:
            n_vers += 1
            ext_db += len(v["giguet"])
            ext_gr += len(v["grec"])
            ext_au += len(v["alexandrie"])
            ext_au += len("".join(v["autres"])) + len("".join(v["titres"]))

print(f"SOURCE  darkblue : {src_db_n} blocs, {src_db} caractères")
print(f"SOURCE  green    : {src_gr_n} blocs, {src_gr} caractères")
print(f"EXTRAIT giguet   : {ext_db} caractères  (écart {ext_db - src_db:+d})")
print(f"EXTRAIT grec     : {ext_gr} caractères")
print(f"EXTRAIT alex+autres : {ext_au} caractères  (green source {src_gr})")
print(f"versets: {n_vers} | chapitres avec brut: {brut_non_vide} | avec intro: {intro_n}")

# vert dans l'extraction (alexandrie seule) vs source green hors header
print()
# contrôle livre par livre des verts
par_livre = {}
for f in (OUT / "livres").glob("*.json"):
    obj = json.loads(f.read_text(encoding="utf-8"))
    n = sum(len(v["alexandrie"]) for c in obj["chapitres"] for v in c["versets"])
    if n:
        par_livre[f.stem] = n
print("livres avec Alexandrie:", ", ".join(sorted(par_livre)))

# fichiers de sortie
print()
for p in sorted(OUT.rglob("*")):
    if p.is_file():
        print(f"  {p.relative_to(OUT)}  {p.stat().st_size:,}")
