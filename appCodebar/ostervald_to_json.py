#!/usr/bin/env python3
"""Convertit les fichiers USFM eBible.org en JSON getbible (un fichier par livre).

Fonctionne pour tout module USFM d'eBible.org : Ostervald (`fra_fob`),
néo-Crampon Libre (`francl`), … Source : https://ebible.org/Scriptures/<id>_usfm.zip

Le schéma de sortie est celui servi par getbible.net pour un livre :
    {translation, abbreviation, lang, nr, name,
     chapters: [{chapter, name, verses: [{chapter, verse, name, text}]}]}

Le texte est nu : les notes de bas de page, renvois et balises Strong USFM
(\\w mot|strong="H1234"\\w*) sont retirés, conformément au format « texte nu »
choisi pour les versions téléchargeables.

Les 66 livres canoniques sont retenus (ordre standard 1=Genèse … 66=Apocalypse) ;
les deutérocanoniques éventuels (Tobie, Judith, Sagesse, Siracide, Baruch,
1-2 Maccabées) sont ignorés.

Usage :
    python ostervald_to_json.py [usfm_dir] [output_dir] [translation] [abbreviation]

Par défaut : lit ./ostervald_usfm/, écrit dans ./ostervald_json,
translation="Ostervald", abbreviation="OST".
"""

import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

# Ordre standard des 66 livres (codes USFM `\id`), Genèse → Apocalypse. C'est
# l'ordre des fichiers eBible.org (39 livres de l'AT puis 27 du NT, sans les
# deutérocanoniques que l'app ne connaît pas).
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

# Marqueurs USFM en tête de ligne qui ne portent PAS le texte du verset :
# titres de section, renvois, titres de psaumes, labels de chapitre, etc. On
# retire toute la ligne — les ajouter au verset courant est exactement ce qui
# faisait fuir « Création de l'homme et de la femme » dans Genèse 2:3.
HEADING = re.compile(r"^\\(?:"
                     r"id|ide|usfm|h|toc[123]|mt[1234]?|ms[1234]?|mr|s[1234]?|"
                     r"d|r|sr|qa|sp|pb|b|cl|cp|fp|ip|rem"
                     r")\b")

# Marqueurs de paragraphe / poésie : leur texte EST le contenu du verset
# (`\p`, `\q1`, `\nb`…), on garde ce qui suit le marqueur.
CONTENT = re.compile(r"^\\(?:p[io]?|pc|m[io]?|nb|q[1234]?|qm[123]?|"
                     r"qr|qc|lit[1234]?|cls)\s+")

# Marqueurs inline appariés (sans attribut) : \add … \add*, \nd … \nd*, etc.
# On garde le contenu, on retire les bornes.
PAIRED_INLINE = re.compile(
    r"\\(add|nd|em|bd|bdit|it|sc|tl|bk|k|wj|lik|pn|qt|qs)\b"
    r"(.*?)\\\1\*",
    flags=re.S,
)


def strip_note_blocks(text: str) -> str:
    """Retire les blocs `\\f…\\f*`, `\\fe…\\fe*` et `\\x…\\x*` (notes, notes de
    fin, renvois), en gérant un renvoi imbriqué dans une note. Les marqueurs
    internes (`\\fr`, `\\ft`, `\\xo`…) commencent par les mêmes lettres mais
    forment un marqueur plus long, donc seuls `\\f`, `\\fe`, `\\x` suivis d'un
    espace / `+` (ouverture) ou d'une `*` (fermeture) sont traités."""
    out = []
    stack = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "\\":
            m = re.match(r"\\([A-Za-z0-9]+)(\*)?", text[i:])
            if m:
                marker, star = m.group(1), m.group(2)
                end = i + len(m.group(0))
                if star is None and marker in ("f", "fe", "x"):
                    after = text[end] if end < n else ""
                    if after in (" ", "+"):
                        stack.append(marker)
                        i = end
                        continue
                if star is not None and marker in ("f", "fe", "x"):
                    if stack and stack[-1] == marker:
                        stack.pop()
                        i = end
                        continue
        if not stack:
            out.append(text[i])
        i += 1
    return "".join(out)


