# -*- coding: utf-8 -*-
"""
Extraction complète de SEF.xml (Septuaginta en français — Biblia Universalis 3).

Sortie : sef/extrait/
  manifest.json          métadonnées, adresses, ordre des livres, anomalies
  rapport.txt            statistiques + anomalies rencontrées
  livres/<CODE>.json     47 livres : chapitres -> versets (grec / Giguet / Alexandrie)
  glossaire/*.html       44 entrées de glossaire
  meta/header.xml        métadonnées de la bible (Rahlfs)
  meta/index.html        page d'index du logiciel
  meta/toc.json          table des matières (noms + adresses)
  meta/words.xml         section <words> (concordance) brute
  meta/words.jsonl       concordance parsée (si format reconnu)
  meta/index-section.xml section <index> brute

Modèle d'un verset :
  {"verset": "1", "grec": "...", "giguet": "...", "alexandrie": "...",
   "autres": ["fragments neutres"], "titres": ["titres placés avant ce verset"]}
Les textes conservent le balisage HTML inline du fichier source (<i>, <a>, &nbsp;…).
"""
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

SRC = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\SEF.xml")
OUT = Path(r"C:\Users\laptek\Desktop\bym3\sef\extrait")

HDR_RE = re.compile(
    r"<font color=darkblue>Traduction fran\xe7aise de Giguet.*?</font><br/>\s*"
    r"<font color=green>Traduction fran\xe7aise d'Alexandrie.*?</font>",
    re.S,
)
TOK_RE = re.compile(
    r"(?P<vv><v/>)"
    r"|(?P<fontopen><font\s+color=(?P<color>darkblue|green)>)"
    r"|(?P<fontclose></font>)"
    r'|(?P<span><span\s+class="(?P<scls>vn|cn)">(?P<sval>[^<]*)</span>)'
    r"|(?P<popen><p[^>]*>)"
    r"|(?P<pclose></p>)"
    r"|(?P<h><(?P<htag>h[1-4])[^>]*>(?P<htext>.*?)</(?P=htag)>)"
    r"|(?P<tag><[^>]+>)"
    r"|(?P<txt>[^<]+)",
    re.S,
)
CN_NUM_RE = re.compile(r"\s*(\d+)")
VERSE_A_RE = re.compile(r"^\d+[a-z]$")
BIBLE_RE = re.compile(r"^([0-9A-Z]{3})/(\d+)([a-z]*)\.html$")
STRIP_TAGS_RE = re.compile(r"<[^>]+>")
BARE_BR = ("<br>", "<br/>", "<br />")
GREEK_RE = re.compile(r"[\u0370-\u03ff\u1f00-\u1fff]")

NOMS_LIVRES = {
    "1CH": "1 Chroniques", "1KI": "1 Rois", "1MA": "1 Maccabées", "1SA": "1 Samuel",
    "2CH": "2 Chroniques", "2KI": "2 Rois", "2MA": "2 Maccabées", "2SA": "2 Samuel",
    "AMO": "Amos", "BAR": "Baruch", "DAN": "Daniel", "DEU": "Deutéronome",
    "ECC": "Ecclésiaste", "EST": "Esther", "EXO": "Exode", "EZK": "Ézéchiel",
    "EZR": "Esdras", "GEN": "Genèse", "HAB": "Habacuc", "HAG": "Aggée", "HOS": "Osée",
    "ISA": "Isaïe", "JDG": "Juges", "JDT": "Judith", "JER": "Jérémie", "JOB": "Job",
    "JOL": "Joël", "JON": "Jonas", "JOS": "Josué", "LAM": "Lamentations",
    "LEV": "Lévitique", "LJE": "Lettre de Jérémie", "MAL": "Malachie", "MIC": "Michée",
    "NAM": "Nahum", "NEH": "Néhémie", "NUM": "Nombres", "OBA": "Abdias",
    "PRO": "Proverbes", "PSA": "Psaumes", "RUT": "Ruth", "SIR": "Siracide (Ecclésiastique)",
    "SNG": "Cantique des Cantiques", "TOB": "Tobie", "WIS": "Sagesse",
    "ZEC": "Zacharie", "ZEP": "Sophonie",
}

