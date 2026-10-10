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

  /// The gloss the source places before its list of senses — « Abiel = Dieu
  /// est mon père », « Paul ou Paulus = petit ». Null when the entry has none.
  final String? signification;
  final List<String> senses;

  /// The senses as the source numbers them — stems (« Qal », « Hifil ») and
  /// rungs (« 1a1) », « 2b1) ») included, each with the indent it asks for.
  /// Empty when the entry is a flat list of bullets.
  final List<StrongOutlineNode> outline;

  /// The lexicon holds no entry for this code: [definition] is then the
  /// notice [StrongLexicon.lookup] writes in its place, not a source text.
  final bool introuvable;

  /// The entry comes from Biblia's extended numbering (H8675+), where a code
  /// names a *form* — a binyan crossed with a tense — rather than a word.
  /// The fiche says so instead of passing for a dictionary headword.
  final bool etendu;

  const StrongDefinition({
    required this.strong,
    required this.definition,
    this.language,
    this.lemma,
    this.transliteration,
    this.pronunciation,
    this.partOfSpeech,
    this.etymology,
    this.signification,
    this.senses = const [],
    this.outline = const [],
    this.introuvable = false,
    this.etendu = false,
  });

  factory StrongDefinition.fromJson(String key, dynamic value,
      {bool etendu = false}) {
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
    final outline = (rawMap['outline'] as List<dynamic>? ?? const [])
        .map(StrongOutlineNode.fromJson)
        .where((node) => node.text.isNotEmpty || node.label != null)
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
      signification: field('signification'),
      senses: senses,
      outline: outline,
      etendu: etendu,
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
        signification,
        ...senses,
      ].whereType<String>().join(' ');
}

/// What a line of the source's own outline means on the fiche.
enum StrongOutlineKind {
  /// A plain sense, shown with the usual bullet.
  sense,

  /// A numbered rung — « 1a1) voir » — whose code is set apart.
  number,

  /// A group the source opens: a stem (« Qal »), a label (« (phrases) »).
  header,
}

/// One line of a [`StrongDefinition.outline`], at the indent the source asks.
class StrongOutlineNode {
  /// Rung of the line: 0 for the entry's own level, one more per step down.
  final int level;
  final StrongOutlineKind kind;

  /// The line's text. For a [StrongOutlineKind.header] this is what follows
  /// the label, spacing included: `label` + `text` reads as the source does.
  final String text;

  /// A header's label, without its parentheses — « Qal », « Pual ». Null for
  /// a label the source already wrote in full — « (phrases) ».
  final String? label;

  const StrongOutlineNode({
    required this.level,
    required this.kind,
    required this.text,
    this.label,
  });

  factory StrongOutlineNode.fromJson(dynamic value) {
    final map = value is Map ? value : const {};
    final kind = map['kind'];
    final rawLabel = map['label']?.toString().trim();
    return StrongOutlineNode(
      level: int.tryParse(map['level']?.toString() ?? '') ?? 0,
      kind: kind == 'number'
          ? StrongOutlineKind.number
          : (kind == 'header' || kind == 'label')
              ? StrongOutlineKind.header
              : StrongOutlineKind.sense,
      // Not trimmed: a header keeps the spacing the source gave it.
      text: map['text']?.toString() ?? '',
      label: rawLabel == null || rawLabel.isEmpty ? null : rawLabel,
    );
  }

  /// « (Qal) » — the header as the source wrote it, label included.
  String get asWritten => label == null ? text : '($label)$text';
}

/// In-memory French Strong lexicon, loaded lazily from `assets/lexicon/`.
class StrongLexicon {
  StrongLexicon._();

  static final StrongLexicon instance = StrongLexicon._();
  static const String _assetPath = 'assets/lexicon/strong_fr.json';

  /// Les codes de la numérotation étendue de Biblia — H8675 et au-delà —
  /// tiennent dans un fichier à part : ce sont des formes (binyan croisé
  /// avec un mode), pas des lexies, et les mêmer dans [all] ferait chercher
  /// « Radical - Qal » comme s'il s'agissait d'un mot.
  static const String _assetFormes = 'assets/lexicon/strong_etendu.json';

