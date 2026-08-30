import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:http/http.dart' as http;

import 'book_catalog.dart';
import 'bym_markdown_converter.dart';
import 'bym_update_store.dart';
import 'fulltext_index.dart';
import 'lexicon_index.dart';
import 'local_repository.dart';
import 'version_repository.dart';

/// Dépôt officiel du texte, public et sans authentification.
///
/// C'est la source de production du projet, pas un miroir à alimenter : l'auteur
/// corrige un verset là-bas, l'application le voit au prochain démarrage. Le
/// chemin est encodé (`anjc%2Fbjc-source`) parce que l'API GitLab prend l'espace
/// de noms comme un unique segment.
const String bymProjectApi =
    'https://gitlab.com/api/v4/projects/anjc%2Fbjc-source';

/// Branche suivie. Le dépôt ne porte aucun tag : le sha de commit joue ce rôle.
const String bymBranch = 'master';

/// Les livres sont lus **épinglés au sha du commit**, jamais sur une branche :
/// une telle URL est immuable, donc aucun texte périmé ne peut arriver, et la
/// durée du cache de bord (mesurée : `s-maxage=60`) devient sans conséquence.
const String bymRawTemplate =
    'https://gitlab.com/anjc/bjc-source/-/raw/{commit}/{file}';

/// Références du texte figé dans l'APK, écrites par
/// `appCodebar/sync_bym_source.py` au moment où il synchronise les assets.
///
/// Ce n'est pas une constante Dart à tenir à la main : les deux dériveraient au
/// premier oubli, et l'application proposerait alors une mise à jour du texte
/// qu'elle contient déjà — plusieurs mégaoctets pour rien — ou masquerait une
/// correction réelle.
const String bymSourceAsset = 'assets/bible/bym/_source.json';

/// Un sha git, et rien d'autre. C'est le **seul** champ distant qui influence
/// une URL : l'hôte et le chemin restent compilés, donc un dépôt compromis ne
/// peut pas rediriger l'application ailleurs.
final RegExp _hexPattern = RegExp(r'^[0-9a-f]{40}$');

/// `01-Genese.md` → `01-Genese.json`, restreint au catalogue local.
///
/// Cette carte est la frontière entre les deux vocabulaires : l'amont parle en
/// `.md`, le lecteur en `.json`. Elle sert aussi de filtre — un nom absent
/// d'ici n'est jamais demandé, quoi qu'annonce le dépôt.
final Map<String, String> bymCatalogByMarkdown = <String, String>{
  for (final entry in bookCatalog)
    if (entry.file.endsWith('.json'))
      '${entry.file.substring(0, entry.file.length - 5)}.md': entry.file,
};

/// `01-Genese.json` → `01-Genese.md`, null si le nom n'est pas un livre connu.
String? bymMarkdownNameOf(String jsonFile) {
  if (!jsonFile.endsWith('.json')) return null;
  final name = '${jsonFile.substring(0, jsonFile.length - 5)}.md';
  return bymCatalogByMarkdown.containsKey(name) ? name : null;
}

/// Empreinte git d'un contenu : `sha1("blob <taille>\0" + octets)`.
///
/// C'est exactement l'`id` que GitLab publie dans l'arbre du dépôt. Vérifiée sur
/// le corpus : les 66 empreintes locales correspondent. Le contrôle porte donc
/// sur les octets **exacts** du fichier, sans normalisation d'aucune sorte —
/// l'ancien système devait neutraliser `CRLF → LF` avant de hacher, ce détour
/// n'existe plus.
String gitBlobId(Uint8List bytes) {
  final header = utf8.encode('blob ${bytes.length}\x00');
  final buffer = Uint8List(header.length + bytes.length)
    ..setRange(0, header.length, header)
    ..setRange(header.length, header.length + bytes.length, bytes);
  return sha1.convert(buffer).toString();
}

/// Comment une vérification ou une application s'est terminée.
enum BymUpdateStatus {
  /// Le texte en place est déjà celui du dépôt.
  upToDate,

  /// Des livres ont changé en amont et attendent l'accord de l'utilisateur.
  available,

  /// La mise à jour est installée et les caches sont invalidés.
  applied,

  /// La requête n'a pas quitté l'appareil (hors ligne, DNS, mode avion).
  noConnection,

