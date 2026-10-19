# -*- coding: utf-8 -*-
"""Interlinéaire complet (AT hébreu + NT grec) vers le schéma interlinéaire BYM.

Entrée : Bible-Interlineaire/at/1.json … 39.json  (hébreu pointillé)
         Bible-Interlineaire/nt/1.json … 27.json  (grec accentué)
Sortie : bym-bibles/il/1.json … 66.json — un fichier par livre.

Le kit est en domaine public (kennethreitz/kjvstudy.org) et parle anglais :
ses gloses restent anglaises, et le drapeau `languageCode` de la carte en
porte la mention. On ne traduit rien : « le français en français et
l'anglais en anglais ».

Ce que le kit porte, et l'endroit où chacun va :

    m   mot original     AT → `h` (hébreu, rendu de droite à gauche)
                         NT → `m` (grec, rendu de gauche à droite)
    s   Strong `H…`/`G…` → `s`, tel quel : l'app a son propre lexique
    g   glose anglaise   → `f`
    d   définition       → **non reportée**, volontairement
    —   translittération → `t`, **générée** : le kit n'en livre aucun

`d` n'a aucune place dans le schéma : c'est la définition anglaise du
Strong, alors que l'app porte déjà `StrongLexicon`, un lexique français
plus riche (sens, étymologie, prononciation, premier bond) couvrant `H`
et `G` — c'est lui que la feuille affiche quand on touche un numéro.
Reportée ici, elle eût rempli la ligne d'analyse d'un texte de
dictionnaire à la place de la grammaire.

La translittération, elle, manque des deux côtés et n'est reportée de
nulle part : elle est **calculée**. L'hébreu passe par l'outil même de la
WLC — un seul générateur pour les deux corpus, donc une seule convention,
au lieu d'une copie qui pourrait dériver en silence. Le grec passe par
`translit_grec`, dont l'accord est mesuré contre le lexique Strong du kit
Stephanus. Les deux écrivent en `t`, et la feuille d'un mot l'affiche
sous le mot : sans elle, qui ne lit ni l'hébreu ni le grec n'a devant
lui qu'un mot illisible et une glose anglaise.

Le kit n'a aucune morphologie : ni `g` (étiquette) ni `a` (analyse) ne
sont écrits, et la feuille d'un mot n'y montre donc pas de ligne
« Analyse ». Rien n'est inventé pour la compléter — l'AT hébreu est déjà
couvert par l'ATI, avec ses gloses et ses analyses françaises.

Nomenclature des fichiers : le jeton `{book}` de `urlTemplate` est
remplacé par le numéro **standard** 1..66 (cf. `DownloadService.bookUri`),
que le kit ne porte pas pour son NT — `nt/1.json` y vaut `standard: 1`
alors que Matthieu est le 40. Le décalage est rétabli ici, et le numéro
BYM (l'ordre de l'app) écrit à côté, comme font l'ATI et le NTI.

Aucune donnée de Biblia Universalis n'entre ici : ce script ne lit que
le kit public-domain et son propre dossier de sortie.
"""
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

SOURCE = Path(__file__).resolve().parent
RACINE = Path(__file__).resolve().parent.parent
SORTIE = RACINE.parent / "bym-bibles" / "il"

# Deux translittérateurs, aucun écrit ici : l'hébreu est celui de la WLC,
# dont le génère `WLC/wlc_to_json.py` — le même outil pour un même texte
# pointé, qui diffère à peine de celui de la WLC (place des accents de
# cantillation, découpage au maqqef) mais se pointe à l'identique. Le grec
# est `translit_grec`, à la racine entre les kits, puisqu'il sert aussi le
# Textus Receptus.
sys.path.insert(0, str(RACINE))
sys.path.insert(0, str(RACINE / "WLC"))
from translit_grec import translitterer as translitterer_grec  # noqa: E402
from wlc_to_json import translitterer as translitterer_hebreu  # noqa: E402

# BYM → standard, copié de bym-classic/lib/data/book_mapping.dart : c'est lui
# qui dit que Ruth est le 8 standard mais le 31e BYM, et Jacques le 59 standard
# mais le 45e BYM. Les deux ordres ne coïncident pas.
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


def fichiers():
    """(numéro standard, chemin) pour les 66 livres du kit."""
    for dossier, decalage in (("at", 0), ("nt", 39)):
        for chemin in sorted((SOURCE / dossier).glob("*.json")):
            numero = int(chemin.stem)
            yield numero + decalage, chemin


def convertir(standard, chemin):
    brut = json.load(open(chemin, encoding="utf-8"))
    grec = brut.get("language") != "he"

    livres = []
    mots = 0
    sans_glose = 0
    for chapitre in brut["chapters"]:
        versets = []
        for verset in chapitre["verses"]:
            mots_lignes = []
            for mot in verset["words"]:
                ligne = {}
                # Le mot d'abord : `h` pour l'hébreu, `m` pour le grec — c'est
                # ce choix qui dit à l'app si la colonne se lit de droite à
                # gauche (`AtiWord.greek`).
                if grec:
                    ligne["m"] = mot["m"]
                    translit = translitterer_grec(mot["m"])
                else:
                    ligne["h"] = mot["m"]
                    translit = translitterer_hebreu(mot["m"])
                if translit:
                    # Le mot reste écrit dans son alphabet ; la
                    # translittération est ce qui le rend suivi de lecture
                    # pour qui ne le lit pas. Elle est posée avant le
                    # Strong, dans l'ordre où la WLC écrit les siennes.
                    ligne["t"] = translit
                if mot.get("s"):
                    ligne["s"] = mot["s"]
                if mot.get("g"):
                    ligne["f"] = mot["g"]
                else:
                    sans_glose += 1
                mots_lignes.append(ligne)
                mots += 1
            versets.append({"verse": verset["verse"], "words": mots_lignes})
        livres.append({"chapter": chapitre["chapter"], "verses": versets})

    return {
        "bym_index": STANDARD_VERS_BYM[standard],
        "standard": standard,
        "book": brut["book"],
        "osis_id": brut["osis_id"],
        "chapters": livres,
    }, mots, sans_glose


def main():
    SORTIE.mkdir(parents=True, exist_ok=True)
    total = total_sans_glose = 0
    livres = 0
    for standard, chemin in fichiers():
        livre, mots, sans_glose = convertir(standard, chemin)
        cible = SORTIE / ("%d.json" % standard)
        with open(cible, "w", encoding="utf-8", newline="\n") as flot:
            json.dump(livre, flot, ensure_ascii=False, separators=(",", ":"))
            flot.write("\n")
        total += mots
        total_sans_glose += sans_glose
        livres += 1
        print("  %-4s -> il/%-2d.json  %-16s %4d ch.  %5d mots"
              % (chemin.name, standard, livre["book"],
                 len(livre["chapters"]), mots))

    print("\n  total : %d livres, %d mots, %d sans glose (laissés vides "
          "par la source)" % (livres, total, total_sans_glose))


if __name__ == "__main__":
    main()
