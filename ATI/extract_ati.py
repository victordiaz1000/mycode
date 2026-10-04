# -*- coding: utf-8 -*-
"""
Extraction complète de ATI.xml (Ancien Testament Interlinéaire — Biblia Universalis 3).

Source : C:\\Users\\laptek\\Documents\\Bible\\Biblia Universalis 3 (1.39)\\Ressources\\bibles\\ATI.xml
Sortie : ATI/extrait/
  fichiers/<chemin TOC>     972 entrées brutes (chapitres, glossaire, styles, index.html)
  meta/toc.json             table des matières (name + addr, dans l'ordre du fichier)
  meta/words.xml            section <words> (concordance) brute
  meta/words.jsonl          concordance parsée : {"n": terme, "r": références}
  meta/index-section.xml    répertoire <index> (découpage alphabétique) brut
  meta/index-lettres.json   lettres -> {addr, size, offset_dans_words}
  manifest.json             métadonnées, inventaire, contrôle d'intégrité
  rapport.txt               statistiques + anomalies

Le conteneur ATI.xml est un <bible> de Biblia Universalis 3 :
  <bible><files><number>N</number> <file><size>S</size><data>…HTML…</data></file>…
  </files><toc>…</toc><words>…</words><index>…</index>
  <addresses> répertoire des quatre sections (addr/size en octets absolus).
Les addr du <toc> pointent sur le début du bloc <file> ; <size> est la longueur
exacte en octets de <data>. Tout est lu/écrit en octets : sortie identique au source.
"""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

SRC = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\ATI.xml")
OUT = Path(r"C:\Users\laptek\Desktop\bym3\ATI\extrait")

HDR_RE = re.compile(rb"<file>\s*<size>(\d+)</size>\s*<data>")
TOC_RE = re.compile(r"<input><name>(.*?)</name><addr>(\d+)</addr></input>", re.S)
NB_RE = re.compile(r"<nb>(\d+)</nb>")
PAIR_RE = re.compile(r"<n>(.*?)</n>\s*<r>(.*?)</r>", re.S)
LETTRE_RE = re.compile(r"<name>(.*?)</name><addr>(\d+)</addr><size>(\d+)</size>", re.S)
CHAP_RE = re.compile(r"^([A-Za-z0-9]{3})/(\d{3})([A-Za-z0-9_]*)\.html$")
WIN_BAD = set('<>:"|?*')
TAILLE_TETE = 512

anomalies = []

# --------------------------------------------------------------------------
# 1. Répertoire des sections (<addresses>, en fin de fichier)
# --------------------------------------------------------------------------
print(f"Lecture de {SRC.name}…")
f = SRC.open("rb")
f.seek(max(0, SRC.stat().st_size - 16384))
tail = f.read().decode("utf-8", errors="replace")

secs = {}
for tag in ("files", "toc", "words", "index"):
    m = re.search(rf"<{tag}><addr>(\d+)</addr><size>(\d+)</size></{tag}>", tail)
    assert m, f"section <{tag}> introuvable dans <addresses>"
    secs[tag] = (int(m.group(1)), int(m.group(2)))
print("  sections : " + ", ".join(f"{k}={v[1]} o" for k, v in secs.items()))

# nombre annoncé de fichiers
f.seek(0)
head = f.read(256).decode("utf-8", errors="replace")
m = re.search(r"<number>(\d+)</number>", head)
nb_fichiers_annonce = int(m.group(1)) if m else None


def lire(addr, size, avant=64, apres=64):
    """Lit [addr, addr+size] en élargissant un peu de part et d'autre."""
    start = max(0, addr - avant)
    f.seek(start)
    return start, f.read(size + avant + apres)


# --------------------------------------------------------------------------
# 2. TOC
# --------------------------------------------------------------------------
toc_addr, toc_size = secs["toc"]
_, toc_raw = lire(toc_addr, toc_size)
toc_txt = toc_raw.decode("utf-8", errors="replace")
entrees = [(n, int(a)) for n, a in TOC_RE.findall(toc_txt)]
assert entrees, "TOC vide"
if len(entrees) != nb_fichiers_annonce:
    anomalies.append(f"TOC: {len(entrees)} entrées alors que <number> annonce {nb_fichiers_annonce}")
print(f"  {len(entrees)} entrées de TOC")

