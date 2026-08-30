import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fichiers et registre de la mise à jour du texte BYM installée sur l'appareil.
///
/// Le texte BYM est embarqué dans l'APK (`assets/bible/bym/`) : corriger une
/// coquille imposerait sinon de republier l'application sur le store. Un livre
/// corrigé arrive donc ici, sous `<documents>/bym_updates/<nom>.json`, avec les
/// mêmes noms de fichiers que `book_catalog.dart` — aucune table de
/// correspondance à tenir. [LocalRepository] lit d'abord ici, puis l'asset.
///
/// Le registre est une carte `fichier → empreinte de blob git`, et non une simple
/// liste : c'est cette empreinte que [BymUpdateService] compare à l'arbre du
/// dépôt amont pour savoir ce qui a changé. Il n'y a donc plus de numéro de
/// version à tenir — le contenu se compare à lui-même.
///
/// Même découpage que [LibraryStore] (fichiers + registre en préférences), pour
/// la même raison : le registre dit ce qui est réellement arrivé, et il est
/// écrit *après* les fichiers.
class BymUpdateStore {
  /// Commit amont dont provient le texte installé (40 hexadécimaux).
  static const String commitKey = 'bym.update.commit';
  static const String committedAtKey = 'bym.update.committedAt';
  static const String notesKey = 'bym.update.notes';

  /// Carte JSON `01-Genese.md` → empreinte de blob du `.md` d'origine.
  static const String blobsKey = 'bym.update.blobs';
  static const String lastCheckKey = 'bym.update.lastCheck';

  /// Clés du système précédent (GitHub + jsDelivr, texte versionné en semver).
  /// Conservées uniquement pour être **effacées** au chargement : voir [load].
  static const String legacyVersionKey = 'bym.update.version';
  static const String legacyFilesKey = 'bym.update.files';

  static const String updatesDirectory = 'bym_updates';

  /// Zone de transit : un livre vérifié y attend que *tous* ses camarades le
  /// soient. Préfixée d'un point pour ne jamais être confondue avec un livre.
  static const String stagingDirectory = '.staging';

  /// Incrémenté à chaque changement d'état — même mécanique que
  /// `LibraryStore.revision`, et **statique** pour la même raison : chaque écran
  /// construit son propre magasin, donc un notificateur d'instance ne
  /// préviendrait personne.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void _bumpRevision() => revision.value++;

  /// Registre en mémoire : `01-Genese.json` → empreinte du `.md` converti.
  ///
  /// Ce champ existe pour offrir un prédicat **synchrone** à
  /// [LocalRepository.loadBook], appelé par une dizaine d'écrans. Un appel
  /// `path_provider` sur ce chemin gèlerait `pumpAndSettle` : le `path_provider`
  /// réel ne répond jamais dans la zone fake-async de `testWidgets` — c'est
  /// exactement la raison d'être des graines `useBundle` / `useRoot`. Tant que
  /// [load] n'a pas été appelé la carte est vide, donc aucun test widget ne
  /// déclenche la moindre E/S et la lecture reste celle des assets.
  static final Map<String, String> _blobs = <String, String>{};

  static String? _commit;
  static DateTime? _committedAt;
  static String? _notes;

  /// Vrai si [file] (`01-Genese.json`) doit être lu dans la mise à jour.
  static bool hasUpdate(String file) => _blobs.containsKey(file);

  /// Commit amont du texte installé, null quand seul l'embarqué est en place.
  static String? get installedCommit => _commit;

  /// Date du commit amont installé.
  static DateTime? get installedAt => _committedAt;

  /// Ce qui a changé en amont, tel qu'affiché dans Réglages.
  static String? get installedNotes => _notes;

  /// Empreintes des livres installés, pour la comparaison avec l'arbre distant.
  static Map<String, String> get installedBlobs => Map.unmodifiable(_blobs);

  /// Nombre de livres remplacés par la mise à jour.
  static int get updatedCount => _blobs.length;

  static Directory? _root;

  /// Dossier contenant `bym_updates/`. Par défaut le dossier documents.
  static Future<Directory> root() async =>
      _root ??= await getApplicationDocumentsDirectory();

  /// Sert les fichiers depuis [dir]. Les tests doivent l'appeler — voir la note
  /// de [_blobs] sur `path_provider` et la zone fake-async.
  static void useRoot(Directory dir) => _root = dir;

  /// Rétablit le vrai dossier de l'application (à appeler en `tearDown`).
  static void useAppDirectory() => _root = null;

  /// Vide l'état en mémoire sans toucher au disque (isolation des tests).
  @visibleForTesting
  static void resetInMemory() {
    _blobs.clear();
    _commit = null;
    _committedAt = null;
    _notes = null;
  }

  /// Charge le registre en mémoire. À appeler une fois au démarrage, avant que
  /// le premier livre ne soit lu.
  ///
  /// Ne lève jamais : sans registre lisible, l'application retombe simplement
  /// sur son texte embarqué, ce qui est toujours un état valide.
  ///
  /// Purge aussi les clés du système précédent. Ses fichiers ne sont rattachables
  /// à aucun commit amont, donc invérifiables : mieux vaut repartir du texte
  /// embarqué que servir un mélange dont on ne saurait plus rien dire.
  static Future<void> load() async {
    var purgeFiles = false;
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.containsKey(legacyVersionKey) ||
          prefs.containsKey(legacyFilesKey)) {
        purgeFiles = !prefs.containsKey(blobsKey);
        await prefs.remove(legacyVersionKey);
        await prefs.remove(legacyFilesKey);
      }

