# -*- coding: utf-8 -*-
r"""
Extraction de la WLC — Westminster Leningrad Codex, avec Strong (wlc).

Source : OSHB-v.2.2 d'openscriptures/morphhb —
         https://github.com/openscriptures/morphhb/releases
         À télécharger soi-même (OSHB-v.2.2.zip, 5,3 Mo) et à décompresser
         à côté, ou chemin indiqué par SOURCE.
Sortie : bym-bibles/wlc/1.json … 39.json — un fichier par livre,
         numérotation standard 1=Genèse … 39=Malachie (jeton {book} de
         urlTemplate).

Ce qu'est le module : le texte hébreu du codex de Leningrad, mot à mot, chaque
mot avec son numéro Strong et son analyse morphologique — l'Ancien Testament
seul, sans un mot de français. Même famille que l'ATI (hébreu de Biblia
Universalis), le NTI et la SES (grec) : la sortie reprend leur schéma
(`cg`/`ca` + mots `h`/`d`/`s`/`g`/`a`), sans les clés qu'ici la source ne
porte pas — ni translittération, ni glose française. L'app lit ce schéma tel
quel (`bookFromAti`, rendu interlinéaire) : les colonnes montent le hébreu,
le Strong et l'analyse, la ligne de texte aplati restant vide, comme pour la
SES.

Rien n'est copié de l'ATI, qui est une autre édition : ce script lit les
fichiers OSIS et les traduit mot à mot. L'ATI n'est consultée nulle part, et
l'ordre des livres vient de la table LIVRES, non de ses données.

Format OSIS (constaté dans OSHB-v.2.2) :
  <div type="book" osisID="Gen">
    <chapter osisID="Gen.1"><verse osisID="Gen.1.1">
      <w lemma="b/7225" morph="HR/Ncfsa" id="01xeN">בְּ/רֵאשִׁ֖ית</w> …

- `lemma` porte le numéro Strong — l'en-tête le dit : `<workPrefix
  path="//w/@lemma" osisWork="Strong"/>`. La forme `b/7225` reflète le
  separateur de morphèmes du texte : la particule préfixée (`בְּ`) n'a pas de
  numéro propre, seule la tige en a une. `1254 a` est un numéro à variante,
  `1008+` un numéro renforcé, `l` un simple morphème sans numéro.
- `morph` porte la morphologie OSHB (`<workPrefix path="//w/@morph"
  osisWork="OSHM"/>`), huit parties de speech : A adjectif, C conjonction,
  D adverbe, N nom, P préposition, R pronom, T particule, V verbe.
- Le séparateur `h/olem` (`בְּ/רֵאשִׁ֖ית`) n'est pas une lettre du codex : il
  disparaît du mot et devient le separateur du découpage (`בְּ • רֵאשִׁ֖ית`),
  comme l'écrit l'ATI.
- `<seg type="x-maqqef">` (42 577), `x-sof-pasuq` (23 192) et `x-paseq`
  (2 278) sont des marqueurs de copiste rattachés au mot précédent : maqqef
  et sof pasuq sont du texte (`כִּי־`, `הָאָֽרֶץ׃`) et vont dans `h`. Les
  marques de parasha (`x-pe`, `x-samekh`) ne sont pas des lettres : elles
  sautent.
- Ketiv/qere : `<w type="x-ketiv">` est écrit sans points, la lecture est
  dans le `<rdg type="x-qere">` qui suit — c'est elle qui est servie. Trois
  cas, tous servis : une ketiv peut se déplier en plusieurs mots lus (Gen
  30:11, « ב/גד » écrit d'un seul tenant se lit « בָּא גָּד »), et un qere
  peut n'avoir aucune ketiv à remplacer (Juges 20:13, où il AJOUTE « בְּנֵי »
  — la note y est marquée « Adaptations to a Qere which L and BHS, by their
  design, do not indicate »).

Versification : la WLC n'est PAS remappée sur la numération KJV, bien que
`VerseMap.xml` le propose. L'ATI, hébreu déjà servi par l'app, compte la
Genèse, les Psaumes, 1 Samuel et en écart zéro chapitre contre la WLC native
— l'hébreu de l'app se lit donc en versification WLC, et remapperait la WLC
seule en décalage avec elle. « La WLC comme tel ».

Écart assumé, et documenté : l'ATI repointe `d` selon la forme canonique
(`h`=יָשָׁב mais `d`=יַשֵּׁב). Ce pointage éditorial n'est pas dérivable de la
WLC ; le pointage du codex est conservé tel quel.

Usage :  C:\Python312\python.exe WLC/wlc_to_json.py [livre]
Python 3.12, stdlib uniquement.
"""

