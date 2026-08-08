import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/translation.dart';
import 'book_mapping.dart';

/// Fetches a chapter of a remote translation (getbible.net) or from a `url:`.
///
/// Chapter JSON from getbible looks like:
///   { "book_name": "...", "chapter": 1, "verses": { "1": {"chapter":1,"verse":1,"text":"..."}, ... } }
class ReadRepository {
  final http.Client _client;

  ReadRepository({http.Client? client}) : _client = client ?? http.Client();

  /// Returns verse texts for [chapter] of the book at [bymIndex] (1..66) in
  /// [translation]. Empty list on failure.
  Future<List<String>> fetchChapter({
    required Translation translation,
    required int bymIndex,
    required int chapter,
  }) async {
    try {
      final int standard = bymToStandard(bymIndex);
      final uri = translationSource(translation, standard, chapter);
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const [];

      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (translation.source == 'getbible') {
        return _parseGetBible(json);
      }
      return _parseGeneric(json);
    } catch (_) {
      return const [];
    }
  }

  Uri translationSource(Translation t, int standardBook, int chapter) {
    if (t.url != null) {
      return Uri.parse(
          t.url!
              .replaceAll('{book}', '$standardBook')
              .replaceAll('{chapter}', '$chapter'));
    }
    // getbible ids come straight from `v2/checksum.json`; there is no
    // per-language variant (`darbyfr` 404s, verified against the live API).
    return Uri.parse(
        'https://api.getbible.net/v2/${t.id}/$standardBook/$chapter.json');
  }

  List<String> _parseGetBible(Map<String, dynamic> json) {
    final verses = json['verses'] as Map<String, dynamic>? ?? {};
    // getbible verse keys are "1".."N" in standard order.
    final sortedKeys = verses.keys.toList()..sort((a, b) {
        final ia = int.parse(a);
        final ib = int.parse(b);
        return ia.compareTo(ib);
      });
    return sortedKeys
        .map((k) => (verses[k]['text'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }

  List<String> _parseGeneric(Map<String, dynamic> json) {
    // Generic fallback: array of {"verse":..., "text":...} or {"verses":[...]}.
    final raw = json['verses'] as List<dynamic>? ?? [];
    return raw
        .map((v) => (v['text'] as String? ?? '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
