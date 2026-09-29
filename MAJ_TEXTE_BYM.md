# MAJ_TEXTE_BYM.md — corriger le texte BYM sans repasser par le store

> **À lire avant toute mise à jour du texte BYM.**
> Phrases déclencheuses : `mets à jour le texte BYM`, `synchronise avec GitLab`, `récupère les
> dernières corrections`.
> Ce fichier décrit le code réellement livré. `appCodebar/CLAUDE.md` ne fait que pointer ici.
> Les références au code nomment des **symboles**, jamais des numéros de ligne : une ligne
> déplacée transformerait ce document en piège, ce qu'il a déjà été une fois.
>
> Il remplace `PUBLISH_Bym.md`. « Publier » ne décrit plus rien : il n'y a plus de dépôt miroir à
> alimenter, plus de manifest, plus de tag, plus de purge de cache. Si vous cherchez
> `publish_bym.py`, `generate_manifest.py` ou `victordiaz1000/bym-text`, ils ont été supprimés —
> les garder aurait reproduit le piège d'un script qui a l'air officiel et pousse vers un dépôt
> mort.

## 1. Le problème résolu

Les 66 livres BYM sont figés dans l'APK (`bible_app/assets/bible/bym/`). Corriger une coquille
imposait de republier l'application entière et d'attendre que chaque lecteur mette à jour.

La source officielle du texte est **`https://gitlab.com/anjc/bjc-source`** — dépôt public, 66
fichiers `NN-Livre.md` sur la branche `master`. C'est le dépôt de production du projet, pas un
miroir : l'auteur corrige un verset là-bas, et l'application le voit au prochain démarrage. Le
livre corrigé est téléchargé dans `<documents>/bym_updates/`, d'où il prend la priorité sur
l'asset embarqué. **Aucun livre n'arrive sans l'accord explicite du lecteur.**

Deux conséquences qui portent tout le reste :

- **Il n'y a plus de numéro de version.** Le signal est la **différence de contenu** : l'empreinte
  de blob git de chaque `.md` est comparée à celle que le dépôt annonce. Un semver de plus serait
  une valeur à tenir à la main, donc à oublier.
- **L'application convertit elle-même.** jsDelivr ne sert pas GitLab (GitHub, npm et WordPress
  seulement), donc les `.md` sont consommés en direct et
  `bible_app/lib/data/bym_markdown_converter.dart` — port fidèle de `md_to_json.py` — fabrique le
  JSON servi au lecteur. Le corpus `.md` pèse 4,9 Mo contre 9,1 Mo de JSON : les transferts sont
  divisés par deux.

## 2. En une commande

```bash
# Depuis la racine bym3/
python appCodebar/sync_bym_source.py --dry-run   # ce qui serait fait, sans rien écrire
python appCodebar/sync_bym_source.py             # applique
python appCodebar/sync_bym_source.py --all       # retélécharge et reconvertit les 66 livres
```

C'est la **seule** commande du flux. Elle enchaîne :

| # | Étape | Effet |
|---|-------|-------|
| 1 | dernier commit de `master` | sha + date + titre (`head_commit`) |
| 2 | arbre de ce commit | `NN-Livre.md` → empreinte de blob (`remote_tree`) |
| 3 | diff | empreinte git des `.md` locaux contre celle de l'arbre (`git_blob_id`) |
| 4 | téléchargement épinglé au sha | **empreinte vérifiée à la réception**, puis écriture dans `appCodebar/bym_md/` |
| 5 | conversion | `md_to_json.parse_book` → `bible_app/assets/bible/bym/NN-Livre.json` |
| 6 | `_source.json` | commit, date et les 66 empreintes, dans les assets |

Un seul refus d'empreinte **annule tout** : mieux vaut un corpus cohérent en retard qu'un corpus
panaché dont `_source.json` mentirait.

Le script signale aussi les divergences de catalogue, sans jamais les corriger tout seul :

