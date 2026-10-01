# -*- coding: utf-8 -*-
"""
sef_to_json.py — convertit l'extraction SEF en fichiers du dépôt bym-bibles.

Entrée : sef/extrait/livres/<CODE>.json   (47 livres, produit par extract_sef.py)
Sortie : <bym-bibles>/sef/<n>.json        (39 livres, numéro standard
         1 = Genèse … 39 = Malachie, comme les autres dossiers du dépôt)

Conventions du dépôt victordiaz1000/-bym-bibles respectées :

- **Canon protestant, 39 livres d'Ancien Testament** : Tobie, Judith, Sagesse,
  Siracide, Baruch, Lettre de Jérémie, 1-2 Maccabées, « Esdras A » (1 Esdras),
  Daniel 13-14 (Suzanne, Bel) et Psaume 151 sont retirés — la même convention
  que chouraqui/ et neocrampon/ (cf. README du dépôt).
- **Schéma getbible enrichi** : `text` = français affiché (Giguet), `grec` =
  ligne grecque de la Septante, `alexandrie` = seconde traduction française
  quand elle existe, `notes` = pieds de page sans ancrage, `section` = titres
  de section de la source. Le balisage HTML est retiré : texte nu seulement.
- **Fusion des versets sur leur numéro de tête** : la source imprime des
  sous-numéros (« 46a », « 35h »), des plages (« 11-13 ») et des renvois
  (« 1 = 2.35c ») — tous ramenés au numéro entier, pour que le comparateur de
  l'app retrouve le même verset d'une version à l'autre.

Contrôles : comptes de chapitres comparés au corpus BYM (source hébraïque),
aucune balise résiduelle, rapport détaillé imprimé à la fin.
"""
import glob
import html
import json
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

EXTRAIT = Path(r"C:\Users\laptek\Desktop\bym3\sef\extrait\livres")
OUT = Path(r"C:\Users\laptek\Desktop\bym-bibles\sef")
BYM = Path(r"C:\Users\laptek\Desktop\bym3\bible_app\assets\bible\bym")

# code → (numéro standard / index BYM, nom français)
OT = {
    "GEN": (1, "Genèse"), "EXO": (2, "Exode"), "LEV": (3, "Lévitique"),
    "NUM": (4, "Nombres"), "DEU": (5, "Deutéronome"), "JOS": (6, "Josué"),
    "JDG": (7, "Juges"), "RUT": (8, "Ruth"), "1SA": (9, "1 Samuel"),
    "2SA": (10, "2 Samuel"), "1KI": (11, "1 Rois"), "2KI": (12, "2 Rois"),
    "1CH": (13, "1 Chroniques"), "2CH": (14, "2 Chroniques"),
    "EZR": (15, "Esdras"), "NEH": (16, "Néhémie"), "EST": (17, "Esther"),
    "JOB": (18, "Job"), "PSA": (19, "Psaumes"), "PRO": (20, "Proverbes"),
    "ECC": (21, "Ecclésiaste"), "SNG": (22, "Cantique des Cantiques"),
    "ISA": (23, "Ésaïe"), "JER": (24, "Jérémie"), "LAM": (25, "Lamentations"),
    "EZK": (26, "Ézéchiel"), "DAN": (27, "Daniel"), "HOS": (28, "Osée"),
    "JOL": (29, "Joël"), "AMO": (30, "Amos"), "OBA": (31, "Abdias"),
    "JON": (32, "Jonas"), "MIC": (33, "Michée"), "NAM": (34, "Nahum"),
    "HAB": (35, "Habacuc"), "ZEP": (36, "Sophonie"), "HAG": (37, "Aggée"),
    "ZEC": (38, "Zacharie"), "MAL": (39, "Malachie"),
}

# Plafonds de chapitres hors-canon dans la source (sinon le livre dépasse le
# corpus BYM : PSA 151, DAN 13-14, EZR 11 [doublon du 10 grec seul]).
CAPS = {"PSA": 150, "DAN": 12, "EZR": 10}

# Droits du fichier : grec = copyright affiché par la source (header.xml) ;
# traductions françaises = le nom du logiciel, Biblia Universalis 3, que la
# source porte pour elles (cf. la page « Septante traduite en langue
# française » et <owner>Laurent SOUFFLET</owner>).
RIGHTS = ("© 1935, 1979 Deutsche Bibelgesellschaft (grec de Rahlfs) · "
          "© Biblia Universalis 3 (traductions françaises Giguet "
          "et Alexandrie)")

STRIP = re.compile(r"<[^>]+>")
NOTE_SPAN = re.compile(r'<span class="(?:note|nn)">(.*?)</span>', re.S)
BR = re.compile(r"<br\s*/?>", re.I)
BASE_NUM = re.compile(r"\s*(\d+)")


