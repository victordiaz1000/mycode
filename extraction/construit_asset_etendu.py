# -*- coding: utf-8 -*-
"""Fabrique l'asset embarqué des codes de forme (numérotation étendue).

Lecture : extraction/strong_etendu_glosses.json      (recupere_etendu_emcitv.py)
          extraction/strong_etendu_glosses_grec.json (tour grec, en parallèle)
Écriture : bible_app/assets/lexicon/strong_etendu.json

Le lexique Strong embarqué s'arrête à H8674, mais Biblia numérote jusqu'à
8853 (5799 en grec). Ces codes ne sont pas des lexies : ils décrivent une
forme — un binyan croisé avec un mode, un kethiv, un mot non rendu. On les
expose comme tels, avec l'intitulé et la définition que la source leur donne.

Deux sources de texte se partagent le fichier, dans cet ordre :
  1. [RADICAUX] et [MODES] — nos propres glosses, écrites pour les seuls
     termes que la vérification sur contextes réels de la LSS a établis, et
     qui contredisent la source nulle part. La source ne définit que six
     termes ; le reste n'aurait que la catégorie.
  2. le texte de la source — nettoyé, jamais complété.

Rien d'autre n'est écrit : un champ vide reste vide, un code que personne ne
définit ne reçoit pas de fiche et retombe sur la notice « hors lexique ».

Usage :
    python construit_asset_etendu.py
"""
import json
import re
from pathlib import Path

ICI = Path(__file__).resolve().parent
# Les deux tours de récupération (hébreu, grec) partent sur des fichiers
# distincts pour pouvoir tourner ensemble : on lit celui qui est là.
SOURCES = (
    ICI / "strong_etendu_glosses.json",
    ICI / "strong_etendu_glosses_grec.json",
)
CIBLE = ICI.parent / "bible_app" / "assets" / "lexicon" / "strong_etendu.json"

# Ce que la source écrit dans une définition de combinaison, dans l'ordre où
# elle l'écrit, avec l'étiquette qu'on lui donne. `nombre` en est dehors : le
# site y met tantôt un compte d'occurrences, tantôt un lien sans rapport.
CHAMPS = (
    ("radical", "radical"),
    ("mode", "mode"),
    ("temps", "temps"),
    ("personne", "personne"),
    ("genre", "genre"),
    ("type", "type"),
)

# Nos glosses — établies sur les formes et les versets réels de la LSS (Gen
# 1:5/1:10/1:27 pour le parfait, les waw consécutifs pour l'imparfait, les
# participes en מְ/מֻ/מִ pour les trois voix…). Elles décrivent une
# catégorie, jamais un sens particulier : ces codes numérotent des formes.
RADICAUX = {
    "qal": "forme simple, à la voix active.",
    "piel": "forme intensive de l'action.",
    "nifal": "forme à la voix moyenne ou passive — le sujet subit l'action.",
    "hifil": "forme causative — le sujet fait faire l'action.",
    "hitpael": (
        "forme réfléchie ou réciproque — le sujet se l'inflige, ou la partage."
    ),
    "hofal": "forme passive du hifil.",
    "pual": "forme passive du piel.",
    "peal": "forme simple de l'araméen biblique.",
    "afel": "causatif de l'araméen biblique, l'équivalent du hifil.",
}

MODES = {
    "impératif": "le verbe est à l'ordre — il commande.",
    "imparfait": (
        "le verbe est au mode de ce qui se fait ou se fera ; avec le waw "
        "consécutif, il raconte au passé."
    ),
    "infinitif": (
        "le verbe est au nom d'action, souvent avec une préposition ou un "
        "suffixe."
    ),
    "participe": "le verbe qualifie, à l'adjectif ou au présent.",
    "participe actif": "le verbe qualifie au sujet faisant.",
    "participe passif": "le verbe qualifie au sujet subissant.",
    "parfait": "le verbe est au passé — il a eu lieu.",
}

# Un libellé tient en peu de mots : au-delà, le champ porte une définition,
# pas un nom — « Mot Hébreu non traduit dans la version Louis Segond » n'est
# pas le nom d'un radical. Huit mots laissent passer « Temps - Plus que
# Parfait Second », qui est pourtant bien un libellé.
def propre(valeur):
    """Le champ, nettoyé, ou None s'il est vide ou n'est pas un libellé."""
    if not isinstance(valeur, str):
        return None
    texte = re.sub(r"\s+", " ", valeur).strip()
    # La grecque écrit « Mode - Indicatif Voir Indicatif (5791) » : l'« Voir »
    # reste quand l'ancre est retirée.
    texte = re.sub(r"\s+Voir$", "", texte, flags=re.I).strip()
    if not texte or len(texte) > 48 or len(texte.split()) > 8:
        return None
    if re.search(r"[.;]", texte):
        return None
    return texte


