# -*- coding: utf-8 -*-
"""Textus Receptus (Stephanus 1550) vers le schéma interlinéaire BYM.

Entrée : TR-Stephanus-1550/texte/1.json … 27.json  (Matthieu … Apocalypse)
Sortie : bym-bibles/tr/40.json … 66.json

Le texte et la morphologie de Maurice A. Robinson (byztxt) sont en domaine
public. Le lexique Strong du kit, lui, est sous GPL 3.0 : il n'est pas
reporté ici, l'app portant son propre lexique.

## Ce qui est écrit

    m   grec sans accents  → `m`, qui fait du mot un mot grec pour l'app
                             (`AtiWord.greek`) : il se lit de gauche à droite
    s   numéro Strong nu   → `s`, préfixé de `G` : l'app le coupe de la même
                             façon pour l'afficher (`ati_interlinear`), et
                             c'est cette forme qu'elle donne à son lexique
    g   code Robinson      → `a`, décodé en français (voir plus bas), et
                             `g`, l'étiquette courte de la cellule

## Ce qui n'est pas écrit, et pourquoi

`s2` — second Strong (catégorie de composition). Aucun champ du schéma ne
le porte : le schéma n'a qu'un numéro par mot.

`variants` — les 216 segments de leçon Scrivener divergente, sur 206 versets.
Le schéma interlinéaire n'a pas d'endroit pour une seconde lecture : plutôt
que de la fondre dans le texte ou de l'écarter en silence, elle est comptée
et signalée ici. Le texte rendu est celui de Stephanus, jamais fusionné.

Les 5 mots dont `s` vaut `"0"` (formes composées ἐκπερισσου, ἐάνπερ) prennent
leur numéro dans `s2`, comme le dit le README du kit : `s2` y est un nombre
unique, ce qui n'est pas le cas partout.

## Le décodage

`N-NSF` n'est pas une analyse : c'est une clé de table. Le kit fournit lui-
même les tables qui lui donnent son sens — `morphologie/PARSING.COD` pour
les formes verbales, `morphologie/DECLINE.COD` pour le reste, tous deux de
Maurice A. Robinson, domaine public. Ce script ne fait que les relire en
français ; il n'y ajoute aucune grammaire qu'un de ces deux fichiers ne
dise.

Une seule règle d'écriture, la même que pour la WLC : les traits vont par
groupes séparés par « · ». `N-GSM` se lit « Nom· génitif singulier
masculin », `V-AAI-3S` « Verbe aoriste actif indicatif· 3ᵉ singulier » — la
nature et ses traits d'inflection d'un côté, ce qui qualifie le mot de
l'autre.

Le kit livre son grec **nu** : ni accents ni esprits, « les accents se
reconstituent par le lexique ou par la morphologie », dit son README. Un
`γενεσεως` sans accent se lit donc moins bien qu'un `γένεσις`, et la
translittération `geneseōs` y supplée. Elle est écrite en `t`, à côté de
chaque mot, d'après `translit_grec` — le même outil que pour le grec
accentué de l'interlinéaire.

Aucune donnée de Biblia Universalis n'entre ici : ce script ne lit que le
kit et son propre dossier de sortie.
"""
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

SOURCE = Path(__file__).resolve().parent
RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE.parent / "bym-bibles" / "tr"

# La translittération grecque vit à la racine, entre les kits : deux d'entre
# eux en ont besoin — l'interlinéaire et celui-ci.
sys.path.insert(0, str(RACINE))
from translit_grec import translitterer  # noqa: E402

# BYM → standard, copié de bym-classic/lib/data/book_mapping.dart.
BYM_VERS_STANDARD = {
    1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6, 7: 7, 8: 9, 9: 10, 10: 11,
    11: 12, 12: 23, 13: 24, 14: 26, 15: 28, 16: 29, 17: 30, 18: 31,
    19: 32, 20: 33, 21: 34, 22: 35, 23: 36, 24: 37, 25: 38, 26: 39,
    27: 19, 28: 20, 29: 18, 30: 22, 31: 8, 32: 25, 33: 21, 34: 17,
    35: 27, 36: 15, 37: 16, 38: 13, 39: 14, 40: 40, 41: 41, 42: 42,
    43: 43, 44: 44, 45: 59, 46: 48, 47: 52, 48: 53, 49: 46, 50: 47,
    51: 45, 52: 49, 53: 50, 54: 51, 55: 57, 56: 54, 57: 56, 58: 60,
    59: 61, 60: 55, 61: 65, 62: 58, 63: 62, 64: 63, 65: 64, 66: 66,
}
STANDARD_VERS_BYM = {v: k for k, v in BYM_VERS_STANDARD.items()}