def norm(s):
    """Espace unique (entités comprises) + trim : le texte tel qu'il s'affiche."""
    return re.sub(r"\s+", " ", s).strip()


def plain_of(s):
    """HTML → texte nu : balisage retiré, entités décodées, espaces réduits."""
    return norm(html.unescape(STRIP.sub("", s)))


def split_bullets(p):
    """Une note « • a • b » → ['a', 'b'] (les puces ne sont pas du texte)."""
    return [x.strip() for x in p.split("•") if x.strip()]


def is_marker(p):
    """Marqueur orphelin (« $ »…) : sans lettre, court → rien à conserver."""
    return len(p) <= 4 and not any(c.isalpha() for c in p)


def clean_field(s, notes_out):
    """Nettoie un champ (grec / Giguet / Alexandrie) et en extrait les notes.

    `<span class="note">• …</span>` est un pied de page : il part dans
    [notes_out]. Tout autre contenu de span (marqueur « * »…) reste dans le
    texte, comme le reste du balisage retiré.
    """
    def repl(m):
        p = plain_of(m.group(1))
        if p.startswith("•"):
            notes_out.extend(split_bullets(p))
            return " "
        return p

    s = NOTE_SPAN.sub(repl, s or "")
    s = BR.sub(" ", s)
    return norm(html.unescape(STRIP.sub("", s)))


def classify_other(frag, notes, french):
    """Un fragment neutre (`autres`) : note, ou français orphelin.

    La source range hors des polices colorées les pieds de page, les liens
    glossaire (« Variante ► »), les notes critiques (« *13.1 Le TM… ») et —
    exceptionnellement — des traductions non reconnues (un verset de Josué
    dont la police a été mal identifiée). [french] ne sert que si Giguet est
    vide pour ce verset ; sinon tout y part en notes (variantes, étiquettes).
    """
    if NOTE_SPAN.search(frag):
        def repl(m):
            p = plain_of(m.group(1))
            if not p:
                return " "
            if p.startswith("•"):
                notes.extend(split_bullets(p))
            else:
                notes.append(p)          # étiquette d'acrostiche : « Alpha-aleph »
            return " "

        rest = NOTE_SPAN.sub(repl, frag)
        p = plain_of(rest)
        if p.startswith("*"):
            notes.append(p.lstrip("*").strip())
        elif p and not is_marker(p):
            french.append(p)
        return

    p = plain_of(frag)
    if not p:
        return
    if 'class="glossaire"' in frag or 'class="ref"' in frag:
        notes.append(p)                  # « Variante ► », renvoi de référence
    elif p.startswith("*"):
        tail = p.lstrip("*").strip()
        if tail:
            notes.append(tail)           # note critique de traduction
    elif not is_marker(p):
        french.append(p)


def base_num(label, prev, stats):
    """Numéro de tête d'un libellé : « 46a » → 46, « 11-13 » → 11."""
    m = BASE_NUM.match(str(label))
    if m:
        return int(m.group(1))
    stats["sans_tete"] += 1
    return prev


def convert_chapter(chapter, stats):
    """Un `<cn>` source → versets fusionnés par numéro de tête."""
    order = []
    groups = {}
    for v in chapter["versets"]:
        b = base_num(v["verset"], order[-1] if order else 1, stats)
        g = groups.get(b)
        if g is None:
            g = {"grec": [], "giguet": [], "alex": [], "autres": [], "titres": []}
            groups[b] = g
            order.append(b)
        else:
            stats["fusionnes"] += 1
        g["grec"].append(v["grec"] or "")
        g["giguet"].append(v["giguet"] or "")
        g["alex"].append(v["alexandrie"] or "")
        g["autres"].extend(v["autres"])
        g["titres"].extend(v["titres"])

    verses = []
    for b in order:
        g = groups[b]
        notes = []
        # Espace de séparation : les sous-versets fusionnés (« 1a » + « 1b »)
        # se colleraient sinon (« vision.Demeurant »).
        grec = clean_field(" ".join(g["grec"]), notes)
        gig = clean_field(" ".join(g["giguet"]), notes)
        alex = clean_field(" ".join(g["alex"]), notes)

        french = []
        for frag in g["autres"]:
            classify_other(frag, notes, french)

        text = gig
        if french:
            if not text:
                text = french.pop(0)     # Giguet muet : le français orphelin
            notes.extend(french)         # sinon : variantes / étiquettes
        if not text:
            text = alex                  # dernier recours : l'Alexandrie
        if not text and not grec:
            stats["vides"] += 1
            continue

        sections = [plain_of(t) for t in g["titres"]]
        sections = [s for s in sections if s]

        verse = {"verse": str(b), "text": text}
        if grec:
            verse["grec"] = grec
        if alex and alex != text:
            verse["alexandrie"] = alex
        if notes:
            verse["notes"] = notes
        if sections:
            verse["section"] = " — ".join(sections)
        verses.append(verse)

    return verses


