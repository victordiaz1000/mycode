# -*- coding: utf-8 -*-
"""Grec → translittération latine, d'après la convention du kit Stephanus.

Le dépôt n'avait aucun translittérateur grec : `k` du NTI est le grec sans
accents, pas du latin. Celui-ci sert deux corpus — le grec accentué de
l'interlinéaire complet, et le grec **sans accents** du Textus Receptus, que
son README laisse délibérément nu (« les accents se reconstituent par le
lexique ou par la morphologie »). Une seule table sert les deux : le texte
accentué reprend son accent sur la voyelle latine, le texte nu n'en a pas.

## La convention n'est pas choisie, elle est lue

`TR-Stephanus-1550/lexique/strongs-greek.json` porte, pour 5 523 lemmes, une
translittération à côté du grec. On en a tiré la table au lieu de l'inventer :

    θεός  → theós          θ donne th, pas t
    φῶς   → phōs           φ donne ph, pas f
    χάρις → cháris         χ donne ch, pas k
    οὐρανός → ouranós      ου donne ou
    αἰών  → aiṓn          αι donne ai, l'accent tombe sur le ι
    βασιλεία → basileía    ει donne ei
    ἔλεγχος → élenchos     γ devant un vélar vaut n
    αἷμα  → haîma          la respiration aspre vaut h
    Ἑβραῖος → Hebraîos     c'est le h qui prend la majuscule
    κύκλῳ → kýklōi         l'iota subscriptum vaut i
    Γάϊος → Gáïos          le tréma se garde, même avec un accent
    γῆ    → gē             le circonflexe sur un η est redondant
    βολή  → bolḗ           l'oxie, elle, se pose

C'est la même famille de conventions que celle des lexiques de référence.
Elle se vérifie : `mesure_translit_grec.py` applique ce module aux 5 523
lemmes du kit et compte l'accord avec `translit`. Le kit sert de **juge**,
jamais de source — aucune translittération de ce lexique n'est reportée dans
les livres servis.

## Ce que fait la table, et ce qu'elle ne fait pas

Elle translittère lettres, digraphes et les quatre particularités que le juge
montre — respiration aspre, assimilation du gamma devant les vélars, iota
subscriptum, tréma — et reporte l'accent grec sur la voyelle latine qui reçoit
la lettre accentuée, **dans l'ordre où le grec l'écrit** : c'est ce qui
donne `i` + tréma + oxia pour `ἀΐδιος`, et non l'inverse.

Elle ne fait **aucune phonétique** : ni valeur de position du gamma ailleurs,
ni traitement du ν mouvable. Le kit lui-même sépare d'ailleurs sa
translittération de sa prononciation (`translit` contre `prononciation`) —
« theós » d'un côté, « theh'-os » de l'autre. On s'en tient au premier.
"""
import unicodedata

# — Lettres ————————————————————————————————————————————————————————
LETTRES = {
    "α": "a", "β": "b", "γ": "g", "δ": "d", "ε": "e", "ζ": "z",
    "η": "ē", "θ": "th", "ι": "i", "κ": "k", "λ": "l", "μ": "m",
    "ν": "n", "ξ": "x", "ο": "o", "π": "p", "ρ": "r", "ς": "s",
    "σ": "s", "τ": "t", "υ": "y", "φ": "ph", "χ": "ch", "ψ": "ps",
    "ω": "ō",
}

# — Digraphes ————————————————————————————————————————————————————————
# Deux voyelles liées ne forment qu'un seul son : ου donne « ou », αι
# donne « ai ». `υι` — Ὑμεναῖος, ὑἱός — se lit « ui », contrairement au υ
# isolé qui donne « y ».
DIGRAPHES = {
    "αι": "ai", "ει": "ei", "οι": "oi", "υι": "ui",
    "αυ": "au", "ευ": "eu", "ηυ": "ēu", "ου": "ou",
}

# — Marques ————————————————————————————————————————————————————————
# Combinaison grecque → marque latine équivalente, **dans cet ordre**.
# Deux marques se suivent comme le grec les écrit : ἀΐδιος se décompose en
# ι, tréma, oxia, et se transcrit dans le même sens.
MARQUES = {
    "́": "́",     # oxia         → aigu
    "̀": "̀",     # varie        → grave
    "͂": "̂",     # périspomène  → circonflexe
    "̈": "̈",     # tréma        → tréma
}
PERISPOMENE = "͂"

# Le tréma ne marque pas un accent mais une coupure : il interdit de
# lier la lettre à la précédente. πραΰς n'a pas de digraphe αυ.
TREMA = "̈"

# La respiration n'est pas un accent : aspre → h, lisse → rien. Sur un ρ le
# h se pose après — βοῤῥᾶς → borrhâs.
SOUFFLE = {
    "̔": "h",    # dasia (aspre)
    "̓": "",     # psili (lisse)
}
IOTA_SUBSCRIT = "ͅ"

# Ce que la table ignore encore : un caractère inconnu est laissé tel quel
# plutôt que dévoré en silence, pour qu'il apparaisse dans la mesure.
INCONNUS = set()

# Le γ prend la valeur nasale devant un vélar : ἔλεγχος → élenchos,
# γογγύζω → gongýzō, ἐγκάθετος → enkáthetos.
VELARS = "γκχξ"


