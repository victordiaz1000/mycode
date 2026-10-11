"""Convertit un ouvrage PDF (livre d'édification) en JSON pour l'onglet « Livres ».

Usage :
    python pdf_book_to_json.py <source.pdf> <dest.json> --code MINISTERE
    python pdf_book_to_json.py <source.pdf> <dest.json> --code MINISTERE --dry-run
    python pdf_book_to_json.py <source.pdf> <dest.json> --code MINISTERE \
        --cover ../bible_app/assets/covers/ministere.jpg

Contrairement aux autres convertisseurs du dossier, celui-ci **sort de la
bibliothèque standard** : il lui faut `pdftotext -layout` (poppler) pour le texte
mis en page et `pypdf` pour les coordonnées de mots. La ligne « aucune
dépendance externe » de CLAUDE.md ne vaut donc pas pour ce script.

Règles de conversion — toutes nées de ce que le PDF fait réellement, pas de ce
qu'un PDF « devrait » faire :

1. **La feuille de sommaire imprimée est le squelette.** Le PDF n'a aucun
   signet (`outline` vide) : on la parse, elle porte la hiérarchie complète
   (chapitres, sections en chiffres romains, sous-sections en lettres) avec les
   numéros de page imprimés. Son titre varie — « SOMMAIRE » chez le pilote,
   « TABLE DES MATIÈRES » ailleurs, porté par la **première page seule** — et
   le filet qui sépare le titre du numéro est tantôt en points, tantôt en
   tirets bas. On suit donc les pages depuis la première titrée tant
   qu'elles livrent au moins une entrée, et la hiérarchie se lit au
   **préfixe** (`I/`, `A/` autant que `I.`, `A.`), jamais à l'indentation.

2. **Le décalage page imprimée / page physique se mesure, il ne se suppose
   pas.** On relève le numéro en pied de *chaque* page ; si le décalage n'est
   pas constant, le script s'arrête. Un livre à numérotation irrégulière doit se
   signaler, pas se tronquer en silence.

3. **Les notes de bas de page s'ancrent sur le compteur, jamais sur un motif.**
   Un `^(\\d+)\\s+texte` naïf ramasse des faux positifs bien réels
   (« 1 Corinthiens 4:7 », « 70 anciens… », « 400 ans esclave… »). On n'accepte
   un numéro que s'il est le **suivant attendu**, et seulement si son marqueur
   est présent dans le corps de la même page. Un bloc de note peut contenir une
   ligne vide interne (c'est le cas de la note 25).

4. **L'en-tête courant est un préfixe du titre, pas le titre.** Les pages du
   chapitre 4 portent « LA FAUSSE IDÉE QUE BEAUCOUP ONT », tronqué. Le
   discriminant fiable est l'indentation : les en-têtes sont centrés, le corps
   commence colonne 0.

5. **Aucune espace n'est retirée devant la ponctuation** — typographie
   française, même règle que les corpus HTML.

6. **Le tableau des noms se reconstruit par coordonnées.** `pdftotext -layout`
   entrelace ses 4 colonnes de travers (il apparie « Shemouél » à « Simon » au
   lieu de « Samuel »). On le rebâtit par abscisse via `pypdf`. Si les deux
   moitiés ne donnent pas le même nombre de lignes, on **avertit et on garde le
   texte brut** plutôt que d'inventer des paires.

7. **Aucune arithmétique d'indices entre les deux extracteurs.** Le découpage se
   fait entièrement dans le texte `layout` ; la page du tableau est retrouvée
   par son contenu. Les deux outils n'ont jamais à être mis en correspondance.

8. **La pochette est une image de la page 1, jamais une invention.** `--cover`
   recopie la plus grande image de la première page (la couverture est pleine
   page, le logo d'éditeur ne l'est pas) et avertit si la page 1 n'en porte
   aucune, plutôt que d'aller chercher une illustration ailleurs dans le livre.
   Une couverture **découpée en bandes** — un tirage qui éclate l'image en
   tranches horizontales — se recoud par leur placement réel dans le flux de
   la page : l'ordre de `pypdf` est lexicographique (`Im1`, `Im10`, `Im2`),
   il ne dit rien de l'empilement, et ne garder qu'une bande livrerait un
   coupon de couverture. La couture n'est acceptée que si les bandes
   bouchent la page, bord à bord ; sinon on retombe sur l'image entière la
   plus grande.

Format de sortie :
{
  "code": "MINISTERE",
  "title": "...", "subtitle": "...", "author": "...", "publisher": "...",
  "rights": "...", "isbn": "...",
  "toc":      [{ "title": "...", "chapter": 2, "level": 0 }],
  "chapters": [{ "number": 1, "title": "INTRODUCTION", "blocks": [
      { "type": "p",     "text": "...", "textWithNotes": "...", "notes": [...] },
      { "type": "h2"|"h3", "text": "..." },
      { "type": "li",    "text": "..." },
      { "type": "quote", "text": "...", "reference": "1 Corinthiens 9:16" },
      { "type": "pair",  "text": "Shemot", "gloss": "Exode" }
  ]}]
}

`notes` suit la convention de la BYM, portée par `note_aware_text.dart` :
{word, position, note} avec l'invariant `text[position:position+len(word)] == word`.
`textWithNotes` insère chaque note entre [crochets] après son mot.
"""

import argparse
import json
import re
import shutil
import subprocess
import sys
import unicodedata
from pathlib import Path
from typing import Any

# --- Avertissements ---------------------------------------------------------

WARNINGS: list[str] = []


def warn(message: str) -> None:
    """Signale une anomalie sans corriger en silence (convention du dossier)."""
    WARNINGS.append(message)
    print(f"  ! {message}")


# --- Localisation de pdftotext ---------------------------------------------

# poppler n'est pas sur le PATH de PowerShell sur cette machine : il vient avec
# Git et ne vit que dans le PATH de Git Bash. On le cherche donc explicitement.
PDFTOTEXT_CANDIDATES = (
    r"C:\Program Files\Git\mingw64\bin\pdftotext.exe",
    r"C:\Program Files (x86)\Git\mingw64\bin\pdftotext.exe",
    "/mingw64/bin/pdftotext",
    "/usr/bin/pdftotext",
)


def find_pdftotext() -> str:
    found = shutil.which("pdftotext")
    if found:
        return found
    for candidate in PDFTOTEXT_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    sys.exit(
        "pdftotext introuvable. Installez poppler, ou lancez ce script depuis "
        "Git Bash (poppler est fourni avec Git dans mingw64/bin)."
    )


# --- Normalisation ----------------------------------------------------------

def fold(text: str) -> str:
    """Plie accents, casse, apostrophes et espaces — pour comparer des titres."""
    text = text.replace("\u2019", "'").replace("\u02bc", "'")
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if unicodedata.category(c) != "Mn")
    text = re.sub(r"[^A-Za-z0-9]+", " ", text)
    return text.upper().strip()


# --- Lecture des pages ------------------------------------------------------

def read_pages(exe: str, pdf: Path) -> list[str]:
    """Texte mis en page, une entrée par page physique (index 1 = page 1).

    `pdftotext` ouvre sa sortie par un saut de page : l'élément 0 est donc vide
    et l'indexation tombe naturellement en 1-based. Un éventuel élément vide
    final (saut de page de clôture) est retiré.
    """
    result = subprocess.run(
        [exe, "-layout", "-enc", "UTF-8", str(pdf), "-"],
        capture_output=True,
        check=True,
    )
    pages = result.stdout.decode("utf-8", errors="replace").split("\f")
    while len(pages) > 2 and not pages[-1].strip():
        pages.pop()
    return pages


PAGE_NUMBER = re.compile(r"^\s*(\d{1,3})\s*$")


def split_chrome(page: str) -> tuple[list[str], int | None]:
    """Sépare le corps de la page de son numéro imprimé.

    Retourne les lignes sans le numéro de pied (droites conservées telles
    quelles, l'indentation est un signal) et le numéro s'il y en a un.
    """
    lines = [line.rstrip() for line in page.split("\n")]
    while lines and not lines[-1].strip():
        lines.pop()
    number = None
    if lines:
        match = PAGE_NUMBER.match(lines[-1])
        if match:
            number = int(match.group(1))
            lines.pop()
    while lines and not lines[-1].strip():
        lines.pop()
    return lines, number


