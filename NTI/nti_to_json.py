# -*- coding: utf-8 -*-
"""
Convertit le NTI en JSON téléchargeable — un fichier par livre.

Entrée  : `NTI/extrait/fichiers/` (sortie de `extract_nti.py`, 260 chapitres)
Sortie  : `NTI/json/` — `40.json` … `66.json`

Les fichiers sont nommés par le **numéro standard** du livre (1..66), pas par
son index BYM : c'est le jeton `{book}` de `urlTemplate` que `DownloadService`
substitue, et `bymToStandard` (`lib/data/book_mapping.dart`) fait la traduction
côté app. Le Nouveau Testament est à la fois 40..66 en standard et 40..66 en
BYM, mais **pas dans le même ordre** — Romains est 51 en BYM et 45 en standard,
Jacques 45 et 59 — d'où la table ci-dessous, vérifiée contre `_bymToStandard`
dans les deux sens. Les numéros 1..39 ne reçoivent rien : le NTI n'a pas
d'Ancien Testament.

Schéma par livre, clés courtes (138 099 mots : chaque octet par mot pèse
0,09 Mo sur le corpus) :

    {"bym_index": 40, "standard": 40, "book": "Matthieu", "osis_id": "MAT",
     "cg": ["N-NFS", "N-GFS", …],
     "ca": ["Nature : Nom · Déclinaison : Nominatif · …", …],
     "chapters": [{"chapter": 1, "verses": [{"verse": 1, "words": [
        {"m": "Βίβλος", "l": "βίβλος", "k": "βιβλοσ", "s": "G976",
         "f": "Livre", "g": 0, "a": 0}]}]}]}

`m` est le mot tel qu'imprimé (rangée « Moderne »), `l` la forme-lemme, `k` la
graphie de base sans accents (rangée « Koinè »), `s` le numéro Strong, `f` la
glose française et `f2` sa variante quand la source en propose une une (« de
genèse **/ de généalogie** »). `g` et `a` sont des index dans `cg` / `ca` :
le même code d'analyse revient des dizaines de milliers de fois, et la table
en rend la quasi-totalité sans rien perdre.

Ce que ce convertisseur ne garde **pas**, et pourquoi :

- **les gloses Strong** que le HTML porte en attribut `title` : déjà servies par
  `StrongLexicon.instance.lookup()` depuis `assets/lexicon/`. Seul le numéro.
- **le renvoi `g*NTI*Analyses`** : ses 138 066 occurrences pointent toutes vers
  la même page, qui ne fait que développer le code d'analyse — le développement
  est déjà dans le `title` de chaque mot, d'où il est lu.
- **les pages de glossaire** (`Note 01` … `Note 18`, `Lexique`, `Analyses`) :
  aucun mot du corpus n'y renvoie (contrôlé : la seule famille de renvois du
  NTI est `Analyses`), donc rien ne pourrait les ouvrir côté app.

La numérotation des chapitres du NTI est celle du canon : aucun renumérotage.
Les numéros de verset, eux, recoupent la BYM **sauf en quatre chapitres**,
contrôle fait une fois contre `assets/bible/bym/` — ce sont des différences de
versification du texte, pas du parseur (chaque chapitre va de 1 à N, sans saut
ni doublon, vérifié à chaque conversion) :

    Actes 19        40 versets ici, 41 dans la BYM
    2 Corinthiens 13 13 versets ici, 14 dans la BYM
    3 Jean 1        15 versets ici, 14 dans la BYM
    Apocalypse 12   18 versets ici, 17 dans la BYM

« Comparer » restera donc aligné partout sauf sur ces quatre chapitres, où
chaque version garde son propre découpage. Aucune n'a de droits sur l'autre.

    python NTI/nti_to_json.py
"""
import gzip
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from nti_parse import COLONNE_RE, ETIQUETTE, groupe_versets, parse_chapitre  # noqa: E402

sys.stdout.reconfigure(encoding="utf-8")

RACINE = Path(__file__).parent
EXTRAIT = RACINE / "extrait" / "fichiers"
SORTIE = RACINE / "json"