  /// Les entrées que les modules SWORD ne portent pas — G2994 (Λαοδικεύς) et
  /// G2995 (λάρυγξ) : citées par les corpus, absentes de la base. La fusion
  /// les construit, mais la fusion complète pèse bien trop lourd pour le
  /// bundle, d'où ces deux-là seules, embarquées à part.
  ///
  /// Ce sont des lexies : elles rejoignent [_definitions] et entrent dans
  /// [all] comme les autres — à la différence des codes de forme, que
  /// [_assetFormes] tient dehors pour ne pas faire chercher « Radical - Qal »
  /// comme s'il s'agissait d'un mot.
  static const String _assetComplements =
      'assets/lexicon/strong_complements.json';

  static final Map<String, StrongDefinition> _definitions = {};
  static final Map<String, StrongDefinition> _formes = {};
  static final Map<String, String> _normalized = {};
  static bool _loaded = false;
  static List<String> _keys = const [];
  static AssetBundle _bundle = rootBundle;

  static AssetBundle get bundle => _bundle;

  static void useBundle(AssetBundle bundle) {
    _bundle = bundle;
    _definitions.clear();
    _formes.clear();
    _normalized.clear();
    _keys = const [];
    _loaded = false;
  }

  static void useRootBundle() => useBundle(rootBundle);
  bool get isLoaded => _loaded;
  int get size => _definitions.length;