from __future__ import annotations

import json
import os
import re
import sys
import unicodedata as ud
import xml.etree.ElementTree as ET
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SOURCE = Path(os.environ.get("WLC_SOURCE", r"C:\Users\laptek\AppData\Local\Temp\opencode\osshb\OSHB-v.2.2"))
RACINE = Path(__file__).resolve().parent
# Le dépôt servi par l'app, comme pour sef/sef_to_json.py : la sortie va
# directement où `urlTemplate` la lira.
SORTIE = Path(r"C:\Users\laptek\Desktop\bym-bibles\wlc")

NS = "{http://www.bibletechnologies.net/2003/OSIS/namespace}"

# Les huit parties de speech OSHB, leur lettre et leur nom français.
POS = {
    "A": "Adjectif",
    "C": "Conjonction",
    "D": "Adverbe",
    "N": "Nom",
    "P": "Préposition",
    "R": "Pronom",
    "T": "Particule",
    "V": "Verbe",
}

# (fichier OSHB, numéro standard, index BYM, nom français, chapitres attendus)
#
# La clé est le nom de fichier d'openscriptures/morphhb, pas le sigle OSIS
# à trois lettres que l'ATI porte dans `osis_id` : `Ps.xml`, `Song.xml`,
# `1Kgs.xml`. Les chapitres attendus sont ceux du canon ; ils servent de
# contrôle, pas de consigne — un écart est signalé, jamais corrigé en
# silence. L'index BYM n'est pas le numéro standard : il en diffère pour les
# livres poétiques (Ruth 31/8, Psaumes 27/19, Cantique 30/22).
LIVRES = [
    ("Gen", 1, 1, "Genèse", 50),
    ("Exod", 2, 2, "Exode", 40),
    ("Lev", 3, 3, "Lévitique", 27),
    ("Num", 4, 4, "Nombres", 36),
    ("Deut", 5, 5, "Deutéronome", 34),
    ("Josh", 6, 6, "Josué", 24),
    ("Judg", 7, 7, "Juges", 21),
    ("Ruth", 8, 31, "Ruth", 4),
    ("1Sam", 9, 8, "1 Samuel", 31),
    ("2Sam", 10, 9, "2 Samuel", 24),
    ("1Kgs", 11, 10, "1 Rois", 22),
    ("2Kgs", 12, 11, "2 Rois", 25),
    ("1Chr", 13, 38, "1 Chroniques", 29),
    ("2Chr", 14, 39, "2 Chroniques", 36),
    ("Ezra", 15, 36, "Esdras", 10),
    ("Neh", 16, 37, "Néhémie", 13),
    ("Esth", 17, 34, "Esther", 10),
    ("Job", 18, 29, "Job", 42),
    # 150 chapitres : la WLC n'a pas le Psaume 151, que la Septante a.
    ("Ps", 19, 27, "Psaumes", 150),
    ("Prov", 20, 28, "Proverbes", 31),
    ("Eccl", 21, 33, "Ecclésiaste", 12),
    ("Song", 22, 30, "Cantique des cantiques", 8),
    ("Isa", 23, 12, "Ésaïe", 66),
    ("Jer", 24, 13, "Jérémie", 52),
    ("Lam", 25, 32, "Lamentations", 5),
    ("Ezek", 26, 14, "Ézéchiel", 48),
    ("Dan", 27, 35, "Daniel", 12),
    ("Hos", 28, 15, "Osée", 14),
    ("Joel", 29, 16, "Joël", 4),
    ("Amos", 30, 17, "Amos", 9),
    ("Obad", 31, 18, "Abdias", 1),
    ("Jonah", 32, 19, "Jonas", 4),
    ("Mic", 33, 20, "Michée", 7),
    ("Nah", 34, 21, "Nahum", 3),
    ("Hab", 35, 22, "Habakuk", 3),
    ("Zeph", 36, 23, "Sophonie", 3),
    ("Hag", 37, 24, "Aggée", 2),
    ("Zech", 38, 25, "Zacharie", 14),
    ("Mal", 39, 26, "Malachie", 3),
]


