# -*- coding: utf-8 -*-
"""Convertit le glossaire SEF (pages HTML) en dictionnaire `{entries}` pour l'app.

Source : sef/extrait/glossaire/*.html — les notices du glossaire de la traduction
française de la Septante (Giguet) livrées avec SEF.xml, plus les introductions,
les index et les documents annexes (Lettre d'Aristée, Rouleau du Temple…).

Sortie : appCodebar/dictionaries_json/glossaire_septante.json, le même schéma que
gbm.json (`bym.dictionary.v1`, `entries` → `{term, definition}`), à héberger sur
victordiaz1000/-bym-dictionaries comme les autres dictionnaires.

Règles de conversion, alignées sur ce que rend `DictionaryArticleView` :
  - le corps HTML est réduit à du texte : chaque `<p>` / `<li>` / `<br>` ouvre un
    paragraphe, les ancres gardent leur texte visible (« Genèse 14.21 » reste —
    `findReferences` le rendra cliquable, « Âme » reliera l'entrée par le
    cross-link du lecteur) ;
  - les entités deviennent leur caractère (&nbsp; → espace insécable, comme dans
    gbm.json) ;
  - le bandeau « ▶ Retour » en tête de page tombe avec tout ce qui précède le
    premier titre ;
  - le titre de tête devient la clé d'entrée et ne reste pas dans le corps.

Usage : python glossaire_to_json.py
"""

import io
import json
import os
import re
import sys
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'extrait', 'glossaire')
OUT = os.path.join(HERE, '..', 'appCodebar', 'dictionaries_json',
                   'glossaire_septante.json')

# Titre des pages qui n'ont pas de h2 de mot. Les vingt-deux notices (ÂME,
# ABOMINATION…) reprennent leur h2, les dix suites de l'introduction générale
# leur h2 « n - … » : voir plus bas.
TITRES = {
    'INTRODUCTION.html': 'INTRODUCTION AU GLOSSAIRE',
    'INTRODUCTION GENERALE.html': 'INTRODUCTION GÉNÉRALE',
    'GIGUET_INTRODUCTION.html': 'INTRODUCTION',
    'INTRODUCTION JUGES.html': 'INTRODUCTION AUX JUGES',
    'intro_EZR_NEH.html': 'INTRODUCTION À ESDRAS ET NÉHÉMIE',
    'DECOUPAGE.html': 'DÉCOUPAGE DU TEXTE',
    'JEREMIE.html': 'JÉRÉMIE',
    'LETTRE_ARISTEE.html': "LETTRE D'ARISTÉE",
    'ROULEAU_DU_TEMPLE.html': 'LE ROULEAU DU TEMPLE',
}
# Les h1 des dix suites (« Introduction générale (suite) ») sont communs : leur
# clé est leur h2, « 1 - La traduction de la Torah en grec »…
SUITES = {'INTRODUCTION GENERALE%d.html' % n for n in range(1, 11)}

# Éléments de flux : une balise de ce genre sépare deux paragraphes. Les
# éléments en ligne (<a>, <i>, <sup>…) n'y figurent pas — couper au milieu d'une
# phrase à chaque lien donnerait un article haché.
BLOCS = {'p', 'li', 'br', 'tr', 'div', 'ol', 'ul', 'table'}


class Extracteur(HTMLParser):
    """Texte visible d'une page, en segments `(texte, niveau)`.

    `niveau` vaut 0 dans le flux courant et 1–6 pour le contenu d'un titre : le
    titre sert de clé d'entrée et de repère de début de page réelle (tout ce qui
    précède le premier titre est le bandeau « ▶ Retour »).
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.chunks = []
        self._buf = []
        self._niveau = 0

    def _flush(self):
        texte = ''.join(self._buf)
        self._buf = []
        if texte.strip():
            self.chunks.append((texte, self._niveau))

    def handle_starttag(self, tag, attrs):
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self._flush()
            self._niveau = int(tag[1])
        elif tag in BLOCS:
            self._flush()

    def handle_endtag(self, tag):
        if tag in ('h1', 'h2', 'h3', 'h4', 'h5', 'h6'):
            self._flush()
            self._niveau = 0
        elif tag in BLOCS:
            self._flush()

    def handle_data(self, data):
        self._buf.append(data)

    def close(self):
        super().close()
        self._flush()


def nettoie(texte):
    """Normalise les espaces autour d'un paragraphe sans toucher aux insécables."""
    texte = texte.replace('\xa0', '\x02')          # l'insécable mise à part
    texte = re.sub(r'[ \t\r\n]+', ' ', texte)
    return texte.replace('\x02', '\xa0').strip()


