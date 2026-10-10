# -*- coding: utf-8 -*-
"""
Extraction des versions LGS et LSS depuis les XML de Biblia Universalis 3,
puis comparaison avec la LSGS embarquée dans l'application.

Source : C:\\Users\\laptek\\Documents\\Bible\\Biblia Universalis 3 (1.39)\\Ressources\\bibles
Sortie : extraction/LGS/ et extraction/LSS/ (registre de ce dépôt, régénérable)
         `--assets LSS` dépose en plus bible_app/assets/bible/lss/ en JSON
         compact (26 Mo au lieu de 75) : l'actif que charge LsgsRepository.

Ce que disent les modules de Biblia (liste `Ressources/4.html`) :

    LSG  Segond Louis (1910)                     ← sans Strong, hors périmètre
    LSS  Segond Louis + Strong                   ← 79 Mo
    LGS  Segond Louis + Strong (2)               ← 141 Mo

Format source (constaté, non documenté) :

    <?xml …?>
    <bible>
      <title>Louis Segond + Strong</title> …       ← en-tête, avant <files>
      <files>
        <number>N</number>                        ← N blocs
        <file>
          <size>S</size>                          ← S = taille EN OCTETS de <data>
          <data>…HTML d'un chapitre…</data>
        </file>…
      </files>
      <toc>                                       ← UNE entrée par bloc, même ordre
        <input><name>GEN/001.html</name><addr>77</addr></input>…
      </toc>
      <words>…</words> <index>…</index> <addresses>…</addresses>
    </bible>

Points de vigilance, tous vérifiés par les sondes :

- **Le `<toc>` porte les références** : `CODE/NNN.html` donne livre et chapitre,
  et chaque `addr` tombe pile sur l'offset du `<file>` correspondant (0 écart
  sur 1190 + 1192 entrées). Sans ce TOC, LGS n'aurait aucune référence : ses
  chapitres ne portent ni titre ni nom de livre.
- 66 codes livre, même ordre dans les deux fichiers, 1189 chapitres réels
  (929 AT + 260 NT). Le reste du TOC est du bruit : `index.html` (LGS + LSS),
  `images/beige.gif` et `styles.css` (LSS) — 4 blocs écartés, dont un GIF qui
  contient un profil ICC et casse un décodage UTF-8 strict.
- `<size>` = octets exacts de `<data>` : invariant vérifié sur les 2382 blocs.
- Découpe des versets sur `<span class="cn|vn">N</span>`, mais **le nombre ne
  fait pas foi** : `cn` porte le numéro de chapitre et ouvre le verset 1 (dont
  le numéro n'est jamais écrit), `vn` porte le numéro de verset à partir du
  deuxième marqueur. Contrôlé à 1..N par chapitre, écarts consignés dans le
  rapport.
- Trois formes d'ancres :
    <a class="glossaire" href="h.php?c=STR&f=H7225" title="…">7225</a>
        code Strong, TOUJOURS après le mot qu'il qualifie, avec un espace
        d'affichage avant (superscript) qu'il faut retirer du texte ;
    <a class="glossaire" href="h.php?c=STR&f=H8804" title="">08804</a>
        LSS seul : mot non traduit (waw, 'eth, article…) sans mot français —
        le code n'a rien à quoi s'accrocher ;
    <a href="" title="livre_écrit">◎</a>
        marqueur de structure, sans Strong : retiré avec son glyphe.
- LSS est le seul à porter les marqueurs de structure `<title>` par chapitre
  (inutilisé ici : le TOC fait foi pour les deux).

Sorties, par version (schéma strictement identique à
`bible_app/assets/bible/lsgs/`, format getbible « with strongs ») :

    <CODE>/<NN>-<Livre>.json   {book, abbreviation, bym_index, osis_id,
                                chapters:[{chapter, verses:[{verse,
                                tokens:[{text, strong}]}]}]}
    rapport_lgs_lss.md         comparaison avec la LSGS embarquée (--rapport)

Le token « fort » porte le mot ; les espaces de jonction vont dans les tokens
sans Strong, comme dans la LSGS de l'app. Un token de texte vide ne porte que
le code : c'est le cas, dans LSS, des mots non traduits (compté, cf. rapport).

Usage :  python extraction/extract_lgs_lss.py [--rapport]
Python 3.12, stdlib uniquement.
"""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import sys
import unicodedata
from collections import Counter, OrderedDict
from pathlib import Path

SOURCE = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles")
OUT = Path(__file__).resolve().parent
ASSETS = OUT.parent / "bible_app" / "assets" / "bible" / "lsgs"
# `--assets CODE` dépose aussi le corpus dans `assets/bible/<dossier>/` : le
# nom du dossier est celui que `LsgsRepository` charge (lib/data/lsgs_repository.dart).
ASSETS_ROOT = OUT.parent / "bible_app" / "assets" / "bible"
ASSETS_DIRS = {"LSS": "lss", "LGS": "lgs"}
CODES = ("LGS", "LSS")

