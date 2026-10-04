# -*- coding: utf-8 -*-
"""
Mesure : que pèserait l'ATI dans l'app, une fois sorti du HTML de Biblia ?

Ne convertit rien pour de bon. Parse un échantillon de chapitres, en extrait
l'information réelle de chaque mot (Strong, translittération, hébreu vocalisé,
découpage, glose française, analyse grammaticale, note), l'écrit dans trois
formats candidats, et extrapole au corpus entier par le nombre de mots.

  brut        le HTML tel que Biblia le livre
  json        un objet par mot, clés courtes
  json_codes  idem, mais les analyses grammaticales répétées passent par une
              table de codes (le même libellé revient des milliers de fois)

Chaque format est aussi pesé en gzip : c'est ce qui voyagerait sur le réseau,
et ce que GitHub raw sert déjà pour OST / NCL / CHO.
"""
import gzip
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

EXTRAIT = Path(__file__).parent / "extrait" / "fichiers"

# Le parseur vit dans `ati_parse.py` : le convertisseur de production s'en sert
# aussi, et les règles de découpage du HTML de Biblia ne doivent exister qu'en un
# seul endroit. Réexporté ici pour que `cout_par_champ.py` le trouve encore.
sys.path.insert(0, str(Path(__file__).parent))
from ati_parse import parse_chapitre, nu  # noqa: E402


def pese(obj):
    """(octets JSON, octets gzip) pour un objet sérialisé compact."""
    b = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return len(b), len(gzip.compress(b, 9))


ECHANTILLON = [
    "GEN/001.html", "GEN/002.html",     # prose narrative
    "PSA/119.html", "PSA/023.html",     # poésie, le plus long psaume
    "ISA/053.html",                     # prophétie
    "LEV/013.html",                     # prose légale, listes
    "1CH/001.html",                     # généalogies, noms propres
]

print("Mesure de l'information réelle, par chapitre")
print("=" * 78)
print(f"{'chapitre':14} {'mots':>6} {'brut':>10} {'json':>9} {'json.gz':>9} "
      f"{'o/mot':>7} {'gain':>6}")
print("-" * 78)

tot_mots = tot_brut = tot_json = tot_gz = 0
grammaires = {}
analyses = {}

for rel in ECHANTILLON:
    p = EXTRAIT / rel
    if not p.exists():
        print(f"{rel:14} ABSENT")
        continue
    html = p.read_text(encoding="utf-8", errors="replace")
    brut = len(html.encode("utf-8"))
    mots = parse_chapitre(html)
    nb = sum(1 for m in mots if "h" in m or "s" in m)
    o_json, o_gz = pese(mots)

    for m in mots:
        if "g" in m:
            grammaires[m["g"]] = grammaires.get(m["g"], 0) + 1
        if "a" in m:
            analyses[m["a"]] = analyses.get(m["a"], 0) + 1

    tot_mots += nb
    tot_brut += brut
    tot_json += o_json
    tot_gz += o_gz
    print(f"{rel:14} {nb:6} {brut:10,} {o_json:9,} {o_gz:9,} "
          f"{o_json / max(nb, 1):7.0f} {brut / max(o_json, 1):5.1f}x")

print("-" * 78)
print(f"{'échantillon':14} {tot_mots:6} {tot_brut:10,} {tot_json:9,} {tot_gz:9,} "
      f"{tot_json / max(tot_mots, 1):7.0f} {tot_brut / max(tot_json, 1):5.1f}x")

# --------------------------------------------------------------------------
# Table de codes : l'analyse grammaticale se répète-t-elle assez pour payer ?
# --------------------------------------------------------------------------
print()
print("Répétition des libellés grammaticaux dans l'échantillon")
print("-" * 78)
tot_g = sum(grammaires.values())
tot_a = sum(analyses.values())
print(f"  étiquettes courtes  : {tot_g:,} occurrences pour {len(grammaires):,} libellés distincts")
print(f"  analyses développées: {tot_a:,} occurrences pour {len(analyses):,} libellés distincts")
octets_a_inline = sum(len(k.encode()) * n for k, n in analyses.items())
octets_a_table = sum(len(k.encode()) for k in analyses) + tot_a * 3
print(f"  analyses en clair   : {octets_a_inline:,} o")
print(f"  analyses en codes   : {octets_a_table:,} o  "
      f"(économie {octets_a_inline - octets_a_table:,} o, "
      f"{100 * (1 - octets_a_table / max(octets_a_inline, 1)):.0f} %)")

gain_codes = (octets_a_inline - octets_a_table) / max(tot_json, 1)

# --------------------------------------------------------------------------
# Extrapolation
# --------------------------------------------------------------------------
MOTS_CORPUS = 333_186
BRUT_CORPUS = 295_873_677
facteur = MOTS_CORPUS / max(tot_mots, 1)

print()
print("Extrapolation au corpus entier (333 186 mots, 39 livres, 929 chapitres)")
print("=" * 78)
par_mot_json = tot_json / max(tot_mots, 1)
par_mot_gz = tot_gz / max(tot_mots, 1)
par_mot_codes = par_mot_json * (1 - gain_codes)

def mo(o):
    return f"{o / 1_048_576:,.0f} Mo"

print(f"  HTML brut de Biblia          {mo(BRUT_CORPUS):>12}   (mesuré)")
print(f"  JSON compact                 {mo(par_mot_json * MOTS_CORPUS):>12}")
print(f"  JSON + table de codes        {mo(par_mot_codes * MOTS_CORPUS):>12}")
print(f"  JSON compact, gzip           {mo(par_mot_gz * MOTS_CORPUS):>12}   "
      f"(ce qui voyage sur le réseau)")
print()
print(f"  rapport au HTML brut         "
      f"{BRUT_CORPUS / max(par_mot_json * MOTS_CORPUS, 1):.0f}x plus léger en JSON, "
      f"{BRUT_CORPUS / max(par_mot_gz * MOTS_CORPUS, 1):.0f}x en gzip")
print()
print(f"  par livre, en moyenne        "
      f"{mo(par_mot_json * MOTS_CORPUS / 39):>12}   (39 fichiers, comme OST/NCL/SEF)")
