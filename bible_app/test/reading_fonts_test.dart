import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

import 'package:bible_app/data/app_preferences.dart';
import 'package:bible_app/widgets/premium_style.dart';

/// La chaîne des polices, de l'énumération jusqu'aux octets du fichier.
///
/// Trois maillons peuvent se rompre sans que rien ne le dise, parce qu'aucun
/// n'est vérifié par le compilateur :
///
/// 1. une entrée de [ReadingFont] dont la famille n'est **pas** déclarée dans
///    `pubspec.yaml` : Flutter ne se plaint pas, il retombe en silence sur la
///    police système, donc le lecteur choisit « Cardo » et lit du Roboto ;
/// 2. une famille déclarée dont le fichier a disparu du dépôt : l'erreur ne
///    sort qu'au `flutter build`, et seulement si l'asset est atteint ;
/// 3. un `.ttf` tronqué ou remplacé par une page d'erreur HTML — les cinq
///    fichiers de Cardo et Newsreader ont été **téléchargés**, donc ce cas n'est
///    pas théorique. Un fichier de 4 Ko qui commence par `<!DOCTYPE` passerait
///    les deux premiers contrôles sans broncher.
///
/// D'où la lecture du `pubspec.yaml` d'un côté et celle des tables `sfnt` de
/// l'autre. Le test tourne depuis la racine du paquet (`flutter test`), donc les
/// chemins relatifs du pubspec s'ouvrent tels quels.
void main() {
  /// famille → chemins des fichiers déclarés, dans l'ordre du pubspec.
  final declared = <String, List<String>>{};

  /// famille → chemins déclarés `style: italic`.
  final italics = <String, List<String>>{};

  setUpAll(() {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final fonts = (pubspec['flutter'] as YamlMap)['fonts'] as YamlList;
    for (final entry in fonts) {
      final family = (entry as YamlMap)['family'] as String;
      expect(
        declared.containsKey(family),
        isFalse,
        reason: 'famille « $family » déclarée deux fois dans pubspec.yaml',
      );
      declared[family] = [];
      italics[family] = [];
      for (final face in entry['fonts'] as YamlList) {
        final asset = (face as YamlMap)['asset'] as String;
        declared[family]!.add(asset);
        if (face['style'] == 'italic') italics[family]!.add(asset);
      }
    }
  });

  test('chaque police proposée au lecteur est déclarée dans pubspec.yaml', () {
    for (final font in ReadingFont.values) {
      expect(
        declared.keys,
        contains(font.fontFamily),
        reason:
            'ReadingFont.${font.name} annonce « ${font.fontFamily} » : '
            'sans déclaration, Flutter retombe en silence sur la police système',
      );
    }
    // La police de l'interface (titres, boutons, badges) suit la même règle.
    expect(declared.keys, contains(kUiFontFamily));
  });

  test('aucune famille déclarée ne dort dans l\'archive', () {
    // Une famille que personne ne demande pèse quelques centaines de Ko dans
    // l'APK sans jamais s'afficher. Le pubspec et l'énumération doivent donc se
    // recouvrir exactement, à la police d'interface près.
    final used = {
      for (final font in ReadingFont.values) font.fontFamily,
      kUiFontFamily,
    };
    expect(declared.keys.toSet(), used);
  });

  test('chaque fichier déclaré existe et est une vraie police', () {
    for (final family in declared.entries) {
      for (final asset in family.value) {
        final file = File(asset);
        expect(
          file.existsSync(),
          isTrue,
          reason: '${family.key} : fichier manquant $asset',
        );
        final bytes = file.readAsBytesSync();
        // Un `.ttf` valide commence par une signature sfnt et porte une table
        // `cmap` non vide : c'est le minimum pour qu'un caractère se dessine.
        final tables = _sfntTables(bytes);
        expect(
          tables,
          isNotNull,
          reason: '$asset : signature sfnt absente (fichier tronqué ?)',
        );
        expect(
          tables!.keys,
          contains('cmap'),
          reason: '$asset : aucune table cmap, aucun caractère ne se dessinerait',
        );
      }
    }
  });

  test('chaque famille porte un italique dessiné', () {
    // Les extraits de versets et les intitulés de notes s'affichent en
    // italique. Sans face italique déclarée, Skia penche le romain lui-même :
    // un faux italique, reconnaissable et laid sur une serif de lecture.
    for (final family in italics.entries) {
      expect(
        family.value,
        isNotEmpty,
        reason: '${family.key} : aucune face « style: italic »',
      );
    }
  });

  test('Cardo est la seule famille embarquée qui couvre l\'hébreu', () {
    // C'est la raison d'être de cette police dans une application qui affiche
    // des lemmes hébreux (fiches Strong) : les onze autres familles rendraient
    // רֵאשִׁית en carrés vides. Le test tient la promesse du commentaire du
    // pubspec, et attrape du même coup un fichier remplacé par une autre police.
    const hebreu = [
      0x05D0, // א aleph
      0x05E9, // ש shin
      0x05B0, // ְ sheva — le seul point-voyelle du corpus BYM (Lv. 19:18)
      0x05C1, // ׁ point du shin
    ];
    const grecPolytonique = 0x1F00; // ἀ alpha esprit doux

    bool couvre(String asset, Iterable<int> points) {
      final cmap = _CharMap.parse(File(asset).readAsBytesSync());
      expect(cmap, isNotNull, reason: '$asset : cmap illisible');
      return points.every((cp) => cmap!.glyphFor(cp) != 0);
    }

    for (final asset in declared['Cardo']!) {
      expect(
        couvre(asset, hebreu),
        isTrue,
        reason: '$asset devrait couvrir l\'hébreu — c\'est sa raison d\'être',
      );
      expect(couvre(asset, [grecPolytonique]), isTrue, reason: asset);
    }

    // L'unicité, mesurée et pas supposée : si une autre famille se met à
    // couvrir l'hébreu, le commentaire du pubspec devient faux et ce test le
    // dit. Ce n'est pas un échec grave — c'est une phrase à corriger.
    final autres = declared.entries
        .where((f) => f.key != 'Cardo')
        .where((f) => couvre(f.value.first, hebreu))
        .map((f) => f.key)
        .toList();
    expect(
      autres,
      isEmpty,
      reason:
          'ces familles couvrent aussi l\'hébreu : $autres — mettre à jour le '
          'commentaire de Cardo dans pubspec.yaml',
    );
  });

  group('la police par défaut de la lecture', () {
    // Un `test()` pur : `SharedPreferences` n'a rien à attendre de la zone
    // fake-async, et `AppPreferences.load` ne touche pas `path_provider`.
    test('une installation neuve lit en Crimson Pro', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPreferences.load();
      expect(prefs.readingFont, ReadingFont.crimson);
    });

    test('le choix déjà pris survit au changement de défaut', () async {
      // La moitié qui compte : changer la police par défaut ne doit pas
      // réécrire le choix d'un lecteur qui en a fait un. Un lecteur qui avait
      // explicitement Literata doit la relire, pas se voir imposer Crimson Pro
      // parce que la version précédente de l'app avait un autre défaut.
      SharedPreferences.setMockInitialValues({'reading.fontFamily': 'literata'});
      final prefs = await AppPreferences.load();
      expect(prefs.readingFont, ReadingFont.literata);
    });

    test('le défaut est une serif de lecture, pas la police d\'interface', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPreferences.load();
      expect(
        prefs.readingFont.fontFamily,
        isNot(kUiFontFamily),
        reason: 'la lecture et l\'interface ne se ressemblent pas à dessein',
      );
    });
  });
}