  /// Le serveur a répondu mais a refusé : 429, 5xx ou délai dépassé.
  serverError,

  /// Un 200 est arrivé mais le contenu n'est pas exploitable : réponse
  /// illisible, sha mal formé, empreinte de blob qui ne correspond pas, ou
  /// Markdown que le convertisseur refuse.
  invalidPayload,

  /// [BymUpdateService.cancel] a été appelé en cours de route.
  cancelled,

  /// Les références du texte embarqué sont introuvables : `_source.json` manque
  /// des assets, donc le build est incomplet. Échec **fermé** : mieux vaut ne
  /// rien proposer que de comparer contre une valeur inventée.
  unconfigured;

  /// Transitoire : une relance automatique a du sens avant d'abandonner.
  bool get transient => this == noConnection || this == serverError;

  /// Une ligne pour le bandeau ou la notification, en français.
  String get message => switch (this) {
        BymUpdateStatus.upToDate => 'Le texte BYM est à jour.',
        BymUpdateStatus.available => 'Une mise à jour du texte est disponible.',
        BymUpdateStatus.applied => 'Texte BYM mis à jour.',
        BymUpdateStatus.cancelled =>
          'Mise à jour interrompue — le texte précédent est conservé.',
        BymUpdateStatus.noConnection =>
          'Vérification impossible — aucune connexion internet. '
              'Réessayez une fois le réseau revenu.',
        BymUpdateStatus.serverError =>
          'Vérification impossible — le serveur est momentanément '
              'indisponible. Patientez quelques minutes puis réessayez.',
        BymUpdateStatus.invalidPayload =>
          'Mise à jour refusée — le texte reçu ne correspond pas à ce que le '
              'dépôt annonce. Rien n\'a été modifié.',
        BymUpdateStatus.unconfigured =>
          'Références du texte embarqué introuvables — cette version de '
              'l\'application est incomplète.',
      };
}

/// L'état d'un corpus : de quel commit il provient, et l'empreinte de chacun de
/// ses livres.
///
/// Trois provenances, une seule forme : l'asset embarqué, la mise à jour
/// installée, ou l'arbre du dépôt. C'est la comparaison de deux de ces index qui
/// remplace le numéro de version — **le signal est la différence de contenu**.
@immutable
class BymSourceIndex {
  /// Commit amont dont provient ce corpus (40 hexadécimaux).
  final String commit;
  final DateTime committedAt;

  /// `01-Genese.md` → empreinte de blob git.
  final Map<String, String> blobs;

  const BymSourceIndex({
    required this.commit,
    required this.committedAt,
    required this.blobs,
  });

  /// Lit `_source.json`. Null si le contenu ne tient pas : un index à demi lu
  /// serait pire qu'absent, il ferait proposer des livres au hasard.
  static BymSourceIndex? parse(Object? decoded) {
    if (decoded is! Map) return null;
    final commit = decoded['commit'];
    if (commit is! String || !_hexPattern.hasMatch(commit)) return null;
    final rawDate = decoded['committedAt'];
    final committedAt = rawDate is String ? DateTime.tryParse(rawDate) : null;
    if (committedAt == null) return null;
    final rawBlobs = decoded['blobs'];
    if (rawBlobs is! Map) return null;

    final blobs = <String, String>{};
    rawBlobs.forEach((key, value) {
      if (key is String && value is String && _hexPattern.hasMatch(value)) {
        blobs[key] = value;
      }
    });
    if (blobs.isEmpty) return null;

    return BymSourceIndex(
      commit: commit,
      committedAt: committedAt,
      blobs: blobs,
    );
  }
}

/// Résultat d'une vérification, et plan de la mise à jour à appliquer.
///
/// Un seul objet pour les deux rôles : ce qui est proposé au lecteur est
/// exactement ce que [BymUpdateService.apply] installera, sans traduction
/// intermédiaire où un livre pourrait se glisser.
@immutable
class BymUpdateCheck {
  final BymUpdateStatus status;

  /// Commit amont visé, vide quand rien n'a pu être lu.
  final String commit;
  final DateTime? committedAt;

  /// Livres à remplacer, en noms `.md`, dans l'ordre du catalogue.
  final List<String> books;

  /// Empreintes attendues pour ces livres, `01-Genese.md` → blobId.
  final Map<String, String> blobs;