- `! NN-Livre.md absent de l'arbre amont — conservé tel quel` : le livre local reste en place.
- `! X.md nouveau en amont — non embarqué (catalogue à revoir)` : c'est le cas de `README.md`, qui
  existe en amont et n'a rien à faire dans les 66 livres. Un vrai nouveau livre demanderait une
  entrée dans `book_catalog.dart`.

## 3. `_source.json`, la référence du texte embarqué

```json
{
  "commit": "cb535d4a3c…",
  "committedAt": "2026-08-29T23:49:15.000+02:00",
  "blobs": {
    "01-Genese.md": "6551d038…",
    "02-Exode.md": "f5817358…"
  }
}
```

`bible_app/assets/bible/bym/_source.json` remplace l'ancien `_version.json`. **Écrit par
`sync_bym_source.py`, jamais à la main.** C'est lui que l'application compare à l'arbre distant, et
il doit donc être **committé avec les JSON qu'il décrit** : les séparer ferait proposer aux lecteurs
une mise à jour qu'ils ont déjà, ou masquerait une correction réelle.

Le piège à connaître : `checkForUpdate()` conclut « à jour » sans même demander l'arbre quand le
commit amont **égale** `_source.json.commit`. Épingler un commit dont le corpus embarqué ne serait
pas la sortie exacte reviendrait donc à masquer définitivement les livres en retard. Le script
n'écrit le sha qu'après avoir aligné les fichiers dessus.

`assets/bible/bym/` est déclaré comme **dossier** dans `pubspec.yaml` : rien à déclarer pour
embarquer le fichier. Son absence est traitée comme `BymUpdateStatus.unconfigured` — bruyant,
jamais silencieux.

Un livre absent de l'arbre amont garde son **empreinte locale** dans `_source.json`
(`write_source`) : sans cela, l'application le reproposerait à chaque vérification sans jamais
pouvoir le corriger.

### L'empreinte de blob git

```
sha1("blob <taille>\0" + octets)
```

C'est exactement l'`id` que GitLab publie dans l'arbre du dépôt — vérifié sur les 66 livres. Le
contrôle porte sur les octets **exacts** du fichier : plus aucune normalisation de fin de ligne.
L'ancien système devait neutraliser `CRLF → LF` de part et d'autre avant de hacher, et une
asymétrie y aurait fait échouer *toutes* les mises à jour sur un artefact d'`core.autocrlf`. Ce
détour n'existe plus.

La fonction est écrite deux fois — `git_blob_id` en Python, `gitBlobId` en Dart — et les deux se
vérifient l'une l'autre sur le même corpus.

`md_to_json.py` et `sync_bym_source.py` écrivent les JSON avec `newline="\n"` : le convertisseur
Dart produit du LF, et le test doré compare octet pour octet.

C'est aussi pourquoi le `.gitattributes` de la racine épingle `bym_md/*.md` et
`assets/bible/bym/*.json` en **LF**. Sous Windows, `core.autocrlf=true` est le réglage courant :
sans cette règle, un clone neuf recevrait le corpus en CRLF, le script reproposerait les 66
livres à chaque passage et le test doré échouerait sur chacun d'eux — sur un artefact de
checkout, pas sur un vrai écart. L'ancienne normalisation `CRLF → LF` masquait ce problème dans
le code ; il est désormais réglé une fois, au bon endroit.

## 4. URLs et coûts (mesurés, pas supposés)

| Rôle | URL | Poids |
|------|-----|-------|
| Y a-t-il du neuf ? | `…/projects/anjc%2Fbjc-source/repository/commits?ref_name=master&per_page=1` | 671 o |
| Quels livres ? | `…/repository/tree?ref=<sha40>&per_page=100` | 9 595 o, sans pagination |
| Ce qui a changé | `…/repository/commits?ref_name=master&per_page=20&since=<iso>` | ~2 Ko |
| Un livre | `https://gitlab.com/anjc/bjc-source/-/raw/<sha40>/<fichier>.md` | 20 à 400 Ko |