def decode_nbsp(s):
    return s.replace("&nbsp;", " ")

# --------------------------------------------------------------------------
# Lecture du fichier source
# --------------------------------------------------------------------------
print("Lecture de SEF.xml…")
data = SRC.read_text(encoding="utf-8", errors="replace")

toc_m = re.search(r"<toc>(.*?)</toc>", data, re.S)
assert toc_m, "section <toc> introuvable"
after_toc = data[toc_m.end():]
words_m = re.search(r"<words>(.*?)</words>", after_toc, re.S)
after_words = after_toc[words_m.end():] if words_m else after_toc
index_m = re.search(r"<index>(.*?)</index>", after_words, re.S)
after_index = after_words[index_m.end():] if index_m else after_words
addr_m = re.search(r"<addresses>(.*?)</addresses>", after_index, re.S)

files_end = data.index("</files>")
files_sec = data[:files_end]
toc_entries = re.findall(
    r"<input><name>([^<]+)</name><addr>(\d+)</addr>(?:<size>(\d+)</size>)?", toc_m.group(1)
)
blocks = re.findall(
    r"<file>\s*<size>(\d+)</size>\s*<data>(.*?)</data>\s*</file>", files_sec, re.S
)
assert len(toc_entries) == len(blocks) == 1118, (len(toc_entries), len(blocks))
print(f"  {len(blocks)} blocs, {len(toc_entries)} entrées de TOC")