def clean_verse(raw: str) -> str:
    """Du texte brut USFM au texte nu d'un verset."""
    text = strip_note_blocks(raw)
    # `\w mot|strong="H1234"\w*` → « mot » (avant le premier `|`), les attributs
    # Strong et les bornes disparaissent. Certains modules (néo-Crampon) marquent
    # le nom divin avec `\+w` au lieu de `\w` : le `+` optionnel couvre les deux.
    text = re.sub(r"\\\+?w\s+([^|\\]*?)(?:\|[^\\]*?)?\\\+?w\*", r"\1", text)
    # Paires inline sans attribut : `\add … \add*` → contenu.
    text = PAIRED_INLINE.sub(r"\2", text)
    # Tout marqueur résiduel (isolé) : on retire `\marqueur` / `\marqueur*`
    # (et la variante `\+marqueur`).
    text = re.sub(r"\\\+?[a-zA-Z0-9]+\*?", "", text)
    # Blancs et ponctuation : un seul espace, pas d'espace avant la ponctuation.
    text = re.sub(r"[ \t\u00a0]+", " ", text)
    text = re.sub(r"\s+([,.;:!?»])", r"\1", text)
    text = re.sub(r"([«])\s+", r"\1", text)
    return text.strip()


def parse_usfm(path: Path):
    """Renvoie (standard_number, book_name, chapters) où chapters est un
    OrderedDict {n: {'chapter': n, 'verses': [{'verse': v, 'text': str}]}}."""
    lines = path.read_text(encoding="utf-8-sig").splitlines()

    book_code = None
    book_name = None
    chapters = OrderedDict()
    current_chapter = None
    current_verse = None
    current_buf = []

    def flush():
        nonlocal current_buf
        if current_chapter is not None and current_verse is not None:
            text = clean_verse(" ".join(current_buf))
            chapters[current_chapter]["verses"].append(
                {"verse": current_verse, "text": text}
            )
        current_buf = []

    for line in lines:
        line = line.rstrip()
        if not line:
            continue

        # `\id GEN` → code du livre.
        m = re.match(r"\\id\s+(\S+)", line)
        if m:
            book_code = m.group(1).upper()
            continue
        m = re.match(r"\\toc2\s+(.*)", line)
        if m and book_name is None:
            book_name = m.group(1).strip()
            continue

        # `\c 1` → nouveau chapitre.
        m = re.match(r"\\c\s+(\d+)", line)
        if m:
            flush()
            current_chapter = int(m.group(1))
            current_verse = None
            chapters[current_chapter] = {"chapter": current_chapter, "verses": []}
            continue

        # `\v 1` ou `\v1` → nouveau verset.
        m = re.match(r"\\v\s+(\d+)(.*)$", line) or re.match(r"\\v(\d+)(.*)$", line)
        if m:
            flush()
            current_verse = int(m.group(1))
            current_buf = [m.group(2).strip()] if m.group(2).strip() else []
            continue

        # Titres, renvois, métadonnées : la ligne entière est ignorée.
        if HEADING.match(line):
            continue

        # Paragraphe / poésie en tête de ligne : on garde le texte qui suit.
        m = CONTENT.match(line)
        if m:
            current_buf.append(line[m.end():].strip())
            continue

        # Continuation du verset courant (texte brut).
        current_buf.append(line)

    flush()
    return book_code, book_name or "", chapters


def remap_deuterocanonical(book_number, chapters):
    """Aligne la numérotation catholique sur le canon 66 livres de l'app, en
    retirant les ajouts deutérocanoniques entrelacés dans Esther et Daniel.

    Ne fait rien si le schéma catholique n'est pas présent (idempotent) : un
    module protestant (Ostervald) garde ses 10 chapitres d'Esther et ses
    30 versets de Daniel 3 intacts."""
    # Esther : les additions grecques donnent 16 chapitres (1-10 + 11-16) et
    # prolongent le chapitre 10 de 3 à 13 versets.
    if book_number == 17:
        if any(ch["chapter"] > 10 for ch in chapters):
            kept = []
            for ch in chapters:
                if ch["chapter"] > 10:
                    continue
                if ch["chapter"] == 10:
                    ch["verses"] = [
                        v for v in ch["verses"] if int(v["verse"]) <= 3
                    ]
                kept.append(ch)
            return kept
    # Daniel : le cantique des trois jeunes gens (catholique 3:24-90) et les
    # chapitres 13-14 (Suzanne, Bel et le Dragon) sont retirés ; 91-100 → 24-33.
    if book_number == 27:
        ch3 = next((c for c in chapters if c["chapter"] == 3), None)
        if ch3 is not None and any(int(v["verse"]) >= 91 for v in ch3["verses"]):
            kept = []
            for ch in chapters:
                if ch["chapter"] > 12:
                    continue
                if ch["chapter"] == 3:
                    remapped = []
                    for v in ch["verses"]:
                        n = int(v["verse"])
                        if 24 <= n <= 90:
                            continue
                        if n >= 91:
                            v["verse"] = n - 67
                        remapped.append(v)
                    ch["verses"] = remapped
                kept.append(ch)
            return kept
    return chapters


