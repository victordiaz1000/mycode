#!/usr/bin/env python3
"""Convertit un corpus HTML « un fichier par chapitre » en JSON getbible.

Même rôle que `ostervald_to_json.py`, mais pour la famille d'archives HTML dont
sont tirés CHO.zip (André Chouraqui) et KJF.zip (King James Française) : un
dossier par livre nommé au code OSIS (`GEN/`, `1CH/`…), un fichier `<NNN>.html>`
par chapitre, et pour tout le balisage :

    <v/><p><span class="cn">1</span> texte du verset 1
    <v/><br><span class="vn">2</span> texte du verset 2
    <br>                                    ← retour à la ligne à l'intérieur
    <h3>Titre de section</h3>               ← retiré (le schéma nu n'en a pas)
    <intro>…</intro><h1>Titre</h1>          ← retiré (entête de livre)

`cn` et `vn` sont les seuls endroits où un numéro est écrit ; le premier marqueur
d'un fichier porte le **numéro de chapitre** (Apocalypse 12:1 est marquée « 12 »)
et non le numéro de verset.

**Les numéros imprimés ne font pas foi — la position fait foi.** Les corpus
contiennent des fautes d'impression qu'aucune ne partage : `222` pour 22
(Genèse 5), deux versets « 2 » puis un « 4 » sauté (Exode 22), « 74 » pour 174
(Psaumes 119), « 152 » pour 125 (Psaumes 119 de la KJF), un « 55 » hébreu en
tête de Genèse 32. Les versets sont donc renumérotés **1…N par position** —
c'est ce que garantit l'app, qui construit `verse = chapitre:numéro` et saute
au verset par ce numéro — et chaque écart entre l'imprimé et la position est
listé en avertissement, pour qu'un défaut du texte source reste visible.

Le schéma de sortie est celui servi par getbible.net pour un livre :
    {translation, abbreviation, lang, nr, name,
     chapters: [{chapter, name, verses: [{chapter, name, verse, text}]}]}

Le texte est nu : balises, titres de section et entêtes disparaissent.

Les 66 livres canoniques sont retenus (ordre standard 1=Genèse … 66=Apocalypse) ;
les deutérocanoniques éventuels (Tobie, Judith, Sagesse, Siracide, Baruch,
1-2 Maccabées, Esther grec, Daniel grec) sont ignorés, les chapitres
supplémentaires d'Esther et de Daniel sont retirés — cf.
`trim_daniel_three` et `remap_deuterocanonical`, les règles déjà en place dans
`ostervald_to_json.py`.

Usage :
    python html_verses_to_json.py <source_dir> <output_dir> [translation] [abbreviation]
                                 [--bym <assets/bible/bym>]

`--bym` compare les comptes chapitre par chapitre avec le corpus BYM : l'app
découpe sa navigation sur la BYM, donc un écart de compte est une information
de fond, pas un détail de mise en forme.

`output_dir` est ensuite poussé tel quel dans `victordiaz1000/-bym-bibles`
(sous-dossier propre), où le `urlTemplate` de `version_catalog.dart` le lit.
"""

import html as html_module
import json
import re
import sys
from collections import OrderedDict
from pathlib import Path

# Ordre standard des 66 livres (codes OSIS des dossiers source), Genèse →
# Apocalypse : la numérotation `nr` des fichiers de sortie, celle que
# `DownloadService.bookUri` substitue dans `{book}`.
STANDARD_BOOKS = [
    "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT",
    "1SA", "2SA", "1KI", "2KI", "1CH", "2CH", "EZR", "NEH", "EST",
    "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN",
    "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG",
    "ZEC", "MAL",
    "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH",
    "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS",
    "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
]

STANDARD_NUMBER = {code: i + 1 for i, code in enumerate(STANDARD_BOOKS)}

# Noms français, même ordre. Le JSON getbible les porte pour être lisible chez
# getbible.net ; l'app, elle, lit `book_catalog.dart` (décision 9) — ces noms ne
# servent jamais à l'affichage, mais un fichier sans nom est un fichier qu'on ne
# peut pas vérifier d'un coup d'œil.
FRENCH_NAMES = [
    "Genèse", "Exode", "Lévitique", "Nombres", "Deutéronome", "Josué", "Juges",
    "Ruth", "1 Samuel", "2 Samuel", "1 Rois", "2 Rois", "1 Chroniques",
    "2 Chroniques", "Esdras", "Néhémie", "Esther", "Job", "Psaumes",
    "Proverbes", "Ecclésiaste", "Cantiques", "Ésaïe", "Jérémie", "Lamentations",
    "Ézéchiel", "Daniel", "Osée", "Joël", "Amos", "Abdias", "Jonas", "Michée",
    "Nahum", "Habacuc", "Sophonie", "Aggée", "Zacharie", "Malachie",
    "Matthieu", "Marc", "Luc", "Jean", "Actes", "Romains", "1 Corinthiens",
    "2 Corinthiens", "Galates", "Éphésiens", "Philippiens", "Colossiens",
    "1 Thessaloniciens", "2 Thessaloniciens", "1 Timothée", "2 Timothée",
    "Tite", "Philémon", "Hébreux", "Jacques", "1 Pierre", "2 Pierre", "1 Jean",
    "2 Jean", "3 Jean", "Jude", "Apocalypse",
]

