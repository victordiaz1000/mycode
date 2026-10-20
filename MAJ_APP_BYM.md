# MAJ_APP_BYM.md — publier une nouvelle version de l'application BYM

**Déménagement — 2026-10-15 :** l'app vit dans `C:\Users\laptek\Desktop\bym-classic\`
(dépôt `victordiaz1000/bym-classic`) ; les chemins `bible_app/…` désignent la racine de ce dépôt.

> **À lire avant de publier une version de l'APK.**
> Phrases déclencheuses : `publie la version 1.0.3`, `monte la version`, `sort une nouvelle release`,
> `l'appli ne détecte pas la mise à jour`.
>
> Ne pas confondre avec `MAJ_TEXTE_BYM.md`, qui décrit la mise à jour **du texte BYM** — un mécanisme
> entièrement distinct : pas de version, pas de release, pas de tag, comparaison d'empreintes de blob
> git. Ici, au contraire, **tout passe par un numéro de version et un tag**.
> Les références nomment des **symboles**, jamais des numéros de ligne.

## 1. Les deux mises à jour, en une phrase

| | Mise à jour **du texte** | Mise à jour **de l'application** |
|---|---|---|
| Signal | différence d'empreinte de blob git | numéro de version plus grand |
| Source | `gitlab.com/anjc/bjc-source` | GitHub Releases de `victordiaz1000/bym-classic` |
| Écran | rangée « MISE À JOUR DU TEXTE » | rangée « MISE À JOUR DE L'APPLICATION » |
| Surface d'annonce | bandeau en **haut**, onglet Lecture seulement | bandeau en **bas**, **tous** les onglets |
| Qui installe | le lecteur, livre par livre | le lecteur, un APK signé + son `.sha256` |

## 2. La règle qui rend la détection possible

`AppVersion` (dans `lib/data/app_version.dart`) compare **majeure, mineure, corrigée — puis build**.
Un tag GitHub vaut **build 0** : `v1.0.3` se lit `(1, 0, 3, 0)`.

Conséquences, toutes vérifiées à la main une fois :

- installé `(1, 0, 1, 2)` contre `v1.0.2` → `(1, 0, 2, 0)` : la **corrigée** 2 > 1 l'emporte → proposé.
- installé `(1, 0, 2, 3)` contre `v1.0.2` → `(1, 0, 2, 0)` : corrigées égales, build 0 < 3 → **rien**.
  Un tag inférieur ou égal à ce qui est installé ne déclenche **jamais** rien.
- Android refuse une régression de **versionCode** (`INSTALL_FAILED_VERSION_DOWNGRADE`) : descendre
  de `1.0.2+3` à `1.0.1+2` impose de **désinstaller**, et une désinstallation efface les données
  locales du lecteur.

## 3. Les quatre endroits du bump

`version: X.Y.Z+N` — `X.Y.Z` est le *versionName* affiché, `N` le *versionCode* d'Android, qui doit
**toujours augmenter**.

1. `pubspec.yaml` → `version: X.Y.Z+N`
2. `lib/screens/settings_screen.dart` → `appVersion = 'X.Y.Z'`
3. `lib/screens/settings_screen.dart` → le commentaire qui suit cette constante, qui cite le pubspec
4. `docs/index.html` → le repli statique du site : JSON-LD `softwareVersion` + `downloadUrl`,
   le bouton `#download`, et les blocs de la frise `#changelog-list`

Le quatrième est celui qu'on oublie. Sans lui, le site affiche encore l'ancienne version tant que
`script.js` n'a pas réussi à joindre l'API GitHub.

## 4. Les notes de release

Le corps de la release n'est **pas** écrit dans la workflow : il est lu depuis
**`docs/RELEASE_NOTES.md`** (`body_path:`, jamais `body:` — un `body: |` écrit à la main finirait par
dériver du fichier).

- **Première ligne, sans puce** : c'est elle que l'application affiche dans Réglages, tronquée à
  120 signes. À écrire comme un titre de phrase.
- Les puces suivantes décrivent la version.
- Le site reprend le corps en striant les puces, **8 lignes au maximum**.

## 5. La publication, en cinq gestes

```bash
# 1. Les quatre endroits du bump, puis les notes, puis le site.
git add -A && git commit -m "Version X.Y.Z : ..."
git push origin main

# 2. ATTENTION — un tag local résiduel rend la création silencieuse impossible
#    et fait repousser l'ANCIEN tag : le build partirait sur le mauvais commit.
git tag -d vX.Y.Z                      # au cas où
git tag -a vX.Y.Z -m "Version X.Y.Z : ..."
git push origin vX.Y.Z
```

