# -*- coding: utf-8 -*-
"""
Coût de chaque champ de l'ATI, et des trois stratégies de stockage.

Complète `mesure_taille.py` : au lieu du total, le détail — ce que coûte
chaque champ par mot, donc ce que chaque renoncement rapporte, et ce que
donnerait un stockage compressé sur l'appareil (dart:io expose `gzip`).

Les champs, tels que le HTML de Biblia les porte :
  s  numéro Strong                H7225
  t  translittération             bə·rê·šîṯ
  h  hébreu vocalisé              בְּרֵאשִׁ֖ית
  d  découpage morphologique      בְּ • רֵאשִׁ֖ית
  f  glose française              En un commencement
  g  étiquette grammaticale       Nom
  a  analyse développée           Nom commun · féminin singulier · état absolu
  n  renvoi de note               12
"""
import gzip
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mesure_taille import parse_chapitre, ECHANTILLON, EXTRAIT, MOTS_CORPUS  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

LIBELLES = {
    "s": "numéro Strong",
    "t": "translittération",
    "h": "hébreu vocalisé",
    "d": "découpage morphologique",
    "f": "glose française",
    "g": "étiquette grammaticale",
    "a": "analyse développée",
    "n": "renvoi de note",
    "v": "numéro de verset",
}

mots = []
for rel in ECHANTILLON:
    p = EXTRAIT / rel
    if p.exists():
        mots += parse_chapitre(p.read_text(encoding="utf-8", errors="replace"))

nb_mots = sum(1 for m in mots if "h" in m or "s" in m)


def poids(objs):
    b = json.dumps(objs, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return len(b), len(gzip.compress(b, 9))


total, total_gz = poids(mots)

print(f"Échantillon : {nb_mots:,} mots — {total:,} o de JSON compact")
print()
print("Coût de chaque champ (ce que son retrait rendrait)")
print("=" * 78)
print(f"{'champ':26} {'présent':>8} {'octets':>10} {'o/mot':>7} {'part':>6} {'corpus':>9}")
print("-" * 78)

couts = []
for cle, libelle in LIBELLES.items():
    presents = sum(1 for m in mots if cle in m)
    if not presents:
        continue
    sans = [{k: v for k, v in m.items() if k != cle} for m in mots]
    o_sans, _ = poids(sans)
    cout = total - o_sans
    couts.append((cout, cle, libelle, presents))

for cout, cle, libelle, presents in sorted(couts, reverse=True):
    par_mot = cout / max(nb_mots, 1)
    print(f"{cle}  {libelle:22} {presents:8,} {cout:10,} {par_mot:7.1f} "
          f"{100 * cout / total:5.1f}% {par_mot * MOTS_CORPUS / 1048576:7.0f} Mo")

print("-" * 78)
print(f"{'total':26} {'':8} {total:10,} {total / max(nb_mots, 1):7.1f} "
      f"{'100%':>6} {total / max(nb_mots, 1) * MOTS_CORPUS / 1048576:7.0f} Mo")

# --------------------------------------------------------------------------
# Stratégies de stockage sur l'appareil
# --------------------------------------------------------------------------
print()
print("Stratégies de stockage, extrapolées au corpus (333 186 mots)")
print("=" * 78)


def mo(octets_par_mot):
    return octets_par_mot * MOTS_CORPUS / 1048576


# 1. tel quel
o1 = total / nb_mots

# 2. table de codes pour `a` et `g`
codes_a, codes_g = {}, {}
compact = []
for m in mots:
    c = dict(m)
    if "a" in c:
        c["a"] = codes_a.setdefault(c["a"], len(codes_a))
    if "g" in c:
        c["g"] = codes_g.setdefault(c["g"], len(codes_g))
    compact.append(c)
o_codes, o_codes_gz = poids({"ca": list(codes_a), "cg": list(codes_g), "m": compact})
o2 = o_codes / nb_mots

# 3. codes + stockage gzip sur l'appareil
o3 = o_codes_gz / nb_mots

lignes = [
    ("JSON tel quel, en clair", o1, "ce que `library_store` ferait aujourd'hui"),
    ("JSON + table de codes, en clair", o2, "aucune information perdue"),
    ("JSON + codes, gzip sur disque", o3, "`dart:io` gzip, décompression à l'ouverture"),
]
for nom, opm, note in lignes:
    print(f"  {nom:34} {mo(opm):6.0f} Mo   {note}")

print()
print(f"  table de codes : {len(codes_a)} analyses distinctes, "
      f"{len(codes_g)} étiquettes — pour {nb_mots:,} mots")
print()
print("Granularité : poids du plus gros livre (Jérémie, 23 649 mots)")
print("-" * 78)
for nom, opm, _ in lignes:
    print(f"  {nom:34} {opm * 23649 / 1048576:6.1f} Mo par fichier de livre")
print(f"  {'découpé par chapitre (Jr, 52 ch.)':34} "
      f"{o3 * 23649 / 52 / 1024:6.0f} Ko par chapitre, gzip")
