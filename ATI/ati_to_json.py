# -*- coding: utf-8 -*-
"""
Convertit l'ATI extrait en JSON téléchargeable — un fichier par livre.

Entrée  : `ATI/extrait/fichiers/` (sortie de `extract_ati.py`, 972 pages HTML)
Sortie  : `ATI/json/` — `1.json` … `39.json` + `notes.json`

Les fichiers sont nommés par le **numéro standard** du livre (1..39), pas par
son index BYM : c'est le jeton `{book}` de `urlTemplate` que `DownloadService`
substitue, et `_bymToStandard` (`lib/data/book_mapping.dart`) fait la traduction
côté app. La BYM suit l'ordre du canon hébreu — Ésaïe y est 12 mais 23 en
standard, Ruth 31 mais 8 — d'où la table ci-dessous, vérifiée contre
`_bymToStandard` dans les deux sens.

Schéma par livre, clés courtes (333 186 mots : chaque octet par mot pèse 0,3 Mo
sur le corpus) :

    {"bym_index": 1, "standard": 1, "book": "Genèse", "osis_id": "GEN",
     "ca": ["Nom commun · féminin singulier · état absolu", …],
     "cg": ["Nom", "Verbe", …],
     "chapters": [{"chapter": 1, "verses": [{"verse": 1, "words": [
        {"s": "H7225", "t": "bə·rê·šîṯ", "h": "בְּרֵאשִׁ֖ית",
         "d": "בְּ • רֵאשִׁ֖ית", "f": "En un commencement",
         "g": 0, "a": 0, "n": "d12"}]}]}]}

`g` et `a` sont des index dans `cg` / `ca` : le même libellé d'analyse revient
des milliers de fois, et la table de codes en rend 80 % sans rien perdre. `n`
est l'identifiant court d'une page de glossaire (`d12` = « Difficulté 12 »),
résolu contre `notes.json`.

Ce que ce convertisseur ne garde **pas**, et pourquoi :

- **les gloses Strong** que le HTML porte en attribut `title` : déjà servies par
  `StrongLexicon.instance.lookup()` depuis `assets/lexicon/`. Seul le numéro.
- **`MIC/001_caduque.html`** : page que l'éditeur a lui-même marquée caduque, et
  seule raison pour laquelle le corpus compte 930 fichiers pour 929 chapitres.

La numérotation des chapitres de l'ATI est déjà celle de la BYM (Joël 4,
Malachie 3, Michée 7) : aucun renumérotage.

    python ATI/ati_to_json.py
"""
import gzip
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from ati_parse import COLONNE_RE, groupe_versets, nu, parse_chapitre, ref_glossaire  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

RACINE = Path(__file__).parent
EXTRAIT = RACINE / "extrait" / "fichiers"
SORTIE = RACINE / "json"

# (code OSIS, numéro standard, index BYM, nom français, chapitres attendus)
#
# Les chapitres attendus sont ceux du canon ; ils servent de contrôle, pas de
# consigne — un écart est signalé, jamais corrigé en silence.
LIVRES = [
    ("GEN", 1, 1, "Genèse", 50),
    ("EXO", 2, 2, "Exode", 40),
    ("LEV", 3, 3, "Lévitique", 27),
    ("NUM", 4, 4, "Nombres", 36),
    ("DEU", 5, 5, "Deutéronome", 34),
    ("JOS", 6, 6, "Josué", 24),
    ("JDG", 7, 7, "Juges", 21),
    ("RUT", 8, 31, "Ruth", 4),
    ("1SA", 9, 8, "1 Samuel", 31),
    ("2SA", 10, 9, "2 Samuel", 24),
    ("1KI", 11, 10, "1 Rois", 22),
    ("2KI", 12, 11, "2 Rois", 25),
    ("1CH", 13, 38, "1 Chroniques", 29),
    ("2CH", 14, 39, "2 Chroniques", 36),
    ("EZR", 15, 36, "Esdras", 10),
    ("NEH", 16, 37, "Néhémie", 13),
    ("EST", 17, 34, "Esther", 10),
    ("JOB", 18, 29, "Job", 42),
    ("PSA", 19, 27, "Psaumes", 150),
    ("PRO", 20, 28, "Proverbes", 31),
    ("ECC", 21, 33, "Ecclésiaste", 12),
    ("SNG", 22, 30, "Cantique des cantiques", 8),
    ("ISA", 23, 12, "Ésaïe", 66),
    ("JER", 24, 13, "Jérémie", 52),
    ("LAM", 25, 32, "Lamentations", 5),
    ("EZK", 26, 14, "Ézéchiel", 48),
    ("DAN", 27, 35, "Daniel", 12),
    ("HOS", 28, 15, "Osée", 14),
    ("JOL", 29, 16, "Joël", 4),
    ("AMO", 30, 17, "Amos", 9),
    ("OBA", 31, 18, "Abdias", 1),
    ("JON", 32, 19, "Jonas", 4),
    ("MIC", 33, 20, "Michée", 7),
    ("NAM", 34, 21, "Nahum", 3),
    ("HAB", 35, 22, "Habakuk", 3),
    ("ZEP", 36, 23, "Sophonie", 3),
    ("HAG", 37, 24, "Aggée", 2),
    ("ZEC", 38, 25, "Zacharie", 14),
    ("MAL", 39, 26, "Malachie", 3),
]