Les livres sont lus **épinglés au sha du commit**, jamais sur `master` : une telle URL est
immuable, donc aucun texte périmé ne peut arriver et la durée du cache de bord (mesurée :
`s-maxage=60`) devient sans conséquence. Il n'y a **rien à purger**.

Le quota GitLab sans authentification est de 500 requêtes par minute et par IP. Une vérification
par lecteur et par jour (`BymUpdateService.checkInterval`, 24 h) tient sans effort, et le
raccourci « même commit » la réduit à une seule requête de 671 octets les jours où rien n'a bougé.

## 5. Côté application

| Fichier | Rôle |
|---------|------|
| `lib/data/bym_markdown_converter.dart` | `convert()`, `encode()`, `convertToJson()` — port fidèle de `md_to_json.py` |
| `lib/data/bym_update_service.dart` | `checkForUpdate()`, `apply()`, `revertToEmbedded()`, `gitBlobId()`, `BymUpdateChecker` |
| `lib/data/bym_update_store.dart` | fichiers `<documents>/bym_updates/`, registre en préférences, zone de transit |
| `lib/data/local_repository.dart` | `loadBook` — priorité mise à jour > asset |
| `lib/screens/settings_screen.dart` | section `MISE À JOUR DU TEXTE` (date du texte, compte de livres, taille) + message de confirmation |
| `lib/screens/library_screen.dart` | pastille `MàJ · 21 livres` sur la tuile BYM |
| `lib/widgets/bym_update_banner.dart` | bandeau défilant de la lecture, `Mettre à jour le texte BYM dans les Réglages · 21 livres` |
| `lib/screens/reader_screen.dart` | pose le bandeau sous les onglets ; masqué en immersion |
| `lib/widgets/chapter_reader.dart` | `_onTextRevisionChanged` — relit le livre affiché après une mise à jour |
| `lib/main.dart` | `BymUpdateStore.load()` puis `BymUpdateChecker.maybeCheck()` au démarrage **et à chaque retour au premier plan** |

Trois garanties, dans l'ordre où elles comptent :

1. **Rien de non vérifié n'est servi.** Empreinte de blob, puis conversion par
   `BymMarkdownConverter` (qui **lève** sur un Markdown sans titre au lieu de rendre un livre
   vide), puis validation structurelle : `book` non vide, `chapters` non vide, chaque chapitre au
   moins un verset. Une page d'erreur arrive avec un 200, donc le code de statut ne prouve rien.
2. **L'état affiché ne peut pas mentir.** Les livres passent par `bym_updates/.staging/` et ne
   basculent que lorsque *tous* sont vérifiés ; le registre est écrit en dernier. Une coupure
   laisse l'état précédent entier.
   *Compromis assumé :* un rattrapage de 21 livres interrompu (2,4 Mo) repart de zéro ; un delta
   ordinaire pèse un à trois livres.
3. **Aucune donnée sans accord.** Le démarrage lit un commit et un arbre (10 Ko), au plus une fois
   par 24 h, et jamais bruyamment : hors ligne, il est silencieux. `apply()` n'est appelé que
   depuis Réglages, sur appui.

### Quand la vérification a réellement lieu

`BymUpdateService.checkInterval` (24 h) est un **plafond** : `maybeCheck` refuse de repartir si la
dernière vérification réussie date de moins de ça. Le plancher, lui, dépend d'où on l'appelle — et
c'est là que le premier jet se trompait.

`initState` de `BymApp` ne s'exécute qu'au **démarrage à froid du processus**. Android garde
volontiers une application en mémoire pendant des jours : un lecteur qui ne ferme jamais BYM
n'aurait jamais revérifié, quel que soit l'intervalle. « Au plus une fois par jour » était vrai,
« au moins une fois par jour » ne l'était pas.

D'où le second appel, sur `didChangeAppLifecycleState(resumed)` (`_BymAppState`, observateur posé
en `initState` et retiré en `dispose`). Il n'ajoute **pas** de requêtes : le verrou des 24 h est
dans `maybeCheck`, donc revenir dix fois dans la journée ne coûte que dix lectures de préférence.
Il ajoute des *occasions* de constater que le délai est écoulé.