      final blobs = purgeFiles
          ? const <String, String>{}
          : _decodeBlobs(prefs.getString(blobsKey));
      _blobs
        ..clear()
        ..addAll(blobs);
      _commit = blobs.isEmpty ? null : prefs.getString(commitKey);
      _notes = blobs.isEmpty ? null : prefs.getString(notesKey);
      final at = blobs.isEmpty ? null : prefs.getString(committedAtKey);
      _committedAt = at == null ? null : DateTime.tryParse(at);
    } catch (_) {
      resetInMemory();
    }
    if (purgeFiles) await BymUpdateStore()._deleteFiles();
    _bumpRevision();
  }

  static Map<String, String> _decodeBlobs(String? raw) {
    final blobs = <String, String>{};
    if (raw == null || raw.isEmpty) return blobs;
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      decoded.forEach((key, value) {
        if (key is String &&
            value is String &&
            key.isNotEmpty &&
            value.isNotEmpty) {
          blobs[key] = value;
        }
      });
    }
    return blobs;
  }

  Future<Directory> directory() async =>
      Directory(p.join((await root()).path, updatesDirectory));

  Future<Directory> staging() async =>
      Directory(p.join((await directory()).path, stagingDirectory));

  Future<File> fileFor(String name) async =>
      File(p.join((await directory()).path, name));

  /// Contenu du livre mis à jour, null s'il manque.
  ///
  /// Un fichier enregistré existe toujours (il est écrit avant le registre),
  /// mais l'inverse n'est pas garanti : un `clear()` interrompu peut laisser un
  /// registre en avance. Renvoyer null laisse [LocalRepository] retomber sur
  /// l'asset au lieu d'échouer.
  Future<String?> read(String name) async {
    try {
      final file = await fileFor(name);
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  /// Dépose un livre vérifié en zone de transit. Rien n'est encore visible du
  /// lecteur : seul [install] fait basculer l'ensemble.
  Future<void> stage(String name, String contents) async {
    final file = File(p.join((await staging()).path, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  /// Jette la zone de transit — mise à jour abandonnée ou interrompue.
  Future<void> discardStaging() async {
    try {
      final dir = await staging();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Un transit résiduel n'est jamais lu : seul le registre décide.
    }
  }

  /// Fait basculer le transit vers le dossier servi, puis enregistre le commit.
  ///
  /// L'ordre est ce qui garantit que l'état affiché ne mente jamais : les
  /// fichiers d'abord, le registre ensuite (comme `LibraryStore.saveBook`), et le
  /// commit seulement quand *tous* les livres annoncés sont en place. Une coupure
  /// laisse l'état précédent intact.
  ///
  /// [blobs] est indexé par nom de fichier JSON (`01-Genese.json`) et porte
  /// l'empreinte du `.md` amont dont il a été converti.
  Future<void> install({
    required String commit,
    required DateTime committedAt,
    required String notes,
    required Map<String, String> blobs,
  }) async {
    final target = await directory();
    await target.create(recursive: true);
    final transit = await staging();

    for (final name in blobs.keys) {
      final source = File(p.join(transit.path, name));
      if (!await source.exists()) {
        throw StateError('Livre absent de la zone de transit : $name');
      }
      // Copie puis suppression plutôt que `rename` : le transit est un
      // sous-dossier du dossier cible, donc sur le même volume, mais un
      // `rename` par-dessus un fichier existant n'est pas portable.
      await source.copy(p.join(target.path, name));
    }
    await discardStaging();

    final prefs = await SharedPreferences.getInstance();
    // Les livres déjà remplacés par une mise à jour antérieure le restent : une
    // mise à jour ne porte que son delta.
    final merged = <String, String>{..._blobs, ...blobs};
    await prefs.setString(blobsKey, jsonEncode(merged));
    await prefs.setString(commitKey, commit);
    await prefs.setString(committedAtKey, committedAt.toIso8601String());
    await prefs.setString(notesKey, notes);

    _blobs
      ..clear()
      ..addAll(merged);
    _commit = commit;
    _committedAt = committedAt;
    _notes = notes;
    _bumpRevision();
  }

  /// Revient au texte embarqué : registre effacé puis fichiers supprimés.
  ///
  /// L'état en mémoire tombe **en premier et de façon synchrone**, pour qu'une
  /// lecture concurrente reparte sur l'asset dès cet instant, sans attendre le
  /// disque.
  Future<void> clear() async {
    resetInMemory();
    _bumpRevision();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(blobsKey);
      await prefs.remove(commitKey);
      await prefs.remove(committedAtKey);
      await prefs.remove(notesKey);
    } catch (_) {
      // Sans registre lisible, la carte en mémoire est déjà vide : le texte
      // embarqué reprend la main de toute façon.
    }
    await _deleteFiles();
  }

  Future<void> _deleteFiles() async {
    try {
      final dir = await directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Des fichiers orphelins ne sont plus lus, faute d'être enregistrés.
    }
  }

  /// Octets occupés par la mise à jour, affichés dans Réglages.
  Future<int> sizeOnDisk() async {
    try {
      final dir = await directory();
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Dernière vérification réussie auprès du dépôt, null si jamais.
  Future<DateTime?> lastCheck() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(lastCheckKey);
      return raw == null ? null : DateTime.tryParse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> markChecked(DateTime when) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(lastCheckKey, when.toIso8601String());
    } catch (_) {
      // Sans horodatage, la prochaine vérification aura simplement lieu tout de
      // suite : dégradation acceptable, jamais un blocage.
    }
  }
}
