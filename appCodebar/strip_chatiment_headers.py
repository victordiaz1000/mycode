# -*- coding: utf-8 -*-
"""Retire les en-têtes courants de chatiment.json (note CHATIMENT_en-tetes_TODO.md).

Deux formes traitées :
  (a) blocs isolés : p dont le plié == titre plié (avec/sans numéro) [+ variante
      titre + numéro de page, ex ch8[0]] ;
  (b) titres incrustés : titre TOUT EN CAPS collé en fin/début de paragraphe
      (le corps écrit ces mots en minuscules : la casse discrimine, pas le plié).

Règles :
  - ne touche jamais aux h2/h3/h4/quote/li ;
  - suppression d'un isolé entre deux p dont le précédent finit SANS ponctuation
    de fin => recoudre prev + next (décalage des notes de next + with_notes) ;
  - un incrusté dépilé en bout de paragraphe participe au même recousage ;
  - n'écrit la sortie qu'après validation (0 invariant violé, 0 résidu, 45 notes,
    fix Hébreux intact).
Usage : python strip_chatiment_headers.py [SRC] [DST]
"""
import json
import re
import sys

sys.path.insert(0, 'appCodebar')
import pdf_book_to_json as conv

SRC = sys.argv[1] if len(sys.argv) > 1 else 'appCodebar/chatiment.json'
DST = sys.argv[2] if len(sys.argv) > 2 else (
    'C:/Users/laptek/AppData/Local/Temp/opencode/chatiment.sans_entetes.json')

END_PUNCT = re.compile(r'[.!?…:;»"\')\]]\s*$')
TRAIL_DIGITS = re.compile(r'^(.*?)\s+(\d{1,3})\s*$')
# Bloc purement numérique (« 1 », « 3 », « 4 » en tête de chapitre) : un numéro
# de page égaré, jamais du texte.
LONE_DIGITS = re.compile(r'^\d{1,3}$')
# Numéro de page/chapitre isolé (« 1 », « 2 ») : jamais une phrase à recoudre.
PREV_NUM = re.compile(r'^[\d\s.\-]+$')
# Fin de paragraphe : corps (avec minuscules) suivi d'une rafale TOUT CAPS,
# une ponctuation faible pouvant s'intercaler (« ...rigueur, LE CHÂTIMENT » —
# la virgule appartient à la phrase et doit survivre au dépilage).
TRAIL_CAPS = re.compile(
    r'^(.*?[a-zà-öø-ÿœæ])(\s*[:,;—–\-]\s+|\s+)([A-ZÀ-ÞÆŒ \-\':;?!()/–—]{6,})\s*(\d{1,3})?\s*$')
TRAIL_PUNCT = re.compile(r'[:,;—–\-]')
LEAD_CAPS = re.compile(
    r'^\s*([A-ZÀ-ÞÆŒ \-\':;?!()/–—]{6,})\s+([a-zà-öø-ÿœæ\(\"«].*)$',
    re.DOTALL)


def is_caps(text):
    letters = [c for c in text if c.isalpha()]
    return bool(letters) and not any(c.islower() for c in text)


def deprefixed(folded):
    s = re.sub(r'^[\dIVXLC]+\s+', '', folded)
    s = re.sub(r'^[A-Z]\s+', '', s)
    return s