def measure_offset(pages: list[str]) -> int:
    """Décalage constant entre index physique et numéro imprimé.

    S'arrête si plusieurs décalages coexistent : c'est le garde-fou de la
    règle 2.
    """
    offsets: dict[int, list[int]] = {}
    for index, page in enumerate(pages):
        _, number = split_chrome(page)
        if number is not None:
            offsets.setdefault(index - number, []).append(index)
    if not offsets:
        sys.exit("Aucun numéro de page imprimé trouvé : pagination non reconnue.")
    dominant = max(offsets, key=lambda key: len(offsets[key]))
    if len(offsets) > 1:
        detail = ", ".join(
            f"{key:+d} sur {len(value)} pages (ex. {value[:4]})"
            for key, value in sorted(offsets.items())
        )
        sys.exit(
            "Décalage de pagination non constant — le livre serait tronqué en "
            f"silence. Décalages observés : {detail}"
        )
    print(
        f"  décalage de pagination : {dominant:+d} "
        f"(constant sur {len(offsets[dominant])} pages numérotées)"
    )
    return dominant


# --- Sommaire ---------------------------------------------------------------

# Un seul point suffit avant le numéro : le sommaire contient réellement
# « …géniteurs.129 ». Le titre est non-greedy pour ne pas avaler les points.
# Le filet qui sépare le titre du numéro n'est pas toujours en points :
# « PRÉAMBULE ____ 9 » porte des tirets bas, et c'est la forme du titre qui
# en décide, pas celle du filet.
TOC_ENTRY = re.compile(r"^(?P<title>.*?\S)\s*(?:\.+|_+)\s*(?P<page>\d{1,3})\s*$")
# Une entrée peut se passer de filet quand elle clôt la feuille : la retenir
# vaut mieux que de la jeter avec les lignes orphelines, mais elle est signalée.
TOC_ENTRY_BARE = re.compile(r"^(?P<title>.*?\S)\s{2,}(?P<page>\d{1,3})\s*$")
ROMAN = re.compile(r"^(?:I|II|III|IV|V|VI|VII|VIII|IX|X)\s*[./]")
ALPHA = re.compile(r"^[A-H]\s*[./]")
CHAPTER_HEAD = re.compile(r"^CHAPITRE\s+(\d+)\s*:\s*(.*)$")

# Titres que peut porter la feuille — `fold` a aplati les accents.
TOC_TITLES = frozenset({"SOMMAIRE", "TABLE DES MATIERES"})


def toc_level(title: str) -> int:
    """Niveau déduit du préfixe, pas de l'indentation.

    L'indentation du sommaire est irrégulière (« I. » tantôt à 2, tantôt à 3
    espaces) ; le préfixe, lui, est sûr — et son signe varie lui aussi : le
    pilote écrit « I. », l'Animalité « I/ ».
    """
    if ROMAN.match(title):
        return 1
    if ALPHA.match(title):
        return 2
    return 0


LABEL = re.compile(r"^((?:I|II|III|IV|V|VI|VII|VIII|IX|X|[A-H])[./])(?=\S)")


def normalize_title(title: str) -> str:
    """Rétablit l'espace après l'étiquette, que l'impression omet parfois.

    Le sommaire porte réellement « III.FAIRE LA VOLONTÉ DU SEIGNEUR » quand le
    corps imprime « III. FAIRE … ». La comparaison les plie de la même façon,
    mais c'est la forme du sommaire qui s'affiche : autant qu'elle soit lisible.
    """
    return LABEL.sub(r"\1 ", re.sub(r"\s{2,}", " ", title.strip()))


def parse_toc(
    pages: list[str], first: int
) -> tuple[list[tuple[str, int, int]], int]:
    """Entrées du sommaire : (titre, page imprimée, niveau), et dernière page lue.

    Une entrée peut courir sur plusieurs lignes, parfois séparées par une ligne
    vide : on accumule jusqu'à tomber sur le filet de conduite et le numéro.

    On suit les pages **tant qu'elles en livrent au moins une** : le pilote
    répète son titre sur chacune des siennes, l'Animalité ne le porte que sur
    la première — c'est la production d'entrées, pas le titre, qui dit où
    finit le sommaire. Une page sans entrée clôt le balayage, et la page
    retournée permet à l'appelant de savoir quelles pages sont du corps.
    """
    buffer: list[str] = []
    entries: list[tuple[str, int, int]] = []
    index = first
    last = first
    while index < len(pages):
        lines, _ = split_chrome(pages[index])
        body = [line.strip() for line in lines if line.strip()]
        # La première ligne de chaque page du sommaire est son propre titre.
        if body and fold(body[0]) in TOC_TITLES:
            body = body[1:]
        found = 0
        for line in body:
            buffer.append(line)
            match = TOC_ENTRY.match(" ".join(buffer))
            if match:
                title = normalize_title(match.group("title"))
                entries.append((title, int(match.group("page")), toc_level(title)))
                buffer = []
                found += 1
        if not found and entries:
            break
        last = index
        index += 1
    if buffer:
        # Une entrée sans filet, en pied de feuille : « Tableau d'aide   255 ».
        # Le numéro suffit à la désigner — à condition qu'il y en ait un, et
        # c'est la seule différence avec la forme filetée.
        bare = TOC_ENTRY_BARE.match(" ".join(buffer))
        if bare:
            title = normalize_title(bare.group("title"))
            entries.append((title, int(bare.group("page")), toc_level(title)))
            warn(f"sommaire : entrée sans filet, retenue — « {title} »")
        else:
            warn(f"sommaire : lignes non appariées, ignorées — {buffer}")
    return (
        [entry for entry in entries if fold(entry[0]) not in TOC_TITLES],
        last,
    )


# --- En-têtes courants ------------------------------------------------------

def header_candidates(chapters: list[tuple[str, int, int]]) -> list[str]:
    """Textes qu'un en-tête courant peut reprendre, pliés pour comparaison."""
    candidates: set[str] = set()
    for title, _, _ in chapters:
        candidates.add(fold(title))
        match = CHAPTER_HEAD.match(title)
        if match:
            candidates.add(fold(f"CHAPITRE {match.group(1)}"))
            candidates.add(fold(match.group(2)))
        if ":" in title:
            head, tail = title.split(":", 1)
            candidates.add(fold(head))
            candidates.add(fold(tail))
    return [candidate for candidate in candidates if len(candidate) >= 6]


MIN_HEADER_INDENT = 1
# Un fragment de titre ne finit jamais sur un point : une fin de phrase en haut
# de page est du corps, même quand son texte est, par accident, un titre connu.
SENTENCE_END = re.compile(r"\.\s*$")


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def strip_headers(lines: list[str], candidates: list[str]) -> list[str]:
    """Retire les blocs de titre et d'en-tête courant en tête de page.

    L'unité est le **bloc** — les lignes consécutives jusqu'à la ligne vide —
    jamais la ligne seule : un titre tient sur une ligne (en-tête courant), deux
    (« LA FAUSSE IDÉE QUE BEAUCOUP » / « ONT DU MINISTÈRE ») ou trois, et
    « QUE PRÉFÈRES-TU ? » seul n'est le préfixe de rien. C'est l'accumulation
    des blocs retirés qui est comparée au sommaire, ce qui permet d'enchaîner
    « CHAPITRE 4 » puis son titre.

    Deux garde-fous contre l'ingestion de corps de texte, car un bas de
    paragraphe peut se trouver en haut de page :

    - le bloc est centré, c'est-à-dire qu'au moins une de ses lignes est
      indentée. Le test porte sur le **maximum** du bloc, pas sur sa première
      ligne : la ligne la plus large d'un titre centré tombe elle-même colonne
      0. Une seule dérogation, pour l'en-tête courant le plus large du livre,
      qui tient sur une ligne et n'a plus de marge du tout : une ligne unique
      **sans aucune minuscule** est un en-tête, pas une fin de phrase.
    - un préfixe strict ne vaut que si le bloc ne finit pas sur un point ; une
      égalité exacte avec un titre connu, elle, suffit.
    """
    result = list(lines)
    accumulated = ""
    while True:
        start = next((i for i, line in enumerate(result) if line.strip()), None)
        if start is None:
            break
        end = start
        while end < len(result) and result[end].strip():
            end += 1
        block = result[start:end]
        text = join_lines(block)
        centred = max(indent_of(line) for line in block) >= MIN_HEADER_INDENT
        if not centred and not (len(block) == 1 and not any(c.islower() for c in text)):
            break
        probe = f"{accumulated} {fold(text)}".strip()
        if len(probe) < 6:
            break
        if probe not in candidates and not (
            any(candidate.startswith(f"{probe} ") for candidate in candidates)
            and not SENTENCE_END.search(text)
        ):
            break
        accumulated = probe
        del result[:end]
    while result and not result[0].strip():
        result.pop(0)
    return result


# --- Notes de bas de page ---------------------------------------------------

