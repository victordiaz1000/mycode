# -*- coding: utf-8 -*-
"""Prototype de rendu ATI : trois maquettes sur données réelles (Genèse 1:1-3).

Écrit ATI/prototype_rendu.html — à ouvrir dans un navigateur.

  A. Interlinéaire en colonnes (le rendu prévu à l'étape 2 du plan)
  B. Bilingue : hébreu d'un côté, texte français de l'autre
  C. Texte de gloses actuel, enrichi des notes résolues

Rien n'est inventé : hébreu, translittération, glose, analyse, découpage et
notes sortent de ATI/json/1.json et ATI/json/notes.json.
"""
import html
import json
import pathlib
import re

RACINE = pathlib.Path(r"C:\Users\laptek\Desktop\bym3\ATI")
SORTIE = RACINE / "prototype_rendu.html"

livre = json.loads((RACINE / "json" / "1.json").read_text(encoding="utf-8"))
notes = json.loads((RACINE / "json" / "notes.json").read_text(encoding="utf-8"))
versets = livre["chapters"][0]["verses"][:3]


def glose(mot):
    """Glose lisible : marqueurs retirés, None si rien ne reste (règle de
    joinAtiGlosses)."""
    brut = mot.get("f", "")
    net = " ".join(t for t in re.split(r"\s+", brut) if t not in ("*", "-"))
    return net or None


def analyse(mot):
    return livre["ca"][mot["a"]] if "a" in mot else None


def categorie(mot):
    return livre["cg"][mot["g"]] if "g" in mot else None


def titre_note(ref):
    return notes.get(ref, {}).get("title", ref)


def mot_colonne(mot, avec_translit=True):
    """Une colonne de mot pour la maquette A."""
    morceaux = []
    if mot.get("h"):
        morceaux.append(f'<span class="he">{html.escape(mot["h"])}</span>')
    if avec_translit and mot.get("t"):
        morceaux.append(f'<span class="tr">{html.escape(mot["t"])}</span>')
    g = glose(mot)
    if g:
        morceaux.append(f'<span class="gl">{html.escape(g)}</span>')
    cat = categorie(mot)
    if cat:
        morceaux.append(f'<span class="cat">{html.escape(cat)}</span>')
    ref = mot.get("n")
    if ref:
        morceaux.append(
            f'<span class="chip" data-note="{ref}" title="{html.escape(titre_note(ref))}">'
            f'{ref}</span>')
    if not morceaux:
        return ""
    return '<div class="col">' + "".join(morceaux) + "</div>"


def bloc_a(verset):
    colonnes = "".join(mot_colonne(m) for m in verset["words"])
    return (f'<div class="verset"><span class="num">{verset["verse"]}</span>'
            f'<div class="rtl">{colonnes}</div></div>')


def bloc_b(verset):
    he = " ".join(html.escape(m["h"]) for m in verset["words"] if m.get("h"))
    fr = " ".join(html.escape(t) for m in verset["words"]
                  if (t := glose(m)))
    return (f'<div class="verset"><span class="num">{verset["verse"]}</span>'
            f'<div class="rtl grand">{he}</div>'
            f'<div class="fr">{fr}</div></div>')


def bloc_c(verset):
    pieces = []
    for m in verset["words"]:
        g = glose(m)
        if not g:
            continue
        pieces.append(html.escape(g))
        if m.get("n"):
            ref = m["n"]
            pieces.append(
                f'<sup class="chip" data-note="{ref}" '
                f'title="{html.escape(titre_note(ref))}">{ref}</sup>')
    fr = " ".join(pieces)
    detail = " · ".join(
        f'<span class="puce">{m["s"]}</span> {html.escape(analyse(m) or "")}'
        for m in verset["words"] if glose(m) and analyse(m))
    return (f'<div class="verset"><span class="num">{verset["verse"]}</span>'
            f'<div class="fr gros">{fr}</div>'
            f'<div class="analyses">{detail}</div></div>')


