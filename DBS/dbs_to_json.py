# -*- coding: utf-8 -*-
"""
Extraction de la Darby + Strong (DBS) depuis Biblia Universalis 3.

Source : C:\\Users\\laptek\\Documents\\Bible\\Biblia Universalis 3 (1.39)\\Ressources\\bibles\\DBS.xml
Sortie : DBS/json/1.json … 66.json — un fichier par livre, numérotation
         standard 1=Genèse … 66=Apocalypse (jeton {book} de urlTemplate).

Schéma de sortie : getbible nu + Strong inline — {translation, abbreviation,
lang, nr, name, chapters:[{chapter, name, verses:[{chapter, verse, name,
text}]}]} — où `text` porte les codes Strong après leur mot (« Dieu H0430 »),
comme `LsgsRepository.joinTokens(includeStrong:true)` les rend dans le
lecteur. C'est ce qui rend les codes cliquables dans l'app avec
`hasStrong:true`, sans nouveau format : `bookFromGetbible` recopie le texte,
`verse_tile` y trouve ses codes via `strongCodePattern`.

Format source (même moteur que LGS/LSS, cf. extraction/extract_lgs_lss.py) :
  <bible><files><number>1257</number><file><size>S</size><data>…HTML…</data></file>…
  <toc><input><name>GEN/001.html</name><addr>offset</addr></input>…</toc>

- 1257 blocs = 1189 chapitres + 66 introductions (glossaire/*) + index.html +
  index_ori.html. Seuls les 1189 chapitres sont gardés.
- Découpage versets sur <span class="cn|vn"> : `cn` = n° chapitre, ouvre le
  verset 1 (non numéroté) ; `vn` = n° verset.
- Ancres Strong : <a … href="h.php?c=STR&f=H7225" …>7225</a>, TOUJOURS après
  le mot qualifié. Codes rembourrés à 4 chiffres (H430 → H0430) pour
  `strongCodePattern` ([A-Z][0-9]{4}) et le lexique.
- Notes Darby : <span class="nn">*</span> (appel) et <span class="note">[..]</span>
  (contenu) — retirés avec leur contenu, comme les versions nues (OST).
  <br> → espace (ne pas souder les mots des Psaumes).
- Astérisque de tête (« *Et Joseph », « *Bienheureux ») : marqueur de
  paragraphe Darby, retiré en tête de verset.
- Lien d'introduction (« Voir l'introduction ») avant le premier marqueur :
  ignoré par construction (texte avant le premier cn).

Usage :  C:\\Python312\\python.exe DBS/dbs_to_json.py
Python 3.12, stdlib uniquement.
"""

from __future__ import annotations

import html as html_lib
import json
import re
import sys
import unicodedata
from collections import Counter, OrderedDict
from pathlib import Path

SOURCE = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\bibles\DBS.xml")
RACINE = Path(__file__).resolve().parent
SORTIE = RACINE / "json"

# Code TOC (3 lettres Biblia) -> osis_id de l'app + nom français (en-tête LSGS).
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

# Ordre standard 1..66 (mêmes codes que le TOC) — le n° du fichier de sortie.
STANDARD_BOOKS = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT",
    "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST",
    "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN",
    "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG",
    "ZEC", "MAL",
    "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH",
    "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS",
    "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]
STANDARD_NUMBER = {code: i + 1 for i, code in enumerate(STANDARD_BOOKS)}