NOTE_START = re.compile(r"^(\d{1,2})\s+(\S.*)$")


def marker_present(body: str, number: int) -> bool:
    """Le numéro apparaît-il isolément dans le corps de la page ?

    Garde-fou contre un bloc de fin de page qui serait du texte courant
    commençant par un chiffre : sans marqueur, ce n'est pas une note.
    """
    return re.search(r"(?<!\d)%d(?!\d)" % number, body) is not None


def take_footnotes(
    lines: list[str], expected: int
) -> tuple[list[str], dict[int, str], int]:
    """Détache le bloc de notes du bas de page.

    Le bloc commence à la **dernière** ligne qui s'ouvre sur le numéro attendu
    (règle 3) ; tout ce qui suit lui appartient. On cherche depuis le bas pour
    qu'un chiffre identique présent dans le corps ne vole pas l'ancre.
    """
    start = None
    for index in range(len(lines) - 1, -1, -1):
        match = NOTE_START.match(lines[index].strip())
        if match and int(match.group(1)) == expected:
            start = index
            break
    if start is None:
        return lines, {}, expected

    # Un bloc de notes est isolé du corps par un blanc. Un paragraphe qui
    # commence par « 1 Timotheos 3:9) … » remplit la même forme que l'appel —
    # un chiffre, une espace, du texte — et la comptabilité seule ne tranche
    # pas : c'est le blanc au-dessus qui dit que l'imprimeur a isolé la note.
    if start == 0 or lines[start - 1].strip():
        warn(
            f"bloc commençant par « {expected} » sans ligne vide au-dessus : "
            "traité comme du texte, pas comme une note"
        )
        return lines, {}, expected

    body = " ".join(lines[:start])
    if not marker_present(body, expected):
        warn(
            f"bloc commençant par « {expected} » sans marqueur dans la page : "
            "traité comme du texte, pas comme une note"
        )
        return lines, {}, expected

    notes: dict[int, str] = {}
    current = expected
    buffer: list[str] = []
    for line in lines[start:]:
        stripped = line.strip()
        if not stripped:
            continue  # le bloc de la note 25 contient une ligne vide interne
        match = NOTE_START.match(stripped)
        if match and int(match.group(1)) == current and not buffer:
            buffer = [match.group(2)]
        elif match and int(match.group(1)) == current + 1:
            notes[current] = " ".join(buffer)
            current += 1
            buffer = [match.group(2)]
        else:
            buffer.append(stripped)
    if buffer:
        notes[current] = " ".join(buffer)
        current += 1
    return lines[:start], notes, current


# --- Assemblage des blocs ---------------------------------------------------

BULLET = re.compile(r"^\s*•\s*(.*)$")
HYPHEN_BREAK = re.compile(r"(\w)-$")


def join_lines(lines: list[str]) -> str:
    """Recolle des lignes coupées dur en un paragraphe.

    Une ligne qui finit par un tiret est recollée **sans perdre le tiret** : le
    livre ne césure pas, il ne coupe qu'aux mots composés. Les 22 coupures du
    pilote le disent toutes — « eux-mêmes », « ci-dessus », « Saint-Esprit »,
    « au-devant », « temps-ci », « taisez-vous », « 6:17-18 ». Retirer ce tiret
    produisait « cidessus » et « audevant » : une corruption silencieuse du
    texte imprimé, ce que ce dossier ne fait jamais. Si un livre césure
    vraiment, le tiret restera visible — un artefact qu'on voit, pas un mot
    qu'on abîme.

    Aucune espace n'est retirée devant la ponctuation (règle 5).
    """
    text = ""
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not text:
            text = stripped
        elif HYPHEN_BREAK.search(text):
            text = text + stripped
        else:
            text = f"{text} {stripped}"
    return re.sub(r"[ \t]{2,}", " ", text).strip()


QUOTE_OPEN = "\u00ab"
QUOTE_CLOSE = "\u00bb"
# Une référence biblique en fin de citation : « … » 1 Corinthiens 9:16
REFERENCE_TAIL = re.compile(
    r"^(?P<ref>(?:[1-3]\s+)?[A-ZÉÈÀÎÔÛ][^,;:]{2,40}?\s+\d{1,3}\s*[:.]\s*\d[\d\-,\s:]*)$"
)


TERMINAL = re.compile(r"[.!?:;»]\s*$")
# La référence qui clôt une citation tient sa propre ligne et finit sur un
# chiffre : « 1 Corinthiens 12:1-11 », « Apokalupsis (Apocalypse) 3:14-22 ».
REFERENCE_END = re.compile(r"\d{1,3}\s*:\s*\d{1,3}(?:\s*[-,:]\s*\d{1,3})*\s*\)?$")


def trim_blanks(lines: list[str]) -> list[str]:
    """Retire les lignes vides des deux bouts, sans toucher à l'intérieur."""
    start = next((i for i, line in enumerate(lines) if line.strip()), None)
    if start is None:
        return []
    end = next(i for i in range(len(lines) - 1, -1, -1) if lines[i].strip())
    return lines[start : end + 1]


def ends_block(line: str) -> bool:
    """Cette ligne peut-elle être la dernière d'un bloc ?

    La ponctuation finale ne suffit pas : une citation se termine sur sa
    référence, qui n'en porte aucune. Page 41 du pilote, le titre
    « 2.3. Le caractère » suivait « 1 Corinthiens 12:1-11 » et s'y voyait
    recollé ; page 106, c'était le premier paragraphe de la page suivante. Les
    deux frontières se lisent sur la page — une référence biblique en fin de
    ligne — et les trois passes qui décident d'un recollement la lisent donc
    ici.
    """
    return bool(TERMINAL.search(line) or REFERENCE_END.search(line))


def paragraph_groups(lines: list[str]) -> list[list[str]]:
    """Découpe en paragraphes sur les lignes vides — avec une exception.

    `pdftotext` insère une ligne vide dès que l'interligne s'élargit. Cela
    arrive **au milieu** d'un bloc centré qui se replie :

        • La vie de prière et d'intercession par   (indenté de 5)
                                                   (ligne vide)
             l'Esprit,                             (indenté de 10)

    et aussi au milieu d'un paragraphe ordinaire, quand le document lui donne
    un interligne plus large que le reste — page 18 du pilote, dont les neuf
    lignes du premier paragraphe sont toutes séparées d'une ligne vide, toutes
    colonne 0, toutes justifiées.

    Une ligne vide n'est donc pas toujours une fin de paragraphe. La
    continuation se reconnaît ici à deux signes conjoints : la ligne d'avant n'a
    pas de ponctuation finale, et la ligne d'après est **plus indentée**. Le cas
    du paragraphe entièrement interligné, lui, est traité par
    `merge_justified_runs` : il demande de voir le train de blocs, pas une seule
    frontière. Sans cette exception-ci, un item de liste sur deux était tronqué
    et les intertitres arrivaient coupés en deux (« I. LE MINISTÈRE, QU'EST-CE »
    / « QUE C'EST ? »).
    """
    groups: list[list[str]] = []
    current: list[str] = []
    index = 0
    while index < len(lines):
        if lines[index].strip():
            current.append(lines[index])
            index += 1
            continue
        following = next(
            (i for i in range(index, len(lines)) if lines[i].strip()), None
        )
        if (
            current
            and following is not None
            and not ends_block(current[-1])
            and indent_of(lines[following]) > indent_of(current[-1])
            and not BULLET.match(lines[following])
        ):
            index = following
            continue
        if current:
            groups.append(current)
            current = []
        index += 1
    if current:
        groups.append(current)
    return groups


# Un sous-titre numéroté que le sommaire n'annonce pas : « 2.1. L'onction »,
# « 1. Les anciens ». Il est court — et centré chez le pilote, colonne 0 chez
# l'Animalité, qui n'imprime ses rangs 3 qu'en gras : la longueur fait la
# démarcation, pas l'indentation.
NUMBERED_HEADING = re.compile(r"^\d+(?:\.\d+)*\.\s*\S")
TRAILING_MARKER = re.compile(r"\d+$")

MAX_HEADING_CHARS = 70


def numbered_heading(group: list[str]) -> bool:
    """Ce groupe est-il un sous-titre numéroté court (« 1. L'intelligence ») ?

    Seuls garde-fous : la longueur, et le fait que le groupe **commence** par
    le numéro — un paragraphe de corps qui s'ouvrirait sur « 1. » pèse bien
    plus de 70 caractères, un titre non. Sert deux fois : à le rendre
    incompatible avec les passes de recollage, et à le classer en niveau 3.
    """
    text = join_lines(group)
    return len(text) < MAX_HEADING_CHARS and bool(NUMBERED_HEADING.match(text.strip()))