  /// Les codes de forme (numérotation étendue) chargés — distincts de
  /// [size], qui compte les lexies.
  int get formesCount => _formes.length;

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
    // Fichiers distincts, échecs distincts : si l'un manque, le lexique
    // principal reste entier.
    await _chargerComplements();
    await _chargerFormes();
  }

  /// Ajoute au lexique les entrées que la fusion a créées hors base SWORD.
  ///
  /// Lecture silencieuse : un fichier absent ne retire rien, il laisse
  /// simplement G2994 et G2995 sans fiche — ce que [_chargerFormes] fait de
  /// son côté pour les codes de forme.
  Future<void> _chargerComplements() async {
    try {
      final decoded = jsonDecode(await _bundle.loadString(_assetComplements));
      final entries = decoded is Map && decoded['entries'] is Map
          ? decoded['entries'] as Map
          : decoded;
      if (entries is! Map) return;
      var ajoute = false;
      for (final entry in entries.entries) {
        final key = entry.key.toString().trim().toUpperCase();
        if (key.isEmpty || entry.value is! Map) continue;
        // La base SWORD prime : ce fichier ne comble qu'une absence.
        if (_definitions.containsKey(key)) continue;
        final value = StrongDefinition.fromJson(key, entry.value);
        if (value.definition.isEmpty) continue;
        _definitions[key] = value;
        _normalized[key] = normalizeForSearch(value.searchText);
        ajoute = true;
      }
      if (ajoute) _keys = _definitions.keys.toList()..sort();
    } catch (_) {
      // Rien à ajouter : le lexique principal est déjà chargé.
    }
  }

  /// Charge les codes de la numérotation étendue, consultés par [lookup] en
  /// second recours — après le lexique, avant la notice « hors lexique ».
  Future<void> _chargerFormes() async {
    try {
      final decoded = jsonDecode(await _bundle.loadString(_assetFormes));
      final entries = decoded is Map && decoded['entries'] is Map
          ? decoded['entries'] as Map
          : decoded;
      if (entries is! Map) return;
      for (final entry in entries.entries) {
        final key = entry.key.toString().trim().toUpperCase();
        if (key.isEmpty || entry.value is! Map) continue;
        final value = StrongDefinition.fromJson(key, entry.value,
            etendu: true);
        if (value.definition.isEmpty) continue;
        _formes[key] = value;
      }
    } catch (_) {
      _formes.clear();
    }
  }

  /// The Strong codes written in [strong], in order, in the form the lexicon
  /// ranges them — see [canonique]. A corpus token may carry two of them for a
  /// single word — « G3588 G4674 » for Jean 18.35 — and the lexicon holds one
  /// entry per code.
  static List<String> codesOf(String strong) => [
        for (final part in strong.split(RegExp(r'\s+')))
          if (part.trim().isNotEmpty) canonique(part),
      ];

  /// La forme canonique d'un code — celle que le lexique range : une lettre
  /// majuscule suivie de quatre chiffres (`H853` → `H0853`, `h7225` → `H7225`).
  ///
  /// Les corpus ne s'accordent pas : la LSGS imprime `H0853`, l'ATI écrit
  /// `H853` comme sa source l'affiche. Sans cette borne, un code
  /// parfaitement valide d'une version est introuvable dans l'autre — et la
  /// fiche se tait sur un mot qui a pourtant son entrée. Un code d'une autre
  /// facture (un nombre nu, une suite) passe tel quel : c'est à l'appelant
  /// de savoir ce qu'il tient.
  static String canonique(String code) {
    final brut = code.trim().toUpperCase();
    final appariement = RegExp(r'^([A-Z])(\d{1,4})$').firstMatch(brut);
    if (appariement == null) return brut;
    return '${appariement.group(1)}${appariement.group(2)!.padLeft(4, '0')}';
  }

  Future<StrongDefinition> lookup(String strong) async {
    await _ensureLoaded();
    // Several codes in one string: answer with the first one the lexicon
    // holds. Each code still has its own fiche — a caller that wants them
    // all asks for them one by one through [codesOf].
    for (final code in codesOf(strong)) {
      final found = _definitions[code] ?? _formes[code];
      if (found != null) return found;
    }
    final key = strong.trim().toUpperCase();
    return StrongDefinition(
      strong: key,
      definition: noticeHorsLexique(key),
      introuvable: true,
    );
  }

  /// Ce que la fiche dit d'un code que le lexique ne porte pas.
  ///
  /// Presque tous viennent de la numérotation étendue de Biblia — son aide
  /// annonce les codes hébreu jusqu'à 8853 et grecs jusqu'à 5799, quand le
  /// Strong standard s'arrête à H8674 / G5624. C'est là que vivent les
  /// particules que la traduction ne rend pas (waw, article, préfixes
  /// pronominaux) : 100 052 des 116 567 codes sans mot français de la LSS, en
  /// tête les plus fréquents de tout le corpus (H8799, H8804, G5719).
  ///
  /// Les codes hébreux ne tombent plus ici : [_chargerFormes] les porte, et
  /// [lookup] les consulte avant d'en venir à cette notice. Restent les codes
  /// grecs au-delà de ce que les modules SWORD portent — 103 en tout, dont
  /// deux seulement sont cités par les corpus (G2994, G2995), et ceux-là
  /// [_chargerComplements] les porte aussi. Ce que la notice survit est donc
  /// un code que ni le lexique ni aucun corpus n'emploie, ou un code de la
  /// numérotation étendue que la source ne définit pas.
  static String noticeHorsLexique(String code) {
    final chiffres = code.length > 1 ? int.tryParse(code.substring(1)) : null;
    final etendu = chiffres != null &&
        ((code.startsWith('H') && chiffres > 8674) ||
            (code.startsWith('G') && chiffres > 5624));
    if (!etendu) {
      return '$code : aucune définition dans le lexique Strong embarqué.';
    }
    return '$code : code de la numérotation étendue de Biblia, au-delà du '
        'Strong standard (H8674 / G5624) — il numérote une particule que la '
        'traduction ne rend pas (waw, article, préfixe…). Aucune définition '
        'n\'est embarquée pour ce code.';
  }

  static bool _estEnregistre(String code) =>
      _definitions.containsKey(code) || _formes.containsKey(code);

  Future<bool> contains(String strong) async {
    await _ensureLoaded();
    return codesOf(strong).any(_estEnregistre);
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