  /// Titres des commits amont depuis le texte en place : le lecteur voit ce qui
  /// a réellement changé, au lieu d'une note saisie à la main.
  final String notes;

  const BymUpdateCheck(
    this.status, {
    this.commit = '',
    this.committedAt,
    this.books = const <String>[],
    this.blobs = const <String, String>{},
    this.notes = '',
  });

  bool get hasUpdate =>
      status == BymUpdateStatus.available && books.isNotEmpty;

  int get bookCount => books.length;

  /// « 21 livres » / « 1 livre », pour les libellés.
  String get bookLabel => '$bookCount livre${bookCount > 1 ? 's' : ''}';
}

/// Où en est l'application d'une mise à jour.
@immutable
class BymUpdateProgress {
  /// Livres déjà vérifiés, convertis et déposés en zone de transit.
  final int done;
  final int total;

  /// Fichier en cours, pour l'afficher sous la barre.
  final String? current;

  const BymUpdateProgress({
    required this.done,
    required this.total,
    this.current,
  });

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
}

/// Issue d'une application.
@immutable
class BymUpdateOutcome {
  final BymUpdateStatus status;

  /// Livres remplacés en cas de succès.
  final int bookCount;

  const BymUpdateOutcome(this.status, [this.bookCount = 0]);

  bool get applied => status == BymUpdateStatus.applied;

  String get message => status == BymUpdateStatus.applied && bookCount > 0
      ? 'Texte BYM mis à jour — $bookCount livre${bookCount > 1 ? 's' : ''}.'
      : status.message;
}

/// Comment une requête s'est terminée, avant de décider quoi en faire.
enum _FetchKind {
  ok,
  noConnection,
  serverError,
  invalidPayload,
  cancelled;

  bool get transient => this == noConnection || this == serverError;

  BymUpdateStatus get status => switch (this) {
        _FetchKind.ok => BymUpdateStatus.applied,
        _FetchKind.noConnection => BymUpdateStatus.noConnection,
        _FetchKind.serverError => BymUpdateStatus.serverError,
        _FetchKind.invalidPayload => BymUpdateStatus.invalidPayload,
        _FetchKind.cancelled => BymUpdateStatus.cancelled,
      };
}

class _FetchResult {
  final _FetchKind kind;

  /// Corps reçu tel quel : aucune normalisation, l'empreinte de blob porte sur
  /// ces octets exacts.
  final Uint8List? body;

  const _FetchResult(this.kind, [this.body]);

  const _FetchResult.cancelled() : this(_FetchKind.cancelled);
}

/// Un commit amont, réduit à ce qui sert.
@immutable
class _Commit {
  final String id;
  final DateTime committedAt;
  final String title;

  const _Commit(this.id, this.committedAt, this.title);
}

/// Télécharge, vérifie et installe une mise à jour du texte BYM depuis le dépôt
/// GitLab officiel.
///
/// Trois garanties, dans l'ordre où elles comptent :
///
/// 1. **Rien de non vérifié n'est servi au lecteur.** Chaque `.md` reçu est
///    comparé à l'empreinte de blob que l'arbre du dépôt annonce, puis converti
///    par [BymMarkdownConverter], puis validé structurellement (un `book` non
///    vide, des `chapters` non vides, chaque chapitre au moins un verset).
/// 2. **L'état affiché ne peut pas mentir.** Les livres passent par une zone de
///    transit et ne basculent que lorsque *tous* sont vérifiés. Une coupure
///    laisse l'état précédent entier.
/// 3. **Aucune donnée sans accord.** [checkForUpdate] lit un commit (671 o) et
///    un arbre (9,6 Ko) ; [apply] n'est appelé que sur action de l'utilisateur.
class BymUpdateService {
  BymUpdateService({
    http.Client? client,
    BymUpdateStore? store,
    AssetBundle? bundle,
    this.attemptsPerFile = 3,
    this.retryBackoff = const Duration(milliseconds: 400),
    this.maxInFlight = 4,
  })  : _injectedClient = client,
        _store = store ?? BymUpdateStore(),
        _bundle = bundle ?? rootBundle;

  /// Relances d'un échec transitoire, comme `DownloadService`.
  final int attemptsPerFile;

  /// Attente avant la n-ième relance : [retryBackoff], puis ×2, ×4…
  final Duration retryBackoff;