def main():
    with open(SRC, encoding='utf-8') as f:
        data = json.load(f)

    chapters = {c['number']: c for c in data['chapters']}
    # Chapitres concernés par le MD (+ annexes 10-11).
    targets = [n for n in (4, 5, 6, 7, 8, 10, 11) if n in chapters]

    report = []
    for num in targets:
        ch = chapters[num]
        title = ch.get('title', '')
        ft = conv.fold(title)
        bare = deprefixed(ft)
        forms = {s for s in (ft, bare) if len(s) >= 6}

        def header_fold(f):
            if f in forms:
                return True
            m = TRAIL_DIGITS.match(f)
            # Titre + numéro de page (ch8[0]) : le plié finit par un chiffre.
            return bool(m) and m.group(1) in forms

        blocks = ch.get('blocks', [])
        # --- passe 1 : dépiler les incrustés (tout caps, plié == titre) ---
        stripped = 0
        stripped_ids = set()
        for b in blocks:
            if b.get('type') != 'p':
                continue
            tx = str(b.get('text', ''))
            if b.get('notes'):
                # Un incrusté sur un bloc noté : on ne touche pas sans preuve.
                # (constaté : aucun cas dans ce livre, garde-fou actif)
                continue
            m = TRAIL_CAPS.match(tx)
            if m and is_caps(m.group(3)) and conv.fold(m.group(3)) in forms:
                punct = TRAIL_PUNCT.search(m.group(2))
                b['text'] = m.group(1).rstrip() + (punct.group(0) if punct else '')
                stripped += 1
                stripped_ids.add(id(b))
                continue
            m = LEAD_CAPS.match(tx)
            if m and is_caps(m.group(1)) and conv.fold(m.group(1)) in forms:
                b['text'] = m.group(2).lstrip()
                stripped += 1
                stripped_ids.add(id(b))
        # --- passe 2 : supprimer les isolés + recoudre ---
        def recoudre(prev, nxt):
            """Fusionne nxt à la suite de prev (phrase coupée par saut de page)."""
            old_len = len(str(prev.get('text', '')))
            prev['text'] = str(prev.get('text', '')) + ' ' + str(nxt.get('text', ''))
            new_notes = list(prev.get('notes', []) or [])
            for n in (nxt.get('notes', []) or []):
                nn = dict(n)
                nn['position'] = int(nn['position']) + old_len + 1
                new_notes.append(nn)
            new_notes.sort(key=lambda n: int(n['position']))
            if new_notes:
                prev['notes'] = new_notes
                prev['textWithNotes'] = conv.with_notes(prev['text'], new_notes)
            elif 'textWithNotes' in prev:
                prev.pop('textWithNotes', None)

        out = []
        removed = 0
        rejoined = 0
        lone_digits = 0
        i = 0
        while i < len(blocks):
            b = blocks[i]
            if b.get('type') == 'p' and LONE_DIGITS.match(str(b.get('text', '')).strip()):
                assert not b.get('notes'), 'chiffre isole note ch%s[%d]' % (num, i)
                lone_digits += 1
                i += 1
                continue
            if b.get('type') == 'p' and header_fold(conv.fold(str(b.get('text', '')))):
                assert not b.get('notes'), 'isole note ch%s[%d]' % (num, i)
                removed += 1
                prev = out[-1] if out else None
                nxt = blocks[i + 1] if i + 1 < len(blocks) else None
                prev_text = str(prev.get('text', '')) if prev is not None else ''
                if (prev is not None and prev.get('type') == 'p'
                        and nxt is not None and nxt.get('type') == 'p'
                        and not PREV_NUM.match(prev_text.strip())
                        and not END_PUNCT.search(prev_text)):
                    recoudre(prev, nxt)
                    blocks[i + 1] = {'type': '__consomme__', 'text': ''}
                    rejoined += 1
                i += 1
                continue
            if b.get('type') == '__consomme__':
                i += 1
                continue
            # Dépilé de passe 1 qui finit sans ponctuation + next p :
            # même phrase coupée (ex ch6[21] "...coupables" + "d'impuretés...").
            nxt = blocks[i + 1] if i + 1 < len(blocks) else None
            if (id(b) in stripped_ids and b.get('type') == 'p'
                    and nxt is not None and nxt.get('type') == 'p'
                    and not END_PUNCT.search(str(b.get('text', '')))
                    and not header_fold(conv.fold(str(nxt.get('text', ''))))):
                recoudre(b, nxt)
                blocks[i + 1] = {'type': '__consomme__', 'text': ''}
                rejoined += 1
            out.append(b)
            i += 1
        ch['blocks'] = out
        report.append('ch %s : isoles_supprimes=%d, chiffres_supprimes=%d, incrustes_depiles=%d, recousus=%d, blocs=%d->%d'
                      % (num, removed, lone_digits, stripped, rejoined, len(blocks), len(out)))

    # --- validation ---
    bad = 0
    count = 0
    for ch in data['chapters']:
        for b in ch.get('blocks', []):
            for n in b.get('notes', []) or []:
                count += 1
                t = str(b.get('text', ''))
                p = int(n['position'])
                w = str(n['word'])
                if t[p:p + len(w)] != w:
                    bad += 1
                    print('INVARIANT VIOLE ch%s : %r @%d' % (ch.get('number'), w, p))
    # résidus : isolés restants + caps-traînantes
    residu = 0
    for ch in data['chapters']:
        if ch.get('number') not in (4, 5, 6, 7, 8, 10, 11):
            continue
        ft = conv.fold(ch.get('title', ''))
        forms = {s for s in (ft, deprefixed(ft)) if len(s) >= 6}
        for b in ch.get('blocks', []):
            if b.get('type') != 'p':
                continue
            tx = str(b.get('text', ''))
            f = conv.fold(tx)
            if f in forms:
                residu += 1
                print('RESIDU ISOLE ch%s : %r' % (ch.get('number'), tx[:80]))
            else:
                m = TRAIL_CAPS.match(tx)
                if m and is_caps(m.group(2)) and conv.fold(m.group(2)) in forms:
                    residu += 1
                    print('RESIDU INCRUSTE ch%s : ...%r' % (ch.get('number'), tx[-100:]))
    # fix Hébreux 12:5-8 intact
    raw = json.dumps(data, ensure_ascii=False)
    heb_ok = '"reference": "Hébreux 12: 5-8"' in raw and '5-81' not in raw
    print('\n'.join(report))
    print('notes=%d (attendu 45) | invariants_violes=%d | residus=%d | hebreux_ok=%s'
          % (count, bad, residu, heb_ok))
    if bad or residu or count != 45 or not heb_ok:
        sys.exit('VALIDATION ECHOUEE — rien n\u2019a été écrit')
    with open(DST, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('écrit : %s' % DST)


if __name__ == '__main__':
    main()