def bym_chapter_counts():
    """Comptes de chapitres du corpus BYM, ramenés au **numéro standard**.

    Les fichiers BYM sont en ordre BYM (`31-Ruth.json`), pas en ordre
    standard (`8.json` = Ruth ici) : la passerelle est
    `book_mapping.dart` ({index BYM: numéro standard}), à inverser.
    """
    mapping_src = (Path(__file__).resolve().parent.parent /
                   "bible_app" / "lib" / "data" / "book_mapping.dart")
    block = re.search(r"_bymToStandard = \{(.*?)\}", mapping_src.read_text(
        encoding="utf-8"), re.S).group(1)
    std_of = {int(bym): int(std) for bym, std in re.findall(r"(\d+):\s*(\d+)", block)}

    counts = {}
    for f in sorted(BYM.glob("*.json")):
        if not re.match(r"^\d\d-", f.name):
            continue  # _source.json et autres fichiers hors numérotation
        bym_idx = int(f.name[:2])
        data = json.load(open(f, encoding="utf-8"))
        std = std_of.get(bym_idx)
        if std is not None:
            counts[std] = len(data["chapters"])
    return counts


def main():
    bym_counts = bym_chapter_counts()
    OUT.mkdir(parents=True, exist_ok=True)
    stats = dict(sans_tete=0, fusionnes=0, vides=0)
    failures = []
    total_verses = 0
    total_notes = 0

    for code, (nr, name) in sorted(OT.items(), key=lambda kv: kv[1][0]):
        src = EXTRAIT / f"{code}.json"
        if not src.exists():
            failures.append(f"{code}: fichier source absent")
            continue
        data = json.load(open(src, encoding="utf-8"))

        chapters = []
        seen = set()
        skipped = []
        for ch in data["chapitres"]:
            n = ch["chapitre"]
            if ch.get("doublon_de"):
                skipped.append(f"{n} (doublon)")
                continue
            if ch.get("groupe"):
                skipped.append(f"{n} ({ch['groupe']})")
                continue
            if n is None:
                skipped.append("sans numéro")
                continue
            n = int(n)
            if n > CAPS.get(code, 10 ** 6):
                skipped.append(f"{n} (hors canon)")
                continue
            if n in seen:
                skipped.append(f"{n} (répété)")
                continue
            seen.add(n)

            verses = convert_chapter(ch, stats)
            chapters.append({
                "chapter": n,
                "name": f"{name} {n}",
                "verses": verses,
            })

        chapters.sort(key=lambda c: c["chapter"])
        expected = bym_counts.get(nr)
        if expected is not None and len(chapters) != expected:
            failures.append(
                f"{code}: {len(chapters)} chapitres, corpus BYM en a {expected}")

        for c in chapters:
            for i, v in enumerate(c["verses"], start=1):
                v["name"] = f"{name} {c['chapter']}:{v['verse']}"
                v["chapter"] = str(c["chapter"])
                total_verses += 1
                total_notes += len(v.get("notes", []))
                # Aucune balise ni entité ne doit subsister dans le texte servi.
                for key in ("text", "grec", "alexandrie", "section"):
                    val = v.get(key) or ""
                    if re.search(r"</?[a-zA-Z][^>]*>", val):
                        failures.append(
                            f"{code} {c['chapter']}:{v['verse']}: balise dans {key}")

        payload = {
            "translation": "Septuaginta (Rahlfs) — traductions françaises de "
                           "Giguet et d'Alexandrie",
            "abbreviation": "SEF",
            "lang": "fr",
            "language": "français (avec le grec de la Septante)",
            "direction": "LTR",
            "encoding": "UTF-8",
            "nr": nr,
            "name": name,
            "copyright": RIGHTS,
            "chapters": chapters,
        }
        out = OUT / f"{nr}.json"
        with open(out, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(payload, fh, ensure_ascii=False, indent=2)
            fh.write("\n")

        nv = sum(len(c["verses"]) for c in chapters)
        print(f"{nr:>2} {code:<3} {name:<24} {len(chapters):>3} ch. "
              f"{nv:>5} versets  {out.stat().st_size // 1024:>5} Ko"
              f"{'   ignorés: ' + ', '.join(skipped) if skipped else ''}")

    print(f"\nTotal : {total_verses} versets, {total_notes} notes de pied de page")
    print(f"Fusions de sous-versets : {stats['fusionnes']} · "
          f"versets vides ignorés : {stats['vides']} · "
          f"libellés sans numéro de tête : {stats['sans_tete']}")

    if failures:
        print("\nÉCHECS :")
        for f in failures:
            print(" -", f)
        sys.exit(1)
    print("Contrôles : comptes de chapitres et nettoyage OK.")


if __name__ == "__main__":
    main()