def clef(nom):
    """« Radical - Hifil » → « radical - hifil » : pour joindre les légendes."""
    brut = re.sub(r"[«»\"()]", " ", str(nom or ""))
    return re.sub(r"\s+", " ", brut).strip().lower()


# Les classes que la source nomme elle-même. En hébreu la première ligne est
# un radical (« Voir Hifil (8818) »), en grec c'est un temps (« Voir Temps -
# Aoriste (5777) ») : le préfixe de l'intitulé dit lequel.
CLASSES = ("radical", "temps", "voix", "mode", "genre", "nombre", "personne", "type")
TIRET = re.compile(r"^(\w+)\s*[-–—]\s*(.*)$")


def classe_de(valeur):
    """« Temps - Aoriste Second » → (« temps », « Aoriste Second »)."""
    brut = re.sub(r"\s+", " ", str(valeur or "")).strip()
    appariement = TIRET.match(brut)
    if appariement and clef(appariement.group(1)) in CLASSES:
        return clef(appariement.group(1)), appariement.group(2).strip()
    return None, brut


def est_combination(entree):
    """Vrai pour une entrée qui combine deux classes, fausse pour un terme.

    Celle de la numérotation hébreue est nette : les 8680-8809 combinent un
    radical et un mode, les 8810-8853 nomment un terme — et un terme cite
    aussi parfois un radical (« Afel → voir Hifil »), d'où la garde. Côté
    grec l'intitulé porte le temps, pas la classe : c'est la présence d'un
    mode à placer qui décide.
    """
    if clef(entree.get("nom")).startswith("radical"):
        return True
    return clef(entree.get("nom")).startswith(("temps", "voix")) and bool(
        propre(entree.get("mode"))
    )


def parties_de(entree):
    """Les classes de l'entrée, étiquette française devant chacune.

    Le mode s'écrit en bas de casse — « mode imparfait », pas « mode
    Imparfait » — ; les autres sont des noms et gardent le leur.
    """
    classes, vus = [], {"radical"}
    radical = propre(entree.get("radical")) or str(entree.get("nom") or "")
    etiquette, valeur = classe_de(radical)
    etiquette = etiquette or "radical"
    if valeur:
        classes.append((etiquette, valeur))
        vus.add(etiquette)
    for champ, etiquette in CHAMPS:
        if etiquette in vus:
            continue
        if (valeur := propre(entree.get(champ))) is None:
            continue
        classes.append((etiquette, clef(valeur) if etiquette == "mode" else valeur))
        vus.add(etiquette)
    return [f"{etiquette} {valeur}" for etiquette, valeur in classes]


def categorie(entree):
    """Le badge de la fiche : l'intitulé des classes, mode compris.

    Un terme seul n'a pas de classes à énumérer — son intitulé suffit, et
    lui en coller une de hasard (le lien « Nombre » de la source) le ferait
    passer pour ce qu'il n'est pas.
    """
    if not est_combination(entree):
        return str(entree.get("nom") or "").strip()
    parties = parties_de(entree)
    if not parties:
        return str(entree.get("nom") or "").strip()
    return f"{parties[0][0].upper()}{parties[0][1:]}" + (
        f", {', '.join(parties[1:])}" if len(parties) > 1 else ""
    )


def prose(entree):
    """Le texte de la source pour un terme seul, espacé proprement."""
    return re.sub(r"\s+", " ", entree.get("texte") or "").strip()


PREMIERE = re.compile(r"^(.{20,400}?[.!?])(?:\s|$)")


def premiere_phrase(texte):
    """La première phrase du texte de la source, pour une carte.

    Les définitions grecques tiennent en un paragraphe — l'aoriste en a dix.
    Ce qui tient au-dessus de la carte suffit à nommer la notion ; la suite
    reste dans la récupération.
    """
    appariement = PREMIERE.match(texte)
    if appariement:
        return appariement.group(1).strip()
    return texte[:200].rstrip() + ("…" if len(texte) > 200 else "")