Deux détails qui ont leur raison d'être :

- L'appel passe par `_storeReady` (le `Future` de `BymUpdateStore.load()`), et pas directement.
  `referenceIndex()` lit `BymUpdateStore.installedBlobs` : une comparaison faite avant la fin du
  chargement reproposerait des livres déjà installés.
- `BymUpdateChecker.debugServiceFactory` existe uniquement pour ce chemin. Le crochet appelle
  `maybeCheck()` sans argument — c'est tout son intérêt, il ne connaît rien du service —, donc
  c'est le seul point d'injection possible pour un client simulé. La production le laisse null.

### Les cinq règles d'échec fermé

Dans l'ordre où elles comptent, telles qu'implémentées :

1. Le sha du commit et chaque empreinte de blob doivent valider `^[0-9a-f]{40}$`
   (`_parseCommits`, `_diffTree`, `_isApplicable`). Sinon `invalidPayload` et **aucune requête de
   fichier**. Le sha est le seul champ distant qui influence une URL ; l'hôte et le chemin restent
   des constantes compilées, donc un dépôt compromis ne peut pas rediriger l'application ailleurs.
2. Les noms de fichiers viennent **toujours** du catalogue local (`bymCatalogByMarkdown`), jamais
   de la réponse : on intersecte, on ne fait pas confiance. `README.md` est ignoré par
   construction.
3. Un livre présent en local mais absent de l'arbre est ignoré, **jamais supprimé**.
4. Une empreinte qui ne correspond pas, une conversion qui échoue ou un livre sans chapitre annule
   **toute** la mise à jour. Pas de panachage.
5. `_source.json` absent → `unconfigured`, rien n'est proposé. Et si aucun des 66 livres n'est
   reconnu dans l'arbre (dépôt réorganisé, redirection, page d'erreur bien formée), c'est un refus
   et non un « à jour ».

### Deux vocabulaires, un seul pont

L'amont parle en `.md`, le lecteur en `.json`. `bymCatalogByMarkdown` et `bymMarkdownNameOf` sont
la **seule** traduction : `_source.json`, l'arbre et `BymUpdateCheck.books` sont en `.md` ; le
registre du magasin et les fichiers servis sont en `.json`. Le registre est indexé en `.json`
pour que `BymUpdateStore.hasUpdate` reste un prédicat **synchrone** — voir la dernière ligne du
tableau du § 8.

### Les quatre caches

Après la bascule, `BymUpdateService.invalidateCaches()` vide `LocalRepository`,
`VersionRepository`, `FulltextIndex` et **`LexiconIndex`**. Le dernier est le moins évident : il
est bâti sur les *notes* des livres BYM, donc il servirait l'ancien texte sans qu'on y pense.

### Trois surfaces d'annonce, une seule source

La pastille de la Bibliothèque, la section de Réglages et le bandeau défilant de la lecture
écoutent tous `BymUpdateChecker.available` : elles ne peuvent donc pas se contredire, et **aucune
n'installe quoi que ce soit** — les trois conduisent à Réglages, seul endroit qui décide d'un
téléchargement. Elles s'effacent ensemble : `BymUpdateChecker.clear()` remet le notificateur à
null après une installation ou un retour au texte embarqué.

Le bandeau (`bym_update_banner.dart`) ne rend **rien** — pas un `SizedBox` de quelques pixels —
quand aucune mise à jour n'attend. C'est ce qui garantit qu'aucune animation ne tourne dans le cas
ordinaire, donc que les tests widget des écrans hôtes continuent de se stabiliser : un défilement
en boucle programme des frames sans fin et `pumpAndSettle` attendrait pour toujours. Un test **du
bandeau** pompe donc des durées explicites (`test/bym_update_banner_test.dart`).

