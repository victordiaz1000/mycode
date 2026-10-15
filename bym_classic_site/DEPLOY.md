# Déploiement de la page de présentation BYM

Cette page vit dans `docs/` du dépôt `victordiaz1000/bym-classic`. Deux approches.

## A) Simple — GitHub Pages depuis le dossier /docs

1. Pousse la branche `main` sur GitHub (avec le dossier `docs/`).
2. Sur GitHub : **Settings → Pages → Build and deployment → Source : Deploy from a branch**.
3. Branche : `main` · Dossier : `/docs`.
4. L'URL sera : `https://victordiaz1000.github.io/bym-classic/`

### Mettre à jour l'APK publié

1. Construis l'APK : `flutter build apk --release`
   → `build/app/outputs/flutter-apk/app-release.apk`
2. Sur GitHub : **Releases → Create a new release**, tag `vX.Y.Z`,
   attache le fichier renommé `bym-X.Y.Z.apk`.
3. **Aucune modification de `index.html` n'est nécessaire** : le bouton
   `#download` et le changelog interrogent l'API GitHub Releases à chaque
   visite et pointent vers la dernière version.
4. Repli hors ligne : si l'API est injoignable, le contenu statique du HTML
   reprend la main — mets alors à jour le lien de `#download` et les blocs
   de versions de `#changelog`.

## B) Automatique — GitHub Actions

Le workflow `.github/workflows/release-apk.yml` construit l'APK et crée la Release à chaque tag `v*`.

Usage :
```bash
git tag v1.1.0
git push origin v1.1.0
```

Signature : enregistre dans **Settings → Secrets and variables → Actions**
les secrets `ANDROID_KEYSTORE_BASE64` (obtenu par `base64 -w0 bym-upload.jks`),
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (= `upload`) et
`ANDROID_KEY_PASSWORD`. Sans eux, le workflow construit quand même… mais
l'APK repart signé en **debug** — le step « Verifier la signature produite »
affiche alors `CN=Android Debug` dans le log. Ne publie jamais un APK ainsi
signé : les utilisateurs ne pourraient plus l'installer par-dessus leur
version existante.

## Personnaliser la page

- Captures : `assets/screenshots/`, référencées dans la galerie de
  `index.html` puis dans `CONTENU.md`.
- Contact : `data-user` / `data-domain` sur `#contact-mail` dans `index.html`.
- Les couleurs sont dans `:root` de `style.css`.

## Limites gratuites à surveiller

- Bande passante GitHub Pages : ~100 Go/mois.
- Taille d'APK conseillée < 150 Mo (le fichier vit dans la Release, pas dans Git, pour éviter de faire grossir le dépôt).
