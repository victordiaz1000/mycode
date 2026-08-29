#!/usr/bin/env python3
"""Export CrossWire/SWORD dictionaries (zLD or RawLD) to the app's JSON format.

The Bibliothèque's « Dictionnaires » tab downloads a single JSON file with the
shape `{entries: {key: {term, definition}}}`. CrossWire serves its French
dictionaries as SWORD modules instead: FreBailly is a zLD (compressed) module,
FreGBM a RawLD (plain) module. This exporter reads both formats from their
official rawzip packages and produces the JSON the app expects.

Usage:
  python appCodebar/sword_dict_to_json.py \
    --source path/to/FreBailly.zip \
    --output path/to/bailly.json \
    --kind zld --module modules/lexdict/zld/frebailly/dict
  python appCodebar/sword_dict_to_json.py \
    --source path/to/FreGBM.zip \
    --output path/to/gbm.json \
    --kind rawld --module modules/lexdict/rawld/fregbm/fregbm
"""
from __future__ import annotations

import argparse
import html
import json
import re
import struct
import zipfile
import zlib
from pathlib import Path


def clean(value: str) -> str:
    text = html.unescape(value)
    text = text.replace('\x00', '')
    # TEI-ish entry markup from the SWORD modules: drop the tags, keep the
    # structure (paragraphs, senses) and the references' display text.
    text = re.sub(r'<entryFree[^>]*>', '', text)
    text = re.sub(r'</entryFree>', '\n\n', text)
    text = re.sub(r'<def[^>]*>', '', text)
    text = re.sub(r'</def>', '\n\n', text)
    text = re.sub(r'<etym[^>]*>', '', text)
    text = re.sub(r'</etym>', '\n\n', text)
    text = re.sub(r'<title[^>]*>(.*?)</title>', r'\n\n\1\n\n', text, flags=re.DOTALL)
    text = re.sub(r'<sense[^>]*>', '\n\n• ', text)
    text = re.sub(r'<orth[^>]*>', '', text)
    text = re.sub(r'<lang[^>]*>', '', text)
    text = re.sub(r'<seg[^>]*>', '', text)
    text = re.sub(r'<hi[^>]*>(.*?)</hi>', r'\1', text)
    text = re.sub(r'<(?:p|section|div|tr)[^>]*>', '\n', text)
    text = re.sub(r'</(?:p|section|div|tr)>', '\n', text)
    text = re.sub(r'<lb\s*/?>', '\n', text)
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
    """A zLD module inside a rawzip package: dict.idx/dat + zdx/zdt blocks."""

    def __init__(self, zip_file: zipfile.ZipFile, module: str) -> None:
        self.zip = zip_file
        self.module = module.strip('/\\')

    def _read(self, relative: str) -> bytes:
        return self.zip.read(f'{self.module}/{relative}')

    def entries(self):
        index = self._read('dict.idx')
        data = self._read('dict.dat')
        block_index = self._read('dict.zdx')
        blocks = self._read('dict.zdt')
        cache: dict[int, bytes] = {}

        def block(number: int) -> bytes:
            cached = cache.get(number)
            if cached is not None:
                return cached
            start, size = struct.unpack_from('<II', block_index, number * 8)
            value = zlib.decompress(blocks[start:start + size])
            cache[number] = value
            return value

        for offset in range(0, len(index), 8):
            data_offset, data_size = struct.unpack_from('<II', index, offset)
            record = data[data_offset:data_offset + data_size]
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
            value = raw[entry_offset:entry_offset + entry_size].decode('utf-8', errors='replace')
            yield key, value


class RawldReader:
    """A RawLD module: the .dat is a plain concatenation of
    `KEY\\r\\n<entryFree…></entryFree>` blocks, so it can be parsed directly
    without trusting the (ambiguously packed) .idx."""

    def __init__(self, zip_file: zipfile.ZipFile, module: str) -> None:
        self.zip = zip_file
        self.module = module.strip('/\\')
        # The base name is the folder's last component (…/rawld/fregbm).
        self.base = self.module.rsplit('/', 1)[-1]

    def _read(self, relative: str) -> bytes:
        return self.zip.read(f'{self.module}/{relative}')

    def entries(self):
        data = self._read(f'{self.base}.dat').decode('utf-8', errors='replace')
        pattern = re.compile(r'([^\r\n]+)\r\n(<entryFree.*?</entryFree>)', re.DOTALL)
        for key, body in pattern.findall(data):
            yield key.strip(), body.strip()


def export(source: Path, module: str, kind: str, output: Path) -> int:
    with zipfile.ZipFile(source) as package:
        if kind == 'zld':
            reader = ZldReader(package, module)
        elif kind == 'rawld':
            reader = RawldReader(package, module)
        else:
            raise ValueError(f'Unknown kind: {kind}')

        entries: dict[str, dict[str, str]] = {}
        for key, raw in reader.entries():
            definition = clean(raw)
            entries[key] = {'term': key, 'definition': definition}

    if not entries:
        raise ValueError('No entries extracted')

    output.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        'schema': 'bym.dictionary.v1',
        'source': source.name,
        'entries': entries,
    }
    output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Exported {len(entries)} entries to {output}')
    return len(entries)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path, help='rawzip package')
    parser.add_argument('--output', required=True, type=Path, help='JSON to write')
    parser.add_argument('--kind', required=True, choices=('zld', 'rawld'))
    parser.add_argument('--module', required=True, help='module folder inside the package')
    args = parser.parse_args()
    export(args.source, args.module, args.kind, args.output)


if __name__ == '__main__':
    main()