def numero_strong(lemma: str) -> str | None:
    """`b/7225` → H7225 ; `1254 a` → H1254 ; `1008+` → H1008 ; `l` → None.

    Le séparateur de morphèmes du texte est reflété dans `lemma` : la
    particule préfixée n'a pas de numéro Strong propre, seule la tige en a.
    """
    dernier = lemma.split("/")[-1].strip()
    chiffres = re.match(r"(\d+)", dernier)
    return "H" + chiffres.group(1) if chiffres else None


def etiquettes(morph: str) -> tuple[str, str]:
    """Renvoie (clé de la table `cg`, clé de la table `ca`).

    La tête du mot est le dernier morphème qui porte une partie de speech —
    et non simplement le dernier. Un suffixe (`Sp3ms`) n'en porte pas : en
    `HNcmsc/Sp3ms` (« son nom »), le mot reste un nom, c'est le suffixe qui
    s'y ajoute, et l'étiquette courte doit dire Nom. En `HR/Ncfsa`
    (préposition + nom), la tête est au contraire le dernier morphème, la
    préposition n'étant qu'un préfixe.
    """
    sans_h = morph[1:] if morph.startswith("H") else morph
    morceaux = [m for m in sans_h.split("/") if m]
    porteurs = [m for m in morceaux if m[0] in POS]
    tete = porteurs[-1] if porteurs else (morceaux[-1] if morceaux else sans_h)
    court = POS.get(tete[0], tete) if tete else sans_h
    return court, sans_h


def mot_de(w: ET.Element) -> dict:
    """Traduit un `<w>` OSIS en entrée de mot, séparateur de morphèmes compris."""
    brut = w.text or ""
    return {
        # Le maqqef et le sof pasuq viennent s'y rattacher ensuite.
        "texte": brut.replace("/", ""),
        # Le découpage garde le pointage du texte, sans les marqueurs de
        # copiste rattachés après coup.
        "decoupe": brut.replace("/", " \u2022 "),
        "strong": numero_strong(w.get("lemma", "")),
        "morph": w.get("morph", ""),
    }


def lire_livre(chemin: Path) -> list[dict]:
    """Renvoie les chapitres, avec les ketiv/qere résolus vers le qere."""
    div = ET.parse(chemin).getroot().find(".//%sdiv[@type='book']" % NS)
    chapters = []
    for chapter in div.findall(NS + "chapter"):
        numero_chapitre = int(chapter.get("osisID").split(".")[1])
        verses = []
        for verse in chapter.findall(NS + "verse"):
            numero_verset = int(verse.get("osisID").split(".")[2])
            mots = []
            for enfant in verse:
                if enfant.tag == NS + "w":
                    if enfant.get("type") == "x-ketiv":
                        # Écrit sans points : la lecture est dans le rdg qui
                        # suit, et c'est elle qui compte.
                        continue
                    mots.append(mot_de(enfant))
                elif enfant.tag == NS + "note":
                    rdg = enfant.find(".//%srdg[@type='x-qere']" % NS)
                    if rdg is not None:
                        # Tous les `<w>` du rdg font partie de la lecture,
                        # qu'il y ait une ketiv à remplacer ou non.
                        mots.extend(mot_de(w) for w in rdg.findall(NS + "w"))
                elif enfant.tag == NS + "seg" and mots:
                    # Marqueurs de copiste rattachés au mot qui précède.
                    marque = enfant.get("type")
                    if marque in ("x-maqqef", "x-sof-pasuq", "x-paseq"):
                        sep = " " if marque == "x-paseq" else ""
                        mots[-1]["texte"] += sep + (enfant.text or "")
            verses.append({"verse": numero_verset, "words": mots})
        chapters.append({"chapter": numero_chapitre, "verses": verses})
    return chapters


