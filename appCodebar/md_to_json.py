"""Convertit les livres de la Bible (Markdown) en fichiers JSON.

Usage :
    python md_to_json.py [dossier_md] [dossier_sortie]

Par défaut : lit ./bym_md et écrit dans ./bym_json

Format de sortie (un JSON par livre) :
{
  "book": "Bereshit (Genèse)",
  "abbreviation": "Ge.",
  "metadata": { "signification": ..., "auteur": ..., "theme": ..., "date": ... },
  "introduction": "...",
  "chapters": [
    {
      "chapter": 1,
      "verses": [
        { "verse": "1:1", "section": "Titre de section", "text": "...", "notes": ["..."] }
      ]
    }
  ]
}
"""

import json
import re
import sys
from pathlib import Path

# --- Nettoyage du texte -----------------------------------------------------

RE_NOTE = re.compile(r"<!--(.*?)-->", re.DOTALL)
RE_W_TAG = re.compile(r"<w\b[^>]*>(.*?)</w>", re.DOTALL)  # garde le texte, retire la balise
RE_TAG = re.compile(r"</?[a-zA-Z][^>]*>")  # toute autre balise résiduelle
RE_SPACES = re.compile(r"[ \t]{2,}")


RE_WORD = re.compile(r"[\w'’-]+")

PLACEHOLDER = "\x00"  # marque l'emplacement des notes pendant le nettoyage


def extract_notes(text: str) -> tuple[str, str, list[dict]]:
    """Nettoie les balises et retire les commentaires <!--...-->.

    Retourne (texte propre, texte avec notes inline entre crochets, notes).
    Chaque note est rattachée au mot qui la précède : {word, position, note},
    où position est l'index du début du mot dans le texte propre.
    """
    # Retirer d'abord les balises pour que le mot précédant la note soit propre
    text = RE_W_TAG.sub(r"\1", text)
    text = RE_TAG.sub("", text)

    raw_notes = [m.group(1).strip() for m in RE_NOTE.finditer(text)]
    text = RE_NOTE.sub(PLACEHOLDER, text)
    text = RE_SPACES.sub(" ", text).strip()

    segments = text.split(PLACEHOLDER)
    clean = "".join(segments)

    notes = []
    with_notes_parts = [segments[0]]
    pos = 0
    for k, note in enumerate(raw_notes):
        pos += len(segments[k])  # index d'insertion de la note dans le texte propre
        matches = list(RE_WORD.finditer(clean, 0, pos))
        if matches:
            word = matches[-1].group(0)
            position = matches[-1].start()
        else:
            word, position = "", pos
        notes.append({"word": word, "position": position, "note": note})
        with_notes_parts.append("[" + note + "]")
        with_notes_parts.append(segments[k + 1])

    return clean, "".join(with_notes_parts), notes


# --- Parsing d'un livre -----------------------------------------------------

RE_TITLE = re.compile(r"^#\s+(.*)$")
RE_CHAPTER = re.compile(r"^##\s+Chapitre\s+(\d+)")
RE_SECTION = re.compile(r"^###\s+(.*)$")
RE_VERSE = re.compile(r"^(\d+):(\d+)\t(.*)$")

# Clés des métadonnées du bloc <h>...</h>
META_KEYS = {
    "signification": "signification",
    "auteur": "auteur",
    "auteurs": "auteur",
    "thème": "theme",
    "theme": "theme",
    "date de rédaction": "date",
}


def parse_title(line: str) -> tuple[str, str]:
    """'# Bereshit (Genèse) (Ge.)' -> ('Bereshit (Genèse)', 'Ge.')"""
    title = RE_TITLE.match(line).group(1).strip()
    m = re.match(r"^(.*)\s+\(([^()]*)\)\s*$", title)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return title, ""


def parse_metadata(block: str) -> dict:
    meta = {}
    for line in block.splitlines():
        line = line.strip()
        if not line or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = META_KEYS.get(key.strip().lower())
        if key:
            meta[key] = value.strip()
    return meta


def parse_book(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8")

    # Titre
    first_line = raw.lstrip().splitlines()[0]
    book_name, abbreviation = parse_title(first_line)

    # Bloc de métadonnées <h>...</h>
    metadata = {}
    m = re.search(r"<h>(.*?)</h>", raw, re.DOTALL)
    if m:
        metadata = parse_metadata(m.group(1))
        raw = raw.replace(m.group(0), "", 1)

    lines = raw.splitlines()

    intro_parts: list[str] = []
    chapters: list[dict] = []
    current_chapter: dict | None = None
    current_section: str | None = None
    current_verse: dict | None = None

    def finish_verse():
        nonlocal current_verse
        if current_verse is not None:
            current_chapter["verses"].append(current_verse)
            current_verse = None

    for line in lines:
        if RE_TITLE.match(line) and not line.startswith("##"):
            continue  # ligne de titre déjà traitée

        m = RE_CHAPTER.match(line)
        if m:
            finish_verse()
            current_chapter = {"chapter": int(m.group(1)), "verses": []}
            chapters.append(current_chapter)
            current_section = None
            continue

        m = RE_SECTION.match(line)
        if m:
            finish_verse()
            section, _, _ = extract_notes(m.group(1))  # les notes des titres sont ignorées
            current_section = section
            continue

        m = RE_VERSE.match(line)
        if m and current_chapter is not None:
            finish_verse()
            current_verse = {
                "verse": f"{m.group(1)}:{m.group(2)}",
                "raw": m.group(3),
            }
            if current_section:
                current_verse["section"] = current_section
            current_section = None  # la section n'est attachée qu'au premier verset qui la suit
            continue

        # Ligne de continuation d'un verset (rare) ou paragraphe d'introduction
        if current_verse is not None and line.strip():
            current_verse["raw"] += " " + line.strip()
        elif current_chapter is None and line.strip():
            text, _, _ = extract_notes(line.strip())
            if text:
                intro_parts.append(text)

    finish_verse()

    # Nettoyage final des versets : extraction des notes et des balises
    for chapter in chapters:
        for verse in chapter["verses"]:
            text, text_with_notes, notes = extract_notes(verse.pop("raw"))
            verse["text"] = text
            if notes:
                verse["textWithNotes"] = text_with_notes
                verse["notes"] = notes

    return {
        "book": book_name,
        "abbreviation": abbreviation,
        "metadata": metadata,
        "introduction": "\n\n".join(intro_parts),
        "chapters": chapters,
    }


# --- Programme principal ----------------------------------------------------

def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "bym_md"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).parent / "bym_json"

    files = sorted(src.glob("*.md"))
    if not files:
        sys.exit(f"Aucun fichier .md trouvé dans {src}")

    dst.mkdir(parents=True, exist_ok=True)

    total_verses = 0
    for path in files:
        book = parse_book(path)
        out_path = dst / (path.stem + ".json")
        out_path.write_text(
            json.dumps(book, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        n_verses = sum(len(c["verses"]) for c in book["chapters"])
        total_verses += n_verses
        print(f"{path.name:30} -> {out_path.name:30} {len(book['chapters']):3} chapitres, {n_verses:5} versets")

    print(f"\n{len(files)} livres convertis, {total_verses} versets au total -> {dst}")


if __name__ == "__main__":
    main()
