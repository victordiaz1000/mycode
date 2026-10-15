# BYM — page de présentation

Site statique pour présenter **BYM — Bible de Yehoshoua Ha Mashiah**
et distribuer l'APK hors Play Store.

URL : `https://victordiaz1000.github.io/bym-classic/`

## Contenu

- `index.html`, `style.css`, `script.js` — la page publique.
- `assets/screenshots/` — 19 captures (7 téléphone, 12 tablette), intégrées à la galerie.
- `assets/favicon.svg` — icône du site.
- `CONTENU.md` — fiche descriptive de chaque section (texte de référence).
- `DEPLOY.md` — guide complet de déploiement.

## Déploiement (GitHub Pages)

Ce dossier est copié dans `docs/` du dépôt `victordiaz1000/bym-classic` :

1. Pousse la branche `main` (avec le dossier `docs/`).
2. Sur GitHub : **Settings → Pages → Build and deployment → Source : Deploy from a branch**.
3. Branche : `main` · Dossier : `/docs`.
4. Attends 1–2 minutes : l'URL est live.

> Le dépôt **doit être public** pour GitHub Pages gratuit. Ce dossier ne contient
> aucun secret ; seuls le code source de la page y vit.

## Publier une nouvelle version d'APK

1. Construis l'APK : `flutter build apk --release` (dans le dépôt de l'app).
2. Sur GitHub : **Releases → Create a new release** → tag `v1.1.0` →
   attache le fichier renommé `bym-1.1.0.apk`.
3. **Rien à changer dans `index.html`** : le bouton de téléchargement et le
   changelog sont rafraîchis depuis l'API GitHub Releases à chaque visite.
4. Si l'API est injoignable (hors ligne, quota), le repli statique du HTML
   reprend la main — mets alors à jour le lien du bloc `#download` et les
   blocs de versions de `#changelog`.

## Personnaliser

- Captures : place-les dans `assets/screenshots/`, référence-les dans la
  galerie de `index.html`, puis dans `CONTENU.md`.
- Couleurs : modifie les variables CSS dans `:root` de `style.css`.
- Contact : change `data-user` / `data-domain` sur `#contact-mail` (`index.html`).
- Nouvelles versions : le bloc statique de `#changelog` ne sert plus que de repli.

## Licence

Code du site et de l'application : **MIT** (voir `LICENSE` à la racine du
dépôt). Les textes bibliques conservent les droits de leurs éditeurs —
chaque version sous copyright affiche sa mention dans l'application.

## Contact

Le lien « Contact » de la page assemble l'adresse au chargement, dans
`script.js` (`initContact`) ; elle n'est jamais écrite en clair dans le
HTML et **n'est jamais affichée à l'écran** — le bouton ne porte que le
libellé « Contact », seul son `mailto:` contient l'adresse. Pour changer
l'adresse, modifier `data-user` et `data-domain` sur l'élément
`#contact-mail` dans `index.html`.