/// Répertoire des tables d'un fichier sfnt : tag → (offset, longueur).
///
/// Rend `null` si la signature n'est pas celle d'une police (`0x00010000` pour
/// le TrueType, `OTTO` pour les contours PostScript, `true` pour l'ancien
/// format Apple).
Map<String, (int, int)>? _sfntTables(Uint8List bytes) {
  if (bytes.length < 12) return null;
  final data = ByteData.sublistView(bytes);
  final version = data.getUint32(0);
  const otto = 0x4F54544F; // 'OTTO'
  const apple = 0x74727565; // 'true'
  if (version != 0x00010000 && version != otto && version != apple) return null;
  final count = data.getUint16(4);
  if (12 + count * 16 > bytes.length) return null;
  final tables = <String, (int, int)>{};
  for (var i = 0; i < count; i++) {
    final record = 12 + i * 16;
    final tag = String.fromCharCodes(bytes, record, record + 4);
    final offset = data.getUint32(record + 8);
    final length = data.getUint32(record + 12);
    if (offset + length > bytes.length) continue; // enregistrement tronqué
    if (length > 0) tables[tag] = (offset, length);
  }
  return tables;
}

/// La table `cmap` d'une police, réduite à ce qui nous intéresse : « ce point de
/// code a-t-il un glyphe ? ».
///
/// Seuls les sous-tableaux Unicode des formats 4 (BMP, le cas courant) et 12
/// (plan complet) sont lus — les deux seuls que produisent les fonderies
/// modernes. Le format 12 est préféré quand les deux sont présents.
class _CharMap {
  _CharMap._(this._data, this._subtable, this._format);