Le défilement a lieu sur **toutes** les largeurs, téléphone comme tablette. Un premier jet ne le
déclenchait que si la phrase débordait de la place offerte — un texte qui glisse alors qu'on peut
le lire d'un coup ressemble à un défaut. À l'usage la décision s'est inversée : c'est le mouvement
qui fait remarquer l'annonce, et une tablette n'a pas moins besoin qu'on la voie. Plus de
`LayoutBuilder`, donc, et plus de démarrage reporté après la mise en page : le ticker part dès la
mesure du texte (`didChangeDependencies`). En test il faut quand même une frame d'amorce — un
`Ticker` relève son origine de temps à sa première frame sans rien rapporter.

Seule l'option système « réduire les animations » arrête le défilement : là, une boucle perpétuelle
qu'on ne peut pas interrompre est exactement ce que le réglage demande d'éviter, et la phrase reste
lisible, tronquée.

### Ce que le lecteur voit une fois la mise à jour posée

Trois choses, et chacune dit ce que les autres ne peuvent pas :

- la ligne d'état de Réglages passe à « Texte du … · 21 livres corrigés · 2,4 Mo » ;
- le sous-titre de la rangée porte `outcome.message` — « Texte BYM mis à jour — 21 livres. » ;
- un message glissant ajoute « La lecture est déjà à jour. » pendant quatre secondes. C'est le seul
  des trois qui puisse dire que l'onglet de lecture resté ouvert derrière porte déjà la correction,
  donc qu'il n'y a rien à refermer ni à rouvrir. Il n'apparaît que si `outcome.applied`, jamais sur
  un échec — un échec a déjà sa ligne, et un message vert sur une panne serait un mensonge.

`test/settings_screen_test.dart` le vérifie en remplaçant `apply()` par une installation qui
réussit sans toucher au disque : `path_provider` ne répond pas dans la zone fake-async d'un
`testWidgets`, et ce test porte sur ce que l'écran **dit**, pas sur ce que le service fait.

### L'écran de lecture se rafraîchit, et l'ordre est le contrat

`BymUpdateService.textRevision` est incrémenté **en dernier** dans `invalidateCaches()`, après le
vidage des quatre caches. C'est ce notificateur — et non `BymUpdateStore.revision` — que
`ChapterReader` écoute : le magasin prévient à l'instant où il écrit son registre, donc *avant*
`invalidateCaches()`, et un écran branché là relirait le livre encore en cache, exactement celui
que la mise à jour vient de remplacer. `test/bym_update_read_priority_test.dart` vérifie l'ordre
en relisant depuis le listener.

`_onTextRevisionChanged` remplace simplement le `Future` du livre, et seulement pour la version
embarquée. La page ne clignote pas : `FutureBuilder` conserve la donnée du snapshot précédent
pendant l'attente, donc le texte affiché et la position de lecture tiennent jusqu'à ce que le
livre corrigé soit prêt (`test/reader_text_refresh_test.dart` le vérifie sur une seule frame, et
vérifie aussi que l'onglet n'est pas remonté). Les chapitres voisins ne sont pas rechargés : une
correction ne change pas le nombre de chapitres.

### Le registre hérité est purgé

`BymUpdateStore.load()` efface les clés `bym.update.version` / `bym.update.files` de l'ancien
système et **supprime les fichiers** qu'elles décrivaient. Ces livres ne sont rattachables à aucun
commit amont, donc invérifiables : mieux vaut repartir du texte embarqué que servir un mélange dont
on ne saurait plus rien dire. Une installation du nouveau système (clé `bym.update.blobs`
présente) n'est pas emportée par ce nettoyage.

## 6. Vérifier

### Automatique

```bash
cd bible_app
flutter analyze
flutter test
```

Sept fichiers couvrent ce système, et aucun n'a besoin du réseau :

