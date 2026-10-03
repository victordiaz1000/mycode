#!/usr/bin/env python3
"""Fusionne strong_fr.json (SWORD) + les sections HEB/GRC de Biblia Universalis.

Sortie : extraction/strong_fr_v2.json, schéma bym.strong.v2 inchangé (le
chargeur Dart ne lit que les champs qu'il connaît) plus un objet « biblia »
par entrée pour le contenu que SWORD ne couvre pas :

    biblia.occurrences  {summary, books}   Occurrences (14 175 entrées)
    biblia.nature       texte              Nature du mot, seulement si ≠
                                           partOfSpeech (1 318 entrées)
    biblia.etymology    texte              Étymologie, seulement si ≠
                                           etymology (11 571 entrées) ; la
                                           ligne « base - lemma » d'ouverture
                                           est retirée, le lemma étant déjà
                                           un champ
    biblia.synonyms     liste de lignes    Synonymes (GRC, 167 entrées)
    biblia.spicq        texte              Spicq (GRC, 2 entrées)

Sections écartées à la demande : « Définition Bailly » et « Définition
Sander et Trenel ». Aucun HTML brut : les valeurs de entries.json sont
déjà du texte (text_of).

Le fichier fusionné n'est PAS embarqué : l'application lit strong_fr.json,
la base SWORD. La sortie vit dans extraction/ et non dans
bible_app/assets/lexicon/ parce que le pubspec y liste le dossier en
entier — y déposer le fichier le remonterait dans le bundle. Pour réintégrer
la fusion : --sortie bible_app/assets/lexicon/strong_fr_v2.json, déclarer ce
fichier dans le pubspec (à l'unité, jamais le dossier), et pointer
_assetPath de strong_lexicon.dart dessus.

Les clés absentes de strong_fr.json (G2994, G2995) sont construites aux
champs mêmes du schéma, avec outline quand la source numérote.

Chaîne de production :
    appCodebar/sword_zld_to_json.py     base SWORD  -> strong_fr.json
    extraction/extract_heb_grc.py       dictionnaires -> entries.json
    extraction/fusion_strong_v2.py      fusion      -> extraction/strong_fr_v2.json

Usage : python extraction/fusion_strong_v2.py
Python 3.12, stdlib uniquement.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "bible_app" / "assets" / "lexicon" / "strong_fr.json"
OUT = ROOT / "extraction" / "strong_fr_v2.json"
DICTS = (
    ROOT / "extraction" / "HEB" / "entries.json",
    ROOT / "extraction" / "GRC" / "entries.json",
)

# Ce qui, dans une entrée de dictionnaire, ne doit jamais rejoindre la fusion :
# sections rejetées, HTML, doublons des champs SWORD déjà portés par la base.
FORBIDDEN = {
    "bailly",
    "sanderTrenel",
    "sections",
    "strongDefinition",
    "strongLineNumber",
    "source",
}
BIBLIA = ("occurrences", "nature", "etymology", "synonyms", "spicq")


def norm(value: str) -> str:
    """Neutralise la typographie pour comparer deux libellés."""
    value = value.replace("’", "'").replace("‘", "'").replace("ʼ", "'")
    value = value.replace("«", "").replace("»", "").replace('"', "")
    value = re.sub(r"\s+", " ", value).strip()
    return value.rstrip(".").strip().lower()


def is_hebrew_greek(char: str) -> bool:
    code = ord(char)
    return 0x0590 <= code <= 0x05FF or 0x0370 <= code <= 0x03FF


def strip_lemma(etymology: str) -> str:
    """Retire la ligne d'ouverture « base - lemma » de l'étymologie.

    Le dictionnaire ouvre son étymologie sur « תשע - תֵּשַׁע » (ou sur le seul
    lemma, parfois avec « < » de comparaison : « α < א ») ; ce couple est déjà
    couvert par le champ lemma, il ne faut pas le dupliquer dans la fiche.
    Sur les 14 176 étymologies de deux lignes, la première est un tel en-tête
    dans tous les cas — jamais de prose — dès lors qu'elle contient des
    caractères hébreux ou grecs. Les étymologies d'une seule ligne sont
    laissées telles quelles : les retirer les viderait.
    """
    lines = (etymology or "").split("\n")
    if len(lines) > 1 and any(is_hebrew_greek(c) for c in lines[0]):
        lines = lines[1:]
    return "\n".join(line for line in lines if line.strip()).strip()


def biblia_block(dic: dict, entry: dict) -> dict:
    """Les sections Biblia non couvertes par les champs SWORD de entry.

    nature et etymology ne sont ajoutés que s'ils disent autre chose que le
    champ déjà présent : la même donnée en double ne sert personne.
    """
    block: dict = {}

    occurrences = dic.get("occurrences") or {}
    if occurrences.get("books") or occurrences.get("summary"):
        block["occurrences"] = {
            "summary": occurrences.get("summary", ""),
            "books": occurrences.get("books", {}),
        }

    nature = (dic.get("nature") or "").strip()
    if nature and norm(nature) != norm(entry.get("partOfSpeech") or ""):
        block["nature"] = nature

    etymology = strip_lemma(dic.get("etymology") or "")
    if etymology and norm(etymology) != norm(entry.get("etymology") or ""):
        block["etymology"] = etymology

    synonyms = [line for line in (dic.get("synonyms") or "").split("\n") if line.strip()]
    if synonyms:
        block["synonyms"] = synonyms

    spicq = (dic.get("spicq") or "").strip()
    if spicq:
        block["spicq"] = spicq

    return block


def synthesize(key: str, dic: dict) -> dict:
    """Construit une entrée bym.strong.v2 pour une clé absente de la base.

    G2994 et G2995 existent dans le dictionnaire et dans le texte LSGS,
    mais pas dans les modules SWORD : sans cette entrée la fiche affiche
    « Définition Strong non disponible » au tap.
    """
    senses = [line for line in (dic.get("strongDefinition") or "").split("\n") if line.strip()]
    definition = "\n".join(f"• {sense}" for sense in dict.fromkeys(senses))
    if not definition:
        definition = "Définition non disponible."

    entry: dict = {
        "strong": key,
        "language": dic["language"],
        "lemma": dic.get("lemma") or "",
        "transliteration": dic.get("transliteration") or "",
        "partOfSpeech": (dic.get("nature") or "").strip(),
        "etymology": strip_lemma(dic.get("etymology") or ""),
        "senses": list(dict.fromkeys(senses)),
        "definition": definition,
    }
    if dic.get("pronunciation"):
        entry["pronunciation"] = dic["pronunciation"]

    # La source numérote parfois ses sens (« la gorge » puis, en dessous,
    # « l'instrument… ») : un <ol> imbriqué dans le premier <li> le signale,
    # et chaque ligne suivante descend d'un cran.
    section = (dic.get("sections") or {}).get("Définition Strong", "")
    if len(senses) > 1 and re.search(r"<li>[^<]*<ol", section, re.S):
        entry["outline"] = [
            {"level": 0, "kind": "sense", "text": senses[0]},
            *(
                {"level": 1, "kind": "sense", "text": sense}
                for sense in senses[1:]
            ),
        ]
    return entry


def ordered(base_entries: dict, new_entries: dict) -> dict:
    """Base dans son ordre, clés neuves insérées à leur rang numérique."""
    pending = {
        prefix: sorted(
            (key for key in new_entries if key.startswith(prefix)),
            key=lambda key: int(key[1:]),
        )
        for prefix in ("H", "G")
    }
    result: dict = {}
    for key, entry in base_entries.items():
        prefix, number = key[0], int(key[1:])
        while pending.get(prefix) and int(pending[prefix][0][1:]) < number:
            new_key = pending[prefix].pop(0)
            result[new_key] = new_entries[new_key]
        result[key] = entry
    for prefix in ("H", "G"):
        for new_key in pending.get(prefix, []):
            result[new_key] = new_entries[new_key]
    return result


def check(payload: dict, base: dict, dicts: dict) -> list[str]:
    """Contrôles de non-régression. Renvoie la liste des échecs."""
    problems: list[str] = []
    entries = payload["entries"]
    base_entries = base["entries"]

    for key, original in base_entries.items():
        merged = entries.get(key)
        if merged is None:
            problems.append(f"{key} : perdue dans la fusion")
            continue
        for field, value in original.items():
            if merged.get(field) != value:
                problems.append(f"{key}.{field} : champ SWORD modifié")

    for key, entry in entries.items():
        banned = FORBIDDEN & set(entry)
        if banned:
            problems.append(f"{key} : clés interdites {sorted(banned)}")
        for field in entry.get("biblia", {}):
            if field not in BIBLIA:
                problems.append(f"{key} : section biblia inattendue {field!r}")

    for key in sorted(set(dicts) - set(base_entries)):
        entry = entries.get(key)
        if entry is None:
            problems.append(f"{key} : entrée du dictionnaire non créée")
        elif not entry.get("senses") or "•" not in entry.get("definition", ""):
            problems.append(f"{key} : entrée vide")

    # HTML résiduel : text_of retire les balises, on vérifie qu'aucune n'échappe.
    # Un « < » de texte (« α < א », comparaison hébreu) n'est pas une balise.
    tag = re.compile(r"</?[a-zA-Z!][^>]*>|&#\d+;")
    for key, entry in entries.items():
        block = entry.get("biblia", {})
        for field, value in block.items():
            texts = value if isinstance(value, list) else [value]
            if isinstance(texts[0], dict):
                texts = list(texts[0].values())
            for text in texts:
                if tag.search(str(text)):
                    problems.append(f"{key}.biblia.{field} : HTML résiduel")
                    break
    return problems


def rapport(payload: dict, base: dict, missing: dict, stats: dict,
            sortie: Path, size: int) -> str:
    """extraction/rapport_fusion.md — régénéré à chaque exécution."""

    def rel(path: Path) -> str:
        try:
            return path.relative_to(ROOT).as_posix()
        except ValueError:
            return path.as_posix()

    origine = {
        "occurrences": "Occurrences (livres + total)",
        "nature": "Nature du mot, seulement si ≠ `partOfSpeech`",
        "etymology": "Étymologie, seulement si ≠ `etymology` "
                     "(en-tête lemma retiré)",
        "synonyms": "Synonymes (GRC)",
        "spicq": "Définition approfondie Spicq (GRC)",
    }
    lines = [
        "# Fusion strong_fr.json + HEB/GRC → strong_fr_v2.json",
        "",
        f"- sortie : `{rel(sortie)}`",
        "- schéma : `bym.strong.v2`, inchangé — le chargeur Dart ne lit que les",
        "  champs qu'il connaît : l'objet `biblia` par entrée est simplement",
        "  ignoré en lecture",
        f"- source : {payload['source']}",
        f"- copyright : {payload['copyright']}",
        "",
        "## Chaîne de production",
        "",
        "```",
        "appCodebar/sword_zld_to_json.py  → assets/lexicon/strong_fr.json    (base, embarquée)",
        "extraction/extract_heb_grc.py    → extraction/{HEB,GRC}/entries.json",
        "extraction/fusion_strong_v2.py   → extraction/strong_fr_v2.json   (hors bundle)",
        "```",
        "",
        "Ce fichier fusionné n'est **pas embarqué** : l'application lit",
        "`assets/lexicon/strong_fr.json`, la base SWORD. La sortie vit dans",
        "`extraction/` parce que le `pubspec.yaml` liste `assets/lexicon/` en entier :",
        "y déposer la fusion la remonterait dans le bundle. Pour la réintégrer —",
        "`--sortie bible_app/assets/lexicon/strong_fr_v2.json`, déclarer ce fichier",
        "dans le `pubspec.yaml` (à l'unité, jamais le dossier) et pointer `_assetPath`",
        "de `strong_lexicon.dart` dessus.",
        "",
        "## Contenu ajouté (objet `biblia`)",
        "",
        "| champ | entrées | origine |",
        "| --- | --- | --- |",
    ]
    for field in BIBLIA:
        lines.append(f"| `biblia.{field}` | {stats[field]:d} | {origine[field]} |")
    lines += [
        "",
        "## Écartés",
        "",
        "- **Définition Bailly** et **Définition Sander et Trenel** : rejetés à la",
        "  demande. Ni ces textes, ni aucun HTML brut, ni les champs `sections`,",
        "  `strongDefinition`, `strongLineNumber` et `source` au sein d'une entrée —",
        "  contrôle inclus dans le générateur (`FORBIDDEN`).",
        "",
        "## Créées",
        "",
        f"- {', '.join(sorted(missing))} : entrées complètes (lemma, nature, sens,",
        "  plan, définition), citées par le LSGS mais absentes de `strong_fr.json`.",
        "",
        "## Contrôles — exécutés à chaque génération",
        "",
        "- base intacte : les 11 champs du schéma repris champ par champ ;",
        "- clés bannies absentes, aucun balisage résiduel ;",
        "- `python extraction/valider_v2.py` : relecture indépendante du fichier",
        "  écrit (même contrôles, plus en-tête, entrées créées et compteurs",
        "  `biblia`).",
        "",
        "## Poids",
        "",
        f"- base : {BASE.stat().st_size / 1e6:.2f} Mo → fusion : {size / 1e6:.2f} Mo",
        f"- entrées : {len(base['entries']):d} + {len(missing)} créées = "
        f"{len(payload['entries']):d}",
        "",
        "Régénérer : `python extraction/fusion_strong_v2.py` (ce fichier suit).",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Fusionne strong_fr.json + HEB/GRC")
    parser.add_argument("--sortie", type=Path, default=OUT, help="JSON fusionné à écrire")
    args = parser.parse_args()

    base = json.loads(BASE.read_text(encoding="utf-8"))
    dicts: dict[str, dict] = {}
    for path in DICTS:
        dicts.update(json.loads(path.read_text(encoding="utf-8"))["entries"])

    entries = {key: dict(value) for key, value in base["entries"].items()}
    stats = {field: 0 for field in BIBLIA}
    for key, dic in dicts.items():
        if key not in entries:
            continue
        block = biblia_block(dic, entries[key])
        if block:
            entries[key]["biblia"] = block
            for field in block:
                stats[field] += 1

    missing = {key: synthesize(key, dic) for key, dic in dicts.items() if key not in entries}
    for entry in missing.values():
        block = biblia_block(dicts[entry["strong"]], entry)
        if block:
            entry["biblia"] = block
            for field in block:
                stats[field] += 1

    payload = {
        "schema": "bym.strong.v2",
        "source": "CrossWire/SWORD FreStrongsHebrew + FreStrongsGreek ; "
                  "sections supplémentaires : Biblia Universalis 3 (1.39) "
                  "dictionnaires HEB/GRC",
        "copyright": "Biblia Universalis — Laurent Soufflet © 2016–2026",
        "entries": ordered(entries, missing),
    }

    problems = check(payload, base, dicts)
    if problems:
        for problem in problems[:40]:
            print(f"ECHEC: {problem}")
        print(f"{len(problems)} échec(s), fichier non écrit")
        return 1

    args.sortie.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    size = args.sortie.stat().st_size
    base_size = BASE.stat().st_size
    print(f"Entrées : {len(base['entries'])} base + {len(missing)} créées "
          f"({', '.join(sorted(missing))}) = {len(payload['entries'])}")
    for field in BIBLIA:
        print(f"  biblia.{field}: {stats[field]}")
    print(f"Contrôles : OK (base intacte, {len(FORBIDDEN)} clés bannies, sans HTML)")
    print(f"Taille : {base_size / 1e6:.2f} Mo -> {size / 1e6:.2f} Mo -> {args.sortie}")
    md = ROOT / "extraction" / "rapport_fusion.md"
    md.write_text(rapport(payload, base, missing, stats, args.sortie, size),
                  encoding="utf-8")
    print(f"Rapport : {md}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