# Code TOC -> osis_id de l'app (les 66 livres, mêmes sigles que SWORD).
TOC_TO_OSIS = {
    "GEN": "Gen", "EXO": "Exod", "LEV": "Lev", "NUM": "Num", "DEU": "Deut",
    "JOS": "Josh", "JDG": "Judg", "RUT": "Ruth", "1SA": "1Sam", "2SA": "2Sam",
    "1KI": "1Kgs", "2KI": "2Kgs", "1CH": "1Chr", "2CH": "2Chr", "EZR": "Ezra",
    "NEH": "Neh", "EST": "Esth", "JOB": "Job", "PSA": "Ps", "PRO": "Prov",
    "ECC": "Eccl", "SNG": "Song", "ISA": "Isa", "JER": "Jer", "LAM": "Lam",
    "EZK": "Ezek", "DAN": "Dan", "HOS": "Hos", "JOL": "Joel", "AMO": "Amos",
    "OBA": "Obad", "JON": "Jonah", "MIC": "Mic", "NAM": "Nah", "HAB": "Hab",
    "ZEP": "Zeph", "HAG": "Hag", "ZEC": "Zech", "MAL": "Mal", "MAT": "Matt",
    "MRK": "Mark", "LUK": "Luke", "JHN": "John", "ACT": "Acts", "ROM": "Rom",
    "1CO": "1Cor", "2CO": "2Cor", "GAL": "Gal", "EPH": "Eph", "PHP": "Phil",
    "COL": "Col", "1TH": "1Thess", "2TH": "2Thess", "1TI": "1Tim",
    "2TI": "2Tim", "TIT": "Titus", "PHM": "Phlm", "HEB": "Heb", "JAS": "Jas",
    "1PE": "1Pet", "2PE": "2Pet", "1JN": "1John", "2JN": "2John",
    "3JN": "3John", "JUD": "Jude", "REV": "Rev",
}
OSIS_TO_CODE = {v: k for k, v in TOC_TO_OSIS.items()}

FILE_RE = re.compile(rb"<file>\s*<size>(\d+)</size>\s*<data>")
TOC_RE = re.compile(rb"<toc>(.*?)</toc>", re.S)
TOC_ENTRY_RE = re.compile(rb"<input><name>(.*?)</name><addr>(\d+)</addr></input>")
CHAPTER_NAME_RE = re.compile(r"^([A-Za-z0-9]{2,5})/(\d{3})\.html$")
# `cn` = numéro de CHAPITRE, toujours sur le premier marqueur du bloc : ce
# marqueur ouvre le verset 1, dont le numéro n'est jamais écrit. `vn` = numéro
# de verset, à partir du deuxième marqueur.
MARK_RE = re.compile(r'<span class="(cn|vn)">(\d+)</span>')
# L'ancre Strong est reconnue à son href ; son contenu (le numéro affiché) ne
# doit jamais atterrir dans le texte.
STRONG_RE = re.compile(r'<a\b[^>]*href="h\.php\?c=STR&f=([HG])(\d+)"[^>]*>.*?</a>', re.S)
# Toute autre ancre (◎ de structure) disparaît avec son glyphe.
OTHER_ANCHOR_RE = re.compile(r"<a\b[^>]*>.*?</a>", re.S)
TAG_RE = re.compile(r"<[^>]+>")
# Mot qui peut recevoir un code Strong : le dernier mot avant l'espace d'affichage.
WORD_RE = re.compile(r"[0-9A-Za-zÀ-ÖØ-öø-ÿŒœ’'\-]+$")


# --------------------------------------------------------------------------- #
# Lecture                                                                      #
# --------------------------------------------------------------------------- #

def load(code: str) -> tuple[list[tuple[int, bytes]], list[tuple[str, int]], list[str]]:
    """Découpe le XML en octets. Renvoie (blocs avec offset, entrées TOC, anomalies)."""
    raw = (SOURCE / f"{code}.xml").read_bytes()
    anomalies: list[str] = []
    blocks: list[tuple[int, bytes]] = []
    for m in FILE_RE.finditer(raw):
        start = m.end()
        size = int(m.group(1))
        end = raw.find(b"</data>", start)
        while end != -1 and end - start != size:
            end = raw.find(b"</data>", end + 1)
        if end == -1:
            anomalies.append(f"bloc @{m.start()}: pas de </data> à <size>={size}")
            end = raw.find(b"</data>", start)
        blocks.append((m.start(), raw[start:end]))
    toc_m = TOC_RE.search(raw)
    if not toc_m:
        raise ValueError(f"{code}: pas de <toc>")
    entries = [(name.decode("utf-8"), int(addr))
               for name, addr in TOC_ENTRY_RE.findall(toc_m.group(1))]
    if len(entries) != len(blocks):
        anomalies.append(f"{len(entries)} entrées TOC != {len(blocks)} blocs")
    for i, ((name, addr), (offset, _)) in enumerate(zip(entries, blocks)):
        if addr != offset:
            anomalies.append(f"#{i}: addr TOC {addr} != offset <file> {offset} ({name})")
    return blocks, entries, anomalies


