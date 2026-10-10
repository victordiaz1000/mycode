# LGS / LSS (Biblia Universalis 3) vs LSGS embarquée

- Sources : `Ressources/bibles/LGS.xml` (Segond Louis + Strong 2) et `LSS.xml` (Segond Louis + Strong), références lues dans leur `<toc>`.
- Référence : `bible_app/assets/bible/lsgs/` — « Bible Segond 1910 + Strongs » (`LSGS`), 66 livres, format getbible.
- Texte comparé après trois normalisations : **forme** (apostrophes, tirets, espaces) puis **sens** (lettres et chiffres seuls), puis **accents ignorés** (LSS omet les diacritiques : « Enosch » / « Énosch »).
- Les codes composites de l'app (`"H8337 H6240"`) sont éclatés en deux codes avant comparaison des séquences.

## 1. Ce qui a été extrait

| version | blocs | chapitres | livres | versets | jetons | dont forts | codes distincts |
|---|---:|---:|---:|---:|---:|---:|---:|
| LGS | 1190 | 1189 | 66 | 31169 | 856947 | 424572 | 14034 |
| LSS | 1192 | 1189 | 66 | 31168 | 802730 | 448256 | 14454 |
| LSGS (app) | — | 1189 | 66 | 31171 | — | 413864 | 14011 |

- **LGS** : blocs non chapitre écartés par le TOC — index.html ; 14198 codes sans mot recevable (mots non traduits, jeton de texte vide) ; 0 caractère(s) hors UTF-8.
  - numérotation : 1..N sur les 1189 chapitres (0 écart)
  - marqueurs : cn d'ouverture conforme au TOC (0 écart(s)) ; 0 chapitre(s) ouvert par un vn ; 0 cn en cours de chapitre
  - 0 chapitre(s) sans marqueur, 2 verset(s) vide(s)
- **LSS** : blocs non chapitre écartés par le TOC — images/beige.gif, index.html, styles.css ; 116567 codes sans mot recevable (mots non traduits, jeton de texte vide) ; 0 caractère(s) hors UTF-8.
  - marqueurs collés fusionnés (3) :
    - 2KI/017.html: <span class="vn">40</span> puis <span class="vn">2</span>
    - GEN/004.html: <span class="vn">16</span> puis <span class="vn">2</span>
    - PRO/010.html: <span class="vn">16</span> puis <span class="vn">2</span>
  - chapitres renumérotés par position (5, numérotation d'origine fautive) :
    - 1CO/001.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31] -> 1..31
    - ACT/007.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60] -> 1..60
    - PRO/005.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 17, 18, 19, 20, 21, 22, 23] -> 1..23
    - PRO/011.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 38, 29, 30, 31] -> 1..31
    - TIT/001.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 14, 15, 16] -> 1..16
  - numérotation encore hors 1..N (1 chapitre(s), marqueur réellement manquant) :
    - EXO/028.html: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 43]
  - marqueurs : cn d'ouverture conforme au TOC (0 écart(s)) ; 0 chapitre(s) ouvert par un vn ; 0 cn en cours de chapitre

## 2. Couverture

- **LGS vs LSGS** : 31169 versets communs ; 2 seulement dans l'app ; 0 seulement dans LGS.
  - absent de LGS : Actes 19:41
  - absent de LGS : Nombres 25:19
- **LSS vs LSGS** : 31168 versets communs ; 3 seulement dans l'app ; 0 seulement dans LSS.
  - absent de LSS : Actes 19:41
  - absent de LSS : Exode 28:42
  - absent de LSS : Nombres 25:19

## 3. Texte

| comparaison | versets communs | même forme | même sens | même sens (accents ignorés) |
|---|---:|---:|---:|---:|
| LGS vs LSGS | 31169 | 10493 | 31166 | 31166 |
| LSS vs LSGS | 31168 | 15217 | 26616 | 30924 |

« Même forme » : espaces, apostrophes et tirets égalisés. « Même sens » : ponctuation et espaces retirés — un écart ici est un écart de rédaction, pas de typographie. « Accents ignorés » : diacritiques retirés en plus — ce qui reste est un vrai écart de texte.

### Écarts de forme seulement

- **1 Chroniques 1:5** (LGS)
  - LSGS : Fils de Japhet : Gomer, Magog, Madaï, Javan, Tubal, Méschec et Tiras. -
  - LGS : Fils de Japhet: Gomer, Magog, Madaï, Javan, Tubal, Méschec et Tiras. -
- **1 Chroniques 1:6** (LGS)
  - LSGS : Fils de Gomer : Aschkenaz, Diphat et Togarma. -
  - LGS : Fils de Gomer: Aschkenaz, Diphat et Togarma. -