# --------------------------------------------------------------------------
# Parseur d'un bloc bible -> sections (une section = un <cn> = un chapitre)
# --------------------------------------------------------------------------
def parse_block(body, toc_name, toc_chap):
    """Retourne (sections, anomalies)."""
    anomalies = []
    if not HDR_RE.search(body):
        anomalies.append("entete_absente")
    body = HDR_RE.sub("", body, count=1)

    sections = []
    section = None
    verse = None
    channel = None          # 'giguet' | 'alex' | None
    para_grec = False
    in_p = False
    pending = []            # contenu hors <p> en attente (titres, notes, liens)
    pending_h1 = None
    p_neutral = []          # contenu neutre du paragraphe en cours (décision à </p>)
    first_section = True

    def flush_p_neutral():
        nonlocal p_neutral
        if not p_neutral:
            return
        joined = "".join(p_neutral)
        p_neutral = []
        if verse is None:
            if section is not None:
                section["brut"].append(joined)
            else:
                pending.append(joined)
        elif GREEK_RE.search(joined):
            # paragraphe grec sans numéro de verset (ex. variantes de Daniel)
            verse["grec"] += ("\n" if verse["grec"] else "") + joined
        elif joined.strip():
            verse["autres"].append(joined)

    def flush_verse():
        nonlocal verse
        flush_p_neutral()
        if verse is not None and section is not None:
            section["versets"].append(verse)
        verse = None

    def new_verse(label):
        nonlocal pending, verse
        v = {"verset": label, "grec": "", "giguet": "", "alexandrie": "",
             "autres": [], "titres": []}
        if pending:
            items, pending = pending, []
            joined = ["".join(items)]
            if section is not None and not section["versets"]:
                section["introduction"].extend(joined)
            else:
                v["titres"].extend(joined)
        verse = v

    def new_section(cn_val):
        nonlocal section, first_section, pending, pending_h1
        flush_verse()
        if section is not None:
            sections.append(section)
        libelle = decode_nbsp(cn_val.strip())
        if first_section:
            chap = toc_chap
            groupe = None
        else:
            m = CN_NUM_RE.match(libelle)
            chap = int(m.group(1)) if m else None
            groupe = pending_h1
        section = {
            "chapitre": chap,
            "libelle": libelle,
            "fichierToc": toc_name,
            "groupe": groupe,
            "introduction": ["".join(pending)] if pending else [],
            "versets": [],
            "brut": [],
        }
        pending = []
        pending_h1 = None
        first_section = False

    def note_h1(text):
        nonlocal pending_h1
        pending_h1 = STRIP_TAGS_RE.sub("", text).strip()

    def route(tok):
        nonlocal pending
        if channel in ("giguet", "alex"):
            if verse is not None:
                verse["giguet" if channel == "giguet" else "alexandrie"] += tok
            elif section is not None:
                section["brut"].append(tok)
            else:
                pending.append(tok)
        elif para_grec and verse is not None:
            verse["grec"] += tok
        elif not tok.strip():
            pass  # espaces neutres cosmétiques
        elif tok in BARE_BR and not in_p:
            pass  # <br> neutre hors paragraphe
        elif in_p:
            if verse is not None:
                p_neutral.append(tok)   # arbitrage à la fermeture du paragraphe
            elif section is not None:
                section["brut"].append(tok)
            else:
                pending.append(tok)
        else:
            pending.append(tok)

    for m in TOK_RE.finditer(body):
        if m.group("vv"):
            flush_verse()
            para_grec = False
        elif m.group("fontopen"):
            channel = "giguet" if m.group("color") == "darkblue" else "alex"
        elif m.group("fontclose"):
            channel = None
        elif m.group("span"):
            cls, val = m.group("scls"), m.group("sval")
            if cls == "cn":
                new_section(val)
                label = val.strip() if VERSE_A_RE.match(val.strip()) else "1"
                new_verse(label)
            else:  # vn
                # cas cn+vn dans le même paragraphe (ex: 1KI/003 « 1 = 2.35c ») :
                # on renomme le verset vide créé par cn au lieu d'en créer un second
                if (verse is not None and not verse["autres"] and not any(
                        verse[k].strip() for k in ("grec", "giguet", "alexandrie"))):
                    verse["verset"] = val.strip()
                else:
                    flush_verse()
                    new_verse(val.strip())
            para_grec = True
        elif m.group("popen"):
            in_p = True
            para_grec = False
        elif m.group("pclose"):
            flush_p_neutral()
            in_p = False
            para_grec = False
        elif m.group("h"):
            if verse is None or (not in_p and channel is None):
                pending.append(m.group(0))
                if m.group("htag") == "h1":
                    note_h1(m.group("htext"))
            else:
                route(m.group(0))
        elif m.group("tag"):
            route(m.group(0))
        elif m.group("txt"):
            route(m.group("txt"))

    flush_verse()
    if section is not None:
        sections.append(section)
    return sections, anomalies

# --------------------------------------------------------------------------
# Traitement de toutes les entrées TOC
# --------------------------------------------------------------------------
livres = {}          # code -> {"code","book","fichiersToc":[],"chapitres":[]}
ordre_toc_livres = []
glossaires = []      # (nom, contenu)
meta_header = None
meta_index = None
anomalies_globales = []