FILE_RE = re.compile(rb"<file>\s*<size>(\d+)</size>\s*<data>")
TOC_RE = re.compile(rb"<toc>(.*?)</toc>", re.S)
TOC_ENTRY_RE = re.compile(rb"<input><name>(.*?)</name><addr>(\d+)</addr></input>")
CHAPTER_NAME_RE = re.compile(r"^([A-Za-z0-9]{2,5})/(\d{3})\.html$")
MARK_RE = re.compile(r'<span class="(cn|vn)">(\d+)</span>')
STRONG_RE = re.compile(r'<a\b[^>]*href="h\.php\?c=STR&f=([HG])(\d+)"[^>]*>.*?</a>', re.S)
OTHER_ANCHOR_RE = re.compile(r"<a\b[^>]*>.*?</a>", re.S)
# Notes Darby : appel + contenu, retirés avec leur texte (pas de notes DL).
NOTE_RE = re.compile(r'<span class="note">.*?</span>', re.S)
NN_RE = re.compile(r'<span class="nn">.*?</span>', re.S)
BR_RE = re.compile(r"<br\s*/?>", re.I)
TAG_RE = re.compile(r"<[^>]+>")
WORD_RE = re.compile(r"[0-9A-Za-zÀ-ÖØ-öø-ÿŒœ’'\-]+$")
LEAD_STAR_RE = re.compile(r"^[\*\s\u00a0\u2009\u202f]+")

ASSETS_LSGS = Path(__file__).resolve().parent.parent / "bible_app" / "assets" / "bible" / "lsgs"


def app_meta() -> dict[str, dict]:
    meta: dict[str, dict] = {}
    for path in sorted(ASSETS_LSGS.glob("*.json")):
        head = path.read_text(encoding="utf-8")[:600]
        osis = re.search(r'"osis_id":\s*"(.*?)"', head).group(1)
        meta[osis] = {
            "file": path.name,
            "book": re.search(r'"book":\s*"(.*?)"', head).group(1),
            "abbreviation": re.search(r'"abbreviation":\s*"(.*?)"', head).group(1),
            "bym_index": int(re.search(r'"bym_index":\s*(\d+)', head).group(1)),
            "osis_id": osis,
        }
    if len(meta) != 66:
        raise ValueError(f"66 livres attendus dans {ASSETS_LSGS}, {len(meta)} lus")
    return meta


def clean(fragment: str) -> str:
    fragment = OTHER_ANCHOR_RE.sub("", fragment)
    fragment = TAG_RE.sub("", fragment)
    return html_lib.unescape(fragment).replace("\xa0", " ").replace("\u202f", " ")


def verse_tokens(content: str, stats: Counter) -> list[tuple[str, str | None]]:
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


def trim(tokens):
    out = list(tokens)
    while out and out[0][1] is None and not out[0][0]:
        out.pop(0)
    while out and out[-1][1] is None and not out[-1][0]:
        out.pop()
    if out and out[0][1] is None:
        out[0] = (out[0][0].lstrip(), None)
    if out and out[-1][1] is None:
        out[-1] = (out[-1][0].rstrip(), None)
    if out and out[0][1] is None and not out[0][0]:
        out.pop(0)
    if out and out[-1][1] is None and not out[-1][0]:
        out.pop()
    return out


def join_tokens(tokens, include_strong=True) -> str:
    """Miroir Python de LsgsRepository.joinTokens(includeStrong:true)."""
    buf = ""
    for text, strong in tokens:
        brut = text.rstrip() if text else ""
        if not brut:
            if not include_strong or not strong:
                continue
            piece = strong
            seul = True
        else:
            piece = brut
            seul = False
        needs_space = False
        if buf:
            prev = buf
            if (not prev.endswith(" ") and not prev.endswith("\n")
                    and not prev.endswith("\t")
                    and not piece.startswith(" ") and not piece.startswith(".")
                    and not piece.startswith(",") and not piece.startswith(";")
                    and not piece.startswith(":") and not piece.startswith("!")
                    and not piece.startswith("?") and not piece.startswith(")")
                    and not piece.startswith('"') and not piece.startswith("«")
                    and not piece.startswith("(")):
                needs_space = True
        if needs_space:
            buf += " "
        if include_strong and not seul and strong:
            buf += f"{piece} {strong}"
        else:
            buf += piece
    # Normalise les blancs (insécables déjà convertis) sans toucher au texte.
    buf = re.sub(r"[ \t\u00a0\u2009\u202f]+", " ", buf).strip()
    # Astérisque Darby de tête (« *Et Joseph ») : marqueur, pas texte.
    buf = LEAD_STAR_RE.sub("", buf)
    return buf