- `test/bym_markdown_converter_golden_test.dart` — **le test qui porte tout** : les 66 `.md` de
  `appCodebar/bym_md/` convertis en Dart et comparés **octet pour octet** aux 66 JSON embarqués,
  qui sont la sortie de Python. Plus 31 169 versets, l'invariant
  `text.substring(position, position + word.length) == word` sur les 5 753 notes du corpus, le
  piège du `\w` ASCII sur un mot accentué, et le sheva hébreu de `03-Levitique 19:18`.
  Le compte de notes suit le corpus : `sync_bym_source.py` peut le faire bouger, il faut alors le
  remesurer — mais **jamais** le remplacer par un `greaterThan`, sinon un bug qui viderait toutes
  les notes rendrait le test vert.
- `test/bym_update_service_test.dart` — empreinte fausse → refus sans rien installer ; sha ou
  empreinte hors forme → refus **avant** toute requête de fichier ; fichier inconnu du catalogue
  ignoré ; livre local absent de l'arbre ignoré ; aucun livre reconnu → refus ; échec sur le 2ᵉ
  livre de 3 → le 3ᵉ n'est pas demandé et rien n'est installé ; Markdown sans titre ou sans
  chapitre → refus ; hors ligne → `noConnection` transitoire ; arbre identique à l'index de
  référence → `upToDate` sans un octet de texte ; mise à jour installée qui recouvre l'embarqué ;
  24 h respectées.
- `test/bym_update_store_test.dart` — transit → bascule, registre relu après redémarrage, refus
  d'un livre annoncé mais absent, cumul de deux mises à jour, purge des clés héritées,
  `clear()` synchrone en mémoire.
- `test/bym_update_read_priority_test.dart` — le livre mis à jour l'emporte, un JSON abîmé retombe
  sur l'asset **et** désinstalle la mise à jour, et — c'est le cas d'ordre — une relecture
  déclenchée *depuis* le listener de `textRevision` donne déjà le texte corrigé.
- `test/bym_update_banner_test.dart` — rien à l'écran sans mise à jour (et l'écran se stabilise) ;
  la phrase et le compte de livres ; le défilement avance vers la gauche ; **sur une largeur de
  tablette il défile aussi** ; apparition puis effacement au rythme de
  `BymUpdateChecker` ; l'appui conduit à Réglages, et sans route vers Réglages `onTap` est null au
  lieu d'un faux bouton ; « réduire les animations » rend un texte tronqué immobile.
- `test/reader_text_refresh_test.dart` — le verset corrigé apparaît sans rouvrir l'onglet, le
  `State` du lecteur est le même (donc la position tient), et aucun squelette de chargement ne
  passe pendant la relecture.
- `test/bym_update_lifecycle_test.dart` — un retour au premier plan fait partir une requête (sans
  le crochet, une application jamais fermée ne revérifierait jamais), et trois allers-retours
  d'affilée après une vérification récente n'en font partir aucune. L'assertion porte sur les
  **requêtes sorties**, pas sur les appels à `maybeCheck` : ce dernier compte monterait aussi quand
  le verrou retient, ce qui est exactement la distinction à tenir.

### À la main, après une synchronisation

1. `python appCodebar/sync_bym_source.py --dry-run` → la liste des livres annoncés doit
   correspondre à ce qu'on attend, et le sha amont doit être celui de GitLab.
2. Puis sans `--dry-run` → 66 livres / 31 169 versets, `_source.json` écrit, `git diff` limité aux
   `.md` et JSON attendus.
3. Sur un build **antérieur** (donc `_source.json` en retard) : redémarrer → pastille dans la
   Bibliothèque **et** bandeau défilant en haut de la lecture → `Réglages > MISE À JOUR DU TEXTE >
   Vérifier les mises à jour` → « Mettre à jour (N livres) ». À la fin, un message doit annoncer
   « Texte BYM mis à jour — N livres. La lecture est déjà à jour. »
4. Revenir à la lecture **sans refermer l'onglet** : le verset corrigé doit être là, à la position
   qu'on avait quittée, et le bandeau doit avoir disparu de lui-même.
5. Ouvrir un verset corrigé dans la lecture, **puis le chercher dans la recherche**. C'est le
   second point qui prouve l'invalidation des index — la lecture seule peut réussir alors que la
   recherche sert encore l'ancien texte.