CHAPITRE_RE = re.compile(r"^(\d{3})\.html$")
H1_RE = re.compile(r"<h1>(.*?)</h1>", re.S)
NAV_RE = re.compile(r'<table width=100% align="center">.*?</table>', re.S)
CORPS_RE = re.compile(r"<body>(.*?)</body>", re.S)

# Corrections de numérotation de la source, déclarées une à une.
#
# L'ATI numérote ses versets dans l'ordre du document, et le contrôle ci-dessous
# le vérifie chapitre par chapitre. Un seul chapitre des 929 s'en écarte.
#
# JOB 40 : la séquence monte de 1 à 27, affiche « 4 », puis reprend de 29 à 32.
# Le verset ainsi étiqueté porte « Est-ce qu'il conclura une alliance avec toi,
# tu le prendras pour serviteur de toujours » — soit Job 40,28 dans la
# numérotation hébraïque, mais 41,4 dans la numérotation chrétienne, que
# l'éditeur a reportée par mégarde. Le trou est exactement 28, le reste de la
# séquence est intact, et la BYM compte elle aussi 32 versets à ce chapitre.
#
# Corrigé, et non pas seulement signalé : deux versets « 4 » et aucun « 28 » se
# verraient à l'écran. La clé porte la position et la valeur attendue, de sorte
# qu'une source corrigée en amont fasse échouer le contrôle au lieu de laisser
# une correction s'appliquer à l'aveugle.
CORRECTIONS = {
    # (livre, chapitre, position 0-indexée) : (numéro trouvé, numéro juste)
    ("JOB", 40, 27): (4, 28),
}

anomalies = []
corrections_faites = []


def ecrit(chemin, obj):
    """Écrit du JSON compact. Retourne (octets, octets gzip)."""
    texte = json.dumps(obj, ensure_ascii=False, separators=(",", ":"))
    chemin.write_text(texte, encoding="utf-8")
    brut = texte.encode("utf-8")
    return len(brut), len(gzip.compress(brut, 9))


