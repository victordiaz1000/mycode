#!/usr/bin/env python3
"""Export CrossWire/SWORD zLD Strong modules to a structured JSON lexicon.

The SWORD modules are zLD dictionaries: dict.idx/dict.dat contain the key and
(block, entry) pointer, while dict.zdx/dict.zdt contain zlib-compressed entry
blocks. This exporter uses only the Python standard library and does not shell
out to diatheke, so regeneration is deterministic and works on CI.

Usage:
  python appCodebar/sword_zld_to_json.py \
    appCodebar/sword_modules/extracted \
    bible_app/assets/lexicon/strong_fr.json
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path
from typing import Iterable

MODULES = (
    ("FreStrongsHebrew", "H", "hebrew", "frestrongshebrew"),
    ("FreStrongsGreek", "G", "greek", "frestrongsgreek"),
)


def clean(value: str) -> str:
    return re.sub(r"\s+", " ", value or "").strip()


def text(element: ET.Element | None) -> str:
    return clean("".join(element.itertext()) if element is not None else "")


class ZldReader:
    def __init__(self, directory: Path) -> None:
        self.index = (directory / "dict.idx").read_bytes()
        self.data = (directory / "dict.dat").read_bytes()
        self.block_index = (directory / "dict.zdx").read_bytes()
        self.blocks = (directory / "dict.zdt").read_bytes()
        self._cache: dict[int, bytes] = {}

    def _block(self, number: int) -> bytes:
        cached = self._cache.get(number)
        if cached is not None:
            return cached
        start, size = struct.unpack_from("<II", self.block_index, number * 8)
        value = zlib.decompress(self.blocks[start : start + size])
        self._cache[number] = value
        return value

    def entries(self) -> Iterable[tuple[str, str]]:
        for offset in range(0, len(self.index), 8):
            data_offset, data_size = struct.unpack_from("<II", self.index, offset)
            record = self.data[data_offset : data_offset + data_size]
            key_bytes = record.split(b"\r", 1)[0]
            if not key_bytes:
                continue
            key = key_bytes.decode("ascii", errors="strict").lstrip("0") or "0"
            block, entry = struct.unpack("<II", record[-8:])
            raw = self._block(block)
            count = struct.unpack_from("<I", raw, 0)[0]
            if entry >= count:
                raise ValueError(f"Entrée {key}: index {entry} hors bloc ({count})")
            entry_offset, entry_size = struct.unpack_from("<II", raw, 4 + entry * 8)
            value = raw[entry_offset : entry_offset + entry_size].decode("utf-8")
            yield key, value


def intro_text(definition: ET.Element) -> str:
    """The gloss line that introduces a definition's list, when it has one.

    The senses are the ``<item>``s; the text presenting them (« Abiel = Dieu
    est mon père », « Paul ou Paulus = petit ») sits between ``<def>`` and
    ``<list>`` — often in the tail of a ``<lb/>`` — so reading only the items
    drops it. This walks the elements before the list, tails included.
    """
    parts = [definition.text or ""]
    for child in definition:
        if child.tag == "list":
            break
        parts.append(text(child))
        parts.append(child.tail or "")
    return clean("".join(parts))


CODE = re.compile(r"^(\d+(?:[A-Za-z]\d*)*)\)")
# A code must carry a letter, so « (Nombres 22.5) » never counts as one.
NUMBERED = re.compile(r"\d+(?:[A-Za-z]+\d*)+\)")
# The source also leaves a numbering header bare — « 1b » on a line of its own.
BARE = re.compile(r"^(\d+(?:[A-Za-z]+\d*)+)$")


def split_numbered(value: str) -> list[str]:
    """Break an item that packs several numbered senses into one.

    The source does write « 1a2) être pur cérémoniellement 1a3) purifier… »
    inside a single ``<item>``; each code then opens a node of its own. The
    six codes glued to the previous word across the corpus (« …passions1a10) »)
    are all real, and the letter a code must carry keeps verse references such
    as « (Nombres 22.5) (Bosor dans 2 Pierre 2.15) » in one piece.
    """
    cuts = [match.start() for match in NUMBERED.finditer(value)]
    pieces: list[str] = []
    previous = 0
    for cut in cuts + [len(value)]:
        if cut > previous:
            piece = value[previous:cut].strip()
            if piece:
                pieces.append(piece)
        previous = cut
    return pieces


def own_text(element: ET.Element) -> str:
    """The text of an element, excluding the content of nested ``<list>``s.

    ``itertext()`` folds a parent item's children into its own line — « entre
    hommes 1a1) traité, alliance, ligue 1a2) constitution… » — and the exporter
    then lists those very children again right after. The children are walked
    as nodes of their own, so a parent keeps only what it says itself.
    """
    parts = [element.text or ""]
    for child in element:
        if child.tag == "list":
            parts.append(child.tail or "")
            continue
        parts.append(text(child))
        parts.append(child.tail or "")
    return clean("".join(parts))


def split_header(value: str) -> tuple[str, str] | None:
    """« (Qal) » → ``("Qal", "")``, « (Pual) être vu » → ``("Pual", "être vu")``.

    Parentheses nest (« (ce qui caractérise : … (maître des rêves)) »), so the
    closing one is found by depth rather than by position.
    """
    if not value.startswith("("):
        return None
    depth = 0
    for index, char in enumerate(value):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                # The remainder keeps its own spacing, so « (Qal), être en
                # excès » and « (Pual) être vu » come back byte for byte.
                return value[1:index].strip(), value[index + 1 :]
    return None


def walk_definition(
    definition: ET.Element,
    nodes: list[dict[str, object]],
    senses: list[str],
) -> None:
    """Append the outline nodes of one ``<def>``, in reading order.

    A node's ``level`` is the indent the fiche applies:

      * an item sits at the level of the list holding it;
      * a nested ``<list>`` sits one level below its parent item;
      * a header — « (Qal) », « (phrases) » — opens a group whose members sit
        one level below it;
      * a numbered item joins the deepest earlier code it extends, so the
        source's own ladder (1a → 1a1 → 1a2) survives; with no such parent in
        sight it simply stays where its group puts it.

    ``nodes`` and ``senses`` receive the same texts, deduplicated together, so
    the fiche's tree and the flat sense list can never drift apart.
    """
    codes: list[tuple[str, int]] = []

    def keep(value: str, node: dict[str, object]) -> bool:
        if value in senses:
            return False
        senses.append(value)
        nodes.append(node)
        return True

    def walk_list(list_element: ET.Element, level: int) -> None:
        context = level
        for item in list_element:
            if item.tag != "item":
                continue
            child_base = level
            emitted_any = False
            for value in split_numbered(own_text(item)):
                header = split_header(value)
                piece_level = level
                emitted = False
                if header:
                    label, rest = header
                    emitted = keep(
                        value,
                        {"level": level, "kind": "header", "label": label, "text": rest},
                    )
                    if emitted:
                        # The group reaches the pieces that follow in this list.
                        context = level + 1
                else:
                    match = CODE.match(value)
                    bare = None if match else BARE.match(value)
                    if match or bare:
                        code = (match or bare).group(1)
                        rest = value[match.end() :] if match else ""
                        parent_code, parent_level = "", None
                        for seen_code, seen_level in codes:
                            if code.startswith(seen_code) and len(seen_code) > len(
                                parent_code
                            ):
                                parent_code, parent_level = seen_code, seen_level
                        if parent_level is None:
                            piece_level = context
                        elif parent_code == code:
                            # A repeated code stays on its own rung.
                            piece_level = parent_level
                        else:
                            piece_level = parent_level + 1
                        codes.append((code, piece_level))
                        emitted = keep(
                            value,
                            {"level": piece_level, "kind": "number", "text": value},
                        )
                        if emitted and not rest.strip():
                            # « 1a) » — or a bare « 1b » — opens a numbering
                            # group: the senses that follow belong to it.
                            context = piece_level + 1
                    elif value:
                        emitted = keep(
                            value, {"level": context, "kind": "sense", "text": value}
                        )
                if emitted:
                    # A nested list belongs to the last thing its item said.
                    emitted_any = True
                    child_base = piece_level
            children_level = child_base + 1 if emitted_any else level
            for child in item:
                if child.tag == "list":
                    walk_list(child, children_level)

    past_list = False
    base = 0
    for child in definition:
        if child.tag == "list":
            walk_list(child, base)
            past_list = True
            trailing = clean(child.tail or "")
        elif past_list:
            trailing = clean(f"{text(child)} {child.tail or ''}")
        else:
            # Text before the first list is the gloss, already collected by
            # intro_text(): the fiche shows it in its own section.
            continue
        if trailing:
            # A label between two lists — « (phrases) » — opens the next one.
            nodes.append({"level": base, "kind": "label", "text": trailing})
            base += 1


def parse_entry(strong: str, language: str, xml: str) -> dict[str, object]:
    root = ET.fromstring(xml.rstrip("\x00"))
    orth = root.findall(".//orth")
    transliteration = next((text(item) for item in orth if item.get("type") == "trans"), "")
    lemma = text(orth[0]) if orth else ""
    pronunciation = text(root.find(".//pron"))
    part_of_speech = text(root.find(".//pos"))
    definitions = root.findall(".//def")
    etymology = text(definitions[0].find(".//orig")) if definitions else ""
    senses: list[str] = []
    significations: list[str] = []
    outline: list[dict[str, object]] = []
    for definition in definitions:
        items = definition.findall(".//item")
        if items:
            # The gloss is not a sense: it names the word, the items list its
            # uses. It gets its own field, so the fiche can show it apart.
            intro = intro_text(definition)
            if intro and intro != etymology:
                significations.append(intro)
            walk_definition(definition, outline, senses)
        elif not etymology or definition is not definitions[0]:
            value = text(definition)
            if value and value != etymology and value not in senses:
                senses.append(value)
                outline.append({"level": 0, "kind": "sense", "text": value})
    # Keep a readable string for search and old consumers while retaining the
    # source fields needed by the structured Strong fiche.
    definition = "\n".join(f"• {item}" for item in dict.fromkeys(senses))
    if not definition:
        definition = etymology or "Définition non disponible."
    entry: dict[str, object] = {
        "strong": f"{language[0].upper()}{int(strong):04d}",
        "language": language,
        "lemma": lemma,
        "transliteration": transliteration,
        "pronunciation": pronunciation,
        "partOfSpeech": part_of_speech,
        "etymology": etymology,
    }
    # Only the entries that carry one pay for the line: the field reads as
    # absent and empty alike on the Dart side.
    signification = "\n".join(dict.fromkeys(significations))
    if signification:
        entry["signification"] = signification
    entry["senses"] = list(dict.fromkeys(senses))
    # The outline is emitted only where it says something the bullets do not:
    # a level to indent, a group to open, a code to set apart. The rest of the
    # lexicon keeps its flat list.
    if any(node["level"] > 0 or node["kind"] != "sense" for node in outline):
        entry["outline"] = outline
    entry["definition"] = definition
    return entry


def download_modules(destination: Path) -> None:
    """Download and unpack the official CrossWire Strong modules."""
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as temporary:
        temporary_path = Path(temporary)
        for url in MODULE_URLS:
            archive = temporary_path / url.rsplit("/", 1)[-1]
            print(f"Téléchargement: {archive.name}")
            urllib.request.urlretrieve(url, archive)
            with zipfile.ZipFile(archive) as package:
                for member in package.infolist():
                    target = (destination / member.filename).resolve()
                    if destination.resolve() not in target.parents and target != destination.resolve():
                        raise ValueError(f"Archive invalide: {member.filename}")
                package.extractall(destination)

def export(source_root: Path, output: Path) -> int:
    entries: dict[str, dict[str, object]] = {}
    for module_name, prefix, language, folder in MODULES:
        directory = source_root / "modules" / "lexdict" / "zld" / folder
        reader = ZldReader(directory)
        count = 0
        for number, xml in reader.entries():
            item = parse_entry(number, language, xml)
            item["strong"] = f"{prefix}{int(number):04d}"
            entries[item["strong"]] = item
            count += 1
        print(f"{module_name}: {count} entrées")
    if not entries:
        raise ValueError("Aucune entrée Strong extraite")
    with_signification = sum(
        1 for item in entries.values() if item.get("signification")
    )
    print(f"Signification: {with_signification} entrées sur {len(entries)}")
    with_outline = sum(1 for item in entries.values() if item.get("outline"))
    print(f"Outline hiérarchique: {with_outline} entrées")
    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema": "bym.strong.v2",
        "source": "CrossWire/SWORD FreStrongsHebrew + FreStrongsGreek",
        "entries": entries,
    }
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Total: {len(entries)} entries -> {output}")
    return len(entries)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    root = Path(__file__).resolve().parents[1]
    parser.add_argument(
        "source", nargs="?", type=Path,
        default=root / "appCodebar" / "sword_modules" / "extracted",
        help="racine SWORD contenant modules/",
    )
    parser.add_argument(
        "output", nargs="?", type=Path,
        default=root / "bible_app" / "assets" / "lexicon" / "strong_fr.json",
        help="JSON structuré à produire",
    )
    parser.add_argument("--download", action="store_true", help="télécharge les modules officiels CrossWire avant l’export")
    args = parser.parse_args()
    if args.download:
        download_modules(args.source)
    export(args.source, args.output)


if __name__ == "__main__":
    main()