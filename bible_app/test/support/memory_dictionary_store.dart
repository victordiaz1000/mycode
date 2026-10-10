import 'package:bible_app/data/dictionary_store.dart';

/// An in-memory [DictionaryStore]: the study sheet only reads the registry
/// and the file of one code, so the disk never has to be involved —
/// `path_provider` never answers inside the fake-async zone of `testWidgets`.
///
/// The map is code → payload, exactly what a download lands.
class MemoryDictionaryStore extends DictionaryStore {
  MemoryDictionaryStore([Map<String, Map<String, dynamic>>? dictionaries])
      : _dictionaries = dictionaries ?? {};

  final Map<String, Map<String, dynamic>> _dictionaries;

  @override
  Future<Set<String>> installed() async => _dictionaries.keys.toSet();

  @override
  Future<Map<String, dynamic>?> load(String code) async => _dictionaries[code];
}