def heading_like(group: list[str], headings: dict[str, int]) -> bool:
    """Ce groupe peut-il être un titre, entier ou commencé ?

    Quatre façons de l'être : porter exactement un titre du sommaire, en être
    le début, être numéroté, ou n'avoir aucune minuscule — une ligne tout en
    capitales n'est jamais de la prose. Sert à protéger les titres des passes
    de recollage.
    """
    probe = heading_probe([group])
    if not probe:
        return False
    if probe in headings or any(key.startswith(f"{probe} ") for key in headings):
        return True
    if numbered_heading(group):
        return True
    text = join_lines(group)
    return not any(character.islower() for character in text)


def merge_justified_runs(
    groups: list[list[str]], headings: dict[str, int]
) -> list[list[str]]:
    """Recolle un paragraphe dont chaque ligne est devenue un bloc.

    Quand le document donne à un paragraphe un interligne plus large que le
    reste, `pdftotext` sépare **chacune** de ses lignes par une ligne vide — la
    page 18 du pilote en donne huit d'affilée, toutes colonne 0 :

        communiquer sa pensée et sa torah 7 morale à
                                              (ligne vide)
        Moshé, son messager. Dans la confirmation des
                                              (ligne vide)
        mitsvot8 reçus, le prophète du Seigneur dira à

    Ni l'indentation ni la marge droite ne distinguent ces lignes d'une fin de
    paragraphe : c'est le **train** qui les trahit. On ne recolle donc que des
    blocs d'une seule ligne consécutifs, de même indentation, dont le précédent
    n'a pas de ponctuation finale — un paragraphe ordinaire, lui, arrive en bloc
    solide de plusieurs lignes et n'entre jamais dans cette passe.

    Les titres en sont tenus à l'écart par `heading_like` : « I. D'ABORD
    L'ADORATION » est, lui aussi, un bloc d'une seule ligne sans ponctuation
    finale.
    """
    result: list[list[str]] = []
    run = False
    for group in groups:
        if (
            run
            and len(group) == 1
            and not ends_block(result[-1][-1])
            and indent_of(group[0]) == indent_of(result[-1][-1])
            and not BULLET.match(group[0])
            and not heading_like(result[-1], headings)
            and not heading_like(group, headings)
        ):
            result[-1].extend(group)
            continue
        result.append(list(group))
        run = len(group) == 1
    return result


def heading_probe(groups: list[list[str]]) -> str:
    """Texte plié d'un ou plusieurs groupes, prêt à être comparé au sommaire."""
    lines = [line for group in groups for line in group]
    return fold(TRAILING_MARKER.sub("", join_lines(lines)))


MAX_HEADING_GROUPS = 5
MAX_HEADING_LINES = 5


def split_trailing_headings(
    groups: list[list[str]], headings: dict[str, int]
) -> list[list[str]]:
    """Détache l'intertitre collé à la fin du bloc qui le précède.

    `pdftotext` n'insère pas toujours de ligne vide avant un titre : le corps
    court colonne 0 et le titre se retrouve dans le même bloc, en queue, trahi
    par son indentation :

        d'Elohîm. Et personne n'osait plus l'interroger.      (0)
                      Markos (Marc) 12:30-34                  (5)
                        III. FAIRE LA VOLONTÉ DU SEIGNEUR     (16)

    On essaie donc les suffixes du bloc, du plus court au plus long, et on
    coupe sur le plus long qui tombe **exactement** sur un titre du sommaire,
    à condition que la ligne de coupe soit plus indentée que celle d'avant —
    sans quoi un paragraphe qui commence par les mots d'un titre (« La
    traitrise, la trahison est devenue… ») se ferait couper en deux.
    """
    result: list[list[str]] = []
    for group in groups:
        split = None
        for count in range(1, min(MAX_HEADING_LINES, len(group) - 1) + 1):
            start = len(group) - count
            if indent_of(group[start]) <= indent_of(group[start - 1]):
                continue
            if heading_probe([group[start:]]) in headings:
                split = start
        if split is None:
            result.append(group)
            continue
        result.append(group[:split])
        result.append(group[split:])
    return result


def merge_split_headings(
    groups: list[list[str]], headings: dict[str, int]
) -> list[list[str]]:
    """Recolle un intertitre que `pdftotext` a éclaté en plusieurs groupes.

    Un titre centré sur plusieurs lignes se voit parfois intercaler une ligne
    vide **entre chacune** de ses lignes, l'interligne s'élargissant :

        I.  COMMENT RECONNAITRE
                                      (ligne vide)
            LES FRUITS ET LE CŒUR
                                      (ligne vide)
            EN QUÊTE DE
                                      (ligne vide)
            LÉGITIMITÉ ?

    L'indentation ne permet pas de le voir (ici 0, 4, 4, 4 : la continuation
    n'est pas toujours plus indentée que la précédente). C'est donc le sommaire
    qui tranche, comme pour tout le reste : on agrège tant que l'accumulation
    reste le préfixe d'un titre annoncé, et on ne fusionne que si elle finit par
    tomber **exactement** sur ce titre. Un paragraphe de corps rompt le préfixe
    dès le premier mot, ce qui rend la boucle inoffensive.
    """
    merged: list[list[str]] = []
    index = 0
    while index < len(groups):
        span = heading_span(groups, index, headings)
        if span is None:
            merged.append(groups[index])
            index += 1
            continue
        merged.append([line for group in groups[index:span] for line in group])
        index = span
    return merged


def heading_span(
    groups: list[list[str]], index: int, headings: dict[str, int]
) -> int | None:
    """Indice de fin des groupes à recoller pour retomber sur un titre annoncé.

    `None` dès que l'accumulation cesse d'être un préfixe — et aussi quand le
    premier groupe est déjà un titre entier : il n'y a alors rien à recoller, et
    `match_heading` le reconnaîtra seul.
    """
    limit = min(index + MAX_HEADING_GROUPS, len(groups))
    for end in range(index + 1, limit + 1):
        probe = heading_probe(groups[index:end])
        if not probe:
            return None
        if probe in headings:
            return end if end > index + 1 else None
        if not any(key.startswith(f"{probe} ") for key in headings):
            return None
    return None


def match_heading(group: list[str], headings: dict[str, int]) -> int | None:
    """Niveau du titre si ce groupe de lignes en est un, sinon None.

    Les intertitres sont reconnus **par le sommaire** : on compare le groupe
    replié à la liste des titres annoncés. Un titre peut courir sur deux lignes
    (« C. Le dépouillement du vieil / homme : la corruption adamique ») et
    porter un marqueur de note collé (« C. Le service évangélique31 »), d'où le
    retrait des chiffres de queue avant comparaison.

    Les sous-titres numérotés absents du sommaire sont rendus au niveau 3.
    """
    level = headings.get(heading_probe([group]))
    if level is not None:
        return level
    if numbered_heading(group):
        return 3
    return None


def split_quote(text: str) -> tuple[str, str | None]:
    """Isole la référence qui suit le guillemet fermant d'une citation.

    Elle s'écrit nue (« … » Loukas (Luc) 16:13 ») ou entre parenthèses — et le
    pilote en imprime une dont la parenthèse fermante manque, page 155 :
    « (Mattithyah (Matthieu) 18:20 ». Les parenthèses sont donc retirées des
    deux bouts avant comparaison, sans exiger qu'elles s'apparient.
    """
    end = text.rfind(QUOTE_CLOSE)
    if end < 0:
        return text, None
    tail = text[end + 1 :].strip(" .()")
    if not tail:
        return text, None
    match = REFERENCE_TAIL.match(tail)
    if not match:
        return text, None
    return text[: end + 1].strip(), match.group("ref").strip()


def close_quotes(blocks: list[dict[str, object]]) -> list[dict[str, object]]:
    """Recolle une citation que le saut de page a coupée avant son fermant.

    Le guillemet ouvrant sans fermant est une preuve imprimée : la citation
    n'est pas finie. Page 35 du pilote, elle s'arrête sur « en vous » et
    reprend page 36 sur « séparant des idoles » ; ailleurs, la coupure tombe
    après un point (« … de nourriture solide. » / « Car quiconque participe au
    lait … » Hébreux 5:12-14 »), et la règle de jonction des pages, qui lit la
    ponctuation, ne pouvait pas la voir.

    On ne recolle que de la prose — jamais un titre ni un item de liste : une
    citation inachevée en fin de chapitre doit rester inachevée plutôt que
    d'avaler la suite du livre.
    """
    merged: list[dict[str, object]] = []
    for block in blocks:
        text = str(block.get("text", ""))
        if (
            merged
            and merged[-1]["type"] == "quote"
            and "reference" not in merged[-1]
            and block["type"] in ("p", "quote")
            and str(merged[-1]["text"]).count(QUOTE_OPEN)
            > str(merged[-1]["text"]).count(QUOTE_CLOSE)
        ):
            joined = f"{merged[-1]['text']} {text}".strip()
            body, reference = split_quote(joined)
            merged[-1]["text"] = body
            if reference:
                merged[-1]["reference"] = reference
            continue
        merged.append(block)
    return merged


