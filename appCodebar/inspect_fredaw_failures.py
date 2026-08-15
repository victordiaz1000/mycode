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

    broken = []
    for offset in range(0, len(idx), 8):
        data_offset, data_size = struct.unpack_from('<II', idx, offset)
        record = dat[data_offset:data_offset + data_size]
        key_bytes = record.split(b'\r', 1)[0]
        if not key_bytes:
            continue
        try:
            key = key_bytes.decode('ascii')
        except Exception:
            key = key_bytes.decode('utf-8', errors='replace')
        block_number, entry_number = struct.unpack('<II', record[-8:])
        raw = block(block_number)
        entry_offset, entry_size = struct.unpack_from('<II', raw, 4 + entry_number * 8)
        entry = raw[entry_offset:entry_offset + entry_size]
        try:
            entry.decode('utf-8')
        except UnicodeDecodeError as e:
            broken.append((key, e.start, entry[e.start-20:e.start+20]))
    print('broken count', len(broken))
    for i, (key, pos, snippet) in enumerate(broken[:20]):
        print('---')
        print('key', key)
        print('pos', pos)
        print('snippet', repr(snippet))