  final ByteData _data;
  final int _subtable;
  final int _format;

  static _CharMap? parse(Uint8List bytes) {
    final tables = _sfntTables(bytes);
    final cmap = tables?['cmap'];
    if (cmap == null) return null;
    final data = ByteData.sublistView(bytes);
    final start = cmap.$1;
    final count = data.getUint16(start + 2);
    int? best;
    var bestFormat = -1;
    for (var i = 0; i < count; i++) {
      final record = start + 4 + i * 8;
      final platform = data.getUint16(record);
      final encoding = data.getUint16(record + 2);
      final offset = start + data.getUint32(record + 4);
      if (offset + 4 > bytes.length) continue;
      // Unicode (0, tout encodage) ou Windows Unicode BMP/complet (3/1 et 3/10).
      final unicode =
          platform == 0 || (platform == 3 && (encoding == 1 || encoding == 10));
      if (!unicode) continue;
      final format = data.getUint16(offset);
      if (format != 4 && format != 12) continue;
      // Le format 12 couvre tout le plan : il l'emporte sur le format 4.
      if (format > bestFormat) {
        bestFormat = format;
        best = offset;
      }
    }
    return best == null ? null : _CharMap._(data, best, bestFormat);
  }

  /// L'identifiant de glyphe du point de code, ou 0 (`.notdef`) s'il n'est pas
  /// couvert.
  int glyphFor(int codePoint) =>
      _format == 12 ? _format12(codePoint) : _format4(codePoint);

  int _format4(int cp) {
    if (cp > 0xFFFF) return 0;
    final segCount = _data.getUint16(_subtable + 6) ~/ 2;
    final endCodes = _subtable + 14;
    final startCodes = endCodes + segCount * 2 + 2; // + reservedPad
    final idDeltas = startCodes + segCount * 2;
    final idRangeOffsets = idDeltas + segCount * 2;
    for (var seg = 0; seg < segCount; seg++) {
      if (_data.getUint16(endCodes + seg * 2) < cp) continue;
      if (_data.getUint16(startCodes + seg * 2) > cp) return 0;
      final rangeOffset = _data.getUint16(idRangeOffsets + seg * 2);
      if (rangeOffset == 0) {
        return (cp + _data.getInt16(idDeltas + seg * 2)) & 0xFFFF;
      }
      // `idRangeOffset` compte les octets depuis sa propre position — un
      // vestige de l'époque où la table se parcourait par pointeurs.
      final at = idRangeOffsets +
          seg * 2 +
          rangeOffset +
          (cp - _data.getUint16(startCodes + seg * 2)) * 2;
      if (at + 2 > _data.lengthInBytes) return 0;
      final glyph = _data.getUint16(at);
      return glyph == 0
          ? 0
          : (glyph + _data.getInt16(idDeltas + seg * 2)) & 0xFFFF;
    }
    return 0;
  }

  int _format12(int cp) {
    final groups = _data.getUint32(_subtable + 12);
    for (var i = 0; i < groups; i++) {
      final group = _subtable + 16 + i * 12;
      final first = _data.getUint32(group);
      if (first > cp) return 0;
      final last = _data.getUint32(group + 4);
      if (last < cp) continue;
      return _data.getUint32(group + 8) + (cp - first);
    }
    return 0;
  }
}
