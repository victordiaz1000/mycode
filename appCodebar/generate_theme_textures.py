#!/usr/bin/env python3
"""Fabrique les deux fonds *générés* du catalogue de thèmes.

Les dix fonds historiques sont des photos ou des motifs importés ; ceux-ci sont
calculés, donc reproductibles — ce fichier est la seule source de
`assets/themes/lin.png` et `assets/themes/veillee.png`. Sans lui les deux PNG
seraient deux binaires que personne ne saurait régénérer ni retoucher.

Deux contraintes gouvernent tout le script :

1. **Le pavage doit être invisible.** Les deux thèmes sont déclarés
   `BackgroundFit.tile` : la tuile se répète des dizaines de fois à l'écran, et
   la moindre discontinuité au bord dessine une grille. Tout le bruit est donc
   filtré *dans le domaine de Fourier* (`np.fft`), ce qui le rend périodique par
   construction, et les trames de tissage sont des sinusoïdes dont la période
   divise exactement la taille de la tuile. Aucun flou à bords ouverts, aucun
   raccord à recoller.

2. **La moyenne de l'image EST le `backgroundTone` du thème.** Dans
   `theme_catalog.dart` ce ton dérive tout le reste (fond d'écran premium,
   cartes, panneau de lecture) : s'il s'écarte de la texture, les surfaces
   opaques jurent avec le fond visible entre elles. Le script recentre donc la
   moyenne exactement sur la cible et l'affiche à la fin, pour qu'on puisse la
   recopier telle quelle dans le catalogue.

Usage :  python appCodebar/generate_theme_textures.py [--out DOSSIER]
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

TILE = 320

# Les tons cibles, tels que le catalogue les déclare.
LIN_TONE = (0xF5, 0xEF, 0xE2)  # ivoire de lin, chaud mais très clair
VEILLEE_TONE = (0x1A, 0x13, 0x0E)  # brun-noir de reliure, à la lampe


def _periodic_noise(rng: np.random.Generator, size: int, sigma: float) -> np.ndarray:
    """Bruit blanc passé au filtre gaussien **circulaire**, donc périodique.

    Le filtrage se fait par multiplication dans le domaine de Fourier : la
    transformée d'un signal discret est cyclique, donc le résultat se raccorde
    de lui-même bord à bord. Un `GaussianBlur` de PIL, lui, traite les bords
    comme des fins d'image et laisse une couture visible au pavage.

    Le résultat est normalisé en écart-type 1 : l'amplitude se décide au point
    d'appel, en unités de niveau de gris.
    """
    freq = np.fft.fftfreq(size) * size
    fx, fy = np.meshgrid(freq, freq, indexing="ij")
    kernel = np.exp(-2 * (np.pi * sigma) ** 2 * (fx**2 + fy**2) / size**2)
    field = np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((size, size))) * kernel))
    return field / field.std()


def _weave(size: int, period: int, jitter: np.ndarray) -> np.ndarray:
    """Trame de tissage : deux réseaux sinusoïdaux croisés, de période entière.

    `period` doit diviser `size` — sinon la sinusoïde se coupe en plein cycle au
    bord et le pavage bat. `jitter` déplace légèrement chaque fil pour éviter la
    régularité mécanique d'une grille parfaite ; il est lui-même périodique.
    """
    if size % period:
        raise ValueError(f"période {period} ne divise pas {size}")
    x = np.arange(size)[None, :] * np.ones((size, 1))
    y = np.arange(size)[:, None] * np.ones((1, size))
    warp = np.sin(2 * np.pi * (x + jitter * 1.6) / period)
    weft = np.sin(2 * np.pi * (y - jitter * 1.6) / period)
    # Le produit croisé marque les points de croisement ; la somme donne les
    # fils. Le mélange des deux imite un lin lâche plutôt qu'un quadrillage.
    return 0.62 * (warp + weft) + 0.38 * warp * weft


def _finish(rgb: np.ndarray, tone: tuple[int, int, int]) -> Image.Image:
    """Recentre chaque canal sur `tone` puis rend l'image 8 bits.

    Le recentrage vient **après** tout le reste : les écrêtages de `clip` ont
    déplacé la moyenne, et c'est la moyenne finale — celle que l'application
    verra — qui doit valoir le ton déclaré.
    """
    out = rgb.copy()
    for channel, target in enumerate(tone):
        plane = out[:, :, channel]
        for _ in range(6):  # quelques passes : `clip` peut redéplacer la moyenne
            plane = np.clip(plane + (target - plane.mean()), 0, 255)
        out[:, :, channel] = plane
    return Image.fromarray(np.round(out).astype(np.uint8), mode="RGB")


def lin(seed: int = 20260830) -> Image.Image:
    """« Lin blanc » : ivoire tissé, contraste très faible.

    C'est un fond de lecture clair : la texture doit se sentir sans se voir. Le
    tissage plafonne donc à ±2,6 niveaux et le grain à ±1,6 — au-delà, les fils
    entrent en concurrence avec les hampes du texte.

    Les deux réglages viennent d'un aperçu, pas d'un calcul : à la période 8 et
    à ±3,5 la trame se lisait comme une moustiquaire, avec un moiré en diagonale
    là où les deux réseaux se croisaient. Une période plus serrée (5 px, soit 64
    cycles par tuile) et un fil deux fois plus tremblé donnent du tissu au lieu
    d'une grille.
    """
    rng = np.random.default_rng(seed)
    jitter = 2.6 * _periodic_noise(rng, TILE, 9.0)
    field = 2.6 * _weave(TILE, 5, jitter)
    field += 2.4 * _periodic_noise(rng, TILE, 16.0)  # irrégularité de la toile
    field += 1.6 * _periodic_noise(rng, TILE, 1.1)  # grain fin
    base = np.array(LIN_TONE, dtype=float)
    # Le lin s'assombrit un peu plus dans le bleu que dans le rouge : les creux
    # tirent vers le beige, pas vers le gris.
    tint = np.array([1.0, 1.06, 1.22])
    rgb = base[None, None, :] + field[:, :, None] * tint[None, None, :]
    return _finish(np.clip(rgb, 0, 255), LIN_TONE)


def veillee(seed: int = 20260831) -> Image.Image:
    """« Veillée » : cuir de reliure sombre, éclairé à la lampe.

    Fond sombre, donc l'inverse du problème du lin : ici la texture doit rester
    visible malgré la faible luminance disponible (le ton est à 7 % de blanc).
    Le marbrage reste sous ±3,5 niveaux, et de rares grains chauds — jamais des
    étoiles, « Nuit étoilée » tient déjà ce rôle — donnent la matière.

    Le marbrage est délibérément de fréquence *moyenne* : un premier essai à
    grande échelle (sigma 26) produisait une tache claire par tuile, et cette
    tache se répétait tous les 320 px en trahissant le pavage aussi sûrement
    qu'une couture. Un marbrage plus serré se lit comme la fleur du cuir et se
    fond dans sa propre répétition.
    """
    rng = np.random.default_rng(seed)
    field = 3.4 * _periodic_noise(rng, TILE, 9.0)  # marbrage du cuir
    field += 2.6 * _periodic_noise(rng, TILE, 4.0)  # fleur, grain moyen
    field += 2.0 * _periodic_noise(rng, TILE, 1.0)  # grain fin
    base = np.array(VEILLEE_TONE, dtype=float)
    # Les reliefs prennent la lumière chaude de la lampe : le rouge monte deux
    # fois plus vite que le bleu, ce qui fait virer les crêtes vers l'ambre.
    tint = np.array([1.6, 1.05, 0.72])
    rgb = base[None, None, :] + field[:, :, None] * tint[None, None, :]

    # Quelques éclats ambrés très diffus, épars : la matière d'un cuir usé.
    speck = np.zeros((TILE, TILE))
    for _ in range(18):
        cy, cx = rng.integers(0, TILE, size=2)
        speck[cy, cx] = rng.uniform(0.5, 1.0)
    # Étalement circulaire — même raison que `_periodic_noise` : au pavage, un
    # éclat posé sur un bord doit reparaître de l'autre côté.
    freq = np.fft.fftfreq(TILE) * TILE
    fx, fy = np.meshgrid(freq, freq, indexing="ij")
    halo = np.exp(-2 * (np.pi * 5.0) ** 2 * (fx**2 + fy**2) / TILE**2)
    speck = np.real(np.fft.ifft2(np.fft.fft2(speck) * halo))
    speck = speck / speck.max() * 5.0
    rgb += speck[:, :, None] * np.array([1.0, 0.66, 0.30])[None, None, :]
    return _finish(np.clip(rgb, 0, 255), VEILLEE_TONE)


def _seam_error(image: Image.Image) -> float:
    """Écart moyen entre les bords opposés, en niveaux.

    C'est la mesure de « le pavage se voit ou pas » : sur une tuile périodique,
    la colonne 0 doit prolonger la colonne N-1 aussi naturellement que deux
    colonnes voisines quelconques. On compare donc l'écart aux bords à l'écart
    intérieur moyen, et on rend leur rapport — 1.0 = couture indétectable.
    """
    a = np.asarray(image, dtype=float)
    seam = np.abs(a[0] - a[-1]).mean() + np.abs(a[:, 0] - a[:, -1]).mean()
    inner = np.abs(np.diff(a, axis=0)).mean() + np.abs(np.diff(a, axis=1)).mean()
    return seam / inner


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "bible_app" / "assets" / "themes",
        help="dossier de destination (défaut : bible_app/assets/themes)",
    )
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    for name, build, tone in (("lin", lin, LIN_TONE), ("veillee", veillee, VEILLEE_TONE)):
        image = build()
        path = args.out / f"{name}.png"
        image.save(path, optimize=True)
        mean = np.asarray(image, dtype=float).reshape(-1, 3).mean(axis=0)
        print(
            f"{path.name:12} {image.size[0]}x{image.size[1]} "
            f"moyenne=#{int(round(mean[0])):02X}{int(round(mean[1])):02X}{int(round(mean[2])):02X} "
            f"(cible #{tone[0]:02X}{tone[1]:02X}{tone[2]:02X}) "
            f"couture={_seam_error(image):.2f}x l'écart interne "
            f"{path.stat().st_size // 1024} Ko"
        )


if __name__ == "__main__":
    main()
