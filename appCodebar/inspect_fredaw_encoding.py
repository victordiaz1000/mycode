from pathlib import Path
import zipfile
import struct
import zlib

source = Path('appCodebar/sword_modules/FreDAW.zip')
prefix = 'modules/lexdict/zld/fredaw/'

with zipfile.ZipFile(source) as z:
    idx = z.read(prefix + 'dict.idx')
    dat = z.read(prefix + 'dict.dat')
    zdx = z.read(prefix + 'dict.zdx')
    zdt = z.read(prefix + 'dict.zdt')

    def block(num: int) -> bytes:
        start, size = struct.unpack_from('<II', zdx, num * 8)
        return zlib.decompress(zdt[start:start + size])

    def entry_bytes(key_name: str):
        for offset in range(0, len(idx), 8):
            data_offset, data_size = struct.unpack_from('<II', idx, offset)
            record = dat[data_offset:data_offset + data_size]
            key_bytes = record.split(b'\r', 1)[0]
            try:
                key = key_bytes.decode('ascii', errors='replace').lstrip('0') or '0'
            except Exception:
                key = repr(key_bytes)
            if key == key_name:
                block_number, entry_number = struct.unpack('<II', record[-8:])
                raw = block(block_number)
                entry_offset, entry_size = struct.unpack_from('<II', raw, 4 + entry_number * 8)
                return raw[entry_offset:entry_offset + entry_size]
        raise KeyError(key_name)

    tests = ['ABD', 'ABDÃ', 'ABDÃEL']
    for test in tests:
        print('\n===', test)
        try:
            data = entry_bytes(test)
        except KeyError:
            print('not found by exact key', test)
            continue
        print('raw repr', repr(data[:200]))
        for enc in ['utf-8', 'cp1252', 'iso-8859-1']:
            try:
                decoded = data.decode(enc, errors='replace')
            except Exception as e:
                decoded = f'<decode error {e}>'
            print(f'{enc}:', decoded[:200])
        print('replacement count utf8', data.decode('utf-8', errors='replace').count('\ufffd'))
        print('replacement count cp1252', data.decode('cp1252', errors='replace').count('\ufffd'))
        print('contains Â in utf8', 'Â' in data.decode('utf-8', errors='replace'))
        print('contains Ã in utf8', 'Ã' in data.decode('utf-8', errors='replace'))