# (code OSIS, numéro standard, index BYM, nom français, chapitres attendus)
#
# Les chapitres attendus sont ceux du canon ; ils servent de contrôle, pas de
# consigne — un écart est signalé, jamais corrigé en silence.
LIVRES = [
    ("MAT", 40, 40, "Matthieu", 28),
    ("MRK", 41, 41, "Marc", 16),
    ("LUK", 42, 42, "Luc", 24),
    ("JHN", 43, 43, "Jean", 21),
    ("ACT", 44, 44, "Actes", 28),
    ("ROM", 45, 51, "Romains", 16),
    ("1CO", 46, 49, "1 Corinthiens", 16),
    ("2CO", 47, 50, "2 Corinthiens", 13),
    ("GAL", 48, 46, "Galates", 6),
    ("EPH", 49, 52, "Éphésiens", 6),
    ("PHP", 50, 53, "Philippiens", 4),
    ("COL", 51, 54, "Colossiens", 4),
    ("1TH", 52, 47, "1 Thessaloniciens", 5),
    ("2TH", 53, 48, "2 Thessaloniciens", 3),
    ("1TI", 54, 56, "1 Timothée", 6),
    ("2TI", 55, 60, "2 Timothée", 4),
    ("TIT", 56, 57, "Tite", 3),
    ("PHM", 57, 55, "Philémon", 1),
    ("HEB", 58, 62, "Hébreux", 13),
    ("JAS", 59, 45, "Jacques", 5),
    ("1PE", 60, 58, "1 Pierre", 5),
    ("2PE", 61, 59, "2 Pierre", 3),
    ("1JN", 62, 63, "1 Jean", 5),
    ("2JN", 63, 64, "2 Jean", 1),
    ("3JN", 64, 65, "3 Jean", 1),
    ("JUD", 65, 61, "Jude", 1),
    ("REV", 66, 66, "Apocalypse", 22),
]

CHAPITRE_RE = re.compile(r"^(\d{3})\.html$")
# Un code de livre du TOC : trois lettres/majuscules, MAT ou 1CO.
CODE_LIVRE_RE = re.compile(r"^[A-Z0-9]{3}$")

anomalies = []


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

    fichiers = []
    for f in sorted(dossier.iterdir()):
        if m := CHAPITRE_RE.match(f.name):
            fichiers.append((int(m.group(1)), f))
        elif f.suffix == ".html":
            anomalies.append(f"{osis} : page inattendue écartée — {f.name}")

    ca, cg = {}, {}
    chapitres = []
    nb_mots = nb_versets = nb_muettes = nb_sans_glose = nb_variante = 0
    nb_marqueur = nb_sans_strong = 0

    for numero, fichier in fichiers:
        html = fichier.read_text(encoding="utf-8", errors="replace")
        colonnes = parse_chapitre(html, anomalies)

        # Contrôle de non-perte : toute colonne du HTML doit ressortir, soit en
        # mot, soit en table d'étiquettes. Le reste sont des colonnes sans
        # aucun champ reconnu — au-delà d'un seuil, c'est le parseur qui laisse
        # tomber de la donnée, et il faut le savoir.
        etiquettes = html.count(ETIQUETTE)
        mots = [c for c in colonnes if "v" not in c]
        muettes = len(COLONNE_RE.findall(html)) - len(mots) - etiquettes
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

        numeros = [v["verse"] for v in versets]
        if numeros != sorted(numeros):
            anomalies.append(f"{osis} {numero} : versets non croissants")
        if len(set(numeros)) != len(numeros):
            anomalies.append(f"{osis} {numero} : numéros de verset en doublon")
        if numeros and numeros[0] != 1:
            anomalies.append(f"{osis} {numero} : le chapitre commence au verset {numeros[0]}")

        for verset in versets:
            for mot in verset["words"]:
                if "a" in mot:
                    mot["a"] = ca.setdefault(mot["a"], len(ca))
                if "g" in mot:
                    mot["g"] = cg.setdefault(mot["g"], len(cg))

                if not mot.get("s"):
                    # « non réf. » dans la source : 34 mots, tous en variantes
                    # textuelles, sans numéro. `strong` reste absent plutôt
                    # qu'un numéro inventé.
                    nb_sans_strong += 1
                brut = mot.get("f", "")
                # La même règle que `AtiWord.readableGloss` côté app : un
                # token égal à `*` ou `-` est un marqueur, pas une glose. Ce
                # n'est pas un contrôle gratuit — 183 mots du NTI ont pour
                # glose « - » et portent leur mot dans la variante (« - / or ») ;
                # c'est elle qui doit rejoindre le texte joint du verset.
                net = " ".join(t for t in brut.split() if t not in ("*", "-"))
                if not brut.strip():
                    # La cellule rouge est vide : le mot reste à l'écran avec
                    # son grec et son étiquette, mais il ne joint rien.
                    nb_sans_glose += 1
                elif not net:
                    # Glose réduite à un marqueur : `readableGloss` la rend
                    # nulle pour la recherche, jamais un substitut.
                    nb_marqueur += 1
                if mot.get("f2"):
                    nb_variante += 1
            if verset["words"] and not any(
                    " ".join(t for t in w.get("f", "").split()
                             if t not in ("*", "-"))
                    for w in verset["words"]):
                anomalies.append(
                    f"{osis} {numero}:{verset['verse']} : verset sans aucune glose")
            nb_mots += len(verset["words"])
        nb_versets += len(versets)
        chapitres.append({"chapter": numero, "verses": versets})

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
        "variante": nb_variante, "sans_strong": nb_sans_strong,
        "ca": len(ca), "cg": len(cg), "octets": octets, "gz": gz,
    }