def convertit_livre(osis, standard, bym, nom, attendus):
    """Un livre : lit ses chapitres, code ses analyses, écrit son JSON."""
    dossier = EXTRAIT / osis
    if not dossier.is_dir():
        anomalies.append(f"{osis} : dossier absent")
        return None

    fichiers, ecartes = [], []
    for f in sorted(dossier.iterdir()):
        if m := CHAPITRE_RE.match(f.name):
            fichiers.append((int(m.group(1)), f))
        elif f.suffix == ".html":
            ecartes.append(f.name)

    # Les pages écartées sont nommées : la seule attendue est MIC/001_caduque.
    for nom_ecarte in ecartes:
        if not nom_ecarte.endswith("_caduque.html"):
            anomalies.append(f"{osis} : page inattendue écartée — {nom_ecarte}")

    ca, cg = {}, {}
    chapitres = []
    nb_mots = nb_versets = nb_muettes = nb_sans_glose = nb_marqueur = 0
    inconnus = []

    for numero, fichier in fichiers:
        html = fichier.read_text(encoding="utf-8", errors="replace")
        colonnes = parse_chapitre(html, inconnus)

        # Contrôle de non-perte : toute colonne du HTML doit ressortir, soit en
        # mot, soit en marqueur de verset. Les seules admises à ne rien produire
        # sont les colonnes d'espacement (cellules `&nbsp;` sans aucun champ) —
        # une dans tout le corpus, un « t » égaré dans Exode 38. Au-delà, c'est
        # le parseur qui laisse tomber de la donnée, et il faut le savoir.
        muettes = len(COLONNE_RE.findall(html)) - len(colonnes)
        nb_muettes += muettes
        if muettes > 1:
            anomalies.append(
                f"{osis} {numero} : {muettes} colonnes sans champ reconnu")

        versets, orphelins = groupe_versets(colonnes)
        if orphelins:
            anomalies.append(
                f"{osis} {numero} : {orphelins} mot(s) avant le premier verset")
        if not versets:
            anomalies.append(f"{osis} {numero} : aucun verset")
            continue

        # Corrections déclarées, appliquées avant les contrôles de séquence :
        # elles sont là précisément pour que la séquence redevienne valide.
        for position, verset in enumerate(versets):
            attendu = CORRECTIONS.get((osis, numero, position))
            if attendu is None:
                continue
            trouve, juste = attendu
            if verset["verse"] != trouve:
                anomalies.append(
                    f"{osis} {numero} : correction obsolète en position "
                    f"{position} — la source porte {verset['verse']}, "
                    f"non {trouve}. À revoir dans CORRECTIONS.")
                continue
            verset["verse"] = juste
            corrections_faites.append(
                f"{osis} {numero} : verset {trouve} → {juste} "
                f"(position {position})")

        numeros = [v["verse"] for v in versets]
        if numeros != sorted(numeros):
            anomalies.append(f"{osis} {numero} : versets non croissants")
        if len(set(numeros)) != len(numeros):
            anomalies.append(f"{osis} {numero} : numéros de verset en doublon")

        for verset in versets:
            for mot in verset["words"]:
                if "a" in mot:
                    mot["a"] = ca.setdefault(mot["a"], len(ca))
                if "g" in mot:
                    mot["g"] = cg.setdefault(mot["g"], len(cg))
            nb_mots += len(verset["words"])

            # Contrôle de glose : la règle du lecteur, mot à mot — un mot dont la
            # glose n'est qu'un marqueur (`*`, `-`) ou qui n'en a pas du tout ne
            # compte pas. Un verset ainsi vide sort **blanc** dans l'app, ligne
            # après ligne de silence : c'est le défaut que ce contrôle est venu
            # chercher (les 929 derniers versets de chaque chapitre, cellules
            # alignées, voir ati_parse.py). Les deux cas restants sont normaux et
            # décomptés à part : marqueur seul, ou cellule rouge vide ou absente
            # dans la source — quatre mots dans tout le corpus.
            gloses = 0
            for mot in verset["words"]:
                brut = mot.get("f", "")
                net = re.sub(r"[*\-\s]", "", brut)
                if net:
                    gloses += 1
                elif brut.strip():
                    nb_marqueur += 1
                else:
                    nb_sans_glose += 1
            if verset["words"] and not gloses:
                anomalies.append(
                    f"{osis} {numero}:{verset['verse']} : verset sans aucune glose")
        nb_versets += len(versets)
        chapitres.append({"chapter": numero, "verses": versets})

    if inconnus:
        for x in sorted(set(inconnus)):
            anomalies.append(f"{osis} : renvoi de glossaire non reconnu — {x}")
    if len(chapitres) != attendus:
        anomalies.append(
            f"{osis} : {len(chapitres)} chapitres, {attendus} attendus")

    octets, gz = ecrit(SORTIE / f"{standard}.json", {
        "bym_index": bym,
        "standard": standard,
        "book": nom,
        "osis_id": osis,
        "ca": list(ca),
        "cg": list(cg),
        "chapters": chapitres,
    })
    return {
        "osis": osis, "standard": standard, "bym": bym, "nom": nom,
        "chapitres": len(chapitres), "attendus": attendus,
        "versets": nb_versets, "mots": nb_mots, "muettes": nb_muettes,
        "sans_glose": nb_sans_glose, "marqueur": nb_marqueur,
        "ca": len(ca), "cg": len(cg), "octets": octets, "gz": gz,
    }


def convertit_glossaire():
    """Les 37 pages de glossaire en un seul `notes.json`.

    Garde le HTML du corps, débarrassé de la table de navigation « page
    précédente / suivante » qui n'a pas de sens hors de Biblia. Le texte seul ne
    suffirait pas : ces pages sont faites de tableaux (Remarque 2 en fait 141 Ko)
    et portent de l'hébreu mis en forme.
    """
    dossier = EXTRAIT / "glossaire"
    notes = {}
    for fichier in sorted(dossier.glob("*.html")):
        nom = fichier.stem
        ref = ref_glossaire(nom)
        if ref is None:
            anomalies.append(f"glossaire : page non classée — {nom}")
            continue
        if ref in notes:
            anomalies.append(f"glossaire : deux pages pour « {ref} »")
        html = fichier.read_text(encoding="utf-8", errors="replace")
        corps = (m.group(1) if (m := CORPS_RE.search(html)) else html)
        corps = NAV_RE.sub("", corps, count=1).strip()
        titre = nu(m.group(1)) if (m := H1_RE.search(corps)) else ""
        notes[ref] = {"name": nom, "title": titre, "html": corps}

    octets, gz = ecrit(SORTIE / "notes.json", notes)
    return len(notes), octets, gz