def sans_renvois(html_texte):
    """Retire les renvois de note (<sup>) des seuls titres : « Pentateuque1 »."""
    def titre_sans_sup(m):
        return m.group(1) + re.sub(r'<sup>.*?</sup>', '', m.group(2),
                                   flags=re.S) + m.group(3)
    return re.sub(r'(<h[1-6][^>]*>)(.*?)(</h[1-6]>)', titre_sans_sup,
                  html_texte, flags=re.S)


def convertir(nom, brut):
    # Deux parses : le corps garde les <sup> (suffixes ordinaux, « IVe »), les
    # titres les perdent (renvoi de note « Pentateuque1 »).
    extrait = Extracteur()
    extrait.feed(brut)
    extrait.close()
    titres = Extracteur()
    titres.feed(sans_renvois(brut))
    titres.close()

    def debut(chunks):
        """Le corps utile : tout après le premier titre (avant = bandeau)."""
        vu_titre = False
        out = []
        for texte, niveau in chunks:
            texte = nettoie(texte)
            if not vu_titre:
                if niveau == 0:
                    continue
                vu_titre = True
            out.append((texte, niveau))
        return out

    corps = debut(extrait.chunks)
    corps_titres = debut(titres.chunks)
    if not corps:
        return None, None

    # La clé : mapping explicite, sinon le premier titre (h2 de mot, ou h2
    # « n - … » des suites d'introduction).
    titre = TITRES.get(nom)
    if titre is None:
        pool = corps_titres[1:] if nom in SUITES else corps_titres
        titre = next((t for t, n in pool if n > 0), None)
    if not titre:
        titre = os.path.splitext(nom)[0].replace('_', ' ')
    # Pas d'insécable dans une clé : une recherche exacte viendrait avec un
    # espace simple (« 1 - La traduction… »).
    titre = titre.replace('\xa0', ' ')

    # Le corps perd les titres de tête : celui de l'entrée (égal à la clé), et
    # le « … (suite) » commun des dix introductions qui l'ouvre parfois.
    paragraphes = []
    for texte, niveau in corps:
        if niveau > 0 and texte.replace('\xa0', ' ').upper() == titre.upper():
            continue
        if niveau > 0 and texte.endswith('(suite)'):
            continue
        paragraphes.append(texte)

    definition = '\n\n'.join(paragraphes)
    return titre, re.sub(r'\n{3,}', '\n\n', definition).strip()


def main():
    if not os.path.isdir(SRC):
        sys.exit('dossier introuvable : %s' % SRC)
    entrees = {}
    for nom in sorted(os.listdir(SRC)):
        if not nom.lower().endswith('.html'):
            continue
        brut = io.open(os.path.join(SRC, nom), encoding='utf-8').read()
        titre, definition = convertir(nom, brut)
        if not titre or not definition:
            print('! sans contenu : %s' % nom)
            continue
        if titre in entrees:
            sys.exit('titre en double : %s (%s)' % (titre, nom))
        entrees[titre] = {'term': titre, 'definition': definition}
        print('%-31s %-46s %8d' % (nom, titre[:46], len(definition)))

    doc = {
        'schema': 'bym.dictionary.v1',
        'source': 'glossaire de la SEF (Septante française, Giguet)',
        'entries': entrees,
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with io.open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    print('\n%d entrées, %d octets -> %s'
          % (len(entrees), os.path.getsize(OUT), OUT))


if __name__ == '__main__':
    main()