- **1 Chroniques 1:7** (LGS)
  - LSGS : Fils de Javan : Élischa, Tarsisa, Kittim et Rodanim.
  - LGS : Fils de Javan: Élischa, Tarsisa, Kittim et Rodanim.
- **1 Chroniques 1:8** (LGS)
  - LSGS : Fils de Cham : Cusch, Mitsraïm, Puth et Canaan. -
  - LGS : Fils de Cham: Cusch, Mitsraïm, Puth et Canaan. -
- **1 Chroniques 1:9** (LGS)
  - LSGS : Fils de Cusch : Saba, Havila, Sabta, Raema et Sabteca. -Fils de Raema : Séba et Dedan.
  - LGS : Fils de Cusch: Saba, Havila, Sabta, Raema et Sabteca. - Fils de Raema: Séba et Dedan.
- **1 Chroniques 1:10** (LGS)
  - LSGS : Cusch engendra Nimrod ; c'est lui qui commença à être puissant sur la terre. -
  - LGS : Cusch engendra Nimrod; c'est lui qui commença à être puissant sur la terre. -
- **1 Chroniques 1:17** (LGS)
  - LSGS : Fils de Sem : Élam, Assur, Arpacschad, Lud et Aram ; Uts, Hul, Guéter et Méschec. -
  - LGS : Fils de Sem: Élam, Assur, Arpacschad, Lud et Aram; Uts, Hul, Guéter et Méschec. -
- **1 Chroniques 1:18** (LGS)
  - LSGS : Arpacschad engendra Schélach ; et Schélach engendra Héber.
  - LGS : Arpacschad engendra Schélach; et Schélach engendra Héber.

### Écarts d'accents seulement

- **1 Chroniques 1:1** (LSS)
  - LSGS : Adam, Seth, Énosch,
  - LSS : Adam, Seth, Enosch,
- **1 Chroniques 1:7** (LSS)
  - LSGS : Fils de Javan : Élischa, Tarsisa, Kittim et Rodanim.
  - LSS : Fils de Javan: Elischa, Tarsisa, Kittim et Rodanim.
- **1 Chroniques 1:17** (LSS)
  - LSGS : Fils de Sem : Élam, Assur, Arpacschad, Lud et Aram ; Uts, Hul, Guéter et Méschec. -
  - LSS : Fils de Sem: Elam, Assur, Arpacschad, Lud et Aram; Uts, Hul, Guéter et Méschec.
- **1 Chroniques 1:33** (LSS)
  - LSGS : Fils de Madian : Épha, Épher, Hénoc, Abida et Eldaa. -Ce sont là tous les fils de Ketura.
  - LSS : Fils de Madian: Epha, Epher, Hénoc, Abida et Eldaa. -Ce sont là tous les fils de Ketura.
- **1 Chroniques 1:34** (LSS)
  - LSGS : Abraham engendra Isaac. Fils d'Isaac : Ésaü et Israël.
  - LSS : Abraham engendra Isaac. Fils d'Isaac: Esaü et Israël.
- **1 Chroniques 1:35** (LSS)
  - LSGS : Fils d'Ésaü : Éliphaz, Reuel, Jeusch, Jaelam et Koré. -
  - LSS : Fils d'Esaü: Eliphaz, Reuel, Jeusch, Jaelam et Koré.
- **1 Chroniques 1:36** (LSS)
  - LSGS : Fils d'Éliphaz : Théman, Omar, Tsephi, Gaetham, Kenaz, Thimna et Amalek. -
  - LSS : Fils d'Eliphaz: Théman, Omar, Tsephi, Gaetham, Kenaz, Thimna et Amalek.
- **1 Chroniques 1:39** (LSS)
  - LSGS : Fils de Lothan : Hori et Homam. Sœur de Lothan : Thimna. -
  - LSS : Fils de Lothan: Hori et Homam. Soeur de Lothan: Thimna.

### Écarts de texte

- **Lévitique 13:35** (LGS)
  - LSGS : Mais si la teigne s'est étendue sur la peau, après qu'il a été déclaré pur,
  - LGS : Mais si la teigne s'est étendue sur la peau, après qu'il a été déclaré pur, le sacrificateur l'examinera.
- **Lévitique 13:36** (LGS)
  - LSGS : le sacrificateur l'examinera. Et si la teigne s'est étendue sur la peau, le sacrificateur n'aura pas à rechercher s'il y a du poil jaunâtre : il est impur.
  - LGS : Et si la teigne s'est étendue sur la peau, le sacrificateur n'aura pas à rechercher s'il y a du poil jaunâtre: il est impur.