CSS = """
* { box-sizing: border-box; }
body { font-family: Georgia, 'Times New Roman', serif; margin: 0; padding: 32px;
  background: #faf7f1; color: #1d1a16; line-height: 1.5; }
h1 { font-size: 22px; margin: 0 0 4px; }
h2 { font-size: 17px; margin: 34px 0 2px; padding-top: 18px; border-top: 1px solid #ddd3c2; }
.ligne { color: #6b6155; font-size: 13.5px; margin: 0 0 14px; font-family: system-ui, sans-serif; }
.carte { background: #fff; border: 1px solid #e6ddd0; border-radius: 10px;
  padding: 18px 20px; }
.verset { position: relative; padding: 10px 0 14px 34px;
  border-bottom: 1px dotted #e6ddd0; }
.verset:last-child { border-bottom: 0; }
.num { position: absolute; left: 0; top: 12px; font-size: 12px; color: #9a8f80;
  font-family: system-ui, sans-serif; }
.rtl { direction: rtl; text-align: right; display: flex; flex-wrap: wrap;
  gap: 4px 14px; justify-content: flex-start; }
.rtl.grand { font-size: 27px; line-height: 1.75; display: block; }
.col { direction: ltr; unicode-bidi: isolate; text-align: center; min-width: 46px; }
.he { display: block; font-size: 25px; color: #141414; }
.tr { display: block; font-size: 11.5px; color: #9a8f80; font-family: system-ui, sans-serif; }
.gl { display: block; font-size: 15.5px; color: #1d1a16; }
.cat { display: block; font-size: 10.5px; color: #2f7a4a; font-family: system-ui, sans-serif; }
.fr { direction: ltr; font-size: 17px; margin-top: 6px; }
.fr.grand { margin-top: 2px; }
.fr.gros { font-size: 19px; }
.analyses { font-size: 11.5px; color: #7b7164; font-family: system-ui, sans-serif;
  margin-top: 7px; }
.puce { background: #f0ece3; border-radius: 4px; padding: 1px 5px; }
.chip { font-family: system-ui, sans-serif; font-size: 10px; color: #8a5a12;
  background: #fdf1d8; border: 1px solid #f0dcb2; border-radius: 9px;
  padding: 0 5px; cursor: pointer; }
.rtl .chip { display: block; margin-top: 3px; }
#note { margin-top: 10px; font-family: system-ui, sans-serif; font-size: 13.5px;
  background: #fdf7ea; border-left: 3px solid #e0b355; padding: 8px 12px;
  display: none; }
.legendes { font-family: system-ui, sans-serif; font-size: 13px; color: #6b6155;
  margin-top: 6px; }
"""

JS = """
document.querySelectorAll('.chip').forEach(function (c) {
  c.addEventListener('click', function () {
    var n = document.getElementById('note');
    n.style.display = 'block';
    n.innerHTML = '<b>' + c.dataset.note + '</b> — ' + c.title;
  });
});
"""

corps = []
corps.append(f"""
<h1>ATI — trois rendus possibles</h1>
<p class="ligne">Données réelles : {html.escape(livre['book'])} 1:1-3, sorties de
<code>ATI/json/1.json</code>. Un clic sur une pastille de note affiche son titre.
Ce que l'app affiche aujourd'hui correspond à la <b>maquette C, sans les notes</b>.</p>
""")

corps.append(f"""
<h2>A. Interlinéaire en colonnes — le rendu prévu à l'étape 2</h2>
<p class="ligne">« Une tuile de verset en colonnes de mots, hébreu droite-à-gauche,
sept champs empilés ». Colonnes de droite à gauche, gloses en ltr à l'intérieur de
chaque colonne. Encombrement : ~40 colonnes pour un verset comme Exode 34:6.</p>
<div class="carte">""" + "".join(bloc_a(v) for v in versets) + "</div>")

corps.append(f"""
<h2>B. Bilingue : hébreu au-dessus, français en dessous</h2>
<p class="ligne">L'hébreu garde son sens de lecture, le français se lit comme une
phrase normale. Deux lignes par verset, pas de colonnes à aligner — plus sobre sur
petit écran, mais on perd la correspondance mot à mot.</p>
<div class="carte">""" + "".join(bloc_b(v) for v in versets) + "</div>")

corps.append(f"""
<h2>C. Texte de gloses (actuel) + notes résolues</h2>
<p class="ligne">Aucun changement de mise en page : la ligne de gloses jointes que
le lecteur affiche déjà, plus les pastilles de notes — <code>notes.json</code> est
publié mais jamais lu pour l'instant. L'analyse grammaticale du verset est posée
en dessous.</p>
<div class="carte" id="c">""" + "".join(bloc_c(v) for v in versets) +
       '<div id="note"></div></div>')

corps.append("""
<p class="legendes">Les trois maquettes lisent les mêmes sept champs : hébreu,
translittération, glose française, découpage morphologique, analyse grammaticale
(<code>cg</code>/<code>ca</code>), renvoi de note. La police Cardo est déjà
embarquée dans l'app et couvre les points-voyelles du corpus.</p>
""")

SORTIE.write_text(
    "<!doctype html><html lang='fr'><head><meta charset='utf-8'>"
    "<title>Rendu ATI — prototype</title>"
    f"<style>{CSS}</style></head><body>"
    + "".join(corps)
    + f"<script>{JS}</script></body></html>",
    encoding="utf-8")

print("écrit :", SORTIE)
print("versets :", [v["verse"] for v in versets],
      "— mots :", sum(len(v["words"]) for v in versets))
