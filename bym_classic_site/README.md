# BYM — page de présentation

Site statique pour présenter **BYM — Bible de Yehoshoua Ha Mashiah**
et distribuer l'APK hors Play Store.

URL après publication : `https://victordiaz1000.github.io/bym-classic/`

## Contenu

- `index.html`, `style.css`, `script.js` — la page publique.
- `assets/` — favicon (et plus tard, captures d'écran).
- `DEPLOY.md` — guide complet de déploiement.

## Déploiement (GitHub Pages)

1. Pousse ce dossier dans un dépôt **public** nommé `bym-classic`.
2. Sur GitHub : **Settings → Pages → Build and deployment → Source : Deploy from a branch**.
3. Branche : `main` · Dossier : `/ (root)`.
4. Attends 1–2 minutes : l'URL est live.

> Le dépôt **doit être public** pour GitHub Pages gratuit. Ce dossier ne contient
> aucun secret ; seuls le code source de la page y vit.

## Publier une nouvelle version d'APK

1. Construis l'APK : `flutter build apk --release` (dans le dépôt de l'app).
2. Sur GitHub : **Releases → Create a new release** → tag `v1.0.0` →
   attache le fichier renommé `bym-1.0.0.apk`.
3. Mets à jour les URL de téléchargement dans `index.html`
   (`https://github.com/victordiaz1000/bym-classic/releases/download/v1.0.0/bym-1.0.0.apk`).
4. Comite et pousse.

## Personnaliser

- Captures d'écran : place-les dans `assets/` et référence-les dans `index.html`.
- Couleurs : modifie les variables CSS dans `:root` de `style.css`.
- Nouvelles versions : ajoute un bloc dans `#changelog`.

## Licence

Contenu du site : libre selon les besoins du projet. Le code de l'app BYM
est publié séparément.