def app_meta() -> dict[str, dict]:
    """Métadonnées des 66 livres, indexées par osis_id (en-tête des JSON de l'app)."""
    meta: dict[str, dict] = {}
    for path in sorted(ASSETS.glob("*.json")):
        with path.open(encoding="utf-8") as fh:
            head = fh.read(400)
        osis = re.search(r'"osis_id":\s*"(.*?)"', head).group(1)
        meta[osis] = {
            "file": path.name,
            "book": re.search(r'"book":\s*"(.*?)"', head).group(1),
            "abbreviation": re.search(r'"abbreviation":\s*"(.*?)"', head).group(1),
            "bym_index": int(re.search(r'"bym_index":\s*(\d+)', head).group(1)),
            "osis_id": osis,
        }
    if len(meta) != 66:
        raise ValueError(f"66 livres attendus dans {ASSETS}, {len(meta)} lus")
    return meta


# --------------------------------------------------------------------------- #
# Parsing d'un chapitre                                                        #
# --------------------------------------------------------------------------- #

def clean(fragment: str) -> str:
    """Balises retirées, entités décodées, espaces insécables normalisés."""
    fragment = OTHER_ANCHOR_RE.sub("", fragment)   # avant : les balises enlevées
    fragment = TAG_RE.sub("", fragment)            # avaleraient les ancres ◎
    return html_lib.unescape(fragment).replace("\xa0", " ")


def verse_tokens(content: str, stats: Counter) -> list[tuple[str, str | None]]:
    """HTML d'un verset -> jetons (texte, strong).

    L'ancre suit le mot (superscript) avec un espace d'affichage avant : cet
    espace est retiré, sinon « Adam , Seth » au lieu de « Adam, Seth ». Un code
    sans mot recevable (LSS, mots non traduits) devient un jeton de texte vide.
    """
    pieces: list[tuple[str, str | None]] = []
    pos = 0
    for m in STRONG_RE.finditer(content):
        pieces.append((content[pos:m.start()], None))
        pieces.append((None, f"{m.group(1)}{int(m.group(2)):04d}"))
        pos = m.end()
    pieces.append((content[pos:], None))

    tokens: list[tuple[str, str | None]] = []
    buf = ""
    for text, strong in pieces:
        if text is not None:
            buf += clean(text)
            continue
        head = buf.rstrip()
        word = WORD_RE.search(head)
        if word:
            if word.start():
                tokens.append((head[:word.start()], None))
            tokens.append((word.group(0), strong))
        else:
            if head:
                tokens.append((head, None))
            tokens.append(("", strong))
            stats["strong_sans_mot"] += 1
        buf = ""
    if buf:
        tokens.append((buf, None))
    return tokens


def trim(tokens: list[tuple[str, str | None]]) -> list[tuple[str, str | None]]:
    """Espaces de début/fin de verset retirés (le marqueur est suivi d'un espace)."""
    out = list(tokens)
    while out and out[0][1] is None and not out[0][0]:
        out.pop(0)
    while out and out[-1][1] is None and not out[-1][0]:
        out.pop()
    if out and out[0][1] is None:
        head = out[0][0].lstrip()
        out[0] = (head, None)
    if out and out[-1][1] is None:
        tail = out[-1][0].rstrip()
        out[-1] = (tail, None)
    if out and out[0][1] is None and not out[0][0]:
        out.pop(0)
    if out and out[-1][1] is None and not out[-1][0]:
        out.pop()
    return out


def merge_adjacent(marks: list, data: str, ref: str, stats: Counter) -> list:
    """Deux marqueurs collés (rien qu'un espace entre eux) : le second n'ouvre rien.

    LSS en insère un à côté du bon numéro — `<span class="vn">16</span>
    <span class="vn">2</span>` — et le premier numéro est le bon : le verset
    deviendrait vide, suivi d'un verset fantôme reprenant son texte.
    """
    kept = [marks[0]]
    for prev, cur in zip(marks, marks[1:]):
        if data[prev[2].end():cur[2].start()].strip():
            kept.append(cur)
            continue
        stats["marqueurs_colles"] += 1
        if stats["marqueurs_colles"] <= 10:
            stats.setdefault("exemples_colles", []).append(
                f"{ref}: {prev[2].group(0)} puis {cur[2].group(0)}")
    return kept


