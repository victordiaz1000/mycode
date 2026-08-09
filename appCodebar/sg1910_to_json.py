#!/usr/bin/env python3
"""Convertit le CSV Segond 1910 + Strong (concordance.bible) en JSON BYM.

Usage :
    python sg1910_to_json.py [csv_path] [output_dir]

Par défaut : lit ../Sg1910-csv/Sg1910.csv et écrit dans ./sg1910_json
"""

import csv
import json
import re
import sys
from pathlib import Path
from collections import OrderedDict

OSIS_TO_BYM = {
    "Gen":    ("Genèse",          "Ge.",  1),
    "Exod":   ("Exode",           "Ex.",  2),
    "Lev":    ("Lévitique",       "Lé.",  3),
    "Num":    ("Nombres",         "No.",  4),
    "Deut":   ("Deutéronome",     "De.",  5),
    "Josh":   ("Josué",           "Jos.",  6),
    "Judg":   ("Juges",           "Jug.",  7),
    "1Sam":   ("1 Samuel",        "1S.",   8),
    "2Sam":   ("2 Samuel",        "2S.",   9),
    "1Kgs":   ("1 Rois",          "1R.",  10),
    "2Kgs":   ("2 Rois",          "2R.",  11),
    "Isa":    ("Ésaïe",           "És.",  12),
    "Jer":    ("Jérémie",         "Jé.",  13),
    "Ezek":   ("Ézéchiel",        "Éz.",  14),
    "Hos":    ("Osée",            "Os.",  15),
    "Joel":   ("Joël",            "Joë.", 16),
    "Amos":   ("Amos",            "Am.",  17),
    "Obad":   ("Abdias",          "Ab.",  18),
    "Jonah":  ("Jonas",           "Jon.", 19),
    "Mic":    ("Michée",          "Mi.",  20),
    "Nah":    ("Nahum",           "Na.",  21),
    "Hab":    ("Habakuk",         "Ha.",  22),
    "Zeph":   ("Sophonie",        "So.",  23),
    "Hag":    ("Aggée",           "Ag.",  24),
    "Zech":   ("Zacharie",        "Za.",  25),
    "Mal":    ("Malachie",        "Ma.",  26),
    "Ps":     ("Psaumes",         "Ps.",  27),
    "Prov":   ("Proverbes",       "Pr.",  28),
    "Job":    ("Job",             "Jb.",  29),
    "Song":   ("Cantique",        "Ca.",  30),
    "Ruth":   ("Ruth",            "Ru.",  31),
    "Lam":    ("Lamentations",    "La.",  32),
    "Eccl":   ("Ecclésiaste",     "Ec.",  33),
    "Esth":   ("Esther",          "Est.", 34),
    "Dan":    ("Daniel",          "Da.",  35),
    "Ezra":   ("Esdras",          "Esd.", 36),
    "Neh":    ("Néhémie",         "Né.",  37),
    "1Chr":   ("1 Chroniques",    "1Ch.", 38),
    "2Chr":   ("2 Chroniques",    "2Ch.", 39),
    "Matt":   ("Matthieu",        "Mt.",  40),
    "Mark":   ("Marc",            "Mc.",  41),
    "Luke":   ("Luc",             "Lu.",  42),
    "John":   ("Jean",            "Jn.",  43),
    "Acts":   ("Actes",           "Ac.",  44),
    "Jas":    ("Jacques",         "Ja.",  45),
    "Gal":    ("Galates",         "Ga.",  46),
    "1Thess": ("1 Thessaloniciens", "1Th.", 47),
    "2Thess": ("2 Thessaloniciens", "2Th.", 48),
    "1Cor":   ("1 Corinthiens",   "1Co.", 49),
    "2Cor":   ("2 Corinthiens",   "2Co.", 50),
    "Rom":    ("Romains",         "Ro.",  51),
    "Eph":    ("Éphésiens",       "Ép.",  52),
    "Phil":   ("Philippiens",     "Ph.",  53),
    "Col":    ("Colossiens",      "Co.",  54),
    "Phlm":   ("Philémon",        "Phm.", 55),
    "1Tim":   ("1 Timothée",      "1Ti.", 56),
    "Titus":  ("Tite",            "Tit.", 57),
    "1Pet":   ("1 Pierre",        "1Pi.", 58),
    "2Pet":   ("2 Pierre",        "2Pi.", 59),
    "2Tim":   ("2 Timothée",      "2Ti.", 60),
    "Jude":   ("Jude",            "Jud.", 61),
    "Heb":    ("Hébreux",         "Hé.",  62),
    "1John":  ("1 Jean",          "1Jn.", 63),
    "2John":  ("2 Jean",          "2Jn.", 64),
    "3John":  ("3 Jean",          "3Jn.", 65),
    "Rev":    ("Apocalypse",      "Ap.",  66),
}


