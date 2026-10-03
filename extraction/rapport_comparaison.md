# HEB / GRC vs strong_fr.json (modules SWORD)

- `strong_fr.json` : schéma bym.strong.v2 — CrossWire/SWORD FreStrongsHebrew + FreStrongsGreek
- 14195 entrées : 8674 hébreu, 5521 grec

## HEB — 8674 entrées Strong (8701 blocs, 2 images, 25 pages sans fiche)
- communes avec strong_fr : 8674
- seulement dans HEB : []
- seulement dans strong_fr : []
- alignement blocs ↔ TOC : OK (0 écart)
- anomalies de la source (10), sans effet sur les clés :
  - #376: h1="'ayal" !~ nom="'aya איל" (A/0354 'aya איל.html)
  - #407: h1="'Iythamar" !~ nom='Iythamar איתמר' (A/0385 Iythamar איתמר.html)
  - #1370: numéro ligne Strong 01448 != numéro nom 1348 (C/1348 ge'uwth גאות.html)
  - #2141: numéro ligne Strong 02019 != numéro nom 2119 (G/2119 zachal זחל.html)
  - #3415: h1='Yĕruwshalem (Chaldéen)' !~ nom='Yĕruwshalem ירושלם' (J/3390 Yĕruwshalem ירושלם.html)
  - #3468: numéro ligne Strong 03343 != numéro nom 3443 (J/3443 Yeshuwa` ישוע.html)
  - #5458: numéro ligne Strong 05333 != numéro nom 5433 (O/5433 caba' סבא.html)
  - #5779: h1='`avvah' !~ nom='`avva עוה' (P/5754 `avva עוה.html)
  - #6494: h1='Pĕull`thay' !~ nom='Pĕull`tha פלעתי' (Q/6469 Pĕull`tha פלעתי.html)
  - #7050: h1='Qiyr Cheres' !~ nom='Qiyr Chere קיר חרש' (S/7025 Qiyr Chere קיר חרש.html)

## GRC — 5523 entrées Strong (5555 blocs, 4 images, 28 pages sans fiche)
- communes avec strong_fr : 5521
- seulement dans GRC : ['G2994', 'G2995']
- seulement dans strong_fr : []
- alignement blocs ↔ TOC : OK (0 écart)
- anomalies de la source (6), sans effet sur les clés :
  - #1442: h1='dus-' !~ nom='dus δυς' (D/1418 dus δυς.html)
  - #3736: h1='paideutes' !~ nom='paideia παιδεια' (P/3810 paideia παιδεια.html)
  - #4378: h1='-po' !~ nom='po πω' (P/4452 po πω.html)
  - #4384: h1='-pos' !~ nom='pos πως' (P/4458 pos πως.html)
  - #4759: h1='summorphoo' !~ nom='summorphos συμμορφος' (R/4833 summorphos συμμορφος.html)
  - #5337: h1='Phoron' !~ nom='phoron φορον' (U/5410 phoron φορον.html)

## Écarts de contenu (sur les entrées communes)
« Identiques » = mêmes puces après neutralisation typographique (apostrophes, espaces, points finaux, guillemets).
- HEB : 3554 définitions identiques, 5120 différentes, sur 8674
  - H0001 dico=["père d'un individu", 'Dieu père de son peuple', "tête ou fondateur d'une maisonnée, d'un groupe, d'une famille, ou clan"]
       strong_fr=["père d'un individu", 'Dieu père de son peuple', "tête ou fondateur d'une maisonnée, d'un groupe, d'une famille, ou clan"]
  - H0005 dico=['Abagtha = heureux, prospère', 'un des sept chambellans du roi de Perse Assuérus', "Gardiens du harem, il s'agit d'eunuques comme l'usage l'exigeait"]
       strong_fr=['un des sept chambellans du roi de Perse Assuérus', "Gardiens du harem, il s'agit d'eunuques comme l'usage l'exigeait", "C'étaient probablement des étrangers, porteurs de noms étrangers"]
  - H0008 dico=['destruction, malheur']
       strong_fr=['destruction']
- GRC : 2824 définitions identiques, 2697 différentes, sur 5521
  - G0002 dico=['Aaron = Haut placé, ou éclairé = étymologie incertaine, peut signifier Brillant', "Le frère aîné de Moïse, le premier souverain sacrificateur d'Israël, dont les descendants héritèrent le sacerdoce"]
       strong_fr=["Aaron = Haut placé, ou éclairé = étymologie incertaine, peut signifier Brillant.Le frère aîné de Moïse, le premier souverain sacrificateur d'Israël, dont les descendants héritèrent le sacerdoce"]
  - G0003 dico=['ruine', 'destruction (Job 31.12)', 'séjour des morts, tombeau (Ps 88.11)']
       strong_fr=['ruine', 'destruction Job 31.12', 'séjour des morts, tombeau Psaume 88.11']
  - G0005 dico=['Abba = père', "Exprime l'affection filiale envers Dieu", 'Le mot hébreu correspondant est ab, qui se retrouve dans les noms propres (Abner, Abimélec, Eliab...)']
       strong_fr=["Exprime l'affection filiale envers Dieu", 'Le mot hébreu correspondant est ab, qui se retrouve dans les noms propres (Abner, Abimélec, Éliab…)']

## Sections de HEB / GRC et ce que strong_fr.json couvre déjà
`strong_fr.json` porte déjà `definition`, `senses`, `outline`, `signification`, `etymology` et `partOfSpeech` : Étymologie et Nature du mot recouvrent ces champs (à dire près), Occurrences, Synonymes et Spicq sont du contenu que la base n'a pas, Bailly et Sander et Trenel sont écartés de la fusion (voir rapport_fusion.md).
- **HEB** (8674 entrées) :
  - Définition Strong : 8674
  - Étymologie : 8674
  - Occurrences : 8673
  - Nature du mot : 8576
  - Définition Sander et Trenel : 511
- **GRC** (5523 entrées) :
  - Définition Strong : 5523
  - Étymologie : 5523
  - Nature du mot : 5518
  - Occurrences : 5505
  - Définition Bailly : 5206
  - Synonymes : 167
  - Définition approfondie Spicq : 2
  - Nom masculin : 1
  - Nom féminin : 1
  - Préposition : 1
