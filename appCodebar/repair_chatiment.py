# -*- coding: utf-8 -*-
"""Repare les notes du CHATIMENT restees dans le corps.

Contexte : le convertisseur a refuse les notes de ce livre parce que sa note
d'ouverture (editoriale, sans marqueur) bloquait le compteur — voir la regle 3
de pdf_book_to_json.py. Resultat : 0 note balisee, ~49 paragraphes numerotes
dans le corps, dont de vraies notes de bas de page a marqueurs presents.

Ce script post-traitement, limite a chatiment.json :
  1. ne retient qu'un paragraphe numerote s'il a un marqueur (colle ou
     separe, memes motifs que le convertisseur) dans le corps du chapitre ;
  2. refuse les enumerations de corps (« 1 - Le rejet ») et les restes
     d'en-tetes courants (« 2 LE CHATIMENT », tout en capitales) ;
  3. impose des numeros croissants dans l'ordre du chapitre (les items de
     corps « 1, 2 » glisses entre les notes 34 et 35 sortent d'eux-memes) ;
  4. decoupe les notes fusionnees (« 6 Pierre ... 7 Etienne ... 8 Gentils »)
     sur numeros consecutifs a marqueurs ;
  5.desuffixe les en-tetes courants colles en fin de note ;
  6. attache via attach_notes/glued_notes du convertisseur (memes invariants),
     puis retire du corps les seuls blocs entierement consommes.

AUCUNE perte de texte : tout candidat non consomme reste un paragraphe.
"""
import copy
import json
import re
import sys

import pdf_book_to_json as conv

SRC = 'chatiment.json'
DST = 'chatiment.fixed.json'

NUM_HEAD = re.compile(r'^(\d{1,2})\s+(\S.*)$', re.DOTALL)
ENUM_BODY = re.compile(r'^\d{1,2}\s+[-–—]\s+\S')
SPLIT_NEXT = re.compile(r' (\d{1,2}) (?=[A-Z\u00c0-\u00de])')
# « ... médias en ligne. 31 ceux qui suivent ... » : la note suivante peut
# s'ouvrir en bas de casse, trahie alors par la fin de phrase qui précède.
SPLIT_SENT = re.compile(r'(?<=[.!?…:;»]) (\d{1,2}) ')
# Un morceau qui reste du corps : 250+ signes, 3 phrases, une tête de 60
# signes sans fin de phrase mais avec un passage minuscule -> Majuscule nu
# (« d'Adam J'ai ») — le cas de la note 48, dont le « J'ai vécu... »
# appartient au texte courant, pas à la glose de « Caïn ».
LONG_PIECE = 250
SENT_END = re.compile(r'[.!?…]\s+[A-Z\u00c0-\u00de]')
BARE_TRANS = re.compile(r'[a-zà-ÿâêîôûäëïöüéèçœæ] [A-ZÀ-ÞÆŒ]')
TRAIL_HEAD = re.compile(
    r'^(.*?\S)\s+([A-Z\u00c0-\u00de\u00c6\u0152\u00df'
    r' :\'\u2019\-/\u2013\u2014()?!]{6,})$'
)


def is_caps_only(text):
    letters = [c for c in text if c.isalpha()]
    return bool(letters) and not any(c.islower() for c in text)


def has_marker(body, number):
    for pattern in conv.marker_patterns(number):
        if pattern.search(body):
            return True
    return False


def strip_running_head(text, candidates):
    """Retire en queue un en-tete courant colle (connu au sommaire)."""
    for _ in range(2):
        m = TRAIL_HEAD.match(text)
        if not m:
            return text
        probe = conv.fold(m.group(2))
        if len(probe) < 6:
            return text
        if probe in candidates or any(
            c.startswith(probe + ' ') for c in candidates
        ):
            text = m.group(1)
        else:
            return text
    return text


def split_merged(num, text, body):
    """Decoupe « 6 Pierre ... 7 Etienne ... 8 Gentils ... ».

    Deux coupes : le numero suivi d'une capitale (« 8 Gentils »), ou le
    numero consecutif apres une fin de phrase (« en ligne. 31 ceux »).
    Seuls les numeros consecutifs a marqueurs coupent ; le reste colle au
    morceau precedent. Retourne [(numero, texte)]. Recursif pour que les
    offsets restent locaux a chaque morceau.
    """
    for pattern, cap_after in ((SPLIT_NEXT, True), (SPLIT_SENT, False)):
        m = pattern.search(text)
        if not m:
            continue
        nxt = int(m.group(1))
        if nxt == num + 1 and has_marker(body, nxt):
            head = text[:m.start()].strip()
            tail = text[m.start() + 1:].strip()
            out = []
            if head:
                out.append((num, head))
            out.extend(split_merged(nxt, tail, body))
            return out
    return [(num, text)] if text.strip() else []