# --------------------------------------------------------------------------
# 3. Extraction des fichiers
# --------------------------------------------------------------------------
def lire_bloc(addr):
    """Retourne (données, taille attendue, écart éventuel)."""
    start = max(0, addr - 8)
    f.seek(start)
    win = f.read(TAILLE_TETE + 512)
    m = HDR_RE.search(win[:192])
    if not m:
        return None, None, "bloc illisible"
    data_start = start + m.end()
    size = int(m.group(1))
    f.seek(data_start)
    data = f.read(size)
    suite = f.read(7)
    if suite.startswith(b"</data>"):
        return data, size, None
    # secours : lecture jusqu'à </data>
    f.seek(data_start)
    buf = bytearray()
    marqueur = b"</data>"
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            return None, None, "fin prématurée"
        buf += chunk
        i = buf.find(marqueur)
        if i >= 0:
            return bytes(buf[:i]), size, "size≠réel (lu jusqu'à </data>)"


racine = OUT / "fichiers"
racine.mkdir(parents=True, exist_ok=True)

stats = {"chapters": 0, "glossaire": 0, "styles": 0, "images": 0, "index": 0, "autres": 0}
octets = 0
livres = []
livre_courant = None
tailles_min, tailles_max = None, 0

for nom, addr in entrees:
    cible = racine / nom
    if any(ch in nom for ch in WIN_BAD) or "\\" in nom:
        anomalies.append(f"nom de fichier non valide pour Windows: {nom!r}")
        continue
    data, size, err = lire_bloc(addr)
    if err:
        anomalies.append(f"{nom}: {err}")
        continue
    if size is not None and len(data) != size:
        anomalies.append(f"{nom}: <size>={size} mais {len(data)} octets lus")
    cible.parent.mkdir(parents=True, exist_ok=True)
    cible.write_bytes(data)
    octets += len(data)
    tailles_max = max(tailles_max, len(data))
    tailles_min = len(data) if tailles_min is None else min(tailles_min, len(data))

    if nom == "index.html":
        stats["index"] += 1
    elif nom.endswith((".gif", ".png", ".jpg")):
        stats["images"] += 1
    elif nom.endswith(".css"):
        stats["styles"] += 1
    elif nom.startswith("glossaire/"):
        stats["glossaire"] += 1
    else:
        m = CHAP_RE.match(nom)
        if m:
            stats["chapters"] += 1
            code = m.group(1)
            if code != livre_courant:
                livre_courant = code
                livres.append({"code": code, "nb_fichiers": 0, "premier": nom})
            livres[-1]["nb_fichiers"] += 1
        else:
            stats["autres"] += 1
            anomalies.append(f"entrée TOC non reconnue: {nom}")

print(f"  {sum(stats.values())} fichiers écrits, {octets:,} octets")

# --------------------------------------------------------------------------
# 4. Sections <words> et <index>
# --------------------------------------------------------------------------
w_addr, w_size = secs["words"]
_, w_raw = lire(w_addr, w_size)
w_txt = w_raw.decode("utf-8", errors="replace")
m = re.search(r"<words>(.*?)</words>", w_txt, re.S)
words_inner = m.group(1) if m else w_txt
if not m:
    anomalies.append("<words>: balises englobantes non trouvées, contenu pris tel quel")

nb_m = NB_RE.search(words_inner)
nb_annonce = int(nb_m.group(1)) if nb_m else None
pairs = PAIR_RE.findall(words_inner)
if nb_annonce is not None and nb_annonce != len(pairs):
    anomalies.append(f"<words>: <nb>={nb_annonce} mais {len(pairs)} paires <n>/<r> parsées")

i_addr, i_size = secs["index"]
_, i_raw = lire(i_addr, i_size)
i_txt = i_raw.decode("utf-8", errors="replace")
m = re.search(r"<index>(.*?)</index>", i_txt, re.S)
index_inner = m.group(1) if m else i_txt
if not m:
    anomalies.append("<index>: balises englobantes non trouvées, contenu pris tel quel")

lettres = [{"nom": n, "addr": int(a), "size": int(s), "offset_dans_words": int(a) - w_addr}
           for n, a, s in LETTRE_RE.findall(index_inner)]

meta = OUT / "meta"
meta.mkdir(exist_ok=True)
(meta / "words.xml").write_text(words_inner, encoding="utf-8")
with open(meta / "words.jsonl", "w", encoding="utf-8", newline="\n") as out:
    for n, r in pairs:
        out.write(json.dumps({"n": n, "r": r}, ensure_ascii=False) + "\n")
(meta / "index-section.xml").write_text(index_inner, encoding="utf-8")
(meta / "index-lettres.json").write_text(
    json.dumps(lettres, ensure_ascii=False, indent=1), encoding="utf-8")
(meta / "toc.json").write_text(
    json.dumps([{"name": n, "addr": a} for n, a in entrees], ensure_ascii=False, indent=1),
    encoding="utf-8")

