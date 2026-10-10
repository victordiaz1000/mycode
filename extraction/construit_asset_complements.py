# -*- coding: utf-8 -*-
"""Fabrique l'asset des entrées Strong que les modules SWORD ne portent pas.

Lecture : extraction/strong_fr_v2.json            (fusion_strong_v2.py)
          bible_app/assets/lexicon/strong_fr.json (base SWORD embarquée)
Écriture : bible_app/assets/lexicon/strong_complements.json

La fusion construit aux champs du schéma les clés que la base SWORD n'a pas —
G2994 (Λαοδικεύς) et G2995 (λάρυγξ), citées par le LSGS et par la LSS mais
absentes des modules. Ces deux-là sont des lexies comme les autres : elles
n'ont rien à faire dans strong_etendu.json, qui porte des formes, ni à
rester hors du bundle au point que la fiche réponde « aucune définition ».

Ce script n'extrait qu'elles : celles que la fusion crée et que la base
ignore. Rien d'autre n'est recopié — le reste du fichier fusionné ne
dépasse pas le bundle pour cause de ses blocs d'occurrences Biblia.

Contrôles, un échec interrompt l'écriture :
  - l'entrée est complète (sens et définition) ;
  - ce n'est pas le texte d'attente « Définition non disponible. » ;
  - aucune clé bannie de la fusion n'y figure ;
  - la sortie est en forme NFC, comme la base SWORD (le dictionnaire GRC
    écrit le grec polytonique décomposé).

Usage :
    python construit_asset_complements.py
"""
import json
import unicodedata
from pathlib import Path

ICI = Path(__file__).resolve().parent
RACINE = ICI.parent
FUSION = ICI / "strong_fr_v2.json"
BASE = RACINE / "bible_app" / "assets" / "lexicon" / "strong_fr.json"
CIBLE = RACINE / "bible_app" / "assets" / "lexicon" / "strong_complements.json"

# Recopiée de fusion_strong_v2.py : ces clés ne doivent jamais être
# embarquées, la fusion les rejette et ce fichier les rejetterait aussi.
INTERDITES = {"bailly", "sanderTrenel", "sections", "strongDefinition",
              "strongLineNumber", "source"}
ATTENTE = "Définition non disponible."


def nfc(valeur):
    """La valeur en forme NFC, récursivement dans la structure JSON.

    Le dictionnaire GRC écrit le grec polytonique hors de sa forme composée
    — U+1F71 « ALPHA WITH OXIA » au lieu de U+03AC « ALPHA WITH TONOS » —
    quand la base SWORD embarquée est en NFC sur ses 14 195 entrées. Les
    deux écritures désignent exactement les mêmes lettres (composantes
    canoniques identiques) : elles ne se comparent toutefois pas telles
    quelles, ni ne s'affichent pareil. On aligne les compléments sur la
    base, sans rien changer au texte.
    """
    if isinstance(valeur, str):
        return unicodedata.normalize("NFC", valeur)
    if isinstance(valeur, list):
        return [nfc(item) for item in valeur]
    if isinstance(valeur, dict):
        return {cle: nfc(item) for cle, item in valeur.items()}
    return valeur


def main():
    for chemin in (FUSION, BASE):
        if not chemin.exists():
            raise SystemExit(
                f"{chemin.name} absent : lancez fusion_strong_v2.py d'abord"
            )
    fusion = json.loads(FUSION.read_text(encoding="utf-8"))
    base = json.loads(BASE.read_text(encoding="utf-8"))

    # Ordre de la base, clés neuves à leur rang numérique : le fichier se
    # relit dans l'ordre Strong, comme l'autre.
    entrees_fusion = fusion["entries"]
    entrees_base = base["entries"]
    manquantes = [c for c in entrees_fusion if c not in entrees_base]
    tri = sorted(
        entrees_fusion,
        key=lambda c: (c[0], int(c[1:]) if c[1:].isdigit() else 0),
    )
    retenues = [c for c in tri if c in manquantes]

    fautes = []
    for code in retenues:
        entree = entrees_fusion[code]
        interdites = INTERDITES & set(entree)
        if interdites:
            fautes.append(f"{code} : clés interdites {sorted(interdites)}")
        if not entree.get("senses"):
            fautes.append(f"{code} : aucun sens")
        definition = str(entree.get("definition") or "").strip()
        if not definition or definition == ATTENTE:
            fautes.append(f"{code} : définition d'attente")
        if "•" not in definition:
            fautes.append(f"{code} : définition sans liste de sens")
    if fautes:
        raise SystemExit("\n".join(fautes))

    fiches = {code: nfc(entrees_fusion[code]) for code in retenues}
    # Contrôle : ce qui sort est en forme composée, comme la base.
    for code, fiche in fiches.items():
        if not unicodedata.is_normalized("NFC", json.dumps(fiche, ensure_ascii=False)):
            raise SystemExit(f"{code} : sortie encore décomposée")
    CIBLE.write_text(
        json.dumps(
            {
                "schema": "bym.strong.v2",
                "source": (
                    "entrées créées par extraction/fusion_strong_v2.py : "
                    "citées par les corpus, absentes des modules SWORD"
                ),
                "entries": fiches,
            },
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        encoding="utf-8",
    )
    print(
        f"{len(fiches)} entrée(s) sur {len(entrees_fusion) - len(entrees_base)} "
        f"créées par la fusion ({', '.join(retenues) or 'aucune'}) → {CIBLE} "
        f"({CIBLE.stat().st_size / 1024:.1f} Ko)"
    )


if __name__ == "__main__":
    main()
