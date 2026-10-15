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
2. Sur GitHub : **Releases → Create a new release**, tag `v1.0.0`, attache le fichier renommé `bym-1.0.0.apk`.
3. Mets à jour l'URL de téléchargement dans `index.html` :
   `https://github.com/victordiaz1000/bym-classic/releases/download/v1.0.0/bym-1.0.0.apk`
4. Comite et pousse.

## B) Automatique — GitHub Actions

Le workflow `.github/workflows/release-apk.yml` construit l'APK et crée la Release à chaque tag `v*`.

Usage :
```bash
git tag v1.0.0
git push origin v1.0.0
```

Les secrets optionnels `ANDROID_KEYSTORE_BASE64` etc. permettent de signer l'APK ; sinon il reste signé en debug et les mises à jour automatiques ne fonctionneront pas.

## Personnaliser la page

- Remplacer les captures d'écran dans `assets/` et référencer `assets/screenshot.png`.
- Renseigner les nouvelles versions dans `#changelog`.
- Les couleurs sont dans `:root` de `style.css`.

## Limites gratuites à surveiller

- Bande passante GitHub Pages : ~100 Go/mois.
- Taille d'APK conseillée < 150 Mo (le fichier vit dans la Release, pas dans Git, pour éviter de faire grossir le dépôt).