def legends(entrees):
    """Ce que la source dit des termes qu'elle nomme elle-même.

    En grec les 5774-5799 (« Temps - Aoriste », « Mode - Indicatif »), en
    hébreu les 8810-8853 (« Qal », « Impératif ») : les combinaisons y
    renvoient, on suit le renvoi.
    """
    table = {}
    for entree in entrees.values():
        if est_combination(entree):
            continue
        texte = prose(entree)
        if not texte:
            continue
        _, nom = classe_de(entree.get("nom"))
        table.setdefault(clef(nom), texte)
    return table


def glosses(entree, code):
    """Ce que nos tables disent du radical et du mode de l'entrée.

    Nos glosses décrivent l'hébreu — le waw consécutif n'existe pas en grec.
    Les codes grecs gardent la seule catégorie que la source leur donne : on
    ne les a pas vérifiés sur contextes, et rien ne justifie d'écrire à leur
    place.
    """
    if not code.startswith("H"):
        return []
    notes = []
    radical = clef(entree.get("radical"))
    if radical in RADICAUX:
        notes.append(RADICAUX[radical])
    mode = clef(entree.get("mode"))
    # « Parfait ou "passé " », « Participe Passif » : le mode tient dans ses
    # un ou deux premiers mots, la source ajoute sa propre appellation.
    for essai in (mode, mode.split()[0] if mode else ""):
        if essai in MODES:
            if MODES[essai] not in notes:
                notes.append(MODES[essai])
            break
    # Chaque glose est une phrase : elles se lisent l'une après l'autre.
    return [note[0].upper() + note[1:] for note in notes]


def definition(entree, code, table):
    """La phrase de la fiche : la catégorie d'abord, la glose ensuite."""
    if not est_combination(entree):
        return phrase_de_terme(entree)
    parties = parties_de(entree)
    if not parties:
        return phrase_de_terme(entree)
    liste = ", ".join(parties)
    categorie_texte = f"{liste[0].upper()}{liste[1:]}"
    notes = glosses(entree, code)
    if not notes:
        # Aucune glose de notre fait : on suit les renvois de la source,
        # un terme après l'autre.
        for partie in parties:
            legende = table.get(clef(partie.split(" ", 1)[1]))
            if legende:
                legende = premiere_phrase(legende)
                if legende not in notes:
                    notes.append(legende)
    if not notes:
        texte = prose(entree)
        return f"{categorie_texte} : {texte}" if texte else f"{categorie_texte}."
    return f"{categorie_texte} : {' '.join(notes)}"


def phrase_de_terme(entree):
    """Un terme seul : notre glose d'abord, le texte de la source ensuite."""
    nom = clef(entree.get("nom"))
    if nom in RADICAUX:
        return RADICAUX[nom]
    texte = prose(entree)
    if texte:
        return premiere_phrase(texte)
    return str(entree.get("nom") or "").strip()


def main():
    entrees, meta, lu = {}, {}, []
    for chemin in SOURCES:
        if not chemin.exists():
            continue
        donnees = json.loads(chemin.read_text(encoding="utf-8"))
        lu.append(chemin.name)
        meta.setdefault("_source", donnees.get("_source", ""))
        meta.setdefault("_recupere", donnees.get("_recupere", ""))
        for code, entree in (donnees.get("entrees") or {}).items():
            entrees.setdefault(code, entree)
    if not lu:
        raise SystemExit(
            "aucune récupération à lire : lancez recupere_etendu_emcitv.py "
            "d'abord (" + ", ".join(p.name for p in SOURCES) + ")"
        )

    table = legends(entrees)

    fiches = {}
    sans = []
    for code, entree in entrees.items():
        texte = definition(entree, code, table)
        if not texte:
            sans.append(code)
            continue
        fiche = {"strong": code, "definition": texte}
        pos = categorie(entree)
        if pos:
            fiche["partOfSpeech"] = pos
        fiches[code] = fiche

    CIBLE.parent.mkdir(parents=True, exist_ok=True)
    CIBLE.write_text(
        json.dumps(
            {
                "source": meta.get("_source", ""),
                "recupere": meta.get("_recupere", ""),
                "entries": fiches,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    print(
        f"{len(fiches)} fiches sur {len(entrees)} entrées lues de "
        f"{', '.join(lu)} ({len(sans)} sans définition : "
        f"{', '.join(sorted(sans, key=lambda c: int(c[1:]) or 0))}) → {CIBLE} "
        f"({CIBLE.stat().st_size / 1024:.1f} Ko)"
    )


if __name__ == "__main__":
    main()