def convert(
    usfm_dir: Path,
    output_dir: Path,
    translation: str = "Ostervald",
    abbreviation: str = "OST",
):
    output_dir.mkdir(parents=True, exist_ok=True)

    files = sorted(usfm_dir.glob("*.usfm"))
    if len(files) != 66:
        print(f"ℹ️ {len(files)} fichiers USFM trouvés — les 66 canoniques seront "
              f"retenus, les deutérocanoniques ignorés.")

    stats = {"books": 0, "chapters": 0, "verses": 0}
    residue = {"backslash": 0, "pipe": 0, "note": 0}

    for path in files:
        book_code, book_name, chapters = parse_usfm(path)
        if book_code is None or book_code not in STANDARD_NUMBER:
            print(f"❌ Livre inconnu ignoré : {path.name} (\\id {book_code})")
            continue
        number = STANDARD_NUMBER[book_code]
        chapters_list = remap_deuterocanonical(number, list(chapters.values()))

        book = OrderedDict([
            ("translation", translation),
            ("abbreviation", abbreviation),
            ("lang", "fr"),
            ("language", "français"),
            ("direction", "LTR"),
            ("encoding", "UTF-8"),
            ("nr", number),
            ("name", book_name),
            ("chapters", chapters_list),
        ])
        for ch in chapters_list:
            n = ch["chapter"]
            ch["name"] = f"{book_name} {n}"
            for v in ch["verses"]:
                v["chapter"] = str(n)
                v["name"] = f"{book_name} {n}:{v['verse']}"
                v["verse"] = str(v["verse"])

        out_path = output_dir / f"{number}.json"
        out_path.write_text(
            json.dumps(book, ensure_ascii=False, indent=2), encoding="utf-8"
        )

        # Comptage des résidus éventuels de balisage.
        for ch in chapters_list:
            for v in ch["verses"]:
                t = v["text"]
                if "\\" in t:
                    residue["backslash"] += 1
                if "|strong" in t or "|" in t:
                    residue["pipe"] += 1
                if re.search(r"\\[fx]", t):
                    residue["note"] += 1

        stats["books"] += 1
        stats["chapters"] += len(chapters_list)
        stats["verses"] += sum(len(ch["verses"]) for ch in chapters_list)
        print(f"✅ {number:02d}.json — {book_code} ({book_name}) : "
              f"{len(chapters_list)} ch., "
              f"{sum(len(ch['verses']) for ch in chapters_list)} v.")

    print(f"\n📊 Total : {stats['books']} livres, {stats['chapters']} chapitres, "
          f"{stats['verses']} versets.")
    if any(residue.values()):
        print(f"⚠️ Résidus de balisage : {residue}")
    else:
        print("✅ Aucun résidu de balisage dans les textes.")


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    usfm_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("./ostervald_usfm")
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("./ostervald_json")
    translation = sys.argv[3] if len(sys.argv) > 3 else "Ostervald"
    abbreviation = sys.argv[4] if len(sys.argv) > 4 else "OST"
    if not usfm_dir.exists():
        print(f"❌ Dossier USFM introuvable : {usfm_dir}")
        sys.exit(1)
    print(f"📖 Conversion : {usfm_dir} → {output_dir} "
          f"({translation}, {abbreviation})")
    convert(usfm_dir, output_dir, translation, abbreviation)
    print("\n🎉 Terminé !")