# — Tables relues de morphologie/DECLINE.COD —————————————————————————

# « UNDECLINED FORMS » : pas de cas, pas de nombre, pas de genre.
INDECLINABLE = {
    "ADV": ("Adverbe", "Adverbe"),
    "CONJ": ("Conjonction", "Conjonction"),
    "COND": ("Particule conditionnelle", "Particule"),
    "PRT": ("Particule", "Particule"),
    "PREP": ("Préposition", "Préposition"),
    "INJ": ("Interjection", "Interjection"),
    "ARAM": ("Mot araméen translittéré", "Araméen"),
    "HEB": ("Mot hébreu translittéré", "Hébreu"),
}

# Les quatre indéclinables que DECLINE.COD écrit à deux letstres après la
# nature : « N-PRI = Indeclinable PRoper Noun » et ses trois compagnons.
INDECLINABLE_POSE = {
    ("N", "PRI"): ("Nom propre", "Nom propre"),
    ("N", "LI"): ("Nom — lettre", "Nom"),
    ("N", "OI"): ("Nom — autre forme", "Nom"),
    ("A", "NUI"): ("Adjectif — nombre cardinal", "Nombre"),
}

# « Prefixes » : la nature du mot décliné, et son étiquette de cellule.
PREFIXE = {
    "N": ("Nom", "Nom"),
    "A": ("Adjectif", "Adjectif"),
    "R": ("Pronom relatif", "Pronom relatif"),
    "C": ("Pronom réciproque", "Pronom réciproque"),
    "D": ("Pronom démonstratif", "Pronom démonstratif"),
    "T": ("Article défini", "Article"),
    "K": ("Pronom corrélatif", "Pronom corrélatif"),
    "I": ("Pronom interrogatif", "Pronom interrogatif"),
    "X": ("Pronom indéfini", "Pronom indéfini"),
    "Q": ("Pronom corrélatif ou interrogatif", "Pronom interrogatif"),
    "F": ("Pronom réfléchi", "Pronom réfléchi"),
    "S": ("Adjectif possessif", "Possessif"),
    "P": ("Pronom personnel", "Pronom"),
    "V": ("Verbe", "Verbe"),
}

# « Cases », « Number », « Gender », « Person ».
CAS = {"N": "nominatif", "V": "vocatif", "G": "génitif",
       "D": "datif", "A": "accusatif"}
NOMBRE = {"S": "singulier", "P": "pluriel"}
GENRE = {"M": "masculin", "F": "féminin", "N": "neutre"}
PERSONNE = {"1": "1ᵉʳ", "2": "2ᵉ", "3": "3ᵉ"}

# « Suffixes » de DECLINE.COD.
SUFFIXE = {
    "S": "superlatif",
    "C": "comparatif",
    "ABB": "forme abrégée",
    "I": "interrogatif",
    "N": "négatif",
    "K": "crase",
    "ATT": "forme attique",
}

# — Tables relues de morphologie/PARSING.COD ————————————————————————

TEMPS = {
    "P": "présent", "I": "imparfait", "F": "futur",
    "A": "aoriste", "R": "parfait", "L": "plus-que-parfait",
    # « Second peRfect » et compagnon : PARSING.COD les écrit 2A, 2F, 2R, 2L.
    "2A": "second aoriste", "2F": "second futur",
    "2R": "second parfait", "2L": "second plus-que-parfait",
}
VOIX = {
    "A": "actif", "M": "moyen", "P": "passif",
    "E": "moyen ou passif",
    "D": "déponent moyen", "O": "déponent passif",
    "N": "déponent moyen ou passif",
}
MODE = {
    "I": "indicatif", "S": "subjonctif", "O": "optatif",
    "M": "impératif", "N": "infinitif", "P": "participe",
}


class Inconnu(Exception):
    """Un code que ni PARSING.COD ni DECLINE.COD ne décrivent."""


def _suffixes(reste):
    """Sépare les suffixes officiels de ce qui qualifie la forme."""
    gardes, valides = [], []
    for bout in reste:
        if bout in SUFFIXE:
            valides.append(SUFFIXE[bout])
        else:
            gardes.append(bout)
    return gardes, valides


def _inflection(cas_nbre_genre):
    """« GSM » → « génitif singulier masculin »."""
    if len(cas_nbre_genre) != 3:
        raise Inconnu(cas_nbre_genre)
    cas, nombre, genre = cas_nbre_genre
    if cas not in CAS or nombre not in NOMBRE or genre not in GENRE:
        raise Inconnu(cas_nbre_genre)
    return "%s %s %s" % (CAS[cas], NOMBRE[nombre], GENRE[genre])