def merge_adjacent(marks, data, ref, stats):
    kept = [marks[0]]
    for prev, cur in zip(marks, marks[1:]):
        if data[prev[2].end():cur[2].start()].strip():
            kept.append(cur)
            continue
        stats["marqueurs_colles"] += 1
    return kept


def renumber(ref, verses, stats):
    nums = [n for n, _ in verses]
    count = len(verses)
    if not count or nums == list(range(1, count + 1)):
        return verses
    if nums[-1] != count:
        return verses
    stats["chapitres_renumeros"] += 1
    return [(i + 1, tokens) for i, (_, tokens) in enumerate(verses)]


def parse_chapter(data: str, chapter: int, ref: str, stats: Counter):
    # Notes et appels hors texte avant tout (sinon leur contenu pollue).
    data = NOTE_RE.sub(" ", data)
    data = NN_RE.sub("", data)
    data = BR_RE.sub(" ", data)
    marks = [(m.group(1), int(m.group(2)), m) for m in MARK_RE.finditer(data)]
    if not marks:
        stats["chapitres_sans_marqueur"] += 1
        return []
    marks = merge_adjacent(marks, data, ref, stats)
    verses = []
    for i, (kind, number, m) in enumerate(marks):
        end = marks[i + 1][2].start() if i + 1 < len(marks) else len(data)
        content = data[m.end():end]
        tokens = trim(verse_tokens(content, stats))
        if not tokens:
            stats["versets_vides"] += 1
        if i == 0:
            # DBS : le premier marqueur est toujours <span class="cn">1</span>
            # (1189/1189 constaté) — il ouvre le verset 1, il ne porte pas le
            # n° de chapitre comme en LGS/LSS. Pas de contrôle au TOC ici.
            verse_no = 1
        else:
            verse_no = number
        verses.append((verse_no, tokens))
    return renumber(ref, verses, stats)


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if not SOURCE.exists():
        print(f"Source introuvable : {SOURCE}")
        return 1
    meta = app_meta()
    raw = SOURCE.read_bytes()
    blocks = []
    for m in FILE_RE.finditer(raw):
        start = m.end()
        size = int(m.group(1))
        end = raw.find(b"</data>", start)
        while end != -1 and end - start != size:
            end = raw.find(b"</data>", end + 1)
        if end == -1:
            print(f"bloc @{m.start()} : pas de </data> à <size>={size}")
            return 1
        blocks.append((m.start(), raw[start:end]))
    toc_m = TOC_RE.search(raw)
    entries = [(n.decode("utf-8"), int(a)) for n, a in TOC_ENTRY_RE.findall(toc_m.group(1))]
    assert len(entries) == len(blocks), f"{len(entries)} TOC != {len(blocks)} blocs"
    for (_, addr), (off, _) in zip(entries, blocks):
        assert addr == off, "TOC addr != offset"

    stats: Counter = Counter()
    chapters: OrderedDict[tuple[str, int], list] = OrderedDict()
    skipped: list[str] = []
    for (_, data), (name, _) in zip(blocks, entries):
        m = CHAPTER_NAME_RE.match(name)
        if not m:
            skipped.append(name)
            continue
        toc_code, toc_chapter = m.group(1), int(m.group(2))
        if toc_code not in TOC_TO_OSIS:
            print(f"code livre inconnu : {name}")
            return 1
        osis = TOC_TO_OSIS[toc_code]
        stats["blocs"] += 1
        text = data.decode("utf-8", errors="replace")
        verses = parse_chapter(text, toc_chapter, name, stats)
        if not verses:
            print(f"{name} : aucun marqueur")
            return 1
        nums = [n for n, _ in verses]
        if nums != list(range(1, len(nums) + 1)):
            stats["chapitres_numerotation"] += 1
            if stats["chapitres_numerotation"] <= 10:
                print(f"  numerotation {name} : {nums[:12]}… ({len(nums)} v.)")
        chapters[(osis, toc_chapter)] = verses

    by_book: OrderedDict[str, list] = OrderedDict()
    for (osis, chapter), verses in chapters.items():
        by_book.setdefault(osis, []).append((chapter, verses))

    SORTIE.mkdir(parents=True, exist_ok=True)
    for old in SORTIE.glob("*.json"):
        old.unlink()

    osis_to_toc = {v: k for k, v in TOC_TO_OSIS.items()}
    total_versets = 0
    total_codes = 0
    codes = Counter()
    for osis, items in by_book.items():
        toc_code = osis_to_toc[osis]
        standard = STANDARD_NUMBER[toc_code]
        info = meta[osis]
        items.sort(key=lambda kv: kv[0])
        ch_list = []
        for chapter, verses in items:
            v_list = []
            for number, tokens in verses:
                txt = join_tokens(tokens, include_strong=True)
                if not txt:
                    stats["texte_vide_apres_jointure"] += 1
                for _, s in tokens:
                    if s:
                        codes.update([s])
                        total_codes += 1
                total_versets += 1
                v_list.append({
                    "chapter": str(chapter),
                    "verse": str(number),
                    "name": f"{info['book']} {chapter}:{number}",
                    "text": txt,
                })
            ch_list.append({
                "chapter": chapter,
                "name": f"{info['book']} {chapter}",
                "verses": v_list,
            })
        doc = OrderedDict([
            ("translation", "Darby + Strong"),
            ("abbreviation", "DBS"),
            ("lang", "fr"),
            ("language", "français"),
            ("direction", "LTR"),
            ("encoding", "UTF-8"),
            ("nr", standard),
            ("name", info["book"]),
            ("chapters", ch_list),
        ])
        (SORTIE / f"{standard}.json").write_text(
            json.dumps(doc, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )

    # Contrôles résidus HTML
    residus = Counter()
    for f in SORTIE.glob("*.json"):
        t = f.read_text(encoding="utf-8")
        if "<" in t and re.search(r"</?(p|span|a|lg|l|i|br|h1)[ >]", t):
            residus["html"] += 1
        if "glossaire" in t or "h.php" in t:
            residus["ancre"] += 1

    print(f"DBS : {len(chapters)} chapitres, {len(by_book)} livres, "
          f"{total_versets} versets, {total_codes} codes Strong, "
          f"{len(codes)} distincts")
    print(f"  ecarte : {len(skipped)} blocs ({', '.join(sorted(set(s.split('/')[0] for s in skipped)))} + index)")
    print(f"  forts sans mot : {stats.get('strong_sans_mot',0)}, "
          f"marqueurs colles : {stats.get('marqueurs_colles',0)}, "
          f"renumerotes : {stats.get('chapitres_renumeros',0)}, "
          f"numerotation HS : {stats.get('chapitres_numerotation',0)}, "
          f"cn hors TOC : {stats.get('cn_hors_toc',0)}, "
          f"vides : {stats.get('versets_vides',0)}")
    print(f"  residus HTML : {dict(residus) or 'aucun'}")
    poids = sum(f.stat().st_size for f in SORTIE.glob("*.json"))
    import gzip
    gz = sum(len(gzip.compress(f.read_bytes(), 9)) for f in SORTIE.glob("*.json"))
    print(f"  sortie : {SORTIE} — {poids/1048576:.1f} Mo clair, {gz/1048576:.1f} Mo gzip")
    plus = max(SORTIE.glob("*.json"), key=lambda f: f.stat().st_size)
    print(f"  plus gros : {plus.name} {plus.stat().st_size/1048576:.2f} Mo")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