6. `Réglages > Revenir au texte embarqué` → l'ancien texte revient, notes et favoris intacts, et
   l'onglet ouvert repasse à l'embarqué sans être refermé.
7. Mode avion → `Vérifier` → message hors ligne, aucun plantage.

### Il n'y a pas de champ d'URL dans l'application

Les URL sont des constantes compilées (`bymProjectApi`, `bymRawTemplate`), et c'est précisément ce
qui empêche une réponse distante de rediriger l'application. Pour essayer un autre dépôt, il faut
modifier ces constantes dans un build jetable — ou, plus simplement, ajouter un cas à
`test/bym_update_service_test.dart`, qui simule le réseau entier.

## 7. Règles

1. **Toujours** passer par `sync_bym_source.py`. Ne jamais éditer `appCodebar/bym_md/` ni
   `bible_app/assets/bible/bym/` à la main : le premier est un miroir de l'amont, le second est
   généré.
2. `--dry-run` d'abord, toujours. Lire la liste des livres annoncés avant d'écrire.
3. Committer `_source.json` **avec** les JSON qu'il décrit, dans le même commit.
4. `flutter analyze` et `flutter test` après toute modification du côté Flutter. Le test doré est
   le premier à regarder : il échoue à la première divergence entre le convertisseur Dart et
   `md_to_json.py`.
5. Toute correction de `md_to_json.py` doit être portée dans `bym_markdown_converter.dart`, et
   inversement. Les deux implémentations doivent rendre les mêmes octets.
6. *(État connu, décision en attente)* Le `bym_json/` de la **racine** — 66 fichiers suivis par git
   — a perdu son unique consommateur avec `publish_bym.py`. Il ne sert plus à rien ; sa suppression
   demande un accord.

## 8. Ce qui peut mal tourner

| Symptôme | Où | Cause et suite |
|---|---|---|
| `GitLab injoignable : …` | script | Hors ligne, ou l'API filtrée. Rien n'a été écrit. |
| `NN-Livre.md : empreinte reçue … au lieu de … — rien de plus n'est écrit.` | script | Réponse tronquée ou altérée. L'arrêt est **avant** l'écriture suivante : le corpus reste cohérent. Relancer. |
| `Arbre sans fichier .md — le dépôt a été réorganisé.` | script | Ne rien forcer : vérifier la structure amont d'abord. |
| `Sha de commit inattendu : …` | script | La réponse de l'API n'est pas celle attendue (proxy, portail captif). |
| `Mise à jour refusée — le texte reçu ne correspond pas à ce que le dépôt annonce` | app | Empreinte, conversion ou structure invalide. Rien n'a été modifié sur l'appareil. |
| `Mise à jour interrompue — le texte précédent est conservé.` | app | Coupure pendant `apply()`. Le transit est jeté, l'état précédent est entier. |
| `Références du texte embarqué introuvables` | app | `_source.json` manque des assets : le build est incomplet. Relancer `sync_bym_source.py` puis rebâtir. |
| Aucune mise à jour proposée alors que le dépôt a bougé | — | Le commit amont est celui de `_source.json` (raccourci du § 3), ou aucun des 66 livres n'a changé — un `README`, la CI. Vérifier avec `--dry-run`. |
| Le test doré échoue après un `sync` | tests | Soit le corpus a bougé (remesurer le compte de notes et le total de versets), soit le convertisseur Dart et Python ont divergé. Le message pointe le premier octet fautif avec son contexte. |
| Un test widget qui gèle | tests | Ne jamais appeler `path_provider` ni `rootBundle` sans graine dans `testWidgets` : ils ne répondent pas dans la zone fake-async. Utiliser `BymUpdateStore.useRoot(temp)` et `LocalRepository.useBundle(...)`. C'est aussi la raison pour laquelle `BymUpdateStore.hasUpdate` est **synchrone** et pour laquelle Réglages charge la date du texte **détaché** de `_load()` — à ne pas « nettoyer ». |
