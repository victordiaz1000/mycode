#!/usr/bin/env python3
"""Export a CrossWire/SWORD zLD dictionary module to JSON.

Usage:
  python appCodebar/sword_zld_to_json_fredaw.py \
    appCodebar/sword_modules/FreDAW.zip \
    bible_app/assets/lexicon/fredaw.json
"""
from __future__ import annotations

import argparse
import html
import json
import re
import struct
import zlib
import zipfile
from pathlib import Path
from typing import Iterable


def clean(value: str) -> str:
    text = html.unescape(value)
    text = text.replace('\x00', '')
    # Preserve paragraph and line structure from the zLD markup.
    text = re.sub(r'<entryFree[^>]*>', '', text)
    text = re.sub(r'</entryFree>', '\n\n', text)
    text = re.sub(r'<def[^>]*>', '', text)
    text = re.sub(r'</def>', '\n\n', text)
    text = re.sub(r'<title[^>]*>(.*?)</title>', r'\n\n\1\n\n', text, flags=re.DOTALL)
    text = re.sub(r'<(?:p|section|div)[^>]*>', '\n\n', text)
    text = re.sub(r'</(?:p|section|div)>', '\n\n', text)
    text = re.sub(r'<lb\s*/?>', '\n', text)
    text = re.sub(r'<hi[^>]*>(.*?)</hi>', r'\1', text)
    text = re.sub(r'<sup[^>]*>(.*?)</sup>', r'\1', text)
    text = re.sub(r'<sub[^>]*>(.*?)</sub>', r'\1', text)
    text = re.sub(r'<(?:xr|ref)[^>]*>', '', text)
    text = re.sub(r'</(?:xr|ref)>', '', text)
    text = re.sub(r'<[^>]+>', '', text)
    text = text.replace('\r', '')
    text = re.sub(r'\n[ \t]+', '\n', text)
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'[ \t]+', ' ', text)
    text = re.sub(r'\n ?\n', '\n\n', text)
    return text.strip()


class ZldReader:
    def __init__(self, source: Path, module_folder: str) -> None:
        self.source = source
        self.module_folder = module_folder.strip('/\\')
        self.zip = None
        if self.source.suffix.lower() == '.zip':
            self.zip = zipfile.ZipFile(self.source)

    def _read_bytes(self, relative: str) -> bytes:
        path = f'{self.module_folder}/{relative}'
        if self.zip is not None:
            return self.zip.read(path)
        return (self.source / path).read_bytes()

    def entries(self) -> Iterable[tuple[str, str]]:
        index = self._read_bytes('dict.idx')
        data = self._read_bytes('dict.dat')
        block_index = self._read_bytes('dict.zdx')
        blocks = self._read_bytes('dict.zdt')
        cache: dict[int, bytes] = {}

        def block(number: int) -> bytes:
            cached = cache.get(number)
            if cached is not None:
                return cached
            start, size = struct.unpack_from('<II', block_index, number * 8)
            value = zlib.decompress(blocks[start : start + size])
            cache[number] = value
            return value

        for offset in range(0, len(index), 8):
            data_offset, data_size = struct.unpack_from('<II', index, offset)
            record = data[data_offset : data_offset + data_size]
            key_bytes = record.split(b'\r', 1)[0]
            if not key_bytes:
                continue
            key = key_bytes.decode('utf-8', errors='replace').lstrip('0') or '0'
            block_number, entry_number = struct.unpack('<II', record[-8:])
            raw = block(block_number)
            count = struct.unpack_from('<I', raw, 0)[0]
            if entry_number >= count:
                raise ValueError(f'Entry {key}: index {entry_number} out of range ({count})')
            entry_offset, entry_size = struct.unpack_from('<II', raw, 4 + entry_number * 8)
            value = raw[entry_offset : entry_offset + entry_size].decode('utf-8', errors='replace')
            yield key, value


def export(source: Path, module_folder: str, output: Path) -> int:
    reader = ZldReader(source, module_folder)
    entries: dict[str, dict[str, str]] = {}
    count = 0
    for key, raw in reader.entries():
        definition = clean(raw)
        entries[key] = {
            'term': key,
            'definition': definition,
        }
        count += 1

    if count == 0:
        raise ValueError('No entries extracted')

    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        'schema': 'bym.fredaw.v1',
        'source': 'CrossWire/SWORD FreDAW',
        'entries': entries,
    }
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Exported {count} entries to {output}')
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='ZIP file or folder containing the SWORD module')
    parser.add_argument('output', type=Path, help='Target JSON file to write')
    parser.add_argument('--module-folder', default='modules/lexdict/zld/fredaw', help='Relative module folder inside the source')
    args = parser.parse_args()
    export(args.source, args.module_folder, args.output)


if __name__ == '__main__':
    main()