def _decouper(mot):
    """« Ἑβραῖος » → [('Ε', '', 'h', False), ('β', '', '', False), …].

    Chaque lettre grecque est rendue seule, ses combinaisons à côté, dans
    l'ordre où le texte les écrit. Respiration et iota subscriptum sont
    gardés à part : ce sont des signes que le juge transcrit, et les jeter
    reviendrait à tronquer `haîma` en `aîma` ou `kýklōi` en `kýklō`.

    Le circonflexe porté par un η ou un ω est, lui, écarté d'ici : ces deux
    lettres se transcrivent déjà par un macron, et le juge n'y ajoute rien —
    γῆ → gē, non gê.
    """
    forme = unicodedata.normalize("NFD", mot)
    lettres = []
    for caractere in forme:
        if unicodedata.combining(caractere):
            if not lettres:
                # Une combinaison sans lettre sous elle : rien à quoi
                # l'accrocher. On la note et on passe.
                if caractere not in INCONNUS:
                    INCONNUS.add(caractere)
                continue
            base, marques, souffle, iota = lettres[-1]
            if caractere in SOUFFLE:
                souffle += SOUFFLE[caractere]
            elif caractere == IOTA_SUBSCRIT:
                iota = True
            elif caractere in MARQUES:
                if caractere == PERISPOMENE and base.lower() in "ηω":
                    pass        # déjà un macron
                else:
                    marques += MARQUES[caractere]
            elif caractere not in INCONNUS:
                INCONNUS.add(caractere)
            lettres[-1] = (base, marques, souffle, iota)
            continue
        lettres.append((caractere, "", "", False))
    return lettres


def _lettre(base, marques, souffle, iota):
    """Une lettre grecque → son bout latin, marque, tréma et iota compris."""
    minuscule = base.lower()
    latin = LETTRES[minuscule]
    if souffle and minuscule == "ρ":
        latin += "h"           # ῥ → rh : le h suit le r, il ne le précède pas
    elif souffle:
        latin = souffle + latin
    # La marque se pose sur la voyelle **avant** l'iota subscriptum, qu'elle
    # précède — ᾄδω → áidō, ῳ → ōi. Posée après, elle tomberait sur l'iota :
    # « aídō » au lieu de « áidō ».
    latin += marques
    if iota:
        latin += "i"
    if base.isupper():
        # La majuscule va au premier caractère : Ἑβραῖος → Hebraîos, ce qui
        # donne un H suivi d'une minuscule, et non « hEbraîos ».
        latin = latin[0].upper() + latin[1:]
    return unicodedata.normalize("NFC", latin)


def translitterer(mot):
    """« Βίβλος » → « Bíblos », « βιβλος » → « biblos ».

    Renvoie une chaîne vide pour un mot vide. Les lettres hors table — la
    ponctuation syllabique, un chiffre — passent telles qu'elles : elles ont
    leur place dans le mot et aucune translittération à subir.
    """
    if not mot:
        return ""
    lettres = _decouper(mot)
    bouts = []
    i = 0
    while i < len(lettres):
        base, marques, souffle, iota = lettres[i]
        minuscule = base.lower()

        if minuscule not in LETTRES:
            # Hors table : ponctuation syllabique, maqaf, chiffre, tiret.
            # On le garde, on ne l'invente pas.
            bouts.append(base)
            i += 1
            continue

        suivant = lettres[i + 1][0].lower() if i + 1 < len(lettres) else ""
        # Un tréma sur la seconde lettre la déclare syllabe à part — c'est
        # même à cela qu'il sert : πραΰς → « praÿs », et non « praus ».
        digraphe = None
        if suivant and TREMA not in lettres[i + 1][1]:
            digraphe = DIGRAPHES.get(minuscule + suivant)

        if digraphe:
            # Digraphe : l'accent porte sur l'une ou l'autre des deux
            # lettres, et va alors sur le bout latin de celle qui le porte.
            (_, marques_suivant, souffle_suivant, iota_suivant) = lettres[i + 1]
            premier = digraphe[0]
            second = digraphe[1:]
            if marques:
                premier += marques
            if iota:
                premier += "i"
            if marques_suivant:
                second += marques_suivant
            if iota_suivant:
                second += "i"
            bout = premier + second
            if souffle:
                bout = souffle + bout
            if souffle_suivant:
                # Unicode range parfois la respiration après la seconde
                # lettre du digraphe alors qu'elle porte sur la première —
                # αἷμα décompose en α, ι, aspre, circonflexe. Le h va donc
                # en tête, comme celui de l'autre lettre.
                bout = souffle_suivant + bout
            if base.isupper():
                # Qu'il y ait un h devant ou non, la majuscule tombe sur le
                # premier caractère : Αἰγύπτιος → Aigýptios, Ἑβραῖος →
                # Hebraîos. Le reste reste minuscule.
                bout = bout[0].upper() + bout[1:]
            bouts.append(unicodedata.normalize("NFC", bout))
            i += 2
            continue

        # Le γ devant un vélar vaut n — il le remplace : ἐγγύς → engýs,
        # ἐγκάθετος → enkáthetos, ἔλεγχος → élenchos. Le `suivant and` est
        # nécessaire : `"" in "γκχξ"` vaut True, et un γ final serait
        # devenu un n.
        if suivant and minuscule == "γ" and suivant in VELARS:
            bouts.append("n")
            i += 1
            continue

        bouts.append(_lettre(base, marques, souffle, iota))
        i += 1

    return unicodedata.normalize("NFC", "".join(bouts))
