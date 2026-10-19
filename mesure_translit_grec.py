# -*- coding: utf-8 -*-
"""Mesure l'accord du translittérateur grec avec le juge du kit Stephanus.

Le juge : `TR-Stephanus-1550/lexique/strongs-greek.json`, 5 624 lemmes, chacun
avec son grec et sa translittération. Ce sont des lemmes, non des formes
fléchies : le Textus Receptus porte `γενεσεως` (génitif) là où le juge porte
`γένεσις`. On ne peut donc pas comparer les livres eux-mêmes — on compare les
**tables**, en appliquant le translittérateur aux lemmes du juge. C'est la
convention qui se mesure, pas une donnée qui se copie.

Deux comptes, et non un seul :
  accord des lettres — accents et macrons ôtés : la table est-elle juste ?
  accord exact      — accents et macrons compris : la table et la position
                      de l'accent sont-elles justes aussi ?

Aucune translittération du juge n'est reportée dans les livres servis : le
script ne fait que compter.
"""
import json
import sys
import unicodedata
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")

RACINE = Path(__file__).resolve().parent
sys.path.insert(0, str(RACINE))
from translit_grec import translitterer, INCONNUS  # noqa: E402

JUGE = RACINE / "TR-Stephanus-1550" / "lexique" / "strongs-greek.json"


def denude(texte):
    """Ôte tout diacritique et ramène en bas de casse : ne restent que les
    lettres de base, ce que la table prétend traduire."""
    forme = unicodedata.normalize("NFD", texte)
    return "".join(c for c in forme
                   if not unicodedata.combining(c)).lower()


def main():
    lexique = json.load(open(JUGE, encoding="utf-8"))

    total = accord_lettres = accord_exact = 0
    ecarts = []
    ecarts_exacts = []

    for code, entree in sorted(lexique.items()):
        grec = entree.get("grec", "")
        attendu = entree.get("translit", "")
        if not grec or not attendu:
            continue
        total += 1
        obtenu = translitterer(grec)

        if denude(obtenu) == denude(attendu):
            accord_lettres += 1
        else:
            ecarts.append((code, grec, attendu, obtenu))

        if obtenu == attendu:
            accord_exact += 1
        else:
            ecarts_exacts.append((code, grec, attendu, obtenu))

    print("juge  : %s" % JUGE.name)
    print("lemmes: %d" % total)
    print()
    print("accord des lettres : %d / %d  = %.2f %%"
          % (accord_lettres, total, 100.0 * accord_lettres / total))
    print("accord exact       : %d / %d  = %.2f %%"
          % (accord_exact, total, 100.0 * accord_exact / total))
    print()

    if ecarts:
        print("ecarts de lettres (%d) — les 25 premiers :" % len(ecarts))
        for code, grec, attendu, obtenu in ecarts[:25]:
            print("  %-7s %-14s juge=%-20s mien=%s"
                  % (code, grec, attendu, obtenu))
        print()
        # Position par position, sur la version dénudée : quelle lettre
        # grecque est le plus souvent mal rendue ?
        import collections
        lettres = collections.Counter()
        for _, grec, attendu, obtenu in ecarts:
            g, attendu_n, obtenu_n = denude(grec), denude(attendu), denude(obtenu)
            for i in range(min(len(attendu_n), len(obtenu_n))):
                if attendu_n[i] != obtenu_n[i] and i < len(g):
                    lettres[g[i]] += 1
        print("lettres grecques les plus souvent mal rendues :")
        for lettre, n in lettres.most_common(12):
            print("   %s  %d" % (lettre, n))
    else:
        print("accord parfait : aucune lettre ne diverge.")

    print()
    if ecarts_exacts:
        print("ecarts exacts (%d) — la lettre est juste, seule la marque "
              "differe :" % len(ecarts_exacts))
        for code, grec, attendu, obtenu in ecarts_exacts:
            print("  %-7s %-14s juge=%-22s mien=%s"
                  % (code, grec, attendu, obtenu))
        print()
        print("  chx   : le juge epelait « stigma », nom du signe "
              "numeral ϛ ;")
        print("          une lettre n'a pas de nom a inventer.")
        print("  praü  : le juge ecarte l'oxia du υ porteur d'un tréma ;")
        print("          lui retirer son accent n'a pas de regle, on le "
              "garde.")

    if INCONNUS:
        print()
        print("caracteres combines hors table (%d) : %s"
              % (len(INCONNUS), " ".join("U+%04X" % ord(c)
                                         for c in sorted(INCONNUS))))


if __name__ == "__main__":
    main()