def renumber(ref: str, verses: list[tuple[int, list]], stats: Counter) -> list[tuple[int, list]]:
    """Numérotation d'origine absurde -> la position fait foi.

    Ne s'applique que si le dernier numéro vaut N (le chapitre contient donc
    bien N versets et seulement des étiquettes fautives : un numéro répété, un
    trou suivi d'une répétition, une coquille « 38 » pour « 28 »). Sinon un
    marqueur manque vraiment : la numérotation d'origine est conservée et
    `check_numbering` la signale.
    """
    nums = [n for n, _ in verses]
    count = len(verses)
    if not count or nums == list(range(1, count + 1)):
        return verses
    if nums[-1] != count:
        return verses
    stats["chapitres_renumeros"] += 1
    if stats["chapitres_renumeros"] <= 20:
        stats.setdefault("exemples_renumeros", []).append(
            f"{ref}: {nums} -> 1..{count}")
    return [(i + 1, tokens) for i, (_, tokens) in enumerate(verses)]


def parse_chapter(data: str, chapter: int, ref: str, stats: Counter) -> list[tuple[int, list[tuple[str, str | None]]]]:
    """Un chapitre HTML -> [(numéro de verset, jetons)].

    Le premier marqueur est un `cn` : il porte le numéro de chapitre et ouvre
    le verset 1, seul numéro de verset non écrit du chapitre. Les suivants sont
    des `vn` et portent leur numéro.
    """
    marks = [(m.group(1), int(m.group(2)), m) for m in MARK_RE.finditer(data)]
    if not marks:
        stats["chapitres_sans_marqueur"] += 1
        return []
    marks = merge_adjacent(marks, data, ref, stats)
    verses: list[tuple[int, list[tuple[str, str | None]]]] = []
    for i, (kind, number, m) in enumerate(marks):
        end = marks[i + 1][2].start() if i + 1 < len(marks) else len(data)
        content = data[m.end():end]
        tokens = trim(verse_tokens(content, stats))
        if not tokens:
            stats["versets_vides"] += 1
        if i == 0:
            if kind != "cn":
                stats["premier_marqueur_hors_cn"] += 1
                verse_no = number
            else:
                verse_no = 1
                if number != chapter:
                    stats["cn_hors_toc"] += 1
                    if stats["cn_hors_toc"] <= 5:
                        stats.setdefault("exemples_cn", []).append(
                            f"chapitre {chapter}: cn={number}")
        else:
            if kind != "vn":
                stats["marqueur_cn_en_cours"] += 1
            verse_no = number
        verses.append((verse_no, tokens))
    return renumber(ref, verses, stats)


def check_numbering(ref: str, verses: list[tuple[int, list]], stats: Counter) -> None:
    """Le chapitre doit porter les versets 1..N, sans trou ni doublon."""
    nums = [n for n, _ in verses]
    if nums != list(range(1, len(nums) + 1)):
        stats["chapitres_numerotation"] += 1
        stats.setdefault("exemples_numerotation", [])
        if len(stats["exemples_numerotation"]) < 10:
            stats["exemples_numerotation"].append(f"{ref}: {nums}")


# --------------------------------------------------------------------------- #
# Extraction fichier par fichier                                               #
# --------------------------------------------------------------------------- #

