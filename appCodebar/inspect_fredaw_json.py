from pathlib import Path
import json

path = Path('bible_app/assets/lexicon/fredaw.json')
text = path.read_text(encoding='utf-8')
print('length', len(text))
print('replacement count', text.count('\ufffd'))
for i in range(min(5, text.count('\ufffd'))):
    idx = text.index('\ufffd', 0 if i == 0 else idx + 1)
    start = max(0, idx - 80)
    end = min(len(text), idx + 80)
    print('--- occurrence', i, 'at', idx)
    print(repr(text[start:end]))
    print()
print('contains Â', 'Â' in text)
if 'Â' in text:
    idx = text.index('Â')
    start = max(0, idx - 80)
    end = min(len(text), idx + 80)
    print('first Â at', idx)
    print(repr(text[start:end]))
