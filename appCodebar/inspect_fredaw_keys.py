from pathlib import Path
import zipfile
import struct
import zlib

SOURCE = Path('appCodebar/sword_modules/FreDAW.zip')
PREFIX = 'modules/lexdict/zld/fredaw/'

with zipfile.ZipFile(SOURCE) as z:
    idx = z.read(PREFIX + 'dict.idx')
    dat = z.read(PREFIX + 'dict.dat')
    zdx = z.read(PREFIX + 'dict.zdx')
    zdt = z.read(PREFIX + 'dict.zdt')

    def block(num: int) -> bytes:
        start, size = struct.unpack_from('<II', zdx, num * 8)
        return zlib.decompress(zdt[start:start + size])

    def decode_key(key_bytes: bytes) -> dict[str, str]:
        results = {}
        for enc in ['ascii', 'utf-8', 'cp1252', 'iso-8859-1']:
            try:
                decoded = key_bytes.decode(enc, errors='replace')
            except Exception as e:
                decoded = f'<error {e}>'
            results[enc] = decoded
        return results

    print('Inspecting keys with non-ASCII bytes and around BAD terms...')
    found = 0
    for offset in range(0, len(idx), 8):
        data_offset, data_size = struct.unpack_from('<II', idx, offset)
        record = dat[data_offset:data_offset + data_size]
        key_bytes = record.split(b'\r', 1)[0]
        if any(b > 0x7f for b in key_bytes) or key_bytes.startswith(b'ABD'):
            dec = decode_key(key_bytes)
            print('RAW KEY BYTES:', key_bytes)
            for enc, decoded in dec.items():
                print(f'  {enc}: {decoded}')
            if key_bytes.startswith(b'ABD'):
                block_number, entry_number = struct.unpack('<II', record[-8:])
                raw = block(block_number)
                count = struct.unpack_from('<I', raw, 0)[0]
                entry_offset, entry_size = struct.unpack_from('<II', raw, 4 + entry_number * 8)
                entry = raw[entry_offset:entry_offset + entry_size]
                print('  ENTRY BYTES', repr(entry[:160]))
                for enc in ['utf-8', 'cp1252', 'iso-8859-1']:
                    try:
                        decoded = entry.decode(enc, errors='replace')
                    except Exception as e:
                        decoded = f'<error {e}>'
                    print(f'    {enc}: {decoded[:200]!r}')
            print('---')
            found += 1
            if found >= 20:
                break