def extract(code: str, meta: dict[str, dict],
            assets_root: Path | None = None) -> tuple[dict, dict]:
    """Extrait une version. Renvoie (rapport, digest de comparaison).

    [assets_root], quand il est donné, reçoit en plus le même corpus en JSON
    compact — c'est l'actif que l'application embarque, et 64 % de blancs (75 →
    26 Mo) ne servent qu'à peser le paquet.
    """
    blocks, entries, anomalies = load(code)
    stats: Counter = Counter()
    # (osis, chapitre) -> versets
    chapters: "OrderedDict[tuple[str, int], list]" = OrderedDict()
    skipped: list[str] = []

    for (_, data), (name, _) in zip(blocks, entries):
        m = CHAPTER_NAME_RE.match(name)
        if not m:
            skipped.append(name)
            continue
        toc_code, toc_chapter = m.group(1), int(m.group(2))
        if toc_code not in TOC_TO_OSIS:
            anomalies.append(f"code livre inconnu dans le TOC: {name}")
            continue
        osis = TOC_TO_OSIS[toc_code]
        stats["blocs"] += 1
        text = data.decode("utf-8", errors="replace")
        if "�" in text:
            stats["caracteres_invalides"] += text.count("�")
        verses = parse_chapter(text, toc_chapter, name, stats)
        if not verses:
            anomalies.append(f"{name}: aucun marqueur de verset")
            continue
        check_numbering(name, verses, stats)
        chapters[(osis, toc_chapter)] = verses

    # écriture, livre par livre, dans l'ordre bym_index de l'app
    root = OUT / code
    root.mkdir(parents=True, exist_ok=True)
    for old in root.glob("*.json"):
        old.unlink()
    if assets_root is not None:
        assets_root.mkdir(parents=True, exist_ok=True)
        for old in assets_root.glob("*.json"):
            old.unlink()
    by_book: "OrderedDict[str, list[tuple[int, list]]]" = OrderedDict()
    for (osis, chapter), verses in chapters.items():
        by_book.setdefault(osis, []).append((chapter, verses))

    digest: dict[tuple[str, int, int], tuple[str, str, str, tuple[str, ...]]] = {}
    for osis, items in by_book.items():
        info = meta[osis]
        items.sort(key=lambda kv: kv[0])
        doc = {
            "book": info["book"],
            "abbreviation": info["abbreviation"],
            "bym_index": info["bym_index"],
            "osis_id": osis,
            "chapters": [
                {
                    "chapter": chapter,
                    "verses": [
                        {
                            "verse": number,
                            "tokens": [
                                {"text": text, "strong": strong}
                                for text, strong in tokens
                            ],
                        }
                        for number, tokens in verses
                    ],
                }
                for chapter, verses in items
            ],
        }
        (root / info["file"]).write_text(
            json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        if assets_root is not None:
            # L'actif embarqué, compact : même contenu, aucun blanc inutile.
            (assets_root / info["file"]).write_text(
                json.dumps(doc, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
        for chapter, verses in items:
            for number, tokens in verses:
                digest[(osis, chapter, number)] = digest_of(tokens)
                stats["versets"] += 1
                stats["jetons"] += len(tokens)
                stats["jetons_forts"] += sum(1 for _, s in tokens if s)

    codes = Counter()
    sans_mot: Counter = Counter()
    for (_, _, _), (_, _, _, strongs) in digest.items():
        codes.update(strongs)
    for chapters_list in by_book.values():
        for _, verses in chapters_list:
            for _, tokens in verses:
                for text, strong in tokens:
                    if strong and not text:
                        sans_mot.update(strong.split())
    stats["codes_distincts"] = len(codes)

    report = {
        "code": code,
        "blocs_toc": len(entries),
        "chapitres": len(chapters),
        "livres": len(by_book),
        "sautes": skipped,
        "anomalies": anomalies,
        **{k: v for k, v in stats.items()
           if k not in ("exemples_numerotation", "exemples_cn")},
        "exemples_numerotation": stats.get("exemples_numerotation", []),
        "exemples_cn": stats.get("exemples_cn", []),
        "codes": codes,
        "codes_sans_mot": sans_mot,
    }
    return report, digest


# --------------------------------------------------------------------------- #
# Version embarquée de l'app + normalisation                                   #
# --------------------------------------------------------------------------- #

def load_app() -> tuple[dict, dict]:
    """Charge la LSGS embarquée. Renvoie (digest, stats des codes composites)."""
    digest: dict[tuple[str, int, int], tuple[str, str, str, tuple[str, ...]]] = {}
    composites: list[str] = []
    for path in sorted(ASSETS.glob("*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        osis = doc["osis_id"]
        for chapter in doc["chapters"]:
            for verse in chapter["verses"]:
                tokens = [(t["text"], t["strong"]) for t in verse["tokens"]]
                for _, strong in tokens:
                    if strong and " " in strong:
                        composites.append(strong)
                digest[(osis, chapter["chapter"], verse["verse"])] = digest_of(tokens)
    return digest, {"jetons_composites": len(composites),
                    "composites_distincts": len(set(composites)),
                    "composites_exemples": sorted(set(composites))[:8]}


def norm_forme(text: str) -> str:
    """Typographie neutralisée : apostrophes, tirets, espaces, insécables."""
    text = unicodedata.normalize("NFC", text)
    for a, b in (("’", "'"), ("‘", "'"), ("ʼ", "'"), ("´", "'"),
                 ("–", "-"), ("—", "-"), ("−", "-")):
        text = text.replace(a, b)
    text = text.replace("\xa0", " ")
    return re.sub(r"\s+", " ", text).strip()


def norm_sens(forme: str) -> str:
    """Lettres et chiffres seuls : « Jésus - Christ » == « Jésus-Christ ».

    Entrée = sortie de [norm_forme].
    """
    return re.sub(r"[^0-9A-Za-zÀ-ÖØ-öø-ÿŒœ]+", "", forme)


def sans_accents(sens: str) -> str:
    """Diacritiques retirés : LSS écrit « Enosch » là où l'app écrit « Énosch »."""
    decomposed = unicodedata.normalize("NFD", sens)
    stripped = "".join(c for c in decomposed if unicodedata.category(c) != "Mn")
    return (stripped.replace("œ", "oe").replace("Œ", "Oe")
                    .replace("æ", "ae").replace("Æ", "Ae"))


def digest_of(tokens: list[tuple[str, str | None]]) -> tuple[str, str, str, tuple[str, ...]]:
    """Jeton d'un verset -> les trois formes normalisées + la séquence de codes.

    La LSGS de l'app porte parfois deux codes dans un même jeton
    (`"strong": "H8337 H6240"`) : ils sont éclatés pour que les séquences soient
    comparables avec celles des XML, qui n'ont qu'un code par ancre.
    """
    text = "".join(t for t, _ in tokens)
    forme = norm_forme(text)
    strongs = tuple(code for _, s in tokens if s for code in s.split())
    return forme, norm_sens(forme), sans_accents(norm_sens(forme)), strongs


# --------------------------------------------------------------------------- #
# Rapport de comparaison                                                       #
# --------------------------------------------------------------------------- #

def excerpt(text: str, limit: int = 170) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def ref_label(meta: dict[str, dict], key: tuple[str, int, int]) -> str:
    osis, chapter, verse = key
    return f"{meta[osis]['book']} {chapter}:{verse}"


def compare(reports: list[dict], digests: dict[str, dict], app: dict,
            meta: dict[str, dict], app_stats: dict) -> str:
    out = ["# LGS / LSS (Biblia Universalis 3) vs LSGS embarquée", ""]
    out.append("- Sources : `Ressources/bibles/LGS.xml` (Segond Louis + Strong 2) et "
               "`LSS.xml` (Segond Louis + Strong), références lues dans leur `<toc>`.")
    out.append("- Référence : `bible_app/assets/bible/lsgs/` — « Bible Segond 1910 + "
               "Strongs » (`LSGS`), 66 livres, format getbible.")
    out.append("- Texte comparé après trois normalisations : **forme** (apostrophes, "
               "tirets, espaces) puis **sens** (lettres et chiffres seuls), puis "
               "**accents ignorés** (LSS omet les diacritiques : « Enosch » / « Énosch »).")
    out.append("- Les codes composites de l'app (`\"H8337 H6240\"`) sont éclatés en "
               "deux codes avant comparaison des séquences.")
    out.append("")
    out.append("## 1. Ce qui a été extrait")
    out.append("")
    out.append("| version | blocs | chapitres | livres | versets | jetons | dont forts | codes distincts |")
    out.append("|---|---:|---:|---:|---:|---:|---:|---:|")
    for rep in reports:
        out.append(f"| {rep['code']} | {rep['blocs_toc']} | {rep['chapitres']} | "
                   f"{rep['livres']} | {rep['versets']} | {rep['jetons']} | "
                   f"{rep['jetons_forts']} | {rep['codes_distincts']} |")
    out.append(f"| LSGS (app) | — | {len({(o, c) for o, c, _ in app})} | "
               f"{len({o for o, _, _ in app})} | {len(app)} | — | "
               f"{sum(len(v[3]) for v in app.values())} | "
               f"{len({s for v in app.values() for s in v[3]})} |")
    out.append("")
    for rep in reports:
        out.append(f"- **{rep['code']}** : blocs non chapitre écartés par le TOC — "
                   f"{', '.join(rep['sautes']) or 'aucun'} ; "
                   f"{rep.get('strong_sans_mot', 0)} codes sans mot recevable "
                   f"(mots non traduits, jeton de texte vide) ; "
                   f"{rep.get('caracteres_invalides', 0)} caractère(s) hors UTF-8.")
        if rep["anomalies"]:
            out.append(f"  - anomalies ({len(rep['anomalies'])}) :")
            out += [f"    - {a}" for a in rep["anomalies"][:10]]
        if rep.get("marqueurs_colles"):
            out.append(f"  - marqueurs collés fusionnés ({rep['marqueurs_colles']}) :")
            out += [f"    - {e}" for e in rep.get("exemples_colles", [])]
        if rep.get("chapitres_renumeros"):
            out.append(f"  - chapitres renumérotés par position "
                       f"({rep['chapitres_renumeros']}, numérotation d'origine fautive) :")
            out += [f"    - {e}" for e in rep.get("exemples_renumeros", [])]
        if rep["exemples_numerotation"]:
            out.append(f"  - numérotation encore hors 1..N "
                       f"({rep['chapitres_numerotation']} chapitre(s), "
                       f"marqueur réellement manquant) :")
            out += [f"    - {e}" for e in rep["exemples_numerotation"]]
        else:
            out.append("  - numérotation : 1..N sur les 1189 chapitres (0 écart)")
        out.append(f"  - marqueurs : cn d'ouverture conforme au TOC "
                   f"({rep.get('cn_hors_toc', 0)} écart(s)"
                   + (f", dont {', '.join(rep['exemples_cn'])}" if rep.get("exemples_cn") else "")
                   + f") ; {rep.get('premier_marqueur_hors_cn', 0)} chapitre(s) ouvert "
                   f"par un vn ; {rep.get('marqueur_cn_en_cours', 0)} cn en cours de chapitre")
        if rep.get("chapitres_sans_marqueur") or rep.get("versets_vides"):
            out.append(f"  - {rep.get('chapitres_sans_marqueur', 0)} chapitre(s) sans "
                       f"marqueur, {rep.get('versets_vides', 0)} verset(s) vide(s)")
    out.append("")

    # ---- couverture ----
    out.append("## 2. Couverture")
    out.append("")
    for code, dig in digests.items():
        app_only = sorted(set(app) - set(dig))
        dig_only = sorted(set(dig) - set(app))
        out.append(f"- **{code} vs LSGS** : {len(set(app) & set(dig))} versets communs ; "
                   f"{len(app_only)} seulement dans l'app ; {len(dig_only)} seulement dans {code}.")
        for key in app_only[:6]:
            out.append(f"  - absent de {code} : {ref_label(meta, key)}")
        for key in dig_only[:6]:
            out.append(f"  - absent de l'app : {ref_label(meta, key)}")
    out.append("")

    # ---- texte ----
    out.append("## 3. Texte")
    out.append("")
    out.append("| comparaison | versets communs | même forme | même sens | même sens (accents ignorés) |")
    out.append("|---|---:|---:|---:|---:|")
    samples: dict[str, list] = {k: [] for k in ("typo", "accents", "texte", "strong", "absent")}
    for code, dig in digests.items():
        common = sorted(set(app) & set(dig))
        meme_forme = sum(1 for k in common if app[k][0] == dig[k][0])
        meme_sens = sum(1 for k in common if app[k][1] == dig[k][1])
        meme_sans_acc = sum(1 for k in common if app[k][2] == dig[k][2])
        out.append(f"| {code} vs LSGS | {len(common)} | {meme_forme} | {meme_sens} | "
                   f"{meme_sans_acc} |")
        for key in common:
            if app[key][1] == dig[key][1]:
                if app[key][0] != dig[key][0]:
                    if len(samples["typo"]) < 8:
                        samples["typo"].append((code, key, app[key][0], dig[key][0]))
            elif app[key][2] == dig[key][2]:
                if len(samples["accents"]) < 8:
                    samples["accents"].append((code, key, app[key][0], dig[key][0]))
            elif len(samples["texte"]) < 10:
                samples["texte"].append((code, key, app[key][0], dig[key][0]))
        for key in sorted(set(dig) ^ set(app))[:4]:
            samples["absent"].append((code, key, app.get(key), dig.get(key)))
    out.append("")
    out.append("« Même forme » : espaces, apostrophes et tirets égalisés. "
               "« Même sens » : ponctuation et espaces retirés — un écart ici est "
               "un écart de rédaction, pas de typographie. « Accents ignorés » : "
               "diacritiques retirés en plus — ce qui reste est un vrai écart de "
               "texte.")
    out.append("")
    if samples["typo"]:
        out.append("### Écarts de forme seulement")
        out.append("")
        for code, key, a, b in samples["typo"]:
            out.append(f"- **{ref_label(meta, key)}** ({code})")
            out.append(f"  - LSGS : {excerpt(a)}")
            out.append(f"  - {code} : {excerpt(b)}")
        out.append("")
    if samples["accents"]:
        out.append("### Écarts d'accents seulement")
        out.append("")
        for code, key, a, b in samples["accents"]:
            out.append(f"- **{ref_label(meta, key)}** ({code})")
            out.append(f"  - LSGS : {excerpt(a)}")
            out.append(f"  - {code} : {excerpt(b)}")
        out.append("")
    if samples["texte"]:
        out.append("### Écarts de texte")
        out.append("")
        for code, key, a, b in samples["texte"]:
            out.append(f"- **{ref_label(meta, key)}** ({code})")
            out.append(f"  - LSGS : {excerpt(a)}")
            out.append(f"  - {code} : {excerpt(b)}")
        out.append("")
    if samples["absent"]:
        out.append("### Versets présents d'un seul côté (échantillon)")
        out.append("")
        for code, key, a, b in samples["absent"]:
            def shown(d: tuple) -> str:
                return "(verset vide)" if not d[0] else excerpt(d[0])
            out.append(f"- **{ref_label(meta, key)}** : "
                       + (f"absent de {code}, LSGS : {shown(a)}" if b is None
                          else f"absent de l'app, {code} : {shown(b)}"))
        out.append("")

    # ---- strong ----
    out.append("## 4. Codes Strong")
    out.append("")
    out.append("| comparaison | versets communs | même séquence | séquences différentes |")
    out.append("|---|---:|---:|---:|")
    str_samples: dict[str, list] = {k: [] for k in digests}
    for code, dig in digests.items():
        common = sorted(set(app) & set(dig))
        memes = [k for k in common if app[k][3] == dig[k][3]]
        out.append(f"| {code} vs LSGS | {len(common)} | {len(memes)} | "
                   f"{len(common) - len(memes)} |")
        for key in common:
            if app[key][3] != dig[key][3] and len(str_samples[code]) < 6:
                str_samples[code].append((code, key, app[key][3], dig[key][3]))
    out.append("")
    for code, samples_code in str_samples.items():
        if not samples_code:
            continue
        out.append(f"### Écarts de séquence — {code} (échantillon)")
        out.append("")
        for code, key, a, b in samples_code:
            only_a = [s for s in a if s not in b]
            only_b = [s for s in b if s not in a]
            out.append(f"- **{ref_label(meta, key)}** — "
                       f"LSGS {len(a)} codes / {code} {len(b)}"
                       + (f" · seulement LSGS {only_a}" if only_a else "")
                       + (f" · seulement {code} {only_b[:14]}"
                          if only_b else ""))
        out.append("")
    out.append("### Codes sans mot rendu (Strong non traduit)")
    out.append("")
    out.append("Un jeton `text: \"\"` + `strong: Hxxxx` : le code est là, le mot "
               "français n'existe pas (waw, ’eth, article, préfixes, particules). "
               "C'est ce qui fait la richesse du lexique mot à mot.")
    out.append("")
    for rep in reports:
        code = rep["code"]
        top = rep["codes_sans_mot"].most_common(14)
        total = sum(rep["codes_sans_mot"].values())
        out.append(f"- **{code}** : {total} occurrences, "
                   f"{len(rep['codes_sans_mot'])} codes distincts — les plus "
                   f"fréquents : "
                   + ", ".join(f"`{c}` ×{n}" for c, n in top) + ".")
    out.append("")
    out.append("### Étendue des codes")
    out.append("")
    out.append(f"- **LSGS (app)** : {app_stats.get('jetons_composites', 0)} jeton(s) "
               f"portant deux codes séparés par un espace "
               f"({app_stats.get('composites_distincts', 0)} combinaisons distinctes, "
               f"ex. {', '.join(app_stats.get('composites_exemples', [])) or 'aucune'}) — "
               f"éclatés avant comparaison.")
    out.append("")
    for rep in reports:
        code = rep["code"]
        app_codes = {s for v in app.values() for s in v[3]}
        dig_codes = set(rep["codes"])
        out.append(f"- **{code}** : {len(dig_codes)} codes distincts — "
                   f"{len(dig_codes & app_codes)} communs avec la LSGS, "
                   f"{len(dig_codes - app_codes)} seulement ici "
                   f"({', '.join(sorted(dig_codes - app_codes)[:12]) or 'aucun'}), "
                   f"{len(app_codes - dig_codes)} seulement dans la LSGS "
                   f"({', '.join(sorted(app_codes - dig_codes)[:12]) or 'aucun'}).")
    out.append("")
    return "\n".join(out)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description="Extrait LGS.xml et LSS.xml")
    ap.add_argument("--rapport", action="store_true",
                    help="génère rapport_lgs_lss.md (compare à la LSGS de l'app)")
    ap.add_argument("--assets", choices=CODES, default=None, metavar="CODE",
                    help="dépose aussi le corpus de CODE dans "
                         "bible_app/assets/bible/<code>/ en JSON compact "
                         "(l'actif que charge LsgsRepository)")
    args = ap.parse_args()

    meta = app_meta()
    reports, digests = [], {}
    for code in CODES:
        assets_root = (ASSETS_ROOT / ASSETS_DIRS[code]
                       if args.assets == code else None)
        rep, dig = extract(code, meta, assets_root=assets_root)
        reports.append(rep)
        digests[code] = dig
        print(f"{code}: {rep['chapitres']} chapitres, {rep['livres']} livres, "
              f"{rep['versets']} versets, {rep['jetons_forts']} codes Strong, "
              f"{rep['codes_distincts']} codes distincts")
        print(f"  TOC écarté : {', '.join(rep['sautes'])}")
        print(f"  {rep.get('strong_sans_mot', 0)} codes sans mot recevable, "
              f"{rep.get('caracteres_invalides', 0)} caractère(s) hors UTF-8")
        if rep["anomalies"]:
            print(f"  {len(rep['anomalies'])} anomalie(s):")
            for a in rep["anomalies"][:10]:
                print(f"    - {a}")
        else:
            print("  aucune anomalie")
        if rep["exemples_numerotation"]:
            print(f"  {rep['chapitres_numerotation']} chapitre(s) encore hors 1..N, "
                  f"dont : {rep['exemples_numerotation'][0]}")
        if rep.get("chapitres_renumeros"):
            print(f"  {rep['chapitres_renumeros']} chapitre(s) renumérotés par position "
                  f"({', '.join(rep.get('exemples_renumeros', [])[:3])})")
        if rep.get("marqueurs_colles"):
            print(f"  {rep['marqueurs_colles']} marqueur(s) collé(s) fusionné(s) "
                  f"({', '.join(rep.get('exemples_colles', [])[:3])})")
        print(f"  marqueurs : cn d'ouverture {rep.get('cn_hors_toc', 0)} écart(s) au TOC, "
              f"{rep.get('premier_marqueur_hors_cn', 0)} chapitre(s) sans cn, "
              f"{rep.get('marqueur_cn_en_cours', 0)} cn en cours de chapitre")
        if assets_root is not None:
            poids = sum(f.stat().st_size for f in assets_root.glob("*.json"))
            print(f"  actif embarqué écrit : {assets_root} "
                  f"({poids / 1048576:.1f} Mo compact)")

    if args.rapport:
        app, app_stats = load_app()
        md = compare(reports, digests, app, meta, app_stats)
        (OUT / "rapport_lgs_lss.md").write_text(md, encoding="utf-8")
        print("\n" + md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