for (toc_name, addr, size), (blk_size, body) in zip(toc_entries, blocks):
    if toc_name.startswith("glossaire/"):
        glossaires.append((toc_name[len("glossaire/"):-len(".html")], body))
        continue
    if toc_name == "header.xml":
        meta_header = body
        continue
    if toc_name == "index.html":
        meta_index = body
        continue
    m = BIBLE_RE.match(toc_name)
    if not m:
        anomalies_globales.append(f"entrée TOC inattendue: {toc_name}")
        continue
    code, chap_s = m.group(1), m.group(2)
    toc_chap = int(chap_s)
    if code not in livres:
        livres[code] = {
            "code": code,
            "book": NOMS_LIVRES.get(code, code),
            "fichiersToc": [],
            "chapitres": [],
        }
        ordre_toc_livres.append(code)
    livres[code]["fichiersToc"].append(toc_name)

    sections, sec_anoms = parse_block(body, toc_name, toc_chap)
    for a in sec_anoms:
        if a == "entete_absente":
            anomalies_globales.append(f"{toc_name}: en-tête Giguet/Alexandrie absent")
        else:
            anomalies_globales.append(f"{toc_name}: {a}")

    # cn ≠ numéro TOC sur la première section
    if sections:
        m2 = CN_NUM_RE.match(sections[0]["libelle"])
        cn_num = int(m2.group(1)) if m2 else None
        if cn_num is not None and cn_num != toc_chap:
            anomalies_globales.append(
                f'{toc_name}: cn="{sections[0]["libelle"]}" ≠ numéro TOC {toc_chap}'
            )

    for s in sections:
        # doublon potentiel (même groupe + même numéro déjà présent)
        for prev in livres[code]["chapitres"]:
            if prev["groupe"] == s["groupe"] and prev["chapitre"] == s["chapitre"]:
                s["doublon_de"] = f'{prev["fichierToc"]}#{prev["libelle"]}'
                anomalies_globales.append(
                    f'{s["fichierToc"]} chap. {s["libelle"]}: doublon de '
                    f'{prev["fichierToc"]}#{prev["libelle"]}'
                )
                break
        livres[code]["chapitres"].append(s)

# --------------------------------------------------------------------------
# Écriture
# --------------------------------------------------------------------------
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "livres").mkdir(exist_ok=True)
(OUT / "glossaire").mkdir(exist_ok=True)
(OUT / "meta").mkdir(exist_ok=True)

print("Écriture des livres…")
stats = {"versets_total": 0, "avec_grec": 0, "avec_giguet": 0, "avec_alexandrie": 0,
         "versets_vides": 0, "chapitres_total": 0, "doublons": 0,
         "sous_versets_non_numeriques": 0}
livres_avec_alex = []
for code in ordre_toc_livres:
    obj = livres[code]
    alex = False
    for ch in obj["chapitres"]:
        stats["chapitres_total"] += 1
        if "doublon_de" in ch:
            stats["doublons"] += 1
        for v in ch["versets"]:
            for k in ("grec", "giguet", "alexandrie"):
                v[k] = v[k].strip()
            stats["versets_total"] += 1
            if v["grec"].strip():
                stats["avec_grec"] += 1
            if v["giguet"].strip():
                stats["avec_giguet"] += 1
            if v["alexandrie"].strip():
                stats["avec_alexandrie"] += 1
                alex = True
            if not any((v["grec"].strip(), v["giguet"].strip(), v["alexandrie"].strip())):
                stats["versets_vides"] += 1
            if v["verset"] and not v["verset"].isdigit():
                stats["sous_versets_non_numeriques"] += 1
    if alex:
        livres_avec_alex.append(code)
    path = OUT / "livres" / f"{code}.json"
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1), encoding="utf-8")

for nom, contenu in glossaires:
    (OUT / "glossaire" / f"{nom}.html").write_text(contenu, encoding="utf-8")

(OUT / "meta" / "header.xml").write_text(meta_header or "", encoding="utf-8")
(OUT / "meta" / "index.html").write_text(meta_index or "", encoding="utf-8")
toc_json = [{"name": n, "addr": int(a), "size": int(s) if s else None}
            for n, a, s in toc_entries]
(OUT / "meta" / "toc.json").write_text(
    json.dumps(toc_json, ensure_ascii=False, indent=1), encoding="utf-8")

# section <words> : brut + parsing
words_raw = words_m.group(1) if words_m else ""
(OUT / "meta" / "words.xml").write_text(words_raw, encoding="utf-8")
word_pairs = re.findall(r"<n>(.*?)</n>\s*<r>(.*?)</r>", words_raw, re.S)
if word_pairs:
    with open(OUT / "meta" / "words.jsonl", "w", encoding="utf-8") as f:
        for n, r in word_pairs:
            f.write(json.dumps({"n": n, "r": r}, ensure_ascii=False) + "\n")