FRENCH_NAME = {i + 1: FRENCH_NAMES[i] for i in range(66)}

TAG = re.compile(r"<[^>]+>")
# Numéro écrit : `<span class="cn">3</span>` (chapitre) ou `…vn…` (verset).
NUMBER = re.compile(r'<span class="(?:cn|vn)">(\d+)</span>')

# Blocs qui ne portent PAS de texte de verset : entête de livre, titres de
# section, tableaux et listes de notes. Retirés entiers — garder leur texte
# serait mêler « Sept jours » à Genèse 1:1.
NON_VERSE_BLOCK = re.compile(
    r"<intro>.*?</intro>"
    r"|<h[1-6][ >].*?</h[1-6]>"
    r"|<table>.*?</table>"
    r"|<ol>.*?</ol>"
    r"|<ul>.*?</ul>",
    flags=re.S | re.I,
)


def clean_verse(raw: str) -> str:
    """Du balisage HTML d'un verset à son texte nu.

    Rien n'est réécrit : les espaces devant la ponctuation et après « « » sont
    celles du corpus (`&nbsp;`, typographie française) et deviennent des
    espaces simples — c'est ce que porte la BYM (« ... Adonaï ! »), le texte de
    référence de l'app. Aucune espace n'est supprimée : un `<br>` ne précède
    jamais une ponctuation dans ces corpus (vérifié : 0 occurrence), donc
    retirer l'espace qui la précède ne pouvait que détruire la française.
    """
    text = raw.replace("<v/>", " ")
    text = TAG.sub(" ", text)
    text = html_module.unescape(text)
    text = text.replace("\xa0", " ")
    return re.sub(r"\s+", " ", text).strip()


def parse_chapter(path: Path):
    """Les versets d'un chapitre : [(numéro imprimé, texte), …] dans l'ordre du
    fichier. Le numéro imprimé est donné à titre d'information seulement."""
    text = path.read_text(encoding="utf-8")
    first = NUMBER.search(text)
    if first is None:
        return []
    # Tout avant le premier numéro est de l'entête (intro, titre, CSS embarqué).
    body = NON_VERSE_BLOCK.sub(" ", text[first.start():])

    marks = list(NUMBER.finditer(body))
    verses = []
    for i, match in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        verses.append((int(match.group(1)), clean_verse(body[match.end():end])))
    return verses


def trim_daniel_three(book_number, chapter_number, verses, report):
    """Retire le cantique des trois jeunes gens de Daniel 3 (24…90), intercalé
    entre le récit hébreu (1…23) et sa reprise.

    Deux formes coexistent dans les corpus : la reprise est numérotée 24…33
    (Chouraqui) ou 91…100 (formes catholiques). Dans les deux cas elle est **les
    dix derniers marqueurs**, et c'est par la position qu'on la reconnaît — les
    deux formes finissent d'ailleurs identiques : 1…23 + reprise = 33 versets,
    le compte de la BYM. Un corpus sans cantique (33 versets) ne déclenche rien."""
    if book_number != 27 or chapter_number != 3 or len(verses) <= 33:
        return verses

    tail_printed = [n for n, _ in verses[-10:]]
    if not all(n <= 33 or n >= 91 for n in tail_printed):
        report(
            f"❌ DAN 003 : {len(verses)} versets et fin {tail_printed} — "
            f"Daniel 3 reconnu mais la reprise n'est pas les 10 derniers"
        )
        return verses

    middle = [n for n, _ in verses[23:-10]]
    if middle and not all(24 <= n <= 90 for n in middle):
        report(
            f"❌ DAN 003 : le bloc retiré ({middle[:3]}…) n'est pas le cantique "
            f"numéroté 24…90"
        )
        return verses

    report(
        f"✂️ DAN 003 : cantique des trois jeunes gens retiré "
        f"({len(middle)} versets, imprimés {middle[0]}…{middle[-1]}), "
        f"reprise conservée (10 versets)"
    )
    return verses[:23] + verses[-10:]


