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
    for definition in definitions:
        items = definition.findall(".//item")
        if items:
            senses.extend(item for item in (text(item) for item in items) if item)
        elif not etymology or definition is not definitions[0]:
            value = text(definition)
            if value and value != etymology:
                senses.append(value)
    # Keep a readable string for search and old consumers while retaining the
    # source fields needed by the structured Strong fiche.
    definition = "\n".join(f"• {item}" for item in dict.fromkeys(senses))
    if not definition:
        definition = etymology or "Définition non disponible."
    return {
        "strong": f"{language[0].upper()}{int(strong):04d}",
        "language": language,
        "lemma": lemma,
        "transliteration": transliteration,
        "pronunciation": pronunciation,
        "partOfSpeech": part_of_speech,
        "etymology": etymology,
        "senses": list(dict.fromkeys(senses)),
        "definition": definition,
    }


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