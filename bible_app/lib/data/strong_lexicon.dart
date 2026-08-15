import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'reference_parser.dart';

/// A French Strong entry. Older flat assets remain accepted, while the v2
/// asset carries the source data needed by the detailed Strong fiche.
class StrongDefinition {
  final String strong;
  final String definition;
  final String? language;
  final String? lemma;
  final String? transliteration;
  final String? pronunciation;
  final String? partOfSpeech;
  final String? etymology;
  final List<String> senses;

  const StrongDefinition({
    required this.strong,
    required this.definition,
    this.language,
    this.lemma,
    this.transliteration,
    this.pronunciation,
    this.partOfSpeech,
    this.etymology,
    this.senses = const [],
  });

  factory StrongDefinition.fromJson(String key, dynamic value) {
    if (value is! Map) {
      return StrongDefinition(strong: key, definition: value.toString().trim());
    }
    final rawMap = value;
    String? field(String name) {
      final fieldValue = valueOrNull(rawMap[name]);
      return fieldValue == null || fieldValue.isEmpty ? null : fieldValue;
    }
    final senses = (rawMap['senses'] as List<dynamic>? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return StrongDefinition(
      strong: field('strong')?.toUpperCase() ?? key,
      definition: field('definition') ?? 'Définition non disponible.',
      language: field('language'),
      lemma: field('lemma'),
      transliteration: field('transliteration'),
      pronunciation: field('pronunciation'),
      partOfSpeech: field('partOfSpeech'),
      etymology: field('etymology'),
      senses: senses,
    );
  }

  static String? valueOrNull(dynamic value) => value?.toString().trim();

  String get searchText => [
        strong,
        definition,
        lemma,
        transliteration,
        pronunciation,
        partOfSpeech,
        etymology,
        ...senses,
      ].whereType<String>().join(' ');
}

/// In-memory French Strong lexicon, loaded lazily from `assets/lexicon/`.
class StrongLexicon {
  StrongLexicon._();

  static final StrongLexicon instance = StrongLexicon._();
  static const String _assetPath = 'assets/lexicon/strong_fr.json';
  static final Map<String, StrongDefinition> _definitions = {};
  static final Map<String, String> _normalized = {};
  static bool _loaded = false;
  static List<String> _keys = const [];
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
  int get size => _definitions.length;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    try {
      final decoded = jsonDecode(await _bundle.loadString(_assetPath));
      final entries = decoded is Map && decoded['entries'] is Map
          ? decoded['entries'] as Map
          : decoded;
      if (entries is Map) {
        for (final entry in entries.entries) {
          final key = entry.key.toString().trim().toUpperCase();
          if (key.isEmpty) continue;
          final value = StrongDefinition.fromJson(key, entry.value);
          if (value.definition.isEmpty) continue;
          _definitions[key] = value;
          _normalized[key] = normalizeForSearch(value.searchText);
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

  Future<StrongDefinition> lookup(String strong) async {
    final key = strong.trim().toUpperCase();
    await _ensureLoaded();
    return _definitions[key] ?? StrongDefinition(
      strong: key,
      definition: 'Définition Strong non disponible pour $key dans le lexique embarqué.',
    );
  }

  Future<bool> contains(String strong) async {
    await _ensureLoaded();
    return _definitions.containsKey(strong.trim().toUpperCase());
  }

  Future<List<StrongDefinition>> all() async {
    await _ensureLoaded();
    return [for (final key in _keys) _definitions[key]!];
  }

  Future<List<StrongDefinition>> search(String query, {int limit = 50}) async {
    await _ensureLoaded();
    final q = query.trim().toUpperCase();
    if (q.isEmpty) return const [];
    final exact = _definitions[q];
    if (exact != null) return [exact];

    final ranked = <({int score, int rank, String key})>[];
    if (q.length >= 2) {
      final needle = normalizeForSearch(q);
      for (var i = 0; i < _keys.length; i++) {
        if (i % 1024 == 0) await Future<void>.delayed(Duration.zero);
        final key = _keys[i];
        final normalizedKey = _normalized[key]!;
      final score = key.startsWith(q)
          ? 1
          : key.contains(q)
              ? 2
              : normalizedKey == needle
                  ? 3
                  : normalizedKey.contains(needle)
                      ? 4
                      : null;
      if (score != null) {
        final rank = score < 4 ? i : normalizedKey.indexOf(needle);
        ranked.add((score: score, rank: rank, key: key));
      }
      }
      ranked.sort((a, b) {
        if (a.score != b.score) return a.score - b.score;
        return a.rank - b.rank;
      });
    }
    return [for (final result in ranked.take(limit)) _definitions[result.key]!];
  }

  String label(String strong) => 'Strong $strong';
}