# Signature de publication Android

Ce que la configuration fait, et les deux commandes qui te restent à lancer.
Elles sont **interactives** (mot de passe au clavier) : tape-les toi-même dans
la session, précédées de `!`.

---

## Pourquoi

`android/app/build.gradle.kts` portait encore le gabarit Flutter d'origine :

```kotlin
release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
}
```

Une release signée avec la clé de debug s'installe et tourne, mais :

- **le Play Store la refuse** ;
- surtout, **le jour où une vraie clé arrive, la signature change** — et Android
  refuse alors d'installer la nouvelle version par-dessus l'ancienne. Tes
  lecteurs devraient désinstaller, donc **perdre notes, favoris et surlignages**,
  qui vivent dans la base locale de l'appareil.

D'où l'urgence de poser la vraie clé **avant** toute diffusion, même restreinte.

---

## Ce qui est déjà en place

| | |
|---|---|
| `bible_app/.gitignore` | exclut `/android/key.properties`, `*.jks`, `*.keystore` |
| `bible_app/android/app/build.gradle.kts` | lit `key.properties` s'il existe et signe la release avec |
| `bible_app/android/key.properties.example` | le modèle à copier, sans secret |

Tant que `key.properties` est absent, la release retombe sur la clé de debug
**en l'annonçant** dans la sortie de build (`*** BYM : android/key.properties
absent …`). Un clone frais continue donc de construire, sans jamais pouvoir
croire qu'il produit un binaire publiable.

> Le remote GitHub de ce dépôt est **public**. Un secret poussé par accident
> reste dans l'historique et dans les caches de GitHub même après suppression :
> la seule parade est de ne jamais l'y mettre.

---

## 1. Créer le keystore

Le dossier doit être **hors du dépôt** — sinon une fausse manœuvre sur
`.gitignore` suffirait à le publier.

```
! mkdir "C:\Users\laptek\cles"
```

Puis, en une seule ligne :

```
! & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore "C:\Users\laptek\cles\bym-upload.jks" -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` va demander, dans cet ordre :

1. **un mot de passe** (deux fois) — c'est lui qui ira dans `key.properties` ;
2. **ton identité** : nom, unité, organisation, ville, région, code pays (`FR`).
   Ces champs partent dans le certificat. Rien n'est vérifié par personne, mais
   ils sont **définitifs** pour cette clé ;
3. une confirmation (`oui`).

Notes :

- `-validity 10000` ≈ 27 ans. Google exige une validité au-delà de 2033.
- `-storetype PKCS12` est le format moderne ; `JKS` fonctionne encore mais
  `keytool` l'annonce comme obsolète à chaque appel.
- `& "..."` est la syntaxe PowerShell pour lancer un exécutable dont le chemin
  contient des espaces.

---

## 2. Renseigner `key.properties`

```
! Copy-Item bible_app\android\key.properties.example bible_app\android\key.properties
```

Puis ouvre `bible_app/android/key.properties` et remplis :

```properties
storePassword=<le mot de passe tapé à l'étape 1>
keyPassword=<le même>
keyAlias=upload
storeFile=C:/Users/laptek/cles/bym-upload.jks
```

**Le piège du chemin Windows** : un `.properties` Java traite `\` comme un
caractère d'échappement. `C:\Users\...` serait lu `C:Users...` et le build
échouerait sur un fichier introuvable. **Des barres obliques avant, toujours.**

Je peux écrire ce fichier pour toi, mais il faudrait que tu me donnes le mot de
passe — il se retrouverait dans l'historique de cette conversation. Mieux vaut
le taper directement dans le fichier.

---

## 3. Vérifier

```
cd bible_app
flutter build apk --release
```

Le build ne doit **plus** afficher l'avertissement `*** BYM : …`. Pour contrôler
la signature du binaire produit :

```
! & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -printcert -jarfile bible_app\build\app\outputs\flutter-apk\app-release.apk
```

Le propriétaire (`Owner:`) doit porter l'identité saisie à l'étape 1, et non
`CN=Android Debug, O=Android, C=US`.

---

## 4. Sauvegarder la clé — la partie qui ne se rattrape pas

**Un keystore perdu ne se régénère pas.** Il n'existe aucune procédure de
récupération : sans lui, plus aucune mise à jour de l'application publiée n'est
possible, jamais.

À conserver, dans deux endroits distincts dont au moins un hors de cette
machine :

- le fichier `bym-upload.jks` ;
- le mot de passe et l'alias, notés séparément du fichier.

Si tu passes par le Play Store, active **Play App Signing** : Google conserve
alors la clé de signature finale, et ton `.jks` ne sert plus qu'à *téléverser*.
Une clé de téléversement perdue peut être remplacée par le support Google — une
clé de signature, non. C'est le seul filet qui existe.

---

## Pour publier

| but | commande |
|---|---|
| Tester sur un appareil | `flutter build apk --release` |
| Diffuser un APK plus léger | `flutter build apk --release --split-per-abi` |
| Play Store | `flutter build appbundle --release` |

Et à chaque publication, incrémenter `version:` dans `bible_app/pubspec.yaml`
(aujourd'hui `1.0.0+1`) : le `+N` est le `versionCode`, que le Play Store exige
strictement croissant. `appVersion`, dans `settings_screen.dart`, est à tenir en
phase avec lui — c'est ce que la section « À PROPOS » affiche.