def main():
    if not EXTRAIT.is_dir():
        sys.exit(f"Extraction absente : {EXTRAIT}\n"
                 f"Lancer d'abord `python ATI/extract_ati.py`.")
    SORTIE.mkdir(exist_ok=True)

    # Contrôle de la table elle-même, avant de produire quoi que ce soit : une
    # collision d'index rendrait deux livres indiscernables côté app.
    for champ, i in (("standard", 1), ("bym", 2)):
        vus = [l[i] for l in LIVRES]
        if len(set(vus)) != len(vus):
            sys.exit(f"Table LIVRES : doublon sur {champ}")
    dossiers = {d.name for d in EXTRAIT.iterdir() if d.is_dir()} - {"glossaire"}
    if manquants := dossiers - {l[0] for l in LIVRES}:
        sys.exit(f"Table LIVRES : livres extraits non listés — {sorted(manquants)}")

    print("Conversion de l'ATI en JSON téléchargeable")
    print("=" * 86)
    print(f"{'livre':24} {'std':>3} {'bym':>3} {'ch.':>4} {'versets':>7} "
          f"{'mots':>7} {'ca':>5} {'json':>9} {'gzip':>8}")
    print("-" * 86)

    lignes = []
    for osis, standard, bym, nom, attendus in LIVRES:
        r = convertit_livre(osis, standard, bym, nom, attendus)
        if r is None:
            continue
        lignes.append(r)
        marque = " " if r["chapitres"] == r["attendus"] else "!"
        print(f"{marque}{osis} {nom:20.20} {standard:3} {bym:3} "
              f"{r['chapitres']:4} {r['versets']:7,} {r['mots']:7,} "
              f"{r['ca']:5} {r['octets']:9,} {r['gz']:8,}")

    tot_ch = sum(r["chapitres"] for r in lignes)
    tot_v = sum(r["versets"] for r in lignes)
    tot_m = sum(r["mots"] for r in lignes)
    tot_sans_glose = sum(r["sans_glose"] for r in lignes)
    tot_marqueur = sum(r["marqueur"] for r in lignes)
    tot_o = sum(r["octets"] for r in lignes)
    tot_gz = sum(r["gz"] for r in lignes)
    print("-" * 86)
    print(f"{'total':24} {'':3} {'':3} {tot_ch:4} {tot_v:7,} {tot_m:7,} "
          f"{'':5} {tot_o:9,} {tot_gz:8,}")

    nb_notes, o_notes, gz_notes = convertit_glossaire()
    tot_muettes = sum(r["muettes"] for r in lignes)

    print()
    print("Résultat")
    print("-" * 86)
    print(f"  livres            : {len(lignes)} / 39")
    print(f"  chapitres         : {tot_ch} (attendu 929)")
    print(f"  versets           : {tot_v:,}")
    print(f"  mots              : {tot_m:,}")
    print(f"  mots sans glose   : {tot_sans_glose:,} sur {tot_m:,} — lacune de "
          f"la source (cellule rouge vide ou absente)")
    print(f"  mots à marqueur   : {tot_marqueur:,} — glose réduite à « * » ou "
          f"« - », le lecteur les saute")
    print(f"  colonnes rendues  : {tot_m + tot_v:,} sur "
          f"{tot_m + tot_v + tot_muettes:,} — {tot_muettes} colonne(s) "
          f"d'espacement sans champ")
    print(f"  pages de glossaire: {nb_notes} (attendu 37) — "
          f"{o_notes / 1024:,.0f} Ko, {gz_notes / 1024:,.0f} Ko gzip")
    print(f"  JSON en clair     : {tot_o / 1048576:,.1f} Mo")
    print(f"  ce qui voyage     : {(tot_gz + gz_notes) / 1048576:,.1f} Mo gzip")
    plus_gros = max(lignes, key=lambda r: r["octets"])
    print(f"  plus gros fichier : {plus_gros['nom']} — "
          f"{plus_gros['octets'] / 1048576:,.1f} Mo "
          f"({plus_gros['gz'] / 1048576:,.1f} Mo gzip)")
    print(f"  sortie            : {SORTIE}")

    if corrections_faites:
        print()
        print("Corrections de la source (déclarées dans CORRECTIONS)")
        print("-" * 86)
        for c in corrections_faites:
            print(f"  - {c}")

    print()
    print("Anomalies")
    print("-" * 86)
    if anomalies:
        for a in anomalies:
            print(f"  - {a}")
        print(f"\n  {len(anomalies)} anomalie(s) — à régler avant publication.")
    else:
        print("  - aucune")
    return 1 if anomalies else 0


if __name__ == "__main__":
    sys.exit(main())