def split_leading_heading(group: list[str]) -> tuple[list[str] | None, list[str]]:
    """Détache le sous-titre numéroté qui ouvre un bloc, s'il y en a un.

    L'Animalité imprime son rang 3 **collé** à son paragraphe, sans ligne vide
    entre les deux — là où le pilote les sépare :

        1. L'esprit du chrétien est né d'en haut
        Avant la conversion, l'esprit est mort …

    Une césure imprimée appartient au titre (« l'Anti- » / « chrétien ») : on
    recolle comme `join_lines`, tant que la somme reste sous la longueur d'un
    titre. Le corps reprend à la première ligne qui ne se recolle pas — un
    paragraphe ne tient jamais en une ligne de titre.
    """
    if len(group) < 2 or not NUMBERED_HEADING.match(group[0].strip()):
        return None, group
    # Un bloc qui tient entier dans la marge d'un titre l'est déjà : le pilote
    # imprime « 2.4. Les moyens accordés pour faire / l'Œuvre du service » sur
    # deux lignes, sans corps dessous. Le couper ne ferait qu'écarter la
    # seconde moitié du titre dans un paragraphe orphelin.
    if len(join_lines(group)) < MAX_HEADING_CHARS:
        return None, group
    take = 1
    while take < len(group):
        if len(join_lines(group[: take + 1])) >= MAX_HEADING_CHARS:
            break
        if not HYPHEN_BREAK.search(join_lines(group[:take])):
            break
        take += 1
    if take >= len(group):
        return None, group
    return group[:take], group[take:]


def build_blocks(
    lines: list[str], headings: dict[str, int]
) -> list[dict[str, object]]:
    """Transforme les lignes d'un chapitre en blocs typés."""
    blocks: list[dict[str, object]] = []
    groups = merge_justified_runs(paragraph_groups(lines), headings)
    groups = split_trailing_headings(groups, headings)
    for group in merge_split_headings(groups, headings):
        opening, group = split_leading_heading(group)
        if opening is not None:
            # `match_heading` ne peut pas rendre None ici — `opening` s'ouvre
            # sur un numéro, donc sur un titre. Un avenir où il rendrait None
            # retomberait en titre de rang 3 : jamais en silence, le texte
            # d'un livre ne se fait pas avaler par un garde-fou.
            level = match_heading(opening, headings)
            blocks.append(
                {
                    "type": f"h{(3 if level is None else level) + 1}",
                    "text": join_lines(opening),
                }
            )
        level = match_heading(group, headings)
        if level is not None:
            blocks.append(
                {"type": f"h{level + 1}", "text": join_lines(group)}
            )
            continue
        # Une puce ouvre un item ; les lignes suivantes indentées lui appartiennent.
        if any(BULLET.match(line) for line in group):
            current: list[str] = []
            for line in group:
                bullet = BULLET.match(line)
                if bullet:
                    if current:
                        blocks.append({"type": "li", "text": join_lines(current)})
                    current = [bullet.group(1)]
                elif current:
                    current.append(line)
            if current:
                blocks.append({"type": "li", "text": join_lines(current)})
            continue
        text = join_lines(group)
        if not text:
            continue
        if text.startswith(QUOTE_OPEN):
            body, reference = split_quote(text)
            block: dict[str, object] = {"type": "quote", "text": body}
            if reference:
                block["reference"] = reference
            blocks.append(block)
            continue
        blocks.append({"type": "p", "text": text})
    return close_quotes(blocks)


# --- Marqueurs de notes -----------------------------------------------------

WORD_BEFORE = re.compile(r"([\w'\u2019\u2010-\u2015\-]+)[^\w]*$")


def marker_patterns(number: int) -> list[re.Pattern[str]]:
    """Les deux formes réelles du marqueur, de la plus sûre à la moins sûre.

    Collé au mot qui précède (« Hava1 », « [abad]4 », « prière du salut »22,
    « Yéhoshoua,39 ») puis séparé d'une espace (« Yaacov 3 »,
    « [apostolos] 29 »). Le caractère précédent n'est pas forcément une lettre :
    l'auteur écrit ses translittérations entre crochets et ses citations entre
    guillemets, et le marqueur se pose après la ponctuation.

    Les gardes écartent les références bibliques, qui sont du chiffre partout :
    le marqueur ne peut ni toucher un chiffre, ni suivre un « : » ou un tiret
    (« 3:10-12 » ne doit pas livrer les notes 10 et 12), ni précéder « : » ou une
    plage. La forme espacée exige en plus de ne pas être suivie d'une majuscule,
    sans quoi « … » 1 Corinthiens 9:16 » offrirait son « 1 » à la note 1.
    """
    head = r"(?<=[^\s\d])(?<![:\-\u2013\u2014])"
    tail = r"(?![\d:\u2013\u2014])(?!-\d)"
    return [
        re.compile(r"%s%d%s" % (head, number, tail)),
        re.compile(r"%s %d%s(?!\s+[A-Z\u00c0-\u00dd])" % (head, number, tail)),
    ]


def glued_notes(
    blocks: list[dict[str, object]], notes: dict[int, str]
) -> set[int]:
    """Notes dont le marqueur est collé à un mot quelque part dans le chapitre.

    Le marqueur s'écrit de deux façons — collé (« Moshé5 ») ou séparé d'une
    espace (« [apostolos] 29 ») — et la forme séparée est la plus faible : un
    « ce verset 5 » lui ressemble. Repérer d'abord, sur tout le chapitre, les
    notes qui existent sous la forme collée permet de **leur interdire** la
    forme séparée, au lieu de laisser le premier bloc venu emporter le numéro.
    """
    found: set[int] = set()
    for number in notes:
        pattern = marker_patterns(number)[0]
        if any(pattern.search(str(block.get("text", ""))) for block in blocks):
            found.add(number)
    return found


def attach_notes(
    block: dict[str, object], notes: dict[int, str], used: set[int],
    glued: set[int] = frozenset(),
) -> None:
    """Retire les marqueurs du texte et pose les notes à leur place.

    Les marqueurs sont d'abord tous repérés, puis retirés en une seule passe de
    gauche à droite : `position` se lit alors sur le texte final, au lieu de
    glisser à chaque suppression. La note est rattachée au mot qui précédait son
    marqueur, ponctuation intermédiaire ignorée.

    `glued` porte les numéros vus collés à un mot ailleurs dans le chapitre :
    ceux-là refusent la forme séparée, qui aurait pu les capturer plus tôt sur
    un faux positif (« ce verset 5 » contre « Moshé5 »).
    """
    text = str(block.get("text", ""))
    if not text or not notes:
        return

    markers: list[tuple[int, int, int]] = []
    for number in sorted(notes):
        if number in used:
            continue
        patterns = marker_patterns(number)
        if number in glued:
            patterns = patterns[:1]
        for pattern in patterns:
            hit = next(
                (
                    match
                    for match in pattern.finditer(text)
                    if not any(
                        start <= match.start() < end for start, end, _ in markers
                    )
                ),
                None,
            )
            if hit is not None:
                markers.append((hit.start(), hit.end(), number))
                break
    if not markers:
        return
    markers.sort()

    result = ""
    cursor = 0
    attached: list[dict[str, object]] = []
    for start, end, number in markers:
        result += text[cursor:start]
        cursor = end
        before = WORD_BEFORE.search(result)
        if before is None:
            warn(f"note {number} : aucun mot avant le marqueur — note écartée")
            continue
        attached.append(
            {
                "word": before.group(1),
                "position": before.start(1),
                "note": notes[number],
            }
        )
        used.add(number)
    result += text[cursor:]

    block["text"] = result
    if not attached:
        return
    # Invariant exigé par note_aware_text.dart.
    for note in list(attached):
        start = int(note["position"])
        word = str(note["word"])
        if result[start : start + len(word)] != word:
            warn(f"position incohérente pour « {word} » — note écartée")
            attached.remove(note)
    if attached:
        block["notes"] = attached
        block["textWithNotes"] = with_notes(result, attached)


