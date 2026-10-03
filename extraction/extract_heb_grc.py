# -*- coding: utf-8 -*-
"""
Extraction des dictionnaires HEB (hébreu-français) et GRC (grec-français)
depuis les fichiers XML de Biblia Universalis 3.

Source : C:\\Users\\laptek\\Documents\\Bible\\Biblia Universalis 3 (1.39)\\Ressources\\dictionnaires
Sortie : extraction/HEB/ et extraction/GRC/ (registre de ce dépôt)

Format source (constaté, non documenté) :

    <dictionary>
      <files>
        <number>N</number>                 ← N blocs, dans l'ordre du TOC
        <file>
          <size>S</size>                   ← S = taille EN OCTETS de <data>
          <data>…contenu brut…</data>      ← HTML UTF-8, ou GIF/PNG binaire
        </file>…
      </files>
      <toc>
        <input><name>A/0001 'ab אב.html</name><addr>…</addr></input>…
      </toc>
      <addresses><files>…</files><toc>…</toc></addresses>
    </dictionary>

Points de vigilance, tous vérifiés par les sondes :

- **Parsing en octets**, pas en texte : quelques <data> contiennent des images
  GIF/PNG brutes (2 dans HEB, 4 dans GRC) qui cassent un décodage UTF-8 strict.
- `<size>` = octets exacts de <data> — vrai pour les 8701 + 5555 blocs.
- L'ordre des blocs `<file>` suit exactement l'ordre du `<toc>` (vérifié par
  appariement h1/nom sur toutes les fiches, voir `check_alignment`).
- Les noms du TOC sont des chemins relatifs (sous-dossiers A/…V/, images/) et
  sont uniques : ils servent de chemin d'écriture sans ambiguity.
- Les HTML référencent `images/…` et `../styles.css` : l'arborescence
  reproduisant les noms du TOC conserve ces liens relatifs tels quels.

Sorties, par dictionnaire :

    <CODE>/<chemins TOC>      les fichiers bruts (HTML, CSS, images)
    <CODE>/toc.tsv            index : numéro, nom, addr, octets, type
    <CODE>/entries.json       entrées parsées (schéma ci-dessous), par clé Strong
    rapport_comparaison.md    comparaison avec strong_fr.json (généré par
                              --rapport)

Schéma d'une entrée de entries.json :

    {
      "strong": "H8672", "language": "hebrew",
      "lemma": "תֵּשַׁע",          ← nom de fichier (partie non translittérée)
      "transliteration": "tesha`",   ← <h1>
      "pronunciation": "tay'-shah",
      "strongDefinition": "…",       ← texte des puces, champ par champ
      "etymology": "…",
      "nature": "…",
      "occurrences": {"summary": "58 fois dans 57 versets…", "books": {"Genèse": 13, …}},
      "sanderTrenel": "…",           ← HEB seul (511 entrées)
      "bailly": "…", "synonyms": "…", "spicq": "…"   ← GRC seul
      "sections": { …HTML brut par section… }        ← rien n'est perdu
    }

Usage :  python extraction/extract_heb_grc.py [--rapport]
Python 3.12, stdlib uniquement.
"""

from __future__ import annotations

import argparse
import html as html_lib
import json
import re
import sys
from collections import Counter
from pathlib import Path

SOURCE = Path(r"C:\Users\laptek\Documents\Bible\Biblia Universalis 3 (1.39)\Ressources\dictionnaires")
OUT = Path(__file__).resolve().parent
ASSETS = OUT.parent / "bible_app" / "assets" / "lexicon" / "strong_fr.json"

# Sections du HTML -> champ d'entrée. Clés = texte exact du <big>.
HEB_FIELDS = {
    "Définition Strong": "strongDefinition",
    "Étymologie": "etymology",
    "Nature du mot": "nature",
    "Définition Sander et Trenel": "sanderTrenel",
}
GRC_FIELDS = {
    "Définition Strong": "strongDefinition",
    "Étymologie": "etymology",
    "Nature du mot": "nature",
    "Définition Bailly": "bailly",
    "Synonymes": "synonyms",
    "Définition approfondie Spicq": "spicq",
}
SECTIONS = {  # sections lues telles quelles en HTML brut, quel que soit le champ
    "Occurrences": "occurrences",
}