# --------------------------------------------------------------------------
# 5. Métadonnées de la bible (page index.html du conteneur)
# --------------------------------------------------------------------------
idx_addr = dict(entrees).get("index.html")
idx_html = ""
if idx_addr:
    idx_html_b, _, _ = lire_bloc(idx_addr)
    idx_html = (idx_html_b or b"").decode("utf-8", errors="replace")

def champ(pattern, défaut=None):
    m = re.search(pattern, idx_html, re.S)
    return re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else défaut

meta_bible = {
    "titre": champ(r"<h1>(.*?)</h1>"),
    "copyright": champ(r'class="green">Copyright[^<]*</td><td[^>]*>(.*?)</td>'),
    "annee": champ(r'class="green">Ann[^<]*</td><td[^>]*>(.*?)</td>'),
    "langue": champ(r'class="green">Langue[^<]*</td>(?:</tr>)?\s*<td[^>]*>(.*?)</td>'),
    "nombre_livres": champ(r"class=\"green\">Nombre[^<]*</td><td[^>]*>(.*?)</td>"),
}

# --------------------------------------------------------------------------
# 6. Manifest + rapport
# --------------------------------------------------------------------------
OUT.mkdir(parents=True, exist_ok=True)
manifest = {
    "source": str(SRC),
    "source_taille_octets": SRC.stat().st_size,
    "bible": {
        "id": "ATI",
        "titre": meta_bible["titre"] or "Ancien Testament Interlinéaire",
        "titre_source": "AT Interlinéaire",
        "langue": "hébreu-français",
        "copyright": meta_bible["copyright"] or "Biblia Universalis",
        "annee": meta_bible["annee"] or "2024",
        "livres_annonces": meta_bible["nombre_livres"] or "39",
        "testament": "Ancien Testament uniquement (39 livres, pas de NT)",
        "index_html": "fichiers/index.html",
        "texte_source": "Bibla Hebraica Stuttgartensia",
    },
    "sections": {
        tag: {"addr": a, "size": s} for tag, (a, s) in secs.items()
    },
    "entrees_toc": {"total": len(entrees), "par_type": stats},
    "livres": livres,
    "sortie": {
        "fichiers": "fichiers/",
        "toc": "meta/toc.json",
        "words": "meta/words.xml",
        "words_parsed": "meta/words.jsonl",
        "index_section": "meta/index-section.xml",
        "index_lettres": "meta/index-lettres.json",
    },
    "stats": {
        "octets_fichiers": octets,
        "taille_min": tailles_min,
        "taille_max": tailles_max,
        "concordance_nb_anonce": nb_annonce,
        "concordance_paires": len(pairs),
        "lettres_index": len(lettres),
    },
    "anomalies": anomalies,
}
(OUT / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")

lignes = [
    "Extraction ATI.xml — Ancien Testament Interlinéaire (Biblia Universalis 3)",
    "=" * 70,
    f"Source                       : {SRC}",
    f"Taille source                : {SRC.stat().st_size:,} octets",
    f"Entrées TOC                  : {len(entrees)} (annoncé : {nb_fichiers_annonce})",
    f"  chapitres                  : {stats['chapters']}",
    f"  pages glossaire            : {stats['glossaire']}",
    f"  feuilles de style          : {stats['styles']}",
    f"  images                     : {stats['images']}",
    f"  index.html                 : {stats['index']}",
    f"  autres                     : {stats['autres']}",
    f"Livres                       : {len(livres)}",
    f"Octets extraits              : {octets:,}",
    f"Concordance <words>          : {len(pairs):,} entrées (annoncé : {nb_annonce})",
    f"Répertoire <index>           : {len(lettres)} tranches",
    "",
    "Anomalies / cas particuliers",
    "-" * 70,
]
lignes += ["  - " + a for a in anomalies] or ["  - aucune"]
lignes += [
    "",
    "Ordre TOC des livres : " + ", ".join(l["code"] for l in livres),
    "",
    "Contenu de la sortie :",
    "  fichiers/              les 972 entrées brutes, chemins du TOC préservés",
    "  meta/toc.json          table des matières (name + addr)",
    "  meta/words.xml|.jsonl  concordance brute + parsée",
    "  meta/index-*           répertoire alphabétique de la concordance",
    "  manifest.json          métadonnées et contrôle d'intégrité",
]
(OUT / "rapport.txt").write_text("\n".join(lignes), encoding="utf-8")

f.close()
print("\n".join(lignes))
print(f"\nSortie : {OUT}")