def parse_tokens(text: str) -> list[dict]:
    tokens = []
    i = 0
    current_text = ""
    while i < len(text):
        if text[i:i+3] == '<w ':
            if current_text:
                tokens.append({"text": current_text, "strong": None})
                current_text = ""
            m = re.match(r'<w strong="([^"]+)">', text[i:])
            if m:
                strong_code = m.group(1)
                i += len(m.group(0))
                end = text.index('</w>', i)
                word_text = text[i:end]
                i = end + 4
                if word_text:
                    tokens.append({"text": word_text, "strong": strong_code})
            else:
                current_text += text[i]
                i += 1
        else:
            current_text += text[i]
            i += 1
    if current_text:
        tokens.append({"text": current_text, "strong": None})
    return tokens


def convert_csv_to_json(csv_path: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    books: dict[str, dict] = {}
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            book_id = row['book_id'].strip()
            chapter = int(row['num_chapter'])
            verse = int(row['num_verse'])
            text = row['text']
            if book_id not in books:
                book_info = OSIS_TO_BYM.get(book_id)
                if book_info is None:
                    print(f"⚠️ Livre inconnu ignoré : {book_id}")
                    continue
                books[book_id] = {
                    "book": book_info[0],
                    "abbreviation": book_info[1],
                    "bym_index": book_info[2],
                    "osis_id": book_id,
                    "chapters": OrderedDict(),
                }
            book = books[book_id]
            if chapter not in book["chapters"]:
                book["chapters"][chapter] = {"chapter": chapter, "verses": []}
            tokens = parse_tokens(text)
            book["chapters"][chapter]["verses"].append({
                "verse": verse,
                "tokens": tokens,
            })

    stats = {"total_books": 0, "total_chapters": 0, "total_verses": 0, "total_strong": 0}
    for book_id, book_data in sorted(books.items(), key=lambda x: x[1]["bym_index"]):
        chapters_list = list(book_data["chapters"].values())
        strong_count = 0
        for ch in chapters_list:
            for v in ch["verses"]:
                strong_count += sum(1 for t in v["tokens"] if t["strong"])
        output = {
            "book": book_data["book"],
            "abbreviation": book_data["abbreviation"],
            "bym_index": book_data["bym_index"],
            "osis_id": book_data["osis_id"],
            "chapters": chapters_list,
        }
        filename = f"{book_data['bym_index']:02d}-{book_data['book'].replace(' ', '')}.json"
        out_path = output_dir / filename
        with open(out_path, 'w', encoding='utf-8') as f:
            json.dump(output, f, ensure_ascii=False, indent=2)
        stats["total_books"] += 1
        stats["total_chapters"] += len(chapters_list)
        stats["total_verses"] += sum(len(ch["verses"]) for ch in chapters_list)
        stats["total_strong"] += strong_count
        print(f"✅ {filename} — {len(chapters_list)} ch., {sum(len(ch['verses']) for ch in chapters_list)} v., {strong_count} Strong")

    print(f"\n📊 Total : {stats['total_books']} livres, {stats['total_chapters']} chapitres, {stats['total_verses']} versets, {stats['total_strong']} mots Strong")


if __name__ == "__main__":
    csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("../Sg1910-csv/Sg1910.csv")
    output_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("./sg1910_json")
    if not csv_path.exists():
        print(f"❌ Fichier CSV introuvable : {csv_path}")
        sys.exit(1)
    print(f"📖 Conversion : {csv_path} → {output_dir}")
    convert_csv_to_json(csv_path, output_dir)
    print("\n🎉 Terminé !")
