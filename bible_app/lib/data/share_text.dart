/// Ce que le lecteur **copie** et ce qu'il **partage**.
///
/// Les deux sont formats ici, en fonctions pures, et nulle part ailleurs — le
/// nom de l'app compris ([appName]), que d'autres écrans viennent chercher
/// plutôt que de le réécrire. C'était
/// le défaut que la revue a mis au jour : les deux chaînes vivaient en dur dans
/// `chapter_reader.dart`, à deux endroits, donc impossibles à éprouver sans monter
/// un lecteur — et libres de diverger. Elles avaient divergé : « Partager »
/// nommait la version traduite, « Copier » non.
library;

import 'dart:ui' show Rect;

import 'package:share_plus/share_plus.dart';

// ── Mise en forme ───────────────────────────────────────────────────────────

/// One verse to hand over, with the reference already resolved.
class PassageRef {
  /// « Genèse 1:1 » — the reader's own label, book and chapter included.
  final String reference;

  /// The verse number alone, used to detect a contiguous run.
  final int verse;

  final String text;

  const PassageRef({
    required this.reference,
    required this.verse,
    required this.text,
  });
}

/// The version badge appended to a reference. The embedded BYM needs none — it
/// is the app's own text and naming it would be noise — whereas a downloaded
/// translation must say whose words these are, or the reader passes them on as
/// if they were the BYM's.
String? versionTag(String? code, String embeddedCode) =>
    (code == null || code == embeddedCode) ? null : ' ($code)';

/// Le nom de l'app, écrit **une seule fois** pour tout le code : première ligne
/// de ce qu'on copie et de ce qu'on partage, pied de l'export des notes, titre
/// de l'écran.
///
/// Un texte qui circule sans sa source se lit comme une parole venue de
/// nulle part. La ligne d'en-tête dit d'où viennent les mots **avant** les
/// mots : un verset collé dans une note, une sélection envoyée dans une
/// conversation, un export relu dans six mois.
const String appName = 'BYM — Bible de Yehoshoua Ha Mashiah';

/// L'en-tête que portent toutes les formes ci-dessous : le nom, un saut de
/// ligne, le corps. Une seule fois — jamais un par verset, une sélection de
/// douze versets n'est pas douze citations de l'application.
String _enTete(String corps) => '$appName\n$corps';

/// « Genèse 1:1 texte » — une seule ligne de citation, **sans** en-tête : c'est
/// elle qui se répète dans une sélection.
String _citation(PassageRef verse, {String? tag}) =>
    '${verse.reference}${tag ?? ''} ${verse.text}';

/// The **copy** form: the app's name opens the block, then the reference, so
/// the line stays greppable when several verses are pasted into a note or a
/// search.
String formatCitation(PassageRef verse, {String? tag}) =>
    _enTete(_citation(verse, tag: tag));

/// Several verses to copy, in reading order: the name once, then one
/// reference-first line each.
String formatCitations(List<PassageRef> verses, {String? tag}) {
  if (verses.isEmpty) return '';
  return _enTete(verses.map((v) => _citation(v, tag: tag)).join('\n'));
}

/// The **share** form of a single verse: the words in guillemets, the reference
/// on its own line beneath, the app's name over both. A quotation is meant to
/// be read, not scanned.
String formatPassage(PassageRef verse, {String? tag}) =>
    _enTete('« ${verse.text} »\n— ${verse.reference}${tag ?? ''}');

/// Several verses, in reading order, under the app's name.
///
/// The attribution line names the **book and chapter once**, then the verse
/// numbers: `— Genèse 1:1-3` for a contiguous run, `— Genèse 1:1, 3, 5` when the
/// selection skips. Writing `1:1-3` for verses 1, 3 and 5 would attribute words to
/// a verse nobody chose, and repeating the book on every number is unreadable.
String formatSelection(List<PassageRef> verses, {String? tag}) {
  if (verses.isEmpty) return '';
  if (verses.length == 1) return formatPassage(verses.first, tag: tag);

  final numeros = verses.map((v) => v.verse).toList();
  final contiguous = numeros.last - numeros.first == verses.length - 1;
  // « Genèse 1:1 » se démonte en « Genèse » + chapitre « 1 » : le livre et le
  // chapitre ne se répètent qu'une fois, la ligne se lit « Genèse 1:1-3 ».
  final reference = verses.first.reference;
  final coupure = reference.lastIndexOf(' ');
  final livre = coupure > 0 ? reference.substring(0, coupure) : '';
  final chapitre = reference.substring(coupure + 1).split(':').first;
  final tete = livre.isEmpty ? chapitre : '$livre $chapitre';
  final attribution = contiguous
      ? '$tete:${numeros.first}-${numeros.last}'
      : '$tete:${numeros.join(', ')}';
  final corps = verses.map((v) => '« ${v.text} »').join('\n');
  return _enTete('$corps\n— $attribution${tag ?? ''}');
}

// ── Coutures ────────────────────────────────────────────────────────────────

/// The system share sheet, as an assignable function so tests can capture
/// what the app shares instead of touching the platform channel.
///
/// [origin] is the tapped button's rectangle. Without it the share sheet has
/// nothing to anchor to, which is the classic cause of a mispositioned — or
/// overflowing — sheet on a tablet; `share_plus` also uses it to dismiss the
/// popover it opens.
Future<void> Function(String message, {Rect? origin}) shareText =
    _systemShare;

/// Same seam for a file export (the notes dump): tests capture the path.
Future<void> Function(String filePath, {String? subject}) shareTextFile =
    _systemShareFile;

Future<void> _systemShare(String message, {Rect? origin}) async {
  await SharePlus.instance.share(
    ShareParams(text: message, sharePositionOrigin: origin),
  );
}

Future<void> _systemShareFile(String filePath, {String? subject}) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(filePath)], subject: subject),
  );
}
