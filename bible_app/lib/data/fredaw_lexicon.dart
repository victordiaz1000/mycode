import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'reference_parser.dart';

/// Le lexique décodé, tel qu'il franchit la frontière d'isolate.
class _ParsedLexicon {
  final Map<String, FreDawEntry> entries;
  final Map<String, String> normalized;
  final List<String> keys;

  const _ParsedLexicon(this.entries, this.normalized, this.keys);
}

/// Décode le JSON du lexique et construit ses index. Fonction de premier
/// niveau et pure : c'est la condition pour la passer à [Isolate.run] sans
/// capturer d'état non transmissible.
_ParsedLexicon _parse(String raw) {
  final decoded = jsonDecode(raw);
  final entries = decoded is Map && decoded['entries'] is Map
      ? decoded['entries'] as Map
      : const {};
  final built = <String, FreDawEntry>{};
  final normalized = <String, String>{};
  for (final item in entries.entries) {
    final key = item.key.toString().trim();
    if (key.isEmpty) continue;
    final value = item.value;
    if (value is Map<String, dynamic>) {
      final entry = FreDawEntry.fromJson(key, value);
      if (entry.definition.isEmpty) continue;
      built[key] = entry;
      normalized[key] = normalizeForSearch(entry.term);
    }
  }
  return _ParsedLexicon(built, normalized, built.keys.toList()..sort());
}

class FreDawEntry {
  final String term;
  final String definition;

  const FreDawEntry({required this.term, required this.definition});

  factory FreDawEntry.fromJson(String term, Map<String, dynamic> json) {
    return FreDawEntry(
      term: term,
      definition: json['definition']?.toString().trim() ?? '',
    );
  }
}

class FreDawLexicon {
  FreDawLexicon._();

  static final FreDawLexicon instance = FreDawLexicon._();
  static const String _assetPath = 'assets/lexicon/fredaw.json';
  static final Map<String, FreDawEntry> _entries = {};
  static final Map<String, String> _normalized = {};
  static List<String> _keys = const [];
  static AssetBundle _bundle = rootBundle;
  static bool _loaded = false;

  /// The characters that make up a dictionary word, used to bound the
  /// cross-links: letters (accents folded in), digits, underscore and hyphen
  /// — but not the apostrophe, so that « l'ABBA » links its « ABBA ».
  static const String _wordChars = r'A-Za-z0-9À-ÖØ-öø-ÿ_\-';

  /// A term is linkable when it is a single word: letters, hyphens and
  /// apostrophes only. Multi-word titles (« ABDIAS OU OBADIA ») or parenthesised
  /// ones (« ABEL (LIEU) ») cannot be matched in running text.
  static final RegExp _linkableTerm = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿ'’\-]{2,}$");

  static RegExp? _linkPattern;

  static AssetBundle get bundle => _bundle;

  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    _entries.clear();
    _normalized.clear();
    _keys = const [];
    _linkPattern = null;
    _loaded = false;
  }

  static void useRootBundle() => useBundle(rootBundle);

  bool get isLoaded => _loaded;
  int get size => _entries.length;

  /// Au-dessous de ce volume, le décodage reste sur l'isolate courant.
  ///
  /// Deux raisons qui vont dans le même sens. D'abord, un isolate coûte plus
  /// cher que ce qu'il économise sur un petit payload. Ensuite — et c'est
  /// dirimant — `flutter_test` exécute ses `testWidgets` dans une zone
  /// `FakeAsync` où le `Future` d'un [Isolate.run] n'aboutit **jamais** : tout
  /// test servant le lexique par un faux bundle finirait sur « pumpAndSettle
  /// timed out ». Constaté en vrai : 48 tests sont tombés d'un coup avant
  /// l'ajout de ce seuil. C'est le même piège que celui déjà documenté pour
  /// `dart:io` sur [ChapterReader.store].
  ///
  /// Les faux bundles des tests pèsent quelques kilo-octets, l'asset réel
  /// 12,18 Mo : le seuil sépare les deux sans ambiguïté.
  static const int _isolateThreshold = 256 * 1024;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await _bundle.loadString(_assetPath);
      // `jsonDecode` de 12,18 Mo plus la construction des 5 535 entrées
      // coûtaient 126 ms sur l'isolate principal — presque 8 frames gelées
      // sur un PC, bien plus sur un téléphone. Déporté dans un isolate, le
      // thread principal ne paye plus que l'envoi du texte et la copie du
      // résultat : ~12 ms, mesurés sur ce même asset.
      //
      // `_parse` est une fonction de premier niveau et ne capture que `raw`
      // (une String, donc transmissible) : rien de l'état statique de la
      // classe ne traverse la frontière d'isolate.
      final parsed = raw.length >= _isolateThreshold
          ? await Isolate.run(() => _parse(raw))
          : _parse(raw);
      _entries.addAll(parsed.entries);
      _normalized.addAll(parsed.normalized);
      _keys = parsed.keys;
    } catch (_) {
      _entries.clear();
      _normalized.clear();
      _keys = const [];
    } finally {
      _loaded = true;
    }
  }

  Future<FreDawEntry> lookup(String term) async {
    final key = term.trim().toUpperCase();
    await _ensureLoaded();
    return _entries[key] ?? FreDawEntry(
      term: key,
      definition: 'Entrée FreDAW non disponible pour "$key".',
    );
  }

  Future<List<FreDawEntry>> all() async {
    await _ensureLoaded();
    return [for (final key in _keys) _entries[key]!];
  }

  Future<List<FreDawEntry>> search(String query, {int limit = 50}) async {
    await _ensureLoaded();
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final exact = _entries[trimmed.toUpperCase()];
    if (exact != null) return [exact];

    final needle = normalizeForSearch(trimmed);
    if (needle.isEmpty) return const [];

    final ranked = <({int score, int rank, String key})>[];
    for (var i = 0; i < _keys.length; i++) {
      final key = _keys[i];
      final normalizedKey = _normalized[key]!;
      final score = normalizedKey == needle
          ? 0
          : normalizedKey.startsWith(needle)
              ? 1
              : normalizedKey.contains(needle)
                  ? 2
                  : null;
      if (score != null) {
        ranked.add((score: score, rank: i, key: key));
      }
    }

    ranked.sort((a, b) {
      if (a.score != b.score) return a.score - b.score;
      return a.rank - b.rank;
    });

    return [for (final result in ranked.take(limit)) _entries[result.key]!];
  }

  String label(String term) => 'FreDAW $term';

  /// A single case-insensitive regex that finds, anywhere in a text, every
  /// word that is itself a dictionary entry. Longest terms first (so
  /// « ABEL-BETH-MAACA » wins over « ABEL » at the same position) and word
  /// boundaries so that « ABEL » inside « ABELARD » or « ABEL-BETH » is not a
  /// link. Null when no term is linkable.
  Future<RegExp?> linkPattern() async {
    await _ensureLoaded();
    if (_linkPattern != null) return _linkPattern;
    final terms = _keys.where(_linkableTerm.hasMatch).toList()
      ..sort((a, b) => b.length - a.length);
    if (terms.isEmpty) return null;
    _linkPattern = RegExp(
      '(?<![$_wordChars])(?:${terms.map(RegExp.escape).join('|')})'
      '(?![$_wordChars])',
      caseSensitive: false,
    );
    return _linkPattern;
  }
}