Le déclencheur est `release-apk.yml`, `on.push.tags: ["v*"]` — ou `workflow_dispatch`, qui prend un
`tag` en entrée et convient pour relancer une publication sans bouger les refs. Elle construit l'APK,
le signe avec la clé de release, fabrique le `.sha256`, crée la release et attache les deux assets.
Le nom attendu par l'app est **`bym-$version.apk`** : `bym-1.0.1.apk`, sans le build.

**Le tag doit viser le commit qui contient le bump.** `git rev-parse "vX.Y.Z^{}"` doit donner `HEAD`
(les guillemets sont nécessaires : PowerShell avale les accolades).

## 6. La vérification, avant de dire à quiconque d'installer

Une release peut exister et être cassée. Les six contrôles, dans l'ordre :

1. `releases/latest` renvoie bien `vX.Y.Z`, `draft=false`, `prerelease=false` — sinon l'app ne la voit pas.
2. Les deux assets sont présents, avec la bonne taille.
3. L'empreinte publiée dans `bym-X.Y.Z.apk.sha256` **égale** celle recalculée sur l'APK téléchargé.
4. L'APK est **différent** de celui de la version précédente — un poids identique est possible
   (alignement zip) ; seule l'empreinte tranche.
5. `apksigner verify --print-certs` rend `CN=DIAZ VICTOR`, jamais `CN=Android Debug`. Un APK signé
   en debug refuse l'installation par-dessus l'installé.
6. Toutes les versions partagent le **même digest de certificat** : sans quoi la chaîne
   installé → nouvelle version casse à l'installation.
7. Le site déployé affiche la bonne `softwareVersion` et le bon lien.

`apksigner` exige `JAVA_HOME` ; le JRE d'Android Studio convient.

## 7. Ce que le lecteur voit, et le piège des 24 heures

`AppUpdateChecker` (dans `lib/data/app_update_service.dart`) fait une vérification **silencieuse au
démarrage**, bornée à une par jour par `checkInterval`. Un redémarrage dans l'heure qui suit ne
re-vérifie **pas** : ce n'est pas un défaut, c'est le quota GitHub non authentifié (60 requêtes/heure
et par IP) qui est préservé.

Le seul chemin qui saute le throttle est la rangée **« Vérifier une nouvelle version »** de Réglages,
qui appelle `maybeCheck(force: true)`. **C'est elle, et elle seule, qui fait un essai fiable.**

Trois surfaces lisent le même notificateur `AppUpdateChecker.available` et ne peuvent donc pas se
contredire :

- **Réglages**, section « MISE À JOUR DE L'APPLICATION » — la seule qui télécharge et qui vérifie.
  Sa rangée affiche en sous-titre la date de la dernière vérification réussie
  (`AppUpdateChecker.lastCheck()`, formatée par `formatRelativeDate`).
- **Le bandeau du bas**, rendu dans le `bottomNavigationBar` du châssis — donc dans **tous** les
  onglets, et nulle part ailleurs. Il disparaît de lui-même quand `available` retombe à null, et
  tait dans le mode immersif.
- ~~La pastille de la Bibliothèque~~ — **supprimée** : deux annonces sur la même tuile se lisaient
  comme un doublon.

Le bandeau **du texte** (`BymUpdateBanner`) garde sa place en haut du lecteur et ne quitte pas
l'onglet Lecture. Les deux ne se ressemblent pas et c'est voulu.

## 8. Les chiffres restent privés

Le compteur de téléchargements n'est **pas** affiché sur le site public — il est une information
privée. Il se lit dans **`outils/dashboard-prive.py`**, qui agrège les visiteurs GoatCounter et les
téléchargements GitHub, et ne tourne que sur la machine locale.

GoatCounter, lui, reste en place sur le site : balise dans le `head` de `docs/index.html`, comptage
des clics de téléchargement dans `docs/script.js`. Le retirer ferait perdre les visites sans rien
gagner.

## 9. Pièges déjà rencontrés

- **Tag local résiduel** — `git tag -a` échoue en silence et le push repousse l'ancien tag. Voir §5.
- **Poussée aveugle du concurrent** — `version_catalog.dart` a déjà été poussé avec des URL
  `127.0.0.1:8734`, illisibles hors de la machine. Toute URL du catalogue doit pointer vers
  `raw.githubusercontent.com`, vérifiée en `200`.
- **`body:` dans la workflow** au lieu de `body_path:` — les notes s'écrivent dans le mauvais fichier
  et finissent par diverger.
- **Sept échecs de tests préexistants** (`ati_interlinear_golden`, `ati_render`, 
  `bym_markdown_converter_golden`, `work_section_jump` qui exige un fichier hors dépôt) : ils sont
  **antérieurs et stables**. Le bon repère est **1141 verts, 1 skippé, 7 échecs** — un 8ᵉ échec est
  une vraie régression.