def is_body_runon(piece):
    """Vrai si le morceau est du corps colle a une note (cas de la 48)."""
    if len(piece) <= LONG_PIECE:
        return False
    if len(SENT_END.findall(piece)) < 2:
        return False
    head = piece[:60]
    return not bool(SENT_END.search(head)) and bool(
        BARE_TRANS.search(head))


def main():
    with open(SRC, encoding='utf-8') as f:
        data = json.load(f)

    toc = [(i.get('title', ''), 0, i.get('level', 0))
           for i in data.get('toc', [])]
    candidates_heads = conv.header_candidates(toc)
    # Les titres du sommaire portent leur prefixe (« 1. ELOHIM ... ») quand
    # l'en-tete courant, lui, est nu : on ajoute les formes deprefixees pour
    # que le desuffixage les reconnaisse.
    bare = set()
    for candidate in list(candidates_heads):
        short = re.sub(r'^[\dIVXLC]+\s+', '', candidate)
        short = re.sub(r'^[A-Z]\s+', '', short)
        if len(short) >= 6:
            bare.add(short)
    candidates_heads = list(set(candidates_heads) | bare)

    report = []
    total_notes = 0
    for chapter in data.get('chapters', []):
        blocks = chapter.get('blocks', [])
        body = ' '.join(
            str(b.get('text', '')) for b in blocks
            if b.get('type') == 'p'
        )
        # 1-3 : candidats gardes.
        kept = []
        for idx, block in enumerate(blocks):
            if block.get('type') != 'p':
                continue
            m = NUM_HEAD.match(str(block.get('text', '')))
            if not m:
                continue
            num = int(m.group(1))
            rest = m.group(2)
            if ENUM_BODY.match(str(block.get('text', ''))):
                continue
            if is_caps_only(rest):
                continue
            if not has_marker(body, num):
                continue
            kept.append((idx, num, rest))
        # 4 : numeros croissants dans l'ordre du chapitre.
        mono = []
        for idx, num, rest in kept:
            if mono and num <= mono[-1][1]:
                continue
            mono.append((idx, num, rest))
        if not mono:
            continue
        # 5-6 : notes, avec decoupage des fusionnees.
        notes = {}
        for idx, num, rest in mono:
            full = '%d %s' % (num, rest)
            for n, t in split_merged(num, full, body):
                if n in notes:
                    continue
                t = strip_running_head(
                    re.sub(r'^%d\s+' % n, '', t), candidates_heads)
                if t and not is_body_runon(t):
                    notes[n] = t
        if not notes:
            continue
        # Attache sur les blocs de corps (candidats exclus du balayage :
        # leurs numeros de tete ne sont pas des marqueurs).
        others = [b for i, b in enumerate(blocks)
                  if not any(i == k[0] for k in mono)]
        glued = conv.glued_notes(others, notes)
        used = set()
        for block in others:
            if block.get('type') == 'p':
                conv.attach_notes(block, notes, used, glued)
        # 7 : retire les seuls blocs entierement consommes.
        consumed_idx = set()
        for idx, num, rest in mono:
            full = '%d %s' % (num, rest)
            piece_nums = [n for n, _ in split_merged(num, full, body)]
            if all(n in used for n in piece_nums):
                consumed_idx.add(idx)
        chapter['blocks'] = [b for i, b in enumerate(blocks)
                             if i not in consumed_idx]
        attached = len(used)
        total_notes += attached
        report.append('ch %d : %d notes attachees, %d blocs retires' % (
            chapter.get('number'), attached, len(consumed_idx)))

    # Validation : invariants de note_aware_text.dart.
    bad = 0
    count = 0
    for chapter in data.get('chapters', []):
        for block in chapter.get('blocks', []):
            for note in block.get('notes', []) or []:
                count += 1
                text = block.get('text', '')
                pos = int(note['position'])
                word = str(note['word'])
                if text[pos:pos + len(word)] != word:
                    bad += 1
    print('\n'.join(report))
    print('total notes : %d | invariants violes : %d' % (count, bad))
    if bad:
        sys.exit('INVARIANTS VIOLÉS — rien n’a été écrit')
    with open(DST, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('écrit : %s' % DST)


if __name__ == '__main__':
    main()