def remap_deuterocanonical(book_number, chapters):
    """Aligne la numérotation catholique sur le canon 66 livres de l'app, en
    retirant les chapitres supplémentaires d'Esther et de Daniel.

    Ne fait rien si le schéma catholique n'est pas présent (idempotent) : un
    corpus protestant (KJF) garde ses 10 chapitres d'Esther et ses 12 chapitres
    de Daniel intacts, le corpus catholique (Chouraqui, Daniel 14 chapitres) est
    ramené à 12. Le cantique de Daniel 3 est traité avant, par
    [trim_daniel_three]."""
    # Esther : les additions grecques donnent 16 chapitres (1-10 + 11-16) et
    # prolongent le chapitre 10 de 3 à 13 versets.
    if book_number == 17 and any(ch["chapter"] > 10 for ch in chapters):
        kept = []
        for ch in chapters:
            if ch["chapter"] > 10:
                continue
            if ch["chapter"] == 10:
                ch["verses"] = [v for v in ch["verses"] if int(v["verse"]) <= 3]
            kept.append(ch)
        return kept
    # Daniel : Suzanne et Bel et le Dragon vivent en 13 et 14.
    if book_number == 27 and any(ch["chapter"] > 12 for ch in chapters):
        return [ch for ch in chapters if ch["chapter"] <= 12]
    return chapters