def _verbe(parts):
    """V-tense-voice-mood[-pers-nbre | -cas-nbre-genre][-ATT]"""
    if len(parts) < 2:
        raise Inconnu("-".join(parts))
    trois_lettres = parts[1]
    if len(trois_lettres) == 3:
        temps, voix, mode = trois_lettres
    elif len(trois_lettres) == 4:
        temps, voix, mode = trois_lettres[:2], trois_lettres[2], trois_lettres[3]
    else:
        raise Inconnu("-".join(parts))
    if temps not in TEMPS or voix not in VOIX or mode not in MODE:
        raise Inconnu("-".join(parts))

    reste, suffixes = _suffixes(parts[2:])
    corps = "Verbe %s %s %s" % (TEMPS[temps], VOIX[voix], MODE[mode])
    traits = [corps]
    if len(reste) > 1:
        raise Inconnu("-".join(parts))
    if reste:
        bout = reste[0]
        if len(bout) == 2 and bout[0] in PERSONNE:
            # Personne + nombre : la terminaison du verbe conjugué.
            if bout[1] not in NOMBRE:
                raise Inconnu("-".join(parts))
            traits.append("%s %s" % (PERSONNE[bout[0]], NOMBRE[bout[1]]))
        else:
            traits.append(_inflection(bout))
    traits.extend(suffixes)
    return "· ".join(traits)


def _decline(parts):
    """PREFIX-cas-nombre-genre-(suffixe).

    La personne est en tête quand la source l'écrit — « F-3DSF »,
    « S-2PDSM », « P-1AP » — et elle ne l'est pas sinon : le pronom de
    3ᵉ personne reste sans elle dans les données (« P-GSM »), les 1ʳᵉ et
    2ᵉ n'ayant pas de genre (« 1st and 2nd personal pronouns have no
    gender », DECLINE.COD). Un cas sans personne rejoint donc la voie
    commune cas-nombre-genre plutôt que d'être complété de mémoire.
    """
    nature = parts[0]
    if nature not in PREFIXE:
        raise Inconnu("-".join(parts))
    reste, suffixes = _suffixes(parts[1:])
    if len(reste) != 1:
        raise Inconnu("-".join(parts))
    nom, badge = PREFIXE[nature]
    forme = reste[0]
    a_personne = nature in ("F", "P", "S") and forme[:1] in PERSONNE

    if a_personne and nature == "S":
        # « S-2PDSM » : la personne, le nombre de l'appartenance, puis le
        # cas, le nombre et le genre du mot possédé.
        if len(forme) != 5 or forme[1] not in NOMBRE:
            raise Inconnu("-".join(parts))
        corps = "%s %s %s" % (nom, PERSONNE[forme[0]], NOMBRE[forme[1]])
        inflexion = _inflection(forme[2:])
    elif a_personne and nature == "F":
        if len(forme) != 4:
            raise Inconnu("-".join(parts))
        corps = "%s %s" % (nom, PERSONNE[forme[0]])
        inflexion = _inflection(forme[1:])
    elif a_personne and nature == "P" and len(forme) == 3:
        if forme[1] not in CAS or forme[2] not in NOMBRE:
            raise Inconnu("-".join(parts))
        corps = "%s %s" % (nom, PERSONNE[forme[0]])
        inflexion = "%s %s" % (CAS[forme[1]], NOMBRE[forme[2]])
    else:
        if len(forme) != 3:
            raise Inconnu("-".join(parts))
        corps = nom
        inflexion = _inflection(forme)

    return badge, "· ".join(t for t in [corps, inflexion] + suffixes if t)


def lire_morph(brut):
    """Code Robinson → (étiquette de cellule, analyse en français).

    Renvoie (None, None) si les deux tables du kit ne décrivent pas le code :
    l'app est appelée à le compter, jamais à l'inventer.
    """
    if not brut:
        return None, None
    parts = brut.split("-")
    nature = parts[0]
    try:
        if nature in INDECLINABLE:
            corps, badge = INDECLINABLE[nature]
            reste, suffixes = _suffixes(parts[1:])
            if reste:
                raise Inconnu(brut)
            return badge, "· ".join([corps] + suffixes)
        if len(parts) >= 2 and (nature, parts[1]) in INDECLINABLE_POSE:
            # « A-NUI-ABB » porte le même indéclinable qu'« A-NUI », suivi
            # de son suffixe : le corps se lit avant, le suffixe après.
            corps, badge = INDECLINABLE_POSE[(nature, parts[1])]
            _, suffixes = _suffixes(parts[2:])
            return badge, "· ".join([corps] + suffixes)
        if nature == "V":
            analyse = _verbe(parts)
        else:
            return _decline(parts)
        return PREFIXE["V"][1], analyse
    except Inconnu:
        return None, None


