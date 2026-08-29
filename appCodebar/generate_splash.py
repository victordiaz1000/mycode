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
    python generate_splash.py              # depuis logoBym/splash_logo_hd.png
    python generate_splash.py <source.png>
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageFilter

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

# Le recadrage se décide sur un masque **médian 5×5**, pas sur l'alpha brut : la
# source porte des pixels clairs isolés (poussière de compression) jusque dans
# ses coins, et un simple `getbbox()` sur l'alpha renvoie alors 94 % du cadre.
# Le médian efface ces points sans ronger les traits, là où une érosion
# supprimait aussi le sous-titre en traits fins.
SEUIL_CADRE = 48
MEDIAN_CADRE = 5

# Marge rendue au cadre détecté, pour compenser ce que le médian a pu ronger sur
# le pourtour des traits les plus fins.
MARGE_CADRE = 4


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

    boite = cadre_utile(im)
    return sortie.crop(boite)


def cadre_utile(im: Image.Image) -> tuple[int, int, int, int]:
    """Cadre de la marque, les pixels clairs isolés de la source étant écartés."""
    largeur, hauteur = im.size
    masque = (
        im.convert("L")
        .filter(ImageFilter.MedianFilter(MEDIAN_CADRE))
        .point(lambda v: 255 if v > SEUIL_CADRE else 0)
    )
    boite = masque.getbbox()
    if boite is None:
        raise SystemExit(
            "ERREUR : aucune marque détectée. La source est-elle bien une marque "
            "claire sur fond sombre ?"
        )
    g, h_, d, b = boite
    return (
        max(0, g - MARGE_CADRE),
        max(0, h_ - MARGE_CADRE),
        min(largeur, d + MARGE_CADRE),
        min(hauteur, b + MARGE_CADRE),
    )


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


def main(argv: list[str]) -> int:
    source = Path(argv[1]) if len(argv) > 1 else SOURCE_DEFAUT
    if not source.is_file():
        raise SystemExit(f"ERREUR : source introuvable : {source}")

    print(f"Source : {source.relative_to(RACINE)}")
    marque = detourer(source)
    lm, hm = marque.size
    print(f"  marque détourée : {lm} x {hm} px (rapport {lm / hm:.2f}:1)")

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