def with_notes(text: str, notes: list[dict[str, object]]) -> str:
    """Texte avec chaque note entre [crochets] après son mot (convention BYM)."""
    result = ""
    cursor = 0
    for note in notes:
        end = int(note["position"]) + len(str(note["word"]))
        result += text[cursor:end] + f" [{note['note']}]"
        cursor = end
    return result + text[cursor:]


# --- Tableau des noms (coordonnées) -----------------------------------------

def name_table(pdf: Path, marker: str) -> list[tuple[str, str]] | None:
    """Reconstruit un tableau à 4 colonnes par abscisse de mot.

    `pdftotext -layout` entrelace les colonnes de droite de travers (il apparie
    « Shemouél » à « Simon » au lieu de « Samuel ») ; seules les coordonnées
    disent la vérité. Retourne None si l'appariement n'est pas net, pour que
    l'appelant garde le texte brut (règle 6).
    """
    try:
        from pypdf import PdfReader
    except ImportError:
        warn("pypdf absent : tableau des noms laissé en texte brut")
        return None

    reader = PdfReader(str(pdf))
    # Depuis la fin : le sommaire mentionne lui aussi « Tableau des noms » dans
    # ses entrées, et c'est l'annexe qu'on veut, pas sa ligne de sommaire.
    page = None
    for candidate in reversed(reader.pages):
        if marker in (candidate.extract_text() or ""):
            page = candidate
            break
    if page is None:
        warn(f"page « {marker} » introuvable : tableau laissé en texte brut")
        return None

    words: list[tuple[float, float, str]] = []

    def visit(text, cm, tm, font, size):  # noqa: ANN001 - signature imposée
        stripped = text.strip()
        if stripped:
            words.append((round(tm[4], 1), round(tm[5], 1), stripped))

    page.extract_text(visitor_text=visit)
    if not words:
        warn("aucun mot localisé dans le tableau : texte brut conservé")
        return None

    anchors = column_anchors(words)
    if len(anchors) != 4:
        warn(f"{len(anchors)} colonnes détectées au lieu de 4 : texte brut conservé")
        return None

    rows: list[list[str]] = []
    for _, group in cluster_rows(words, 2.0):
        cells = ["", "", "", ""]
        for x, _, text in sorted(group):
            # À l'ancre la **plus proche**, pas à la dernière ancre inférieure :
            # « Jér » commence à x=210.7, une fraction de point à gauche de son
            # ancre 211.1, et tomberait sinon dans la colonne précédente.
            index = min(range(4), key=lambda i: abs(anchors[i] - x))
            # Sans séparateur : une cellule à plusieurs fragments est une
            # coupure d'encodage, pas une suite de mots. pypdf livre les espaces
            # réelles **dans** le fragment (« Hava ou » en est un seul), donc
            # « È »+« ve » fait « Ève » et « Y »+« erusha »+« layim » fait
            # « Yerushalayim ».
            cells[index] += text
        if all(not cell for cell in cells):
            continue
        # Le pied de page tombe dans une colonne comme n'importe quel mot.
        if re.fullmatch(r"\d{1,3}", "".join(cells).strip()):
            continue
        rows.append(cells)

    # Le titre de l'annexe est une ligne à une cellule : on n'entre dans le
    # tableau qu'à la première ligne complète.
    while rows and sum(1 for cell in rows[0] if cell) < 4:
        rows.pop(0)

    merged: list[list[str]] = []
    for cells in rows:
        if sum(1 for cell in cells if cell) == 4 or not merged:
            merged.append(cells)
            continue
        # Ligne de continuation (« Chavvah » sous « Hava ou », « Mashiah »
        # /« Christ » sous « Yéhoshoua »/« Jésus ») : elle prolonge la cellule
        # du dessus — et là, c'est bien un mot de plus, donc une espace.
        for index, cell in enumerate(cells):
            if cell:
                merged[-1][index] = f"{merged[-1][index]} {cell}".strip()

    left = [(row[0], row[1]) for row in merged if row[0] and row[1]]
    right = [(row[2], row[3]) for row in merged if row[2] and row[3]]
    if not left or len(left) != len(right):
        warn(
            f"appariement douteux ({len(left)} paires à gauche, {len(right)} à "
            "droite) : texte brut conservé"
        )
        return None
    return left + right