def main():
    if not EXTRAIT.is_dir():
        sys.exit(f"Extraction absente : {EXTRAIT}\n"
                 f"Lancer d'abord `python NTI/extract_nti.py`.")
    SORTIE.mkdir(exist_ok=True)

    # Contrôle de la table elle-même, avant de produire quoi que ce soit : une
    # collision d'index rendrait deux livres indiscernables côté app.
    for champ, i in (("standard", 1), ("bym", 2)):
        vus = [l[i] for l in LIVRES]
        if len(set(vus)) != len(vus):
            sys.exit(f"Table LIVRES : doublon sur {champ}")
    # `glossaire/` cohabite avec les livres dans `fichiers/` : seuls les noms
    # qui ont la forme d'un code de livre (MAT, 1CO) entrent dans la comparaison.
    dossiers = {d.name for d in EXTRAIT.iterdir()
                if d.is_dir() and CODE_LIVRE_RE.match(d.name)}
    if manquants := dossiers - {l[0] for l in LIVRES}:
        sys.exit(f"Table LIVRES : livres extraits non listés — {sorted(manquants)}")
    if absents := {l[0] for l in LIVRES} - dossiers:
        sys.exit(f"Table LIVRES : livres listés non extraits — {sorted(absents)}")

    print("Conversion du NTI en JSON téléchargeable")
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
    tot_o = sum(r["octets"] for r in lignes)
    tot_gz = sum(r["gz"] for r in lignes)
    print("-" * 86)
    print(f"{'total':24} {'':3} {'':3} {tot_ch:4} {tot_v:7,} {tot_m:7,} "
          f"{'':5} {tot_o:9,} {tot_gz:8,}")

    tot_muettes = sum(r["muettes"] for r in lignes)
    tot_sans_glose = sum(r["sans_glose"] for r in lignes)
    tot_marqueur = sum(r["marqueur"] for r in lignes)
    tot_variante = sum(r["variante"] for r in lignes)
    tot_strong = sum(r["sans_strong"] for r in lignes)

    print()
    print("Résultat")
    print("-" * 86)
    print(f"  livres            : {len(lignes)} / 27")
    print(f"  chapitres         : {tot_ch} (attendu 260)")
    print(f"  versets           : {tot_v:,} (attendu 7 957)")
    print(f"  mots              : {tot_m:,}")
    print(f"  mots sans Strong  : {tot_strong:,} — « non réf. » dans la source :")
    print(f"                      le champ reste absent, il n'est pas rempli")
    print(f"  mots sans glose   : {tot_sans_glose:,} sur {tot_m:,} — cellule rouge vide")
    print(f"  gloses marqueur   : {tot_marqueur:,} — réduites à un marqueur,")
    print(f"                      donc nulles à la recherche")
    print(f"  gloses à variante : {tot_variante:,} — rangée « Français » "
          f"portant aussi sa variante (« x / y »)")
    print(f"  colonnes rendues  : {tot_m + tot_v:,} — {tot_muettes} colonne(s) "
          f"sans champ en sus")
    print(f"  JSON en clair     : {tot_o / 1048576:,.1f} Mo")
    print(f"  ce qui voyage     : {tot_gz / 1048576:,.1f} Mo gzip")
    plus_gros = max(lignes, key=lambda r: r["octets"])
    print(f"  plus gros fichier : {plus_gros['nom']} — "
          f"{plus_gros['octets'] / 1048576:,.1f} Mo "
          f"({plus_gros['gz'] / 1048576:,.1f} Mo gzip)")
    print(f"  sortie            : {SORTIE}")

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