def check_against_bym(bym_dir: Path, output_dir: Path, report):
    """Compare les comptes de versets livre par livre avec le corpus BYM.

    L'app découpe sa navigation sur la BYM (`bymToStandard`) : un livre qui
    compte moins de versets que la BYM s'affiche bien, mais son dernier verset
    n'a pas d'équivalent dans l'autre sens — un écart est donc toujours à lire,
    jamais à supprimer. Seul un écart **positif** (plus de versets qu'en BYM)
    est suspect : la BYM ne perd pas de verset."""
    from_bym = {}
    for path in sorted(bym_dir.glob("[0-9][0-9]-*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        # index BYM du fichier (01..66) → numéro standard
        bym_index = int(path.name[:2])
        from_bym[_standard_from_bym(bym_index)] = [
            len(ch["verses"]) for ch in data["chapters"]
        ]

    for path in sorted(output_dir.glob("*.json")):
        number = int(path.stem)
        data = json.loads(path.read_text(encoding="utf-8"))
        got = [len(ch["verses"]) for ch in data["chapters"]]
        want = from_bym.get(number)
        if want is None:
            report(f"⚠️ BYM : livre {number} introuvable dans {bym_dir}")
            continue
        if len(got) != len(want):
            report(
                f"⚠️ BYM {data['name']} : {len(got)} chapitres contre "
                f"{len(want)} en BYM"
            )
        for i in range(min(len(got), len(want))):
            if got[i] != want[i]:
                signe = "+" if got[i] > want[i] else ""
                report(
                    f"⚠️ BYM {data['name']} {i + 1} : {signe}{got[i] - want[i]}"
                    f" verset(s) ({got[i]} lus, {want[i]} en BYM)"
                )


# Table BYM (01..66, ordre hébreu) → numéro standard, recopiée de
# `bible_app/lib/data/book_mapping.dart` : le seul endroit où elle existe en
# dehors de l'app.
_BYM_TO_STANDARD = {
    1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 9, 9: 10, 10: 11, 11: 12,
    12: 23, 13: 24, 14: 26, 15: 28, 16: 29, 17: 30, 18: 31, 19: 32, 20: 33,
    21: 34, 22: 35, 23: 36, 24: 37, 25: 38, 26: 39, 27: 19, 28: 20, 29: 18,
    30: 22, 31: 8, 32: 25, 33: 21, 34: 17, 35: 27, 36: 15, 37: 16, 38: 13,
    39: 14, 40: 40, 41: 41, 42: 42, 43: 43, 44: 44, 45: 59, 46: 48, 47: 52,
    48: 53, 49: 46, 50: 47, 51: 45, 52: 49, 53: 50, 54: 51, 55: 57, 56: 54,
    57: 56, 58: 60, 59: 61, 60: 55, 61: 65, 62: 58, 63: 62, 64: 63, 65: 64,
    66: 66,
}


def _standard_from_bym(bym_index: int) -> int:
    return _BYM_TO_STANDARD.get(bym_index, bym_index)


def convert(
    source_dir: Path,
    output_dir: Path,
    translation: str = "Chouraqui",
    abbreviation: str = "CHO",
    bym_dir: Path | None = None,
):
    output_dir.mkdir(parents=True, exist_ok=True)

    problems = []
    warnings = []

    def report(line):
        (problems if line.startswith("❌") else warnings).append(line)

    stats = {"books": 0, "chapters": 0, "verses": 0}

    for code in STANDARD_BOOKS:
        book_dir = source_dir / code
        if not book_dir.is_dir():
            report(f"❌ Dossier livre manquant : {code}")
            continue
        number = STANDARD_NUMBER[code]
        book_name = FRENCH_NAME[number]

        chapters = []
        for path in sorted(book_dir.glob("*.html"), key=lambda p: int(p.stem)):
            chapter_number = int(path.stem)
            printed = parse_chapter(path)
            if not printed:
                report(f"❌ {code} {path.name} : aucun verset lu")
                continue

            printed = trim_daniel_three(number, chapter_number, printed, report)

            # Le premier marqueur porte le numéro de chapitre, pas 1 — c'est
            # la position qui numérote. Tout écart entre l'imprimé et la
            # position est une faute du corpus, listée mais jamais corrigée en
            # silence.
            expected_printed = [chapter_number] + list(
                range(2, len(printed) + 1)
            )
            faulty = [
                (i + 1, printed[i][0])
                for i in range(len(printed))
                if printed[i][0] != expected_printed[i]
            ]
            if faulty:
                detail = ", ".join(f"#{i}→{v}" for i, v in faulty[:6])
                report(
                    f"⚠️ {code} {path.name} : {len(faulty)} numéro(s) imprimé(s) "
                    f"hors position ({detail}"
                    f"{'…' if len(faulty) > 6 else ''}) — renuméroté par position"
                )

            for index, (_, text) in enumerate(printed, start=1):
                if not text:
                    report(f"❌ {code} {path.name} : {index}: texte vide")
                elif "<" in text:
                    report(f"❌ {code} {path.name} : {index}: balisage résiduel")

            chapters.append({
                "chapter": chapter_number,
                "verses": [
                    {"verse": str(index), "text": text}
                    for index, (_, text) in enumerate(printed, start=1)
                ],
            })

        chapters = remap_deuterocanonical(number, chapters)

        book = OrderedDict([
            ("translation", translation),
            ("abbreviation", abbreviation),
            ("lang", "fr"),
            ("language", "français"),
            ("direction", "LTR"),
            ("encoding", "UTF-8"),
            ("nr", number),
            ("name", book_name),
            ("chapters", chapters),
        ])
        for ch in chapters:
            n = ch["chapter"]
            ch["name"] = f"{book_name} {n}"
            for v in ch["verses"]:
                v["chapter"] = str(n)
                v["name"] = f"{book_name} {n}:{v['verse']}"

        (output_dir / f"{number}.json").write_text(
            json.dumps(book, ensure_ascii=False, indent=2), encoding="utf-8"
        )

        book_verses = sum(len(ch["verses"]) for ch in chapters)
        stats["books"] += 1
        stats["chapters"] += len(chapters)
        stats["verses"] += book_verses
        print(f"✅ {number}.json — {code} ({book_name}) : "
              f"{len(chapters)} ch., {book_verses} v.")

    if bym_dir is not None:
        check_against_bym(bym_dir, output_dir, report)

    print(f"\n📊 Total : {stats['books']} livres, {stats['chapters']} chapitres, "
          f"{stats['verses']} versets.")
    if warnings:
        print(f"\n—— {len(warnings)} avertissement(s) ——")
        print("\n".join(warnings))
    if problems:
        print(f"\n—— {len(problems)} problème(s) ——")
        print("\n".join(problems))
        print(f"\n❌ {len(problems)} problème(s) — ne pas publier en l'état.")
        return 1
    print("\n✅ Aucun problème : textes complets, aucun résidu de balisage.")
    return 0


if __name__ == "__main__":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    args = [a for a in sys.argv[1:]]
    bym_dir = None
    if "--bym" in args:
        i = args.index("--bym")
        bym_dir = Path(args[i + 1])
        del args[i:i + 2]
    if len(args) < 2:
        print(__doc__)
        sys.exit(2)
    source_dir = Path(args[0])
    output_dir = Path(args[1])
    translation = args[2] if len(args) > 2 else "Chouraqui"
    abbreviation = args[3] if len(args) > 3 else "CHO"
    if not source_dir.is_dir():
        print(f"❌ Dossier source introuvable : {source_dir}")
        sys.exit(1)
    if bym_dir is not None and not bym_dir.is_dir():
        print(f"❌ Dossier BYM introuvable : {bym_dir}")
        sys.exit(1)
    print(f"📖 Conversion : {source_dir} → {output_dir} "
          f"({translation}, {abbreviation})")
    sys.exit(convert(source_dir, output_dir, translation, abbreviation, bym_dir))