# --------------------------------------------------------------------------- #
# Lecture                                                                      #
# --------------------------------------------------------------------------- #

def load(code: str) -> tuple[list[bytes], list[tuple[str, int]]]:
    """Découpe le XML en octets. Renvoie (blocs data, entrées TOC)."""
    raw = (SOURCE / f"{code}.xml").read_bytes()
    files = []
    for m in re.finditer(rb"<file>\s*<size>(\d+)</size>\s*<data>", raw):
        start = m.end()
        end = raw.index(b"</data>", start)
        size = int(m.group(1))
        if end - start != size:  # invariant vérifié sur les 14 256 blocs
            raise ValueError(f"{code}: taille <size>={size} != réel {end - start}")
        files.append(raw[start:end])
    toc_m = re.search(rb"<toc>\s*((?:<input>.*?</input>\s*)+)</toc>", raw, re.S)
    if not toc_m:
        raise ValueError(f"{code}: pas de <toc>")
    toc = [
        (name.decode("utf-8"), int(addr))
        for name, addr in re.findall(
            rb"<input><name>(.*?)</name><addr>(\d+)</addr></input>", toc_m.group(1), re.S
        )
    ]
    return files, toc


def check_alignment(code: str, files: list[bytes], toc: list[tuple[str, int]]) -> tuple[list[str], list[str]]:
    """Vérifie que le bloc i correspond au nom TOC i.

    Renvoie (bloquants, anomalies). Le contrôle qui engage réellement
    l'alignement est le numéro : numéro du nom de fichier == numéro de la
    ligne « Strong n° » du contenu. Le <h1> sert de contrôle secondaire, mais
    la source contient 12 fiches où le h1 diverge du nom (titre plus complet,
    tiret parasite, mot différent) sans que l'alignement soit en cause — la
    navigation ⏴⏵ de la fiche confirme alors le voisinage.
    """
    problems: list[str] = []
    quirks: list[str] = []
    for i, (data, (name, _)) in enumerate(zip(files, toc)):
        if data[:3] == b"GIF" or data[:4] == b"\x89PNG":
            if not name.endswith((".gif", ".png")):
                problems.append(f"#{i}: binaire mais nom={name}")
            continue
        mnum = re.match(r"^(\d{4}) ", Path(name).stem)
        if not mnum:
            continue  # index général, page de lettre, styles.css, intro Bailly
        head = data[:6000].decode("utf-8", "replace")
        h1 = re.search(r"<h1>(.*?)</h1>", head, re.S)
        strong = re.search(r"Strong n[^\d]{0,3}(\d+)", head)
        if not strong:
            problems.append(f"#{i}: pas de ligne Strong ({name})")
            continue
        # Le numéro du nom fait foi ; la ligne Strong est notée quand elle
        # diverge (4 coquilles de la source, cf. rapport).
        if int(strong.group(1)) != int(mnum.group(1)):
            quirks.append(f"#{i}: numéro ligne Strong {strong.group(1)} != "
                          f"numéro nom {mnum.group(1)} ({name})")
        if not h1:
            problems.append(f"#{i}: fiche sans <h1> ({name})")
            continue
        titre = html_lib.unescape(re.sub(r"<[^>]+>", "", h1.group(1))).strip()
        # Le <h1> porte la translittération, parfois « translittération - lemma » ;
        # le nom (sans le numéro) ajoute le lemma, souvent sans points. Le h1 est
        # donc un préfixe du nom — sauf les ~12 fiches à titre divergent.
        attendu = re.sub(r"^\d{4} ", "", Path(name).stem).strip()
        tete = titre.split(" - ", 1)[0].strip()
        if not attendu.startswith(tete):
            quirks.append(f"#{i}: h1={titre!r} !~ nom={attendu!r} ({name})")
    if len(files) != len(toc):
        problems.append(f"{len(files)} blocs != {len(toc)} entrées TOC")
    return problems, quirks


