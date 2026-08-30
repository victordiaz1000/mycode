"""Génère les `splash_logo.png` Android depuis le logo source de `logoBym/`.

Le logo source est une marque **blanche sur fond noir opaque**. Android a besoin
de l'inverse : la marque détourée sur transparence, posée au centre d'un canevas
carré, le fond étant fourni par le thème (`@color/splash_background`).

Deux contraintes dictent la géométrie :

1. **Android 12+ masque l'icône de démarrage en cercle**
   (`windowSplashScreenAnimatedIcon`). Pour une icône sans fond propre, la zone
   d'icône vaut 288 dp et le contenu doit tenir dans le disque central des deux
   tiers, soit 192 dp. Ce n'est pas la largeur de la marque qu'il faut borner
   mais sa **diagonale** : un rectangle ne rentre dans un disque que si
   `sqrt(l² + h²) <= diamètre`. Une marque paysage bornée en largeur seule voit
   ses coins rognés — c'est le « logo encerclé ».

2. **Android 11 et avant** dessinent le bitmap à sa taille native via
   `launch_background.xml`, sans masque. Le même fichier sert aux deux, donc le
   rendu reste comparable d'une version à l'autre.

Usage :
    python generate_splash.py                       # marque noire, source par défaut
    python generate_splash.py --encre blanc         # marque blanche (fond sombre)
    python generate_splash.py <source.png> [--encre noir|blanc]

L'encre doit contraster avec `@color/splash_background` dans
`bible_app/android/app/src/main/res/values/colors.xml` : les deux se règlent
ensemble, sinon on retombe sur le défaut d'origine — une marque noire sur un
fond noir, donc un écran vide.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

RACINE = Path(__file__).resolve().parent.parent
SOURCE_DEFAUT = RACINE / "logoBym" / "splash_logo_hd.png"
RES = RACINE / "bible_app" / "android" / "app" / "src" / "main" / "res"

# Base 288 dp (spec Android 12 pour une icône sans fond propre) × facteur de densité.
DENSITES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
BASE_DP = 288

# Part du canevas occupée par la *diagonale* de la marque. La limite dure est
# 2/3 ; on garde 0.60 pour que l'antialiasing ne vienne pas mordre le masque.
DIAGONALE_CIBLE = 0.60

# Plancher de luminance sous lequel un pixel est tenu pour du fond. Le noir des
# sources n'est pas pur — les coins de `splash_logo_hd.png` mesurent 3 à 16 —
# et sans ce plancher le recadrage garde tout le cadre, ce qui réduit la marque
# à une vignette au centre du canevas.
SEUIL_FOND = 32

# Le recadrage se décide sur la **masse d'encre par ligne et par colonne**, pas
# sur un seuil de pixel : la source porte des taches grises isolées (poussière de
# compression) jusque dans ses coins, et une décision au pixel les prend pour du
# contenu. Deux d'entre elles, invisibles à l'œil, collaient au bord droit et
# ajoutaient 22 % de vide — la marque partait alors visiblement à gauche une fois
# le bitmap centré. Une colonne n'est retenue que si sa masse atteint cette
# fraction de la colonne la plus chargée ; les taches pèsent 0,1 %, le plus fin
# des traits du sous-titre pèse 1 % et plus. Le balayage part des bords vers
# l'intérieur, donc un creux entre deux lettres ne coupe rien.
SEUIL_MASSE = 0.005

# Marge rendue au cadre détecté, pour ne pas raboter l'antialiasing du pourtour.
MARGE_CADRE = 2

# Écart toléré entre le centre du cadre et le centre de masse de l'encre, en
# pourcentage du côté concerné. Le vide non rogné se voyait ici à -13,6 %.
ECART_ALERTE = 8.0

# Couleur d'encre appliquée à la marque, son alpha étant conservé tel quel. La
# source est blanche sur noir ; l'encrer en noir sert un fond clair, et c'est le
# réglage retenu pour BYM afin qu'aucune transition de fenêtre ne montre du noir.
ENCRES = {"noir": (0, 0, 0), "blanc": (255, 255, 255)}
ENCRE_DEFAUT = "noir"


def detourer(source: Path) -> Image.Image:
    """Marque blanche sur fond noir -> marque sur transparence, recadrée.

    L'alpha vaut la luminance, et la couleur est redivisée par cette luminance :
    sans cette division, un pixel d'antialiasing gris moyen ressortirait à moitié
    transparent *et* à moitié sombre, donc deux fois trop faible une fois composé.
    """
    im = Image.open(source).convert("RGB")
    largeur, hauteur = im.size
    px = im.load()
    sortie = Image.new("RGBA", (largeur, hauteur), (0, 0, 0, 0))
    spx = sortie.load()

    sature = 0
    for y in range(hauteur):
        for x in range(largeur):
            r, g, b = px[x, y]
            lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            if lum <= SEUIL_FOND:
                continue
            if max(r, g, b) - min(r, g, b) > 40:
                sature += 1
            # Le plancher est étalé sur toute la plage, sinon les pixels juste
            # au-dessus du seuil formeraient une marche visible sur le pourtour.
            a = min(255, int(round(255 * (lum - SEUIL_FOND) / (255 - SEUIL_FOND))))
            f = 255.0 / lum  # remonte la couleur à pleine intensité
            spx[x, y] = (
                min(255, int(r * f)),
                min(255, int(g * f)),
                min(255, int(b * f)),
                a,
            )

    if sature:
        pct = 100 * sature / (largeur * hauteur)
        print(f"  ! {sature} pixels colorés ({pct:.2f} %) : le logo n'est pas")
        print(f"    strictement monochrome, vérifie le rendu des parties teintées.")

    boite = cadre_utile(sortie.getchannel("A"))
    return sortie.crop(boite)


def cadre_utile(alpha: Image.Image) -> tuple[int, int, int, int]:
    """Cadre de la marque, les taches isolées de la source étant écartées.

    Le recadrage porte sur l'alpha déjà calculé, et non sur la source : c'est
    exactement la matière qui sera composée, donc le cadre trouvé ici est aussi
    celui qui décidera du centrage.
    """
    largeur, hauteur = alpha.size
    px = alpha.load()

    colonnes = [sum(px[x, y] for y in range(hauteur)) for x in range(largeur)]
    lignes = [sum(px[x, y] for x in range(largeur)) for y in range(hauteur)]
    if not any(colonnes):
        raise SystemExit(
            "ERREUR : aucune marque détectée. La source est-elle bien une marque "
            "claire sur fond sombre ?"
        )

    g, d = bornes(colonnes)
    h_, b = bornes(lignes)
    return (
        max(0, g - MARGE_CADRE),
        max(0, h_ - MARGE_CADRE),
        min(largeur, d + 1 + MARGE_CADRE),
        min(hauteur, b + 1 + MARGE_CADRE),
    )


def bornes(masses: list[int]) -> tuple[int, int]:
    """Premier et dernier indice dont la masse compte, bords vers l'intérieur."""
    seuil = max(masses) * SEUIL_MASSE
    debut = next(i for i, v in enumerate(masses) if v > seuil)
    fin = next(i for i in range(len(masses) - 1, -1, -1) if masses[i] > seuil)
    return debut, fin


