import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Une page du glossaire de l'Ancien Testament Interlinéaire — celle que le
/// renvoi d'un mot (`n12`, `d12`, `r2`, `abr`) promet d'ouvrir.
///
/// Trois champs, tels que `notes.json` les porte : l'intitulé court (`Note 12`),
/// le titre qui le complète (`Mot rare, hapax…`) et le corps en HTML. Ce corps
/// est de la source, tables et points-voyelles compris — `ati_note_html.dart`
/// le démonte, personne ne le réécrit.
class AtiNote {
  /// L'identifiant court du renvoi, la clé dans `notes.json` : `n12`, `d1`,
  /// `r2`, `abr`. C'est la chaîne que porte `AtiWord.note`, sans traduction à
  /// faire.
  final String id;

  /// L'intitulé affiché par la source : « Note 12 », « Difficulté 1 »,
  /// « Remarque 2 », « Liste des abréviations ».
  final String name;

  /// Le titre complet, sous l'intitulé.
  final String title;

  /// Le corps de la page, en HTML de source.
  final String html;

  const AtiNote({
    required this.id,
    required this.name,
    required this.title,
    required this.html,
  });

  factory AtiNote.fromJson(String id, Map<String, dynamic> json) => AtiNote(
    id: id,
    name: (json['name'] as String?)?.trim() ?? '',
    title: (json['title'] as String?)?.trim() ?? '',
    html: json['html'] as String? ?? '',
  );

  /// Le titre complet, ou l'intitulé court s'il est le seul — un renvoi sans
  /// titre reste nommé plutôt que blanc.
  String get heading => title.isEmpty ? name : title;
}

/// Les 37 pages de `notes.json`, lues une fois et gardées.
///
/// Le fichier est **embarqué** (`assets/ati/notes.json`), pas téléchargé avec
/// le corpus : 306 Ko de référence statique, dont un renvoi a besoin au moment
/// exact où le lecteur tape un mot — un quarante-et-unième fichier à aller
/// chercher ajouterait une panne possible à un geste qui n'en doit avoir
/// aucune. Le corpus ATI (36 Mo) reste téléchargé, lui.
///
/// Lecture **tolérante**, à la manière de [StrongLexicon] : un fichier absent
/// ou abîmé donne un glossaire vide, jamais une exception — le renvoi ne
/// s'ouvrira pas, le reste de l'interlinéaire n'en sait rien.
class AtiNotes {
  AtiNotes._();

  static final AtiNotes instance = AtiNotes._();

  /// Chemin dans le bundle, le même que dans le `pubspec.yaml`.
  static const String assetPath = 'assets/ati/notes.json';

  static AssetBundle _bundle = rootBundle;

  /// Les tests servent un glossaire faux sans toucher au réseau ni au bundle
  /// réel, puis rendent la main par [useRootBundle].
  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    instance._pages = null;
  }

  static void useRootBundle() => useBundle(rootBundle);

  Map<String, AtiNote>? _pages;

  /// Le glossaire complet, ou un dictionnaire vide si la lecture a échoué.
  Future<Map<String, AtiNote>> _ensureLoaded() async {
    final cached = _pages;
    if (cached != null) return cached;
    final pages = <String, AtiNote>{};
    try {
      final decoded = jsonDecode(await _bundle.loadString(assetPath));
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is! Map<String, dynamic>) continue;
          pages[entry.key.toString()] = AtiNote.fromJson(
            entry.key.toString(),
            entry.value as Map<String, dynamic>,
          );
        }
      }
    } catch (_) {
      pages.clear();
    } finally {
      _pages = pages;
    }
    return pages;
  }

  /// La page que [id] nomme, `null` pour un renvoi que le glossaire ne
  /// connaît pas — un identifiant hors table se lit « introuvable », pas en
  /// erreur.
  Future<AtiNote?> lookup(String id) async {
    final pages = await _ensureLoaded();
    return pages[id.trim()];
  }

  /// Le titre d'un renvoi, pour l'afficher à côté de son identifiant sans
  /// ouvrir la page — `null` si la page n'existe pas.
  Future<String?> headingOf(String id) async {
    final note = await lookup(id);
    return note?.heading;
  }

  /// La page dont [pageName] est l'intitulé — la forme que les renvois
  /// **internes** du glossaire portent (`g.php?…&g=Difficulté 7`), pas
  /// l'identifiant. Cherché sur les 37 sans index : le geste est rare et le
  /// détour, lui, ne l'est jamais.
  Future<AtiNote?> lookupByName(String pageName) async {
    final pages = await _ensureLoaded();
    final wanted = pageName.trim();
    for (final note in pages.values) {
      if (note.name == wanted) return note;
    }
    return null;
  }

  /// Nombre de pages lues — le contrôle des chargements de test.
  Future<int> size() async => (await _ensureLoaded()).length;
}