- **Nombres 26:1** (LGS)
  - LSGS : l'Éternel dit à Moïse et à Éléazar, fils du sacrificateur Aaron :
  - LGS : À la suite de cette plaie, l'Éternel dit à Moïse et à Éléazar, fils du sacrificateur Aaron:
- **1 Chroniques 1:22** (LSS)
  - LSGS : Ébal, Abimaël, Séba,
  - LSS : Ebal, Abimaël, Séba, Ophir, Havila et Jobab.
- **1 Chroniques 1:23** (LSS)
  - LSGS : Ophir, Havila et Jobab. Tous ceux-là furent fils de Jokthan.
  - LSS : Tous ceux-là furent fils de Jokthan.
- **1 Chroniques 3:7** (LSS)
  - LSGS : Noga, Népheg, Japhia,
  - LSS : Noga, Népheg, Japhia, Elischama,
- **1 Chroniques 3:8** (LSS)
  - LSGS : Élischama, Éliada et Éliphéleth, neuf.
  - LSS : Eliada et Eliphéleth, neuf.
- **1 Chroniques 9:42** (LSS)
  - LSGS : Achaz engendra Jaera ; Jaera engendra Alémeth, Azmaveth et Zimri ; Zimri engendra Motsa ;
  - LSS : Achaz engendra Jaera; Jaera engendra Alémeth, Azmaveth et Zimri; Zimri engendra Motsa; Motsa engendra Binea.
- **1 Chroniques 9:43** (LSS)
  - LSGS : Motsa engendra Binea. Rephaja, son fils ; Éleasa, son fils ; Atsel, son fils.
  - LSS : Rephaja, son fils; Eleasa, son fils; Atsel, son fils.
- **1 Chroniques 19:17** (LSS)
  - LSGS : On l'annonça à David, qui assembla tout Israël, passa le Jourdain, marcha contre eux, et se prépara à les attaquer. David se rangea en bataille contre les Syriens.
  - LSS : On l'annonça à David, qui assembla tout Israël, passa le Jourdain, marcha contre eux, et se prépara à les attaquer. David se rangea en bataille contre les Syriens. Mais …

### Versets présents d'un seul côté (échantillon)

- **Actes 19:41** : absent de LGS, LSGS : (verset vide)
- **Nombres 25:19** : absent de LGS, LSGS : À la suite de cette plaie,
- **Actes 19:41** : absent de LSS, LSGS : (verset vide)
- **Exode 28:42** : absent de LSS, LSGS : Fais-leur des caleçons de lin, pour couvrir leur nudité ; ils iront depuis les reins jusqu'aux cuisses.
- **Nombres 25:19** : absent de LSS, LSGS : À la suite de cette plaie,

## 4. Codes Strong

| comparaison | versets communs | même séquence | séquences différentes |
|---|---:|---:|---:|
| LGS vs LSGS | 31169 | 22159 | 9010 |
| LSS vs LSGS | 31168 | 883 | 30285 |

### Écarts de séquence — LGS (échantillon)

- **1 Chroniques 1:19** — LSGS 14 codes / LGS 15
- **1 Chroniques 1:50** — LSGS 16 codes / LGS 17
- **1 Chroniques 2:16** — LSGS 9 codes / LGS 10
- **1 Chroniques 2:23** — LSGS 16 codes / LGS 17
- **1 Chroniques 2:51** — LSGS 7 codes / LGS 8
- **1 Chroniques 2:54** — LSGS 10 codes / LGS 11

### Écarts de séquence — LSS (échantillon)

- **1 Chroniques 1:10** — LSGS 8 codes / LSS 8 · seulement LSGS ['H1931', 'H1961'] · seulement LSS ['H8804', 'H8689']
- **1 Chroniques 1:11** — LSGS 6 codes / LSS 7 · seulement LSS ['H8804']
- **1 Chroniques 1:12** — LSGS 7 codes / LSS 6 · seulement LSGS ['H0834', 'H8033'] · seulement LSS ['H8804']
- **1 Chroniques 1:13** — LSGS 5 codes / LSS 6 · seulement LSS ['H8804']
- **1 Chroniques 1:18** — LSGS 6 codes / LSS 8 · seulement LSS ['H8804', 'H8804']
- **1 Chroniques 1:19** — LSGS 14 codes / LSS 15 · seulement LSGS ['H3588'] · seulement LSS ['H8795', 'H8738']

### Codes sans mot rendu (Strong non traduit)

Un jeton `text: ""` + `strong: Hxxxx` : le code est là, le mot français n'existe pas (waw, ’eth, article, préfixes, particules). C'est ce qui fait la richesse du lexique mot à mot.