def construire(fichier: str, standard: int, bym_index: int, nom: str) -> dict:
    chapters = lire_livre(SOURCE / (fichier + ".xml"))
    ca: list[str] = []
    cg: list[str] = []
    index_ca: dict[str, int] = {}
    index_cg: dict[str, int] = {}

    for chapter in chapters:
        for verse in chapter["verses"]:
            mots = []
            for mot in verse["words"]:
                out: dict[str, object] = {}
                # Normalisation NFC : le codex pose les points dans l'ordre
                # où le copiste les a écrits — בְּ arrive en ב + dagesh +
                # sheva, alors que l'Unicode canonique commande sheva puis
                # dagesh. Rien n'y perd son contenu : 20 613 mots sur 20 613
                # vérifiés, mêmes caractères, même longueur — pure
                # réordonnance. La WLC rejoint alors l'ordre de l'ATI, déjà
                # servie, où בְּ est elle aussi en sheva puis dagesh. Sans
                # cela, deux éditions du même mot diffèrent octet pour octet
                # pour une raison qui n'est pas textuelle.
                texte = ud.normalize("NFC", mot["texte"])
                decoupe = ud.normalize("NFC", mot["decoupe"])
                if texte:
                    out["h"] = texte
                # Le découpage n'est écrit que s'il apprend quelque chose :
                # un mot sans morphème scindé ni marqueur n'a rien à dire de
                # plus que `h`.
                if decoupe != texte:
                    out["d"] = decoupe
                if mot["strong"]:
                    out["s"] = mot["strong"]
                if mot["morph"]:
                    court, long = etiquettes(mot["morph"])
                    if court not in index_cg:
                        index_cg[court] = len(cg)
                        cg.append(court)
                    if long not in index_ca:
                        index_ca[long] = len(ca)
                        ca.append(long)
                    out["g"] = index_cg[court]
                    out["a"] = index_ca[long]
                mots.append(out)
            verse["words"] = mots

    return {
        "bym_index": bym_index,
        "standard": standard,
        "book": nom,
        # La casse titrée est celle de la maison : les assets embarqués
        # (lsg, lss, lsgs) et la SES portent tous `Gen`, `Exod`, `Josh` —
        # et c'est aussi le nom de fichier de la source.
        "osis_id": fichier,
        "ca": ca,
        "cg": cg,
        "chapters": chapters,
    }


def main(cibles: list[str] | None = None) -> int:
    if not SOURCE.is_dir():
        print("  source absente : %s" % SOURCE)
        print("  télécharger OSHB-v.2.2.zip depuis "
              "https://github.com/openscriptures/morphhb/releases")
        return 1

    SORTIE.mkdir(parents=True, exist_ok=True)
    ecarts = 0
    total_mots = 0

    for fichier, standard, bym_index, nom, attendus in LIVRES:
        if cibles and fichier not in cibles:
            continue
        source = SOURCE / (fichier + ".xml")
        if not source.exists():
            print("  ! %-6s fichier absent : %s" % (fichier, source.name))
            ecarts += 1
            continue

        livre = construire(fichier, standard, bym_index, nom)
        nb_chapitres = len(livre["chapters"])
        nb_versets = sum(len(c["verses"]) for c in livre["chapters"])
        nb_mots = sum(len(v["words"]) for c in livre["chapters"] for v in c["verses"])
        total_mots += nb_mots

        if nb_chapitres != attendus:
            print("  ! %-6s %d chapitres, %d attendus — signalé, non corrigé" % (
                fichier, nb_chapitres, attendus))
            ecarts += 1

        chemin = SORTIE / ("%d.json" % standard)
        with open(chemin, "w", encoding="utf-8") as f:
            json.dump(livre, f, ensure_ascii=False, separators=(",", ":"))

        print("  %-6s -> %-8s %2d ch. %5d versets %6d mots  (%d o)" % (
            fichier, chemin.name, nb_chapitres, nb_versets, nb_mots,
            chemin.stat().st_size))

    print()
    print("  total : %d mots, %d avertissement(s)" % (total_mots, ecarts))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:] or None))