  /// Requêtes simultanées. Un delta ordinaire pèse un à trois livres ; la borne
  /// ne sert qu'aux rattrapages d'un texte très en retard.
  final int maxInFlight;

  static const Duration requestTimeout = Duration(seconds: 20);

  /// Au plus une vérification par jour et par appareil. Le quota GitLab non
  /// authentifié (500 requêtes/min et par IP) tient largement.
  static const Duration checkInterval = Duration(hours: 24);

  /// Titres de commits repris dans les notes, et longueur de chacun.
  static const int maxNoteLines = 5;
  static const int maxNoteLength = 120;

  final http.Client? _injectedClient;
  final BymUpdateStore _store;
  final AssetBundle _bundle;

  http.Client? _ownedClient;

  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    if (_injectedClient == null) {
      _ownedClient?.close();
      _ownedClient = null;
    }
  }

  void close() {
    _ownedClient?.close();
    _ownedClient = null;
  }

  BymSourceIndex? _embedded;

  /// Références du texte figé dans l'APK, lues une fois depuis les assets.
  /// Null quand `_source.json` manque : voir [BymUpdateStatus.unconfigured].
  Future<BymSourceIndex?> embeddedIndex() async {
    if (_embedded != null) return _embedded;
    try {
      final raw = await _bundle.loadString(bymSourceAsset);
      return _embedded = BymSourceIndex.parse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Date du texte en vigueur : celle du commit installé, sinon l'embarquée.
  Future<DateTime?> effectiveDate() async =>
      BymUpdateStore.installedAt ?? (await embeddedIndex())?.committedAt;

  /// Commit du texte en vigueur, null quand `_source.json` manque.
  Future<String?> effectiveCommit() async =>
      BymUpdateStore.installedCommit ?? (await embeddedIndex())?.commit;

  /// Le corpus tel qu'il est réellement sur l'appareil : l'embarqué, recouvert
  /// livre par livre par ce qu'une mise à jour a déjà remplacé.
  ///
  /// Une mise à jour ne porte que son delta, donc les deux couches sont
  /// nécessaires : comparer l'arbre distant au seul registre installé
  /// reproposerait tous les livres jamais corrigés.
  Future<BymSourceIndex?> referenceIndex() async {
    final embedded = await embeddedIndex();
    if (embedded == null) return null;

    final installed = BymUpdateStore.installedBlobs;
    if (installed.isEmpty) return embedded;

    final blobs = <String, String>{...embedded.blobs};
    installed.forEach((jsonFile, blob) {
      final markdown = bymMarkdownNameOf(jsonFile);
      if (markdown != null) blobs[markdown] = blob;
    });
    return BymSourceIndex(
      commit: BymUpdateStore.installedCommit ?? embedded.commit,
      committedAt: BymUpdateStore.installedAt ?? embedded.committedAt,
      blobs: blobs,
    );
  }

  /// Demande au dépôt ce qui a changé. Ne télécharge aucun livre.
  ///
  /// Deux requêtes au plus : le dernier commit, puis l'arbre — et l'arbre n'est
  /// même pas demandé si le commit est celui du texte en place.
  Future<BymUpdateCheck> checkForUpdate() async {
    _cancelled = false;

    final reference = await referenceIndex();
    if (reference == null) {
      return const BymUpdateCheck(BymUpdateStatus.unconfigured);
    }

    final head = await _fetchJson(
        '$bymProjectApi/repository/commits?ref_name=$bymBranch&per_page=1');
    if (head.kind != _FetchKind.ok) {
      return BymUpdateCheck(head.kind.status);
    }
    final commits = _parseCommits(head.value);
    if (commits.isEmpty) {
      return const BymUpdateCheck(BymUpdateStatus.invalidPayload);
    }
    final head0 = commits.first;

    // Le commit est déjà celui du texte en place : rien à demander de plus.
    if (head0.id == reference.commit) {
      await _store.markChecked(DateTime.now());
      return BymUpdateCheck(
        BymUpdateStatus.upToDate,
        commit: head0.id,
        committedAt: head0.committedAt,
      );
    }

    // Le sha est validé par [_parseCommits] : aucune requête n'est construite
    // avec une valeur distante non conforme à `^[0-9a-f]{40}$`.
    final tree = await _fetchJson(
        '$bymProjectApi/repository/tree?ref=${head0.id}&per_page=100');
    if (tree.kind != _FetchKind.ok) {
      return BymUpdateCheck(tree.kind.status);
    }

    final changed = _diffTree(tree.value, reference);
    if (changed == null) {
      return const BymUpdateCheck(BymUpdateStatus.invalidPayload);
    }

    await _store.markChecked(DateTime.now());

    if (changed.isEmpty) {
      // Le dépôt a bougé, mais aucun de nos 66 livres : un README, la CI.
      return BymUpdateCheck(
        BymUpdateStatus.upToDate,
        commit: head0.id,
        committedAt: head0.committedAt,
      );
    }

    final books = <String>[
      for (final markdown in bymCatalogByMarkdown.keys)
        if (changed.containsKey(markdown)) markdown,
    ];

    return BymUpdateCheck(
      BymUpdateStatus.available,
      commit: head0.id,
      committedAt: head0.committedAt,
      books: books,
      blobs: changed,
      notes: await _fetchNotes(reference),
    );
  }

  /// Livres de l'arbre dont l'empreinte diffère de [reference].
  ///
  /// Null quand la réponse n'est pas un arbre exploitable. Les noms viennent
  /// **toujours** du catalogue local : on intersecte, on ne fait pas confiance.
  /// Un livre local absent de l'arbre est simplement ignoré, jamais supprimé.
  static Map<String, String>? _diffTree(Object? decoded, BymSourceIndex reference) {
    if (decoded is! List || decoded.isEmpty) return null;

    final changed = <String, String>{};
    var known = 0;
    for (final raw in decoded) {
      if (raw is! Map) continue;
      if (raw['type'] != 'blob') continue;
      final name = raw['name'];
      if (name is! String || !bymCatalogByMarkdown.containsKey(name)) continue;
      final id = raw['id'];
      if (id is! String || !_hexPattern.hasMatch(id)) return null;
      known++;
      if (reference.blobs[name] != id) changed[name] = id;
    }

    // Aucun livre reconnu : ce n'est pas l'arbre de notre corpus (redirection,
    // page d'erreur bien formée, dépôt réorganisé). Refuser plutôt que de
    // conclure « à jour » à tort.
    if (known == 0) return null;
    return changed;
  }

  /// Titres des commits amont postérieurs au texte en place.
  ///
  /// Au mieux : un échec ici ne fait pas échouer la vérification, il prive juste
  /// le lecteur du détail.
  Future<String> _fetchNotes(BymSourceIndex reference) async {
    final since = reference.committedAt.toUtc().toIso8601String();
    final result = await _fetchJson('$bymProjectApi/repository/commits'
        '?ref_name=$bymBranch&per_page=20'
        '&since=${Uri.encodeQueryComponent(since)}');
    if (result.kind != _FetchKind.ok) return '';

    final lines = <String>[];
    for (final commit in _parseCommits(result.value)) {
      // `since` est inclusif : le commit du texte en place en fait partie.
      if (commit.id == reference.commit) continue;
      if (commit.title.isEmpty) continue;
      lines.add(commit.title.length > maxNoteLength
          ? '${commit.title.substring(0, maxNoteLength - 1)}…'
          : commit.title);
      if (lines.length >= maxNoteLines) break;
    }
    return lines.join('\n');
  }

  /// Commits d'une réponse de l'API, ceux au sha conforme uniquement.
  static List<_Commit> _parseCommits(Object? decoded) {
    if (decoded is! List) return const <_Commit>[];
    final commits = <_Commit>[];
    for (final raw in decoded) {
      if (raw is! Map) continue;
      final id = raw['id'];
      if (id is! String || !_hexPattern.hasMatch(id)) continue;
      final rawDate = raw['committed_date'] ?? raw['created_at'];
      final date = rawDate is String ? DateTime.tryParse(rawDate) : null;
      if (date == null) continue;
      final title = raw['title'];
      commits.add(_Commit(id, date, title is String ? title.trim() : ''));
    }
    return commits;
  }

  /// Télécharge, vérifie, convertit et installe les livres de [plan].
  ///
  /// N'écrit rien tant que tout n'est pas vérifié : le premier refus annule
  /// l'ensemble et le texte précédent reste en place. Pas de panachage.
  Future<BymUpdateOutcome> apply(
    BymUpdateCheck plan, {
    void Function(BymUpdateProgress)? onProgress,
  }) async {
    _cancelled = false;

    if (!_isApplicable(plan)) {
      return const BymUpdateOutcome(BymUpdateStatus.invalidPayload);
    }

    await _store.discardStaging();

    final total = plan.books.length;
    var done = 0;
    onProgress?.call(BymUpdateProgress(done: 0, total: total));

    _FetchKind? failure;
    for (var start = 0; start < total; start += maxInFlight) {
      if (_cancelled) {
        failure = _FetchKind.cancelled;
        break;
      }
      final slice = plan.books.skip(start).take(maxInFlight).toList();
      final kinds = await Future.wait(slice.map(
          (markdown) => _fetchAndStage(plan.commit, markdown, plan.blobs[markdown]!)));
      for (var i = 0; i < kinds.length; i++) {
        if (kinds[i] == _FetchKind.ok) {
          done++;
          onProgress?.call(BymUpdateProgress(
            done: done,
            total: total,
            current: slice[i],
          ));
        } else {
          failure ??= kinds[i];
        }
      }
      if (failure != null) break;
    }

    if (failure != null) {
      await _store.discardStaging();
      return BymUpdateOutcome(failure.status);
    }

    try {
      await _store.install(
        commit: plan.commit,
        committedAt: plan.committedAt!,
        notes: plan.notes,
        blobs: <String, String>{
          for (final markdown in plan.books)
            bymCatalogByMarkdown[markdown]!: plan.blobs[markdown]!,
        },
      );
    } catch (_) {
      await _store.discardStaging();
      return const BymUpdateOutcome(BymUpdateStatus.invalidPayload);
    }

    invalidateCaches();
    return BymUpdateOutcome(BymUpdateStatus.applied, total);
  }

  /// Un plan n'est appliqué que s'il est entièrement décrit : sha du commit,
  /// date, livres connus du catalogue, et une empreinte conforme pour chacun.
  /// Sans cela, aucune requête n'est émise.
  static bool _isApplicable(BymUpdateCheck plan) {
    if (!_hexPattern.hasMatch(plan.commit)) return false;
    if (plan.committedAt == null) return false;
    if (plan.books.isEmpty) return false;
    for (final markdown in plan.books) {
      if (!bymCatalogByMarkdown.containsKey(markdown)) return false;
      final blob = plan.blobs[markdown];
      if (blob == null || !_hexPattern.hasMatch(blob)) return false;
    }
    return true;
  }

  /// Revient au texte embarqué.
  Future<void> revertToEmbedded() async {
    await _store.clear();
    invalidateCaches();
  }

  /// Oublie tout texte BYM tenu en mémoire.
  ///
  /// Les quatre caches sont nécessaires, et le dernier est le moins évident :
  /// [LexiconIndex] est bâti sur les **notes** des livres BYM
  /// (`lexicon_index.dart`), donc il survivrait à la mise à jour en servant
  /// l'ancien texte. Idem pour [FulltextIndex] : sans lui, la recherche
  /// continuerait de trouver le verset non corrigé.
  static void invalidateCaches() {
    LocalRepository.clearCache();
    VersionRepository.forget(VersionRepository.embeddedCode);
    FulltextIndex.forget(VersionRepository.embeddedCode);
    LexiconIndex.instance.clearIndex();
  }

  /// Un livre : téléchargement, empreinte, conversion, structure, transit.
  Future<_FetchKind> _fetchAndStage(
      String commit, String markdown, String expectedBlob) async {
    final url = bymRawTemplate
        .replaceAll('{commit}', commit)
        .replaceAll('{file}', Uri.encodeComponent(markdown));

    for (var attempt = 1;; attempt++) {
      if (_cancelled) return _FetchKind.cancelled;
      final result = await _fetch(url);
      if (result.kind == _FetchKind.ok) {
        final body = result.body!;

        // L'empreinte porte sur les octets exacts du blob. Une page d'erreur
        // servie en 200 échoue ici, sans même être décodée.
        if (gitBlobId(body) != expectedBlob) return _FetchKind.invalidPayload;

        final Map<String, Object?> book;
        try {
          book = BymMarkdownConverter.convert(utf8.decode(body));
        } catch (_) {
          // Markdown tronqué ou sans titre : le convertisseur lève plutôt que
          // de rendre un livre vide, et c'est ce qui protège le lecteur ici.
          return _FetchKind.invalidPayload;
        }
        if (!_isBook(book)) return _FetchKind.invalidPayload;

        try {
          await _store.stage(
              bymCatalogByMarkdown[markdown]!, BymMarkdownConverter.encode(book));
        } catch (_) {
          return _FetchKind.invalidPayload;
        }
        return _FetchKind.ok;
      }
      if (!result.kind.transient) return result.kind;
      if (_cancelled) return _FetchKind.cancelled;
      if (attempt >= attemptsPerFile) return result.kind;
      await Future<void>.delayed(retryBackoff * (1 << (attempt - 1)));
    }
  }

  /// Une conversion réussie ne suffit pas : un `.md` amputé de ses versets se
  /// convertirait sans erreur en un livre que personne ne peut lire.
  static bool _isBook(Map<String, Object?> book) {
    final name = book['book'];
    if (name is! String || name.isEmpty) return false;
    final chapters = book['chapters'];
    if (chapters is! List || chapters.isEmpty) return false;
    for (final chapter in chapters) {
      if (chapter is! Map) return false;
      final verses = chapter['verses'];
      if (verses is! List || verses.isEmpty) return false;
    }
    return true;
  }

  /// Une requête d'API, corps décodé en JSON.
  Future<_JsonResult> _fetchJson(String url) async {
    final result = await _fetch(url);
    if (result.kind != _FetchKind.ok) return _JsonResult(result.kind);
    try {
      return _JsonResult(_FetchKind.ok, jsonDecode(utf8.decode(result.body!)));
    } catch (_) {
      return const _JsonResult(_FetchKind.invalidPayload);
    }
  }

  /// Une requête, classée plutôt qu'avalée.
  Future<_FetchResult> _fetch(String url) async {
    try {
      final response =
          await _client.get(Uri.parse(url)).timeout(requestTimeout);
      if (_cancelled) return const _FetchResult.cancelled();
      if (response.statusCode != 200) {
        return _FetchResult(_kindOfStatus(response.statusCode));
      }
      return _FetchResult(_FetchKind.ok, response.bodyBytes);
    } on TimeoutException {
      return const _FetchResult(_FetchKind.serverError);
    } on SocketException {
      return const _FetchResult(_FetchKind.noConnection);
    } on http.ClientException {
      return const _FetchResult(_FetchKind.noConnection);
    } catch (_) {
      return const _FetchResult(_FetchKind.invalidPayload);
    }
  }

  static _FetchKind _kindOfStatus(int status) {
    if (status == 429 || status >= 500) return _FetchKind.serverError;
    return _FetchKind.invalidPayload;
  }
}

class _JsonResult {
  final _FetchKind kind;
  final Object? value;

  const _JsonResult(this.kind, [this.value]);
}

/// Vérification silencieuse au démarrage, et source de vérité unique pour les
/// deux endroits qui l'affichent.
///
/// Réglages porte la section complète, la Bibliothèque une simple pastille :
/// tous deux écoutent [available], donc ils ne peuvent pas se contredire.
class BymUpdateChecker {
  /// Mise à jour repérée et non encore installée, null sinon.
  static final ValueNotifier<BymUpdateCheck?> available =
      ValueNotifier<BymUpdateCheck?>(null);

  static bool _running = false;

  /// Vérifie au plus une fois par [BymUpdateService.checkInterval].
  ///
  /// Ne lève jamais et n'attend rien : hors ligne, le démarrage est simplement
  /// silencieux. Aucun livre n'est téléchargé ici.
  static Future<void> maybeCheck({
    BymUpdateService? service,
    BymUpdateStore? store,
    bool force = false,
  }) async {
    if (_running) return;
    _running = true;
    final owned = service == null;
    final svc = service ?? BymUpdateService();
    try {
      final st = store ?? BymUpdateStore();
      if (!force) {
        final last = await st.lastCheck();
        if (last != null &&
            DateTime.now().difference(last) < BymUpdateService.checkInterval) {
          return;
        }
      }
      final check = await svc.checkForUpdate();
      available.value = check.hasUpdate ? check : null;
    } catch (_) {
      // Une vérification ratée ne doit rien coûter au démarrage.
    } finally {
      if (owned) svc.close();
      _running = false;
    }
  }

  /// À appeler après une installation ou un retour au texte embarqué.
  static void clear() => available.value = null;
}