# Caractères interdits dans un nom de fichier Windows. Les noms du TOC en
# contiennent 4 dans HEB (ex: `E/1897 hagah הגה".html`) : remplacés par `_`,
# ce qui ne crée aucun doublon (vérifié : 0 collision après nettoyage).
WINDOWS_BAD = re.compile(r'[<>:"|?*]')


def sanitize(name: str) -> str:
    return WINDOWS_BAD.sub("_", name)


def safe_path(root: Path, relname: str) -> Path:
    """Chemin d'écriture sûr à partir d'un nom du TOC."""
    parts = [p for p in sanitize(relname).replace("\\", "/").split("/") if p not in ("", ".")]
    if not parts or any(p == ".." for p in parts):
        raise ValueError(f"nom TOC suspect: {relname!r}")
    dest = root.joinpath(*parts)
    if not str(dest.resolve()).startswith(str(root.resolve())):
        raise ValueError(f"hors racine: {relname!r}")
    return dest


# --------------------------------------------------------------------------- #
# Parsing des fiches                                                           #
# --------------------------------------------------------------------------- #

def text_of(fragment: str) -> str:
    """HTML -> texte lisible : puces sur une ligne, balises retirées."""
    s = re.sub(r"<br\s*/?>", "\n", fragment)
    s = re.sub(r"</li>", "\n", s)
    s = re.sub(r"<a [^>]*>(.*?)</a>", r"\1", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", s)
    s = html_lib.unescape(s).replace("\xa0", " ")  # &nbsp; -> espace simple
    lines = [ln.strip() for ln in s.split("\n")]
    return "\n".join(ln for ln in lines if ln).strip()


def split_sections(data: str) -> tuple[str, dict[str, str]]:
    """Sépare l'en-tête des sections. Chaque section = un tableau dont l'intitulé
    porte sur <td class="strong"><big>…</big></td>. On découpe sur cet intitululé :
    le contenu peut contenir des tableaux imbriqués (Occurrences), donc on prend
    tout jusqu'à l'intitulé suivant puis on ferme au dernier </table>."""
    parts = re.split(r'<td class="strong"><big>(.*?)</big></td>', data, flags=re.S)
    header = parts[0]
    sections = {}
    for i in range(1, len(parts), 2):
        nom = parts[i].strip()
        corps = parts[i + 1] if i + 1 < len(parts) else ""
        fin = corps.rfind("</table>")
        if fin != -1:
            corps = corps[:fin]
        # enlever l'ouverture de la rangée de contenu. Certains intitulés ont une
        # 2e cellule dans la même rangée (« ► Introduction » de Sander/Trenel) :
        # on coupe sur la fin de rangée qui ouvre le contenu, pas forcément en tête.
        m = re.search(r"</tr>\s*<tr[^>]*>\s*<td[^>]*>", corps)
        if m:
            corps = corps[m.end():]
        sections[nom] = corps
    return header, sections


def parse_entry(code: str, name: str, data: bytes) -> dict | None:
    """Une fiche HTML -> entrée structurée. None pour index/CSS/images.

    La clé Strong vient du NOM DE FICHIER, pas de la ligne « Strong n° » du
    contenu : les deux concordent pour 14 193 des 14 197 fiches, les 4 écarts
    restants sont des coquilles de la source (le nom correspond alors à la
    bonne entrée de strong_fr.json, la ligne du contenu non).
    """
    if data[:3] == b"GIF" or data[:4] == b"\x89PNG" or name.endswith(("styles.css",)):
        return None
    html_text = data.decode("utf-8", "replace")
    fields = HEB_FIELDS if code == "HEB" else GRC_FIELDS
    pref = "H" if code == "HEB" else "G"
    language = "hebrew" if code == "HEB" else "greek"

    stem = Path(name).stem
    mnum = re.match(r"^(\d{4}) (.+)$", stem)
    if not mnum:
        return None  # index général, page de lettre, intro Bailly
    num, rest = mnum.groups()
    header, sections = split_sections(html_text)

    # Lemma : dernier bloc du nom, reconnu à ses lettres hébreu/grec.
    # « 0001 'ab אב » -> lemma « אב », translittération « 'ab ».
    mlem = list(re.finditer(r"\S+", rest))
    lemma_nom = ""
    translit_nom = rest
    for tok in mlem:
        if any(is_hebrew_greek(c) for c in tok.group(0)):
            lemma_nom = tok.group(0)
            translit_nom = rest[:tok.start()].strip()
            break

    h1 = re.search(r"<h1>(.*?)</h1>", header, re.S)
    if not h1:
        return None
    h1_txt = html_lib.unescape(re.sub(r"<[^>]+>", "", h1.group(1))).strip()
    # Le <h1> est tantôt la seule translittération (« tesha` »), tantôt
    # « translittération - lemma pointillé » (« 'ab - אָב »).
    if " - " in h1_txt:
        translit = h1_txt.split(" - ", 1)[0].strip()
    else:
        translit = h1_txt or translit_nom

    # Longueur variable et fiable seulement en contrôle : « Strong n° 01 »,
    # « 010 », « 08672 ». La regex est non gloutonne — `.{0,3}` équieré mangé
    # un chiffre et créait des milliers de faux doublons.
    strong_line = re.search(r"Strong n[^\d]{0,3}(\d+)", header)

    pron = re.search(r"<i>Prononciation \[(.*?)\]</i>", header)
    entry = {
        "strong": f"{pref}{int(num):04d}",
        "language": language,
        "lemma": lemma_nom or translit,
        "transliteration": translit,
        "pronunciation": pron.group(1) if pron else None,
        "source": name,
    }
    if strong_line and int(strong_line.group(1)) != int(num):
        entry["strongLineNumber"] = int(strong_line.group(1))

    raw_sections = {}
    for titre, corps in sections.items():
        raw_sections[titre] = corps.strip()
        champ = fields.get(titre)
        if champ:
            entry[champ] = text_of(corps)
    if not entry.get("nature"):
        # 3 fiches GRC portent la valeur dans l'intitulé (« Nom masculin »)
        # au lieu du libellé « Nature du mot » : le corps de rangée est vide,
        # la valeur fait donc foi. Les intitulés restent bruts dans sections.
        for titre, corps in sections.items():
            if titre not in fields and not text_of(corps):
                entry["nature"] = titre
                break
    if "Occurrences" in sections:
        entry["occurrences"] = parse_occurrences(sections["Occurrences"])
    entry["sections"] = raw_sections

    # Lemma accentué/pointillé : l'étymologie s'ouvre sur « base - variante »
    # (« תשע - תֵּשַׁע », « παιδευτης - παιδευτής »). On le prend quand les deux
    # côtés sont de l'hébreu ou du grec — sinon on garde le lemma du nom.
    if entry.get("etymology"):
        first = entry["etymology"].split("\n", 1)[0].strip()
        m = re.match(r"^(\S+)\s+-\s+(\S+)$", first)
        if (m and all(any(is_hebrew_greek(c) for c in part) for part in m.groups())):
            entry["lemma"] = m.group(2)

    return entry


def is_hebrew_greek(c: str) -> bool:
    o = ord(c)
    return 0x0590 <= o <= 0x05FF or 0x0370 <= o <= 0x03FF


def parse_occurrences(html_text: str) -> dict:
    """<p>58 fois dans 57 versets de 14 livres bibliques (AT)</p><ul><li>Genèse (13)</li>…"""
    txt = text_of(html_text)
    summary = ""
    books: dict[str, int] = {}
    for line in txt.split("\n"):
        m = re.match(r"(.+?) \((\d+)\)$", line)
        if m:
            books[m.group(1).strip()] = int(m.group(2))
        elif "fois dans" in line and not summary:
            # « 0 fois dans la Bible » (formule des entrées vides) comme
            # « 1215 fois dans 1061 versets… ». Deux fiches ont perdu le
            # total : « fois dans 7 versets… » — il vaut la somme des livres.
            summary = line
    if summary.startswith("fois dans") and books:
        summary = f"{sum(books.values())} {summary}"
    return {"summary": summary, "books": books}


# --------------------------------------------------------------------------- #
# Extraction fichier par fichier                                               #
# --------------------------------------------------------------------------- #

def extract(code: str) -> dict:
    files, toc = load(code)
    problems, quirks = check_alignment(code, files, toc)
    root = OUT / code
    entries: dict[str, dict] = {}
    written = images = skipped = 0

    for data, (name, addr) in zip(files, toc):
        dest = safe_path(root, name)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        written += 1
        if data[:3] == b"GIF" or data[:4] == b"\x89PNG":
            images += 1
            continue
        entry = parse_entry(code, name, data)
        if entry:
            if entry["strong"] in entries:
                problems.append(f"clé dupliquée {entry['strong']} ({name})")
            entries[entry["strong"]] = entry
        else:
            skipped += 1

    # index TOC
    lines = ["index\tnom\taddr\toctets\ttype"]
    for i, ((name, addr), data) in enumerate(zip(toc, files)):
        if data[:3] == b"GIF" or data[:4] == b"\x89PNG":
            kind = "image"
        elif name.endswith("styles.css"):
            kind = "css"
        elif re.match(r"^\d{4} ", Path(name).stem):
            kind = "fiche"
        else:
            kind = "index"
        lines.append(f"{i}\t{name}\t{addr}\t{len(data)}\t{kind}")
    (root / "toc.tsv").write_text("\n".join(lines), encoding="utf-8")

    # entrées parsées
    bundle = {
        "schema": "bym.biblia-dict.v1",
        "source": f"Biblia Universalis 3 (1.39) — Dictionnaires {'hébreu-français' if code == 'HEB' else 'grec-français'}",
        "language": "hebrew" if code == "HEB" else "greek",
        "count": len(entries),
        "entries": dict(sorted(entries.items())),
    }
    (root / "entries.json").write_text(
        json.dumps(bundle, ensure_ascii=False, indent=1), encoding="utf-8"
    )

    report = {
        "code": code,
        "blocs": len(files),
        "entrees_toc": len(toc),
        "fichiers_ecrits": written,
        "images": images,
        "pages_sans_fiche": skipped,
        "entrees_strong": len(entries),
        "problemes_alignement": problems,
        "anomalies_source": quirks,
    }
    return report


# --------------------------------------------------------------------------- #
# Rapport de comparaison avec strong_fr.json                                   #
# --------------------------------------------------------------------------- #

def rapport(reports: list[dict]) -> str:
    sf = json.loads(ASSETS.read_text(encoding="utf-8"))
    sf_entries = sf["entries"]
    sf_keys = {"H": set(), "G": set()}
    for k in sf_entries:
        sf_keys[k[0]].add(k)

    out = ["# HEB / GRC vs strong_fr.json (modules SWORD)", ""]
    out.append(f"- `strong_fr.json` : schéma {sf['schema']} — {sf['source']}")
    out.append(f"- {len(sf_entries)} entrées : "
               f"{len(sf_keys['H'])} hébreu, {len(sf_keys['G'])} grec")
    out.append("")
    for rep in reports:
        code = rep["code"]
        pref = "H" if code == "HEB" else "G"
        keys = set(json.loads((OUT / code / "entries.json").read_text(encoding="utf-8"))["entries"])
        commun = keys & sf_keys[pref]
        out.append(f"## {code} — {rep['entrees_strong']} entrées Strong "
                   f"({rep['blocs']} blocs, {rep['images']} images, "
                   f"{rep['pages_sans_fiche']} pages sans fiche)")
        out.append(f"- communes avec strong_fr : {len(commun)}")
        out.append(f"- seulement dans {code} : {sorted(keys - sf_keys[pref])}")
        out.append(f"- seulement dans strong_fr : {sorted(sf_keys[pref] - keys)}")
        if rep["problemes_alignement"]:
            out.append(f"- **problèmes d'alignement : {len(rep['problemes_alignement'])}**")
            out += [f"  - {p}" for p in rep["problemes_alignement"][:20]]
        else:
            out.append("- alignement blocs ↔ TOC : OK (0 écart)")
        if rep["anomalies_source"]:
            out.append(f"- anomalies de la source ({len(rep['anomalies_source'])}), "
                       f"sans effet sur les clés :")
            out += [f"  - {p}" for p in rep["anomalies_source"][:20]]
        out.append("")
    # comparaison de contenu sur les entrées communes
    out.append("## Écarts de contenu (sur les entrées communes)")
    out.append("« Identiques » = mêmes puces après neutralisation typographique "
               "(apostrophes, espaces, points finaux, guillemets).")
    for code in ("HEB", "GRC"):
        entries = json.loads((OUT / code / "entries.json").read_text(encoding="utf-8"))["entries"]
        pref = "H" if code == "HEB" else "G"
        commun = sorted(set(entries) & sf_keys[pref])
        identiques = diff = 0
        exemples = []
        for k in commun:
            a = [_norm(ln) for ln in entries[k].get("strongDefinition", "").split("\n")
                 if ln.strip()]
            b = [_norm(s) for s in sf_entries[k].get("senses", [])]
            if a == b:
                identiques += 1
            else:
                diff += 1
                if len(exemples) < 3:
                    exemples.append((k, a[:3], b[:3]))
        out.append(f"- {code} : {identiques} définitions identiques, "
                   f"{diff} différentes, sur {len(commun)}")
        for k, a, b in exemples:
            out.append(f"  - {k} dico={a}")
            out.append(f"       strong_fr={b}")

    # sections portées par les dictionnaires, et ce qu'elles recouvrent
    out.append("")
    out.append("## Sections de HEB / GRC et ce que strong_fr.json couvre déjà")
    out.append("`strong_fr.json` porte déjà `definition`, `senses`, `outline`, "
               "`signification`, `etymology` et `partOfSpeech` : Étymologie et "
               "Nature du mot recouvrent ces champs (à dire près), Occurrences, "
               "Synonymes et Spicq sont du contenu que la base n'a pas, "
               "Bailly et Sander et Trenel sont écartés de la fusion "
               "(voir rapport_fusion.md).")
    for code in ("HEB", "GRC"):
        entries = json.loads((OUT / code / "entries.json").read_text(encoding="utf-8"))["entries"]
        from collections import Counter
        secs: Counter = Counter()
        for e in entries.values():
            secs.update(e.get("sections", {}).keys())
        out.append(f"- **{code}** ({len(entries)} entrées) :")
        for titre, n in secs.most_common():
            out.append(f"  - {titre} : {n}")
    out.append("")
    return "\n".join(out)


def _norm(s: str) -> str:
    """Apostrophes, espaces, guillemets, points finaux -> canonique."""
    s = s.replace("’", "'").replace("‘", "'").replace("ʼ", "'")
    s = s.replace("«", "").replace("»", "").replace('"', "")
    s = re.sub(r"\s+", " ", s).strip()
    return s.rstrip(".").strip()


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description="Extrait HEB.xml et GRC.xml")
    ap.add_argument("--rapport", action="store_true",
                    help="génère rapport_comparaison.md (compare à strong_fr.json)")
    args = ap.parse_args()

    reports = []
    for code in ("HEB", "GRC"):
        rep = extract(code)
        reports.append(rep)
        print(f"{code}: {rep['fichiers_ecrits']} fichiers, "
              f"{rep['entrees_strong']} entrées Strong, "
              f"{rep['images']} images, {rep['pages_sans_fiche']} pages index/css")
        if rep["problemes_alignement"]:
            print(f"  {len(rep['problemes_alignement'])} problème(s) d'alignement:")
            for p in rep["problemes_alignement"][:10]:
                print(f"    - {p}")
        else:
            print("  alignement blocs ↔ TOC : OK")
        if rep["anomalies_source"]:
            print(f"  {len(rep['anomalies_source'])} anomalie(s) de la source "
                  f"(numéro/titre, sans effet sur les clés)")

    if args.rapport:
        md = rapport(reports)
        (OUT / "rapport_comparaison.md").write_text(md, encoding="utf-8")
        print("\n" + md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