index_raw = index_m.group(1) if index_m else ""
(OUT / "meta" / "index-section.xml").write_text(index_raw, encoding="utf-8")

glossaire_map = {f"g*SEF*{nom}": f"glossaire/{nom}.html" for nom, _ in glossaires}

manifest = {
    "source": str(SRC),
    "bible": {
        "id": "SEF", "titre": "Septuaginta", "auteur": "Alfred Rahlfs",
        "langue_source": "grec (Septante)",
        "traductions_francaises": [
            {"nom": "Traduction française de Giguet", "couleur_source": "darkblue",
             "couverture": "tous les livres"},
            {"nom": "Traduction française d'Alexandrie", "couleur_source": "green",
             "couverture": "partiel",
             "livres": livres_avec_alex},
        ],
        "header_xml": "meta/header.xml",
    },
    "ordre_toc_livres": ordre_toc_livres,   # commence par 1CH (classement alphabétique)
    "livres": [{"code": c, "book": livres[c]["book"],
                "nb_fichiers": len(livres[c]["fichiersToc"]),
                "nb_chapitres": len(livres[c]["chapitres"])} for c in ordre_toc_livres],
    "entrees_toc": {"total": len(toc_entries),
                    "bible": sum(1 for n, a, s in toc_entries if BIBLE_RE.match(n)),
                    "glossaire": len(glossaires),
                    "autres": 2},
    "glossaire_map": glossaire_map,
    "sections_extraites": {
        "toc": "meta/toc.json", "words": "meta/words.xml",
        "words_parsed": "meta/words.jsonl" if word_pairs else None,
        "index": "meta/index-section.xml",
        "addresses": addr_m.group(1).strip() if addr_m else None,
    },
    "stats": stats,
    "anomalies": anomalies_globales,
}
(OUT / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")

# --------------------------------------------------------------------------
# Rapport
# --------------------------------------------------------------------------
lignes = []
lignes.append("Extraction SEF.xml — Septuaginta en français (Biblia Universalis 3)")
lignes.append("=" * 70)
lignes.append(f"Blocs bible                      : {manifest['entrees_toc']['bible']}")
lignes.append(f"Entrées glossaire                : {len(glossaires)}")
lignes.append(f"Livres (ordre TOC, 1CH d'abord)  : {len(ordre_toc_livres)}")
lignes.append(f"Chapitres extraits               : {stats['chapitres_total']} "
              f"(dont {stats['doublons']} doublons signalés)")
lignes.append(f"Versets total                    : {stats['versets_total']}")
lignes.append(f"  avec texte grec                : {stats['avec_grec']}")
lignes.append(f"  avec traduction Giguet         : {stats['avec_giguet']}")
lignes.append(f"  avec traduction Alexandrie     : {stats['avec_alexandrie']}")
lignes.append(f"  sans aucun texte               : {stats['versets_vides']}")
lignes.append(f"Sous-versets non numériques      : {stats['sous_versets_non_numeriques']}")
lignes.append(f"Entrées <words> parsées          : {len(word_pairs)}")
lignes.append("")
lignes.append("Anomalies / cas particuliers du source")
lignes.append("-" * 70)
for a in anomalies_globales:
    lignes.append("  - " + a)
lignes.append("  - EZR/011: grec seul (sans traduction), texte identique au grec du")
lignes.append("    chapitre 10, titré « Esdras A » dans la source")
lignes.append("  - EZR/010 contient aussi Esdras A chapitres 1 à 9 (groupe « Esdras A »)")
lignes.append("  - PSA/150 contient aussi le psaume 151 ; SIR/051 contient aussi le prologue (52)")
lignes.append("  - 1KI/020b est une variante orthographique de 1KI/020 (&nbsp; vs espace fine)")
lignes.append("")
lignes.append("Ordre TOC des livres : " + ", ".join(ordre_toc_livres))
(OUT / "rapport.txt").write_text("\n".join(lignes), encoding="utf-8")

print("\n".join(lignes[:14]))
print(f"\nSortie : {OUT}")