- **LGS** : 14198 occurrences, 1048 codes distincts — les plus fréquents : `G2532` ×2461, `G0846` ×1480, `G1161` ×1219, `G3588` ×638, `G3450` ×374, `G4675` ×335, `H6240` ×284, `G5216` ×256, `G2257` ×226, `G3754` ×204, `H3588` ×185, `G3767` ×170, `H0413` ×169, `G1063` ×157.
- **LSS** : 116567 occurrences, 2620 codes distincts — les plus fréquents : `H8799` ×19883, `H8804` ×12557, `H8802` ×5385, `H8800` ×4887, `H8686` ×4046, `G5719` ×3003, `H8798` ×2846, `G2532` ×2834, `H8689` ×2675, `G5723` ×2530, `H8762` ×2446, `G5656` ×2315, `G5627` ×2125, `H8765` ×2121.

### Étendue des codes

- **LSGS (app)** : 4481 jeton(s) portant deux codes séparés par un espace (476 combinaisons distinctes, ex. G0118 G5100, G0142 G0575, G0156 G2018, G0235 G2228, G0235 G3756, G0302 G1096, G0302 G1344, G0302 G1410) — éclatés avant comparaison.

- **LGS** : 14034 codes distincts — 14010 communs avec la LSGS, 24 seulement ici (G0403, G0972, G1444, G1895, G2355, G3002, G3375, G3389, G3977, G4513, G4759, G5107), 1 seulement dans la LSGS (H2044).
- **LSS** : 14454 codes distincts — 14008 communs avec la LSGS, 446 seulement ici (G0033, G0149, G0168, G0197, G0348, G0403, G0534, G0542, G0848, G0925, G0933, G0962), 3 seulement dans la LSGS (G0090, G0821, H1585).

## 5. Couverture du lexique Strong embarqué

L'aide de Biblia annonce « codes Strong hébreu 1 à 8853, grecs 1 à 5799 » —
plage plus large que le Strong standard (H1-H8674, G1-G5624). Deux ressources
combloquent ce qui manquait.

### 5.1 Codes de forme (H8675-H8853, G5625-G5799)

Source : <https://emcitv.com/bible/strong/> (ex-enseignemoi). C'est la même
table que celle que l'aide de Biblia décrit : les bornes vérifiées
(H8854 et G5800 n'existent pas, H8674 = « Tattenay ») tombent exactement sur
celles de l'aide. Ces codes ne sont pas des lexies mais des combinaisons —
radical × mode en hébreu, temps × mode en grec.

| plage | couvertes | observé |
|---|---:|---:|
| H8675-H8853 | 179 / 179 | 0 manquant |
| G5625-G5799 | 173 / 175 | G5625, G5626 absents de la source |

- Asset : `bible_app/assets/lexicon/strong_etendu.json`, 352 fiches, 73,3 Ko,
  aucune sans définition.
- **LSS : 277 / 278 codes étendus couverts, soit 100 008 / 100 061
  occurrences.** La LGS et la LSGS n'emploient aucun code étendu.
- La LSS n'emploie aucun code de terme (8810-8853) : seulement H8675-H8809 et
  G5625-G5773.
- Corrections apportées par la source : `H8801` est un **participe** Qal (pas
  une « forme stative »), `H8713-H8717` sont des **Hofal** et `H8792-H8795`
  des **Pual** — l'identification en surface était indécidable.
- G5625 garde volontairement `introuvable` : ce n'est pas un mot mais le
  marqueur de séparation toujours coincé entre le code grammatical et le code
  du mot (`[G5723][G5625][G4687][G5660]`), à jeton vide.

### 5.2 Codes standard absents des modules SWORD

`strong_fr.json` porte 14 195 entrées : **H1-H8674 intégralement (8674 /
8674), G1-G5624 à 5521 / 5624 — 103 trous**, dont un bloc continu
G3203-G3302.

Sondage des trois corpus : **seuls 2 de ces 103 codes sont jamais employés** —
`G2994` (Λαοδικεύς, Col 4:16 et Ap 3:14) et `G2995` (λάρυγξ, Rom 3:13), 3
occurrences au total. Les 101 autres, bloc G3203-G3302 compris, n'apparaissent
dans ni la LSS, ni la LGS, ni la LSGS.

`fusion_strong_v2.py` construisait déjà ces deux entrées, mais dans la fusion
complète, trop lourde pour être embarquée — d'où la fiche « aucune définition »
à leur tap. Elles sont désormais extraites seules :

- `extraction/construit_asset_complements.py` →
  `bible_app/assets/lexicon/strong_complements.json` (2 entrées, 1,2 Ko) ;
- chargées dans `StrongLexicon` avec le lexique principal. Ce sont des lexies :
  elles entrent dans `all()` et `search()`, à la différence des codes de forme.

Reste sans fiche **un seul code sur les 14 454 distincts de la LSS** : G5625
(ci-dessus).
