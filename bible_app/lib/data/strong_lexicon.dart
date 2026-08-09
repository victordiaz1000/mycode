import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'reference_parser.dart';

/// One French Strong definition: the code and its readable text.
class StrongDefinition {
  final String strong;
  final String definition;

  const StrongDefinition({required this.strong, required this.definition});
}

/// In-memory French Strong lexicon, loaded lazily from `assets/lexicon/`.
///
/// The file holds one readable French definition per Strong code —
/// `{'H0430': "’elohiym …", 'G2316': "theos …"}`. It is built from
/// CrossWire/SWORD `FreStrongsHebrew` and `FreStrongsGreek` (see
/// `plan-strong-fr.md`), converted once by `sword_zld_to_json.py`.
class StrongLexicon {
  StrongLexicon._();

  static final StrongLexicon instance = StrongLexicon._();
  static const String _assetPath = 'assets/lexicon/strong_fr.json';

  /// Strong code → definition, populated on first access.
  static final Map<String, String> _definitions = <String, String>{};

  /// Strong code → accent-free, lowercased version of the definition.
  ///
  /// Built once at load so [search] only does `contains` on each candidate
  /// instead of re-normalizing all 14 195 definitions for every keystroke
  /// (the old code blocked the UI thread on a common word).
  static final Map<String, String> _normalized = <String, String>{};
  static bool _loaded = false;

  /// Sorted codes, for [search].
  static List<String> _keys = const [];

  /// Asset bundle the lexicon is read through — injectable so widget tests can
  /// serve a small synthetic lexicon (same seam as [LocalRepository.useBundle]).
  static AssetBundle _bundle = rootBundle;

  static AssetBundle get bundle => _bundle;

  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    _definitions.clear();
    _normalized.clear();
    _keys = const [];
    _loaded = false;
  }

  static void useRootBundle() => useBundle(rootBundle);

  bool get isLoaded => _loaded;

  /// Number of definitions after loading.
  int get size => _definitions.length;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final raw = await _bundle.loadString(_assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _definitions.clear();
        _normalized.clear();
        for (final entry in decoded.entries) {
          final key = entry.key.toString().trim();
          final value = entry.value.toString().trim();
          if (key.isNotEmpty && value.isNotEmpty) {
            _definitions[key.toUpperCase()] = value;
            _normalized[key.toUpperCase()] = normalizeForSearch(value);
          }
        }
        _keys = _definitions.keys.toList()..sort();
      }
    } catch (_) {
      _definitions.clear();
      _normalized.clear();
      _keys = const [];
    } finally {
      _loaded = true;
    }
  }

  /// The French definition of [strong], or a placeholder when missing.
  Future<StrongDefinition> lookup(String strong) async {
    final key = strong.trim().toUpperCase();
    await _ensureLoaded();

    final definition = _definitions[key];
    if (definition != null && definition.isNotEmpty) {
      return StrongDefinition(strong: key, definition: definition);
    }

    return StrongDefinition(
      strong: key,
      definition:
          'Définition Strong non disponible pour $key dans le lexique embarqué.',
    );
  }

  /// Whether [strong] has a definition.
  Future<bool> contains(String strong) async {
    await _ensureLoaded();
    return _definitions[strong.trim().toUpperCase()] != null;
  }

  /// Entries matching [query], best first, capped at [limit].
  ///
  /// Ranking: exact code (0) > code prefix (1) > code substring (2) >
  /// definition mentions the query (3). Ties keep the lexicographic order.
  Future<List<StrongDefinition>> search(
    String query, {
    int limit = 50,
  }) async {
    await _ensureLoaded();
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return const [];

    final exact = _definitions[q];
    if (exact != null) {
      return [StrongDefinition(strong: q, definition: exact)];
    }

    final ranked = <({int score, int rank, String key})>[];
    final definitions = _definitions;
    final normalized = _normalized;
    if (q.length >= 2) {
      final needle = normalizeForSearch(q);
      for (var i = 0; i < _keys.length; i++) {
        // 14 195 entries: yield so the spinner and the keyboard keep animating
        // while a common word walks the whole lexicon.
        if (i % 1024 == 0) await Future<void>.delayed(Duration.zero);
        final key = _keys[i];
        int? score;
        if (key.startsWith(q)) {
          score = 1;
        } else if (key.contains(q)) {
          score = 2;
        } else if (normalized[key]!.contains(needle)) {
          score = 3;
        }
        if (score == null) continue;
        ranked.add((score: score, rank: i, key: key));
      }
      ranked.sort(
          (a, b) => a.score != b.score ? a.score - b.score : a.rank - b.rank);
    }
    return [
      for (final r in ranked.take(limit))
        StrongDefinition(strong: r.key, definition: definitions[r.key]!),
    ];
  }

  /// Human-friendly label for a Strong reference.
  String label(String strong) => 'Strong $strong';
}