def encrer(marque: Image.Image, rgb: tuple[int, int, int]) -> Image.Image:
    """Repeint la marque dans la couleur voulue, en gardant son alpha.

    Le détourage a déjà ramené chaque pixel à pleine intensité, donc l'alpha
    porte à lui seul la forme et l'antialiasing : remplacer le RVB ne dégrade
    aucun contour.
    """
    plein = Image.new("RGBA", marque.size, rgb + (255,))
    plein.putalpha(marque.getchannel("A"))
    return plein


def composer(marque: Image.Image, cote: int) -> Image.Image:
    """Place la marque au centre d'un canevas carré, diagonale bornée."""
    lm, hm = marque.size
    diagonale = (lm**2 + hm**2) ** 0.5
    facteur = (cote * DIAGONALE_CIBLE) / diagonale
    taille = (max(1, round(lm * facteur)), max(1, round(hm * facteur)))
    redim = marque.resize(taille, Image.LANCZOS)

    canevas = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    canevas.paste(redim, ((cote - taille[0]) // 2, (cote - taille[1]) // 2))
    return canevas


def controler_centrage(marque: Image.Image) -> None:
    """Signale un cadre qui ne serait pas centré sur l'encre qu'il contient.

    La composition centre le *cadre*, pas la matière : si le cadre garde du vide
    d'un côté, la marque paraît décalée à l'écran alors que le calcul est juste.
    Un écart de quelques pour cent est normal pour un logotype (les lettres ne
    pèsent pas toutes pareil) ; au-delà de ECART_ALERTE, c'est que le recadrage
    a mordu sur du vide, et c'est là qu'il faut chercher.
    """
    largeur, hauteur = marque.size
    px = marque.getchannel("A").load()
    colonnes = [sum(px[x, y] for y in range(hauteur)) for x in range(largeur)]
    lignes = [sum(px[x, y] for x in range(largeur)) for y in range(hauteur)]
    total = sum(colonnes)

    ecarts = []
    for masses, taille, nom in ((colonnes, largeur, "horizontal"), (lignes, hauteur, "vertical")):
        centre = sum(i * v for i, v in enumerate(masses)) / total
        ecart = 100 * (centre - taille / 2) / taille
        ecarts.append(ecart)
        print(f"  centre de masse {nom} : {ecart:+.1f} % du centre du cadre")

    if max(abs(e) for e in ecarts) > ECART_ALERTE:
        print(f"  ! écart supérieur à {ECART_ALERTE:.0f} % : le cadre contient")
        print("    probablement du vide, vérifie les taches isolées de la source.")


def main(argv: list[str]) -> int:
    encre = ENCRE_DEFAUT
    positionnels: list[str] = []
    reste = argv[1:]
    while reste:
        arg = reste.pop(0)
        if arg == "--encre":
            if not reste:
                raise SystemExit("ERREUR : --encre attend une valeur (noir ou blanc).")
            encre = reste.pop(0)
        elif arg.startswith("--encre="):
            encre = arg.split("=", 1)[1]
        elif arg.startswith("--"):
            raise SystemExit(f"ERREUR : option inconnue : {arg}")
        else:
            positionnels.append(arg)

    if encre not in ENCRES:
        raise SystemExit(
            f"ERREUR : encre inconnue : {encre} (valeurs : {', '.join(ENCRES)})"
        )

    source = Path(positionnels[0]) if positionnels else SOURCE_DEFAUT
    if not source.is_file():
        raise SystemExit(f"ERREUR : source introuvable : {source}")

    print(f"Source : {source.relative_to(RACINE)}")
    print(f"Encre  : {encre} — le fond du thème doit contraster avec elle")
    marque = encrer(detourer(source), ENCRES[encre])
    lm, hm = marque.size
    print(f"  marque détourée : {lm} x {hm} px (rapport {lm / hm:.2f}:1)")
    controler_centrage(marque)

    for densite, facteur in DENSITES.items():
        cote = round(BASE_DP * facteur)
        dossier = RES / f"drawable-{densite}"
        dossier.mkdir(parents=True, exist_ok=True)
        cible = dossier / "splash_logo.png"
        image = composer(marque, cote)
        image.save(cible, "PNG", optimize=True)

        boite = image.getchannel("A").getbbox()
        diag = ((boite[2] - boite[0]) ** 2 + (boite[3] - boite[1]) ** 2) ** 0.5
        print(
            f"  {cible.relative_to(RACINE)}  {cote}x{cote}  "
            f"diagonale {100 * diag / cote:.0f}% (limite 67%)"
        )

    # `drawable-nodpi/` ferait doublon avec l'échelle de densités ci-dessus et
    # rendrait la résolution de `@drawable/splash_logo` ambiguë.
    obsolete = RES / "drawable-nodpi" / "splash_logo.png"
    if obsolete.is_file():
        obsolete.unlink()
        print(f"  supprimé : {obsolete.relative_to(RACINE)} (doublon nodpi)")

    print("Terminé.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