def chiffres(brut):
    """Strong du kit → `G976`, ou None si le kit n'en donne aucun."""
    if brut and brut.isdigit() and brut != "0":
        return "G" + brut
    return None


def convertir(standard, chemin):
    brut = json.load(open(chemin, encoding="utf-8"))
    court, long = [], []       # tables cg / ca du livre
    index_court, index_long = {}, {}
    livres, mots, sans_code, inconnus = [], 0, 0, 0
    s2_utilises = variants = 0

    for chapitre in brut["chapters"]:
        versets = []
        for verset in chapitre["verses"]:
            if verset.get("variants"):
                variants += len(verset["variants"])
            lignes = []
            for mot in verset["words"]:
                ligne = {"m": mot["m"]}
                translit = translitterer(mot["m"])
                if translit:
                    # Le mot nu se lit mal dans l'alphabet grec ; la
                    # translittération le restitue tel quel, y compris
                    # quand une même racine revient deux fois.
                    ligne["t"] = translit
                numero = chiffres(mot.get("s"))
                if numero is None:
                    numero = chiffres(mot.get("s2"))
                    if numero:
                        s2_utilises += 1
                if numero:
                    ligne["s"] = numero

                code = mot.get("g")
                etiquette, analyse = lire_morph(code)
                if not code:
                    # Le kit n'en donne pas à ce mot : il n'y a rien à
                    # lire, et rien à inventer à la place.
                    sans_code += 1
                elif analyse is None:
                    # Un code que PARSING.COD et DECLINE.COD ne décrivent
                    # pas — compté, jamais complété de mémoire.
                    inconnus += 1
                else:
                    if analyse not in index_long:
                        index_long[analyse] = len(long)
                        long.append(analyse)
                    ligne["a"] = index_long[analyse]
                    if etiquette not in index_court:
                        index_court[etiquette] = len(court)
                        court.append(etiquette)
                    ligne["g"] = index_court[etiquette]
                lignes.append(ligne)
                mots += 1
            versets.append({"verse": verset["verse"], "words": lignes})
        livres.append({"chapter": chapitre["chapter"], "verses": versets})

    return {
        "bym_index": STANDARD_VERS_BYM[standard],
        "standard": standard,
        "book": brut["book"],
        "osis_id": brut["osis_id"],
        "chapters": livres,
        "cg": court,
        "ca": long,
    }, mots, sans_code, inconnus, s2_utilises, variants


def main():
    SORTIE.mkdir(parents=True, exist_ok=True)
    total = sans_code = inconnus = total_s2 = total_variants = 0
    tailles_court, tailles_long = [], []
    for chemin in sorted((SOURCE / "texte").glob("*.json")):
        standard = int(chemin.stem) + 39        # Matthieu = standard 40
        livre, mots, codes_absents, codes_inconnus, s2, variants = \
            convertir(standard, chemin)
        with open(SORTIE / ("%d.json" % standard), "w",
                  encoding="utf-8", newline="\n") as flot:
            json.dump(livre, flot, ensure_ascii=False,
                      separators=(",", ":"))
            flot.write("\n")
        total += mots
        sans_code += codes_absents
        inconnus += codes_inconnus
        total_s2 += s2
        total_variants += variants
        tailles_court.append(len(livre["cg"]))
        tailles_long.append(len(livre["ca"]))
        print("  %-7s -> tr/%-2d.json  %-16s %3d ch.  %5d mots  "
              "%4d analyses"
              % (chemin.name, standard, livre["book"],
                 len(livre["chapters"]), mots, len(livre["ca"])))

    print("\n  total : %d mots" % total)
    print("  mots sans code morphologique: %d (laissés sans analyse)"
          % sans_code)
    print("  codes indécodables          : %d  (doit valoir 0)" % inconnus)
    print("  forts pris dans s2          : %d (les 5 annoncés)"
          % total_s2)
    print("  segments Scrivener ignorés  : %d (216 annoncés par le kit)"
          % total_variants)
    print("  table cg : %d … %d libellés par livre" % (min(tailles_court),
                                                       max(tailles_court)))
    print("  table ca : %d … %d analyses par livre" % (min(tailles_long),
                                                       max(tailles_long)))


if __name__ == "__main__":
    main()