def column_anchors(words: list[tuple[float, float, str]]) -> list[float]:
    """Abscisses des colonnes, lues sur la fréquence des débuts de cellule.

    Les cellules sont alignées à gauche : l'abscisse d'une colonne est donc
    celle qui revient à chaque ligne (×18 ici), quand les fragments internes
    n'apparaissent qu'une fois. Regrouper des abscisses proches ne marcherait
    pas — un fragment peut tomber à 4 points de son ancre.
    """
    counts: dict[float, int] = {}
    for x, _, _ in words:
        counts[x] = counts.get(x, 0) + 1
    if not counts:
        return []
    floor = max(2, max(counts.values()) // 4)
    return sorted(x for x, count in counts.items() if count >= floor)


def cluster_rows(
    words: list[tuple[float, float, str]], tolerance: float
) -> list[tuple[float, list[tuple[float, float, str]]]]:
    """Regroupe les mots en lignes par ordonnée (tolérance : lignes décalées)."""
    rows: list[tuple[float, list[tuple[float, float, str]]]] = []
    for word in sorted(words, key=lambda item: -item[1]):
        if rows and abs(rows[-1][0] - word[1]) <= tolerance:
            rows[-1][1].append(word)
        else:
            rows.append((word[1], [word]))
    return rows


# --- Métadonnées ------------------------------------------------------------

ISBN = re.compile(r"ISBN\s*:\s*([\d\-]+)")
COPYRIGHT = re.compile(
    "©" + r"\s*(?P<year>\d{4})?\s*,?\s*(?P<publisher>\S[^\n]*?)\s*,?\s*$"
)
# Étiquettes qui ouvrent une mention d'édition sans en être une : le nom
# d'éditeur vient après les deux-points.
PUBLISHER_LABEL = re.compile(r"^(?:é|e)dition\s*:\s*", re.IGNORECASE)


def metadata(pages: list[str]) -> dict[str, str]:
    """Titre, sous-titre, auteur, éditeur, année et ISBN des pages de garde.

    La page de titre se lit par **blocs** — une suite de lignes fermée par une
    ligne vide — et non par ses numéros de ligne : le titre tient sur deux
    lignes chez l'Animalité (« L'ANIMALITÉ DE » / « L'ÊTRE HUMAIN »), qui
    met l'auteur dans le bloc suivant, où l'éditeur l'attend déjà ; le pilote
    plie son titre en deux lignes puis sépare l'auteur d'une ligne vide. Un
    bloc de titre à trois lignes porte son auteur en dernière ligne.
    """
    front = "\n".join(pages[1 : min(4, len(pages))])
    blocks: list[list[str]] = [[]]
    for line in pages[1].split("\n"):
        stripped = line.strip()
        if stripped:
            blocks[-1].append(stripped)
        elif blocks[-1]:
            blocks.append([])
    if blocks and not blocks[-1]:
        blocks.pop()
    data: dict[str, str] = {}
    if blocks:
        data["title"] = blocks[0][0].rstrip(",")
        if len(blocks[0]) > 1:
            data["subtitle"] = blocks[0][1]
        if len(blocks[0]) > 2:
            data["author"] = blocks[0][-1]
        elif len(blocks) > 1:
            data["author"] = blocks[1][0]
    match = ISBN.search(front)
    if match:
        data["isbn"] = match.group(1)
    for line in front.split("\n"):
        # La ligne de copyright porte l'ann\u00e9e **et** l'\u00e9diteur, s\u00e9par\u00e9s par une
        # virgule et suivis d'une autre : \u00ab \u00a9 2024, Vases de Terre les
        # \u00c9ditions, \u00bb. Tout hard-coder sur un \u00e9diteur rendrait le script
        # inutilisable sur les 44 autres titres.
        found = COPYRIGHT.search(line.strip())
        if found:
            publisher = found.group("publisher").rstrip(",").strip()
            # « © 2022 Édition : ANJC PRODUCTIONS » : « Édition : » est une
            # étiquette, pas un nom. Le pilote n'en porte pas, la règle ne
            # lui change donc rien.
            publisher = PUBLISHER_LABEL.sub("", publisher).strip()
            data["publisher"] = publisher
            if found.group("year"):
                data["year"] = found.group("year")
            break
    for key in ("title", "author", "publisher"):
        if not data.get(key):
            warn(f"métadonnée absente des pages de garde : {key}")
    return data


# --- Conversion -------------------------------------------------------------

def convert(pdf: Path, code: str) -> dict[str, object]:
    exe = find_pdftotext()
    pages = read_pages(exe, pdf)
    print(f"  {len(pages) - 1} pages physiques lues")

    offset = measure_offset(pages)

    # Le sommaire : la première page qui en porte le titre, quel qu'il soit.
    toc_first = next(
        (
            index
            for index, page in enumerate(pages)
            if any(
                fold(line) in TOC_TITLES
                for line in page.split("\n")[:3]
                if line.strip()
            )
        ),
        None,
    )
    if toc_first is None:
        sys.exit("Aucune page de sommaire trouvée : structure non reconnue.")
    entries, toc_last = parse_toc(pages, toc_first)
    chapters_toc = [entry for entry in entries if entry[2] == 0]
    print(f"  sommaire : {len(entries)} entrées, {len(chapters_toc)} de niveau 0")

    headings = {fold(title): level for title, _, level in entries if level > 0}
    candidates = header_candidates(chapters_toc)

    # Bornes de chaque chapitre, en index physiques.
    bounds: list[tuple[str, int, int]] = []
    for position, (title, printed, _) in enumerate(chapters_toc):
        start = printed + offset
        if position + 1 < len(chapters_toc):
            end = chapters_toc[position + 1][1] + offset - 1
        else:
            end = len(pages) - 1
        bounds.append((title, start, end))

    expected = 1
    notes_by_page: dict[int, dict[int, str]] = {}
    body_by_page: dict[int, list[str]] = {}
    empty_pages: list[int] = []

    for index in range(toc_last + 1, len(pages)):
        lines, _ = split_chrome(pages[index])
        if not lines:
            continue
        lines = strip_headers(lines, candidates)
        lines, notes, expected = take_footnotes(lines, expected)
        notes_by_page[index] = notes
        # Retirer l'en-tête, les notes et le numéro laisse des lignes vides aux
        # deux bouts. Elles ne sont pas des fins de paragraphe imprimées : si on
        # les gardait, elles couperaient toute citation et tout paragraphe qui
        # traverse un saut de page, et la règle de jonction ci-dessous
        # n'arbitrerait plus rien.
        body_by_page[index] = trim_blanks(lines)
        if not any(line.strip() for line in lines) and notes:
            empty_pages.append(index)

    total_notes = sum(len(value) for value in notes_by_page.values())
    numbers = sorted(n for value in notes_by_page.values() for n in value)
    if numbers:
        gaps = [n for n in range(numbers[0], numbers[-1] + 1) if n not in numbers]
        if gaps:
            warn(f"notes manquantes dans la numérotation : {gaps}")
        print(f"  notes de bas de page : {total_notes} ({numbers[0]} à {numbers[-1]})")

    chapters: list[dict[str, object]] = []
    used: set[int] = set()
    for number, (title, start, end) in enumerate(bounds, start=1):
        lines: list[str] = []
        notes: dict[int, str] = {}
        for index in range(start, min(end, len(pages) - 1) + 1):
            page_lines = body_by_page.get(index)
            if page_lines is None:
                continue
            if lines and page_lines:
                # Un paragraphe traverse les sauts de page : on ne coupe que si
                # la page précédente finissait sur une fin de bloc — une
                # ponctuation finale, ou la référence d'une citation.
                previous = next(
                    (line for line in reversed(lines) if line.strip()), ""
                )
                if ends_block(previous):
                    lines.append("")
            lines.extend(page_lines)
            notes.update(notes_by_page.get(index, {}))
        blocks = build_blocks(lines, headings)
        glued = glued_notes(blocks, notes)
        for block in blocks:
            attach_notes(block, notes, used, glued)
        chapters.append({"number": number, "title": title, "blocks": blocks})

    orphans = sorted(set(numbers) - used)
    if orphans:
        warn(f"notes dont le marqueur n'a pas été localisé : {orphans}")

    # L'annexe des noms, reconstruite par coordonnées.
    annex = next(
        (
            chapter
            for chapter in chapters
            if fold(str(chapter["title"])).startswith("TABLEAU DES NOMS")
        ),
        None,
    )
    if annex is not None:
        pairs = name_table(pdf, "Tableau des noms")
        if pairs:
            annex["blocks"] = [
                {"type": "pair", "text": left, "gloss": right}
                for left, right in pairs
            ]
            print(f"  tableau des noms : {len(pairs)} paires reconstruites")

    for chapter in chapters:
        if not chapter["blocks"]:
            warn(f"chapitre « {chapter['title']} » vide — en-tête trop gourmand ?")
    if empty_pages:
        warn(f"pages réduites à leurs seules notes : {empty_pages}")

    data = metadata(pages)
    document: dict[str, object] = {
        "code": code,
        "title": data.get("title", ""),
        "subtitle": data.get("subtitle", ""),
        "author": data.get("author", ""),
        "publisher": data.get("publisher", ""),
        "isbn": data.get("isbn", ""),
        "rights": rights_line(data),
        "toc": toc_items(entries),
        "chapters": chapters,
    }
    counts = {
        "blocs": sum(len(chapter["blocks"]) for chapter in chapters),
        "paragraphes": sum(
            1
            for chapter in chapters
            for block in chapter["blocks"]
            if block["type"] == "p"
        ),
        "citations": sum(
            1
            for chapter in chapters
            for block in chapter["blocks"]
            if block["type"] == "quote"
        ),
        "notes posées": len(used),
    }
    print("  " + ", ".join(f"{value} {key}" for key, value in counts.items()))
    return document


def toc_items(
    entries: list[tuple[str, int, int]]
) -> list[dict[str, object]]:
    """Le sommaire, chaque entrée pointant le chapitre qui l'ouvre ou la porte.

    Les titres de niveau 0 sont, dans l'ordre, les chapitres stockés : le
    compteur suit donc l'ordre de lecture plutôt que de rechercher le titre —
    une section pointe le dernier chapitre déclaré avant elle, pas sa page (une
    section peut déborder sur la page du chapitre suivant).

    Une section rencontrée avant tout chapitre garde 0 : l'app y lira « aucune
    destination » au lieu d'ouvrir l'introduction par erreur.
    """
    items: list[dict[str, object]] = []
    current = 0
    for title, _, level in entries:
        if level == 0:
            current += 1
        items.append({"title": title, "level": level, "chapter": current})
    return items


def rights_line(data: dict[str, str]) -> str:
    """Ligne de droits : l'éditeur, son année si elle a été lue, la mention.

    La mention de non-vente est la condition de la licence du livre pilote et
    ne s'abrège pas. L'année est optionnelle parce qu'un ouvrage peut ne pas
    l'imprimer ; l'éditeur manquant est en revanche un défaut d'extraction, que
    l'avertissement du relevé de métadonnées a déjà signalé.
    """
    holder = " ".join(
        part for part in (data.get("year", ""), data.get("publisher", "")) if part
    )
    return (
        f"© {holder} · diffusion gratuite autorisée · "
        "STRICTEMENT INTERDIT À LA VENTE"
    )


# --- Pochette ---------------------------------------------------------------

# Largeur au-delà de laquelle la pochette est réduite. La vignette de la
# Bibliothèque fait 44 px de large, l'en-tête du sommaire guère plus : 600 px
# laisse de la marge pour un écran à forte densité sans embarquer une image
# d'impression. Le pilote sort à 486 px, donc en dessous — ses octets passent
# tels quels.
COVER_MAX_WIDTH = 600

# Jetons du flux de contenu dont dépend la couture : `q` et `Q` (la pile de la
# matrice de transformation), `cm` (la poser) et `/Nom Do` (y dessiner l'image).
# Le reste du flux — textes, gs, couleurs — n'intéresse pas la pochette.
PDF_TOKEN = re.compile(
    r"(?P<push>\bq\b)"
    r"|(?P<pop>\bQ\b)"
    r"|(?P<cm>(?:[-+]?(?:\d+\.\d*|\.\d+|\d+)\s+){5}[-+]?(?:\d+\.\d*|\.\d+|\d+)\s+cm)"
    r"|(?P<do>/[\w\-.]+\s+Do)"
)

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

# Tolérance de couture, en points : une bande peut buter sur une fraction.
BAND_TOLERANCE = 1.0


def concatenate(
    matrix: tuple[float, ...], ctm: tuple[float, ...]
) -> tuple[float, ...]:
    """Pose `matrix` sur `ctm` — concaténation PDF, `M × C`.

    Les six coefficients suivent la convention `[a b c d e f]`, qui applique
    `(x, y) → (a·x + c·y + e, b·x + d·y + f)`.
    """
    a, b, c, d, e, f = matrix
    A, B, C, D, E, F = ctm
    return (
        a * A + b * C,
        a * B + b * D,
        c * A + d * C,
        c * B + d * D,
        e * A + f * C + E,
        e * B + f * D + F,
    )


def image_placements(page: Any) -> list[tuple[str, tuple[float, ...]]]:
    """(nom d'XObject, matrice finale) de chaque image posée sur la page.

    La pile `q`/`Q` est suivie : sans elle, la matrice de chaque bande se
    composerait avec celle de la précédente et l'empilement serait lu de travers.
    """
    contents = page.get_contents()
    if contents is None:
        return []
    text = contents.get_data().decode("latin-1", errors="replace")
    placements: list[tuple[str, tuple[float, ...]]] = []
    ctm = IDENTITY
    stack: list[tuple[float, ...]] = []
    for token in PDF_TOKEN.finditer(text):
        if token.group("push"):
            stack.append(ctm)
        elif token.group("pop"):
            ctm = stack.pop() if stack else IDENTITY
        elif token.group("cm"):
            values = tuple(float(v) for v in token.group("cm").split()[:6])
            ctm = concatenate(values, ctm)
        else:
            placements.append((token.group("do").split()[0][1:], ctm))
    return placements


def stitched_cover(page: Any, images: list[Any]) -> Any:
    """Re-coud une couverture découpée en bandes horizontales — ou None.

    Un tirage qui éclate l'image de couverture en tranches la redessine bande
    par bande (`q … cm /Im3 Do Q`), et `pypdf` les rend dans l'ordre
    lexicographique de leur nom : `Im1`, `Im10`, `Im11`, …, `Im2`, `Im20`,
    `Im3`. En retenir une seule — « la plus grande image de la page 1 » —
    livrerait un coupon.

    La couture n'est acceptée que si les bandes **taillent la page** : même
    largeur, même abscisse, posées bord à bord du sommet au pied. Le moindre
    trou, chevauchement ou rotation rend None, et l'appelant retombe sur
    l'image entière la plus grande — jamais sur une bande par hasard.
    """
    placements = image_placements(page)
    if len(placements) < 2:
        return None

    by_name = {Path(image.name).stem: image for image in images}
    bands: list[tuple[float, float, float, float, object]] = []
    for name, matrix in placements:
        a, b, c, d, e, f = matrix
        image = by_name.get(name)
        if image is None or b or c:
            return None  # image absente du décodage, ou posée de travers
        bands.append((f + d, a, d, e, image))  # (haut, largeur, hauteur, abscisse)

    # Du haut vers le bas : l'origine PDF est en bas à gauche.
    bands.sort(key=lambda band: -band[0])

    width = float(page.mediabox.width)
    height = float(page.mediabox.height)
    if abs(bands[0][0] - height) > BAND_TOLERANCE:
        return None
    if abs(bands[-1][0] - bands[-1][2] - 0.0) > BAND_TOLERANCE:
        return None
    for previous, current in zip(bands, bands[1:]):
        if abs(previous[0] - previous[2] - current[0]) > BAND_TOLERANCE:
            return None
    for _, band_width, _, band_x, _ in bands:
        if abs(band_width - width) > BAND_TOLERANCE or abs(band_x) > BAND_TOLERANCE:
            return None

    # Pillow vient avec pypdf (c'est lui qui décode `image.image`).
    from PIL import Image

    canvas_width = max(image.image.size[0] for *_, image in bands)
    parts = []
    for *_, image in bands:
        band = image.image.convert("RGB")
        if band.size[0] != canvas_width:
            band = band.resize(
                (canvas_width, round(band.size[1] * canvas_width / band.size[0])),
                Image.LANCZOS,
            )
        parts.append(band)

    canvas = Image.new("RGB", (canvas_width, sum(part.size[1] for part in parts)))
    cursor = 0
    for part in parts:
        canvas.paste(part, (0, cursor))
        cursor += part.size[1]
    return canvas


def extract_cover(pdf: Path, dest: Path) -> bool:
    """Écrit la pochette de l'ouvrage — la couverture de la page 1 — dans `dest`.

    La couverture est une **image**, pas du texte : elle ne passe donc pas par
    `pdftotext` mais par `pypdf`. On prend la plus grande image de la première
    page, parce qu'une page de garde peut porter autre chose qu'une couverture
    (page 2 du pilote montre le bandeau de l'éditeur, 198 × 69) et que la
    couverture est, elle, pleine page — sauf quand'elle est imprimée en
    tranches, auquel cas [stitched_cover] la recoud d'abord, faute de quoi
    « la plus grande image » n'est qu'un coupon de couverture.

    Les octets d'origine sont recopiés sans recompression tant que l'image tient
    sous [COVER_MAX_WIDTH] ; au-delà, Pillow la réduit et la réécrit en JPEG.
    Une page 1 sans image **avertit** et ne produit rien : la tuile de la
    Bibliothèque retombe alors sur son icône, ce qui vaut mieux qu'une pochette
    prise au hasard dans le livre.
    """
    try:
        from pypdf import PdfReader
    except ImportError:
        warn("pypdf absent : pochette non extraite")
        return False

    reader = PdfReader(str(pdf))
    if not reader.pages:
        warn("PDF sans page : pochette non extraite")
        return False

    page = reader.pages[0]
    try:
        images = list(page.images)
    except Exception as error:  # pypdf lève selon le filtre de l'image
        warn(f"pochette illisible ({error}) : non extraite")
        return False
    if not images:
        warn("aucune image en page 1 : pochette non extraite")
        return False

    stitched = None
    if len(images) > 1:
        try:
            stitched = stitched_cover(page, images)
        except Exception as error:  # un filtre que Pillow refuse
            warn(f"couture de la pochette illisible ({error}) : image entière retenue")

    detail = ""
    if stitched is not None:
        source, raw = stitched, None
        detail = f", recousue de {len(images)} bandes"
    else:
        cover = max(images, key=lambda image: image.image.size[0] * image.image.size[1])
        source = cover.image
        raw = cover.data if source.size[0] <= COVER_MAX_WIDTH else None

    width, height = source.size
    dest.parent.mkdir(parents=True, exist_ok=True)

    if raw is not None:
        dest.write_bytes(raw)
    else:
        # Pillow vient avec pypdf (c'est lui qui décode `cover.image`), mais il
        # n'est importé qu'ici : seul le redimensionnement s'en sert.
        from PIL import Image

        scaled = source.convert("RGB")
        scaled.thumbnail(
            (COVER_MAX_WIDTH, COVER_MAX_WIDTH * 4), resample=Image.LANCZOS
        )
        scaled.save(dest, "JPEG", quality=88, optimize=True)
        width, height = scaled.size

    size = dest.stat().st_size
    print(
        f"  pochette : {dest} ({width} × {height}, {size / 1024:.0f} Ko{detail})"
    )
    return True


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convertit un ouvrage PDF en JSON pour l'onglet « Livres »."
    )
    parser.add_argument("source", type=Path, help="le PDF de l'ouvrage")
    parser.add_argument("dest", type=Path, help="le JSON à écrire")
    parser.add_argument("--code", required=True, help="code court (ex. MINISTERE)")
    parser.add_argument(
        "--cover",
        type=Path,
        help="écrit aussi la pochette (image de la page 1) à ce chemin",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="analyse et rapporte sans écrire le fichier",
    )
    args = parser.parse_args()

    if not args.source.exists():
        sys.exit(f"Introuvable : {args.source}")

    print(f"Conversion de {args.source.name}")
    document = convert(args.source, args.code)

    sections = [
        f"{chapter['number']}. {chapter['title']} "
        f"({len(chapter['blocks'])} blocs)"
        for chapter in document["chapters"]
    ]
    print("  chapitres :")
    for section in sections:
        print(f"    {section}")

    if WARNINGS:
        print(f"\n{len(WARNINGS)} avertissement(s) — à lire avant publication.")
    else:
        print("\nAucun avertissement.")

    if args.dry_run:
        print("--dry-run : rien n'a été écrit.")
        return

    args.dest.parent.mkdir(parents=True, exist_ok=True)
    args.dest.write_text(
        json.dumps(document, ensure_ascii=False, indent=1), encoding="utf-8"
    )
    size = args.dest.stat().st_size
    print(f"Écrit : {args.dest} ({size / 1024:.0f} Ko)")

    # Après le JSON : la pochette est un agrément de la tuile, le livre est le
    # produit. Un échec d'extraction avertit (voir [extract_cover]) sans
    # invalider la conversion.
    if args.cover is not None:
        extract_cover(args.source, args.cover)


if __name__ == "__main__":
    main()
