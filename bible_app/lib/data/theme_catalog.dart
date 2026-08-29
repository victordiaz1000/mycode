import 'dart:io';

import 'package:flutter/material.dart';

/// How the background asset fills the screen. Most fonds are small seamless
/// textures (32–320 px) that must repeat as tiles; the two scene-like images
/// (bas-relief frieze, pale world map) are compositions that cover instead —
/// covering a 32 px texture stretches it into a blur.
enum BackgroundFit { tile, cover }

/// A reading theme: a named palette + a background image (from thème/).
class BibleTheme {
  final String id;
  final String name;
  final String backgroundAsset;
  final BackgroundFit backgroundFit;

  /// File path of a user-picked photo (galerie). When set it REPLACES the
  /// asset as the background, always covered — a photo is a scene, not a
  /// tile. The rest of the palette was derived from the photo's luminosity
  /// at pick time and persisted.
  final String? customFile;
  final Color backgroundTone;
  final Color textColor;
  final Color titleColor;
  final Color verseNumColor;
  final Color accentColor;
  final Color highlightRef; // liseré doré des notes

  const BibleTheme({
    required this.id,
    required this.name,
    this.backgroundAsset = '',
    this.backgroundFit = BackgroundFit.tile,
    this.customFile,
    required this.backgroundTone,
    required this.textColor,
    required this.titleColor,
    required this.verseNumColor,
    required this.accentColor,
    required this.highlightRef,
  });

  bool get hasBackground => backgroundAsset.isNotEmpty || customFile != null;

  /// Light veil for bright motifs, dark veil when the palette uses light text.
  bool get usesLightText => textColor.computeLuminance() > .55;

  Color get readingOverlay =>
      usesLightText ? const Color(0x33000000) : const Color(0x2EFFFFFF);

  ImageProvider get backgroundImage => customFile != null
      ? FileImage(File(customFile!))
      : AssetImage(backgroundAsset);

  /// The background exactly as the reader paints it — tiles at natural size
  /// for textures, cover for the two scene images and for photos, always
  /// under the veil — so previews cannot drift from the reading screen.
  DecorationImage decorationImage() => DecorationImage(
    image: backgroundImage,
    fit: backgroundFit == BackgroundFit.cover || customFile != null
        ? BoxFit.cover
        : null,
    repeat: backgroundFit == BackgroundFit.cover || customFile != null
        ? ImageRepeat.noRepeat
        : ImageRepeat.repeat,
    colorFilter: ColorFilter.mode(readingOverlay, BlendMode.srcOver),
  );

  /// Harmonised reading surfaces and secondary text derived from the palette.
  Color get panelColor => usesLightText
      ? Color.lerp(backgroundTone, Colors.black, .55)!.withValues(alpha: .88)
      : Color.lerp(backgroundTone, Colors.white, .58)!.withValues(alpha: .88);

  /// The semi-transparent panel the verses sit on. [opacity] is the reader's
  /// « Opacité du panneau » preference (default reproduces the historical
  /// .80 alpha); lower = the background shows through more.
  Color readingPanelColor([double opacity = .80]) =>
      panelColor.withValues(alpha: opacity);

  Color get noteColor => Color.lerp(textColor, accentColor, .28)!;
  Color get linkColor => Color.lerp(accentColor, titleColor, .22)!;
  Color get panelBorderColor => accentColor.withValues(alpha: .32);

  /// The wash that marks the verse a jump just landed on, the time the reader
  /// needs to find it. Follows the theme's accent — it used to be one fixed
  /// gold, which on the slate or forest palettes read as a stain from another
  /// theme. Stronger than the selection (.15) and the find-in-page hits (.10):
  /// this one has to catch the eye by itself, once.
  Color get jumpFlashColor => accentColor.withValues(alpha: .40);

  /// A copy of this theme with [color] as the body text colour — the reader's
  /// « Couleur du texte » override. Everything derived from the text colour
  /// recomputes (notes, links), and `usesLightText` follows: picking a light
  /// colour on a light theme flips the panels dark, so any choice stays
  /// readable.
  BibleTheme withTextColor(Color color) => BibleTheme(
    id: id,
    name: name,
    backgroundAsset: backgroundAsset,
    backgroundFit: backgroundFit,
    customFile: customFile,
    backgroundTone: backgroundTone,
    textColor: color,
    titleColor: titleColor,
    verseNumColor: verseNumColor,
    accentColor: accentColor,
    highlightRef: highlightRef,
  );
}

/// The 12 named themes — 10 fonds historiques + Sinaï (ocre chaud, 0% gris)
/// + Nuit étoilée (second fond sombre, texture étoilée générée).
///
/// ⚠️ Les **ids** sont les noms des maquettes d'origine et ne disent plus rien
/// du fond affiché : plusieurs thèmes ont été rebaptisés (ou re-pointés vers un
/// autre fonds) sans que leur id change. Table de vérité :
///
/// | id (persisté)    | nom affiché      |
/// |------------------|------------------|
/// | vitrail          | Bas-relief       |
/// | oliveraie        | Oliveraie        |
/// | parchemin        | Papier clair     |
/// | papyrus          | Mosaïque grise   |
/// | forest           | Bois doré        |
/// | sepia            | Cacao            |
/// | minimal          | Brume            |
/// | metal            | Acier            |
/// | desert           | Sable minéral    |
/// | azur             | Azur profond     |
/// | nuit             | Nuit étoilée     |
/// | sinai            | Sinaï            |
///
/// Les ids NE DOIVENT PAS être renommés à la légère : `themeId` est persisté
/// dans les préférences et une clé orpheline retomberait silencieusement sur
/// [bibleThemes.first].
const List<BibleTheme> bibleThemes = [
  BibleTheme(
    id: 'vitrail',
    name: 'Bas-relief',
    backgroundAsset: 'assets/themes/assyriens.png',
    // Frise sculptée : une composition, pas un motif — la couvrir préserve
    // les personnages ; la tuilerie les répéterait côte à côte.
    backgroundFit: BackgroundFit.cover,
    backgroundTone: Color(0xFFDBDBDB),
    textColor: Color(0xFF241D16),
    titleColor: Color(0xFF684B20),
    verseNumColor: Color(0xFF8D691F),
    accentColor: Color(0xFF9C7A1E),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'oliveraie',
    name: 'Oliveraie',
    backgroundAsset: 'assets/themes/beige.png',
    backgroundTone: Color(0xFFF6EFD3),
    textColor: Color(0xFF24301F),
    titleColor: Color(0xFF35533A),
    verseNumColor: Color(0xFF527044),
    accentColor: Color(0xFF45633A),
    highlightRef: Color(0xFF8B6F1F),
  ),
  BibleTheme(
    id: 'parchemin',
    name: 'Papier clair',
    backgroundAsset: 'assets/themes/bg.png',
    // Mappemonde pâle : scène unique, à couvrir comme le bas-relief.
    backgroundFit: BackgroundFit.cover,
    backgroundTone: Color(0xFFF2EBD9),
    textColor: Color(0xFF342719),
    titleColor: Color(0xFF664628),
    verseNumColor: Color(0xFF8A6336),
    accentColor: Color(0xFF8D6738),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'papyrus',
    name: 'Mosaïque grise',
    backgroundAsset: 'assets/themes/blanc.png',
    backgroundTone: Color(0xFFA2A2A2),
    textColor: Color(0xFF302B25),
    titleColor: Color(0xFF5E5041),
    verseNumColor: Color(0xFF806F59),
    accentColor: Color(0xFF6E6051),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'forest',
    name: 'Bois doré',
    backgroundAsset: 'assets/themes/bois.png',
    backgroundTone: Color(0xFFD7B05B),
    textColor: Color(0xFF292118),
    titleColor: Color(0xFF4F3B24),
    verseNumColor: Color(0xFF705332),
    accentColor: Color(0xFF8A5E2B),
    highlightRef: Color(0xFF8B6F1F),
  ),
  BibleTheme(
    id: 'sepia',
    name: 'Cacao',
    backgroundAsset: 'assets/themes/chocolat.png',
    backgroundTone: Color(0xFFE7D8C3),
    textColor: Color(0xFF302113),
    titleColor: Color(0xFF5B3E22),
    verseNumColor: Color(0xFF7F5A31),
    accentColor: Color(0xFF8A6037),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'minimal',
    name: 'Brume',
    backgroundAsset: 'assets/themes/gris.png',
    backgroundTone: Color(0xFFF3F3F3),
    textColor: Color(0xFF24272A),
    titleColor: Color(0xFF414950),
    verseNumColor: Color(0xFF657079),
    accentColor: Color(0xFF617681),
    highlightRef: Color(0xFFD4AF37),
  ),
  BibleTheme(
    id: 'metal',
    name: 'Acier',
    backgroundAsset: 'assets/themes/metal.png',
    backgroundTone: Color(0xFFBEBEBE),
    textColor: Color(0xFF22272A),
    titleColor: Color(0xFF3D4A50),
    verseNumColor: Color(0xFF5B6C73),
    accentColor: Color(0xFF526D78),
    highlightRef: Color(0xFFB89436),
  ),
  BibleTheme(
    id: 'desert',
    name: 'Sable minéral',
    backgroundAsset: 'assets/themes/sable_gris.png',
    backgroundTone: Color(0xFFE2DAC6),
    textColor: Color(0xFF3B2E1E),
    titleColor: Color(0xFF754B27),
    verseNumColor: Color(0xFF9A6532),
    accentColor: Color(0xFFA05A2C),
    highlightRef: Color(0xFFB8860B),
  ),
  // Le premier fond sombre du lot (bleu azur vif, lum 93) : il exige du texte
  // clair, contrairement aux 9 thèmes à texte sombre. Harmonie « bleu + or +
  // blanc glacé » — l'or chaud contraste sur le bleu tout en restant le même
  // langage que le liseré doré des notes des autres thèmes.
  BibleTheme(
    id: 'azur',
    name: 'Azur profond',
    backgroundAsset: 'assets/themes/bleu.png',
    backgroundTone: Color(0xFF0771DA),
    textColor: Color(0xFFEDF3FC),
    titleColor: Color(0xFFF0C75C),
    verseNumColor: Color(0xFFA3BBDC),
    accentColor: Color(0xFFE0B24A),
    highlightRef: Color(0xFFE6BE55),
  ),
  // Nouveau — Nuit étoilée : le second fond sombre, plus neutre et plus profond
  // que l'azur — bleu-noir étoilé, or discret, texte glacé. Même mécanique que
  // l'azur (`usesLightText`) : toute l'app bascule en surfaces sombres.
  BibleTheme(
    id: 'nuit',
    name: 'Nuit étoilée',
    backgroundAsset: 'assets/themes/nuit.png',
    backgroundTone: Color(0xFF121622),
    textColor: Color(0xFFE8ECF5),
    titleColor: Color(0xFFF0C75C),
    verseNumColor: Color(0xFF9FAECB),
    accentColor: Color(0xFFD9B44A),
    highlightRef: Color(0xFFE6BE55),
  ),
  // Nouveau — Sinaï : pierre ocre du désert, chaleur terre cuite.
  // Répond à la demande « sans gris » : ton pêche-ocre #E8B88A, aucune
  // composante grise. Texte brun profond pour contraste sur fond clair.
  BibleTheme(
    id: 'sinai',
    name: 'Sinaï',
    backgroundAsset: 'assets/themes/sinai.png',
    backgroundTone: Color(0xFFE8B88A),
    textColor: Color(0xFF3B2312),
    titleColor: Color(0xFF7A3A1E),
    verseNumColor: Color(0xFF9E5A2E),
    accentColor: Color(0xFFB85C2A),
    highlightRef: Color(0xFFD18A1F),
  ),
];

/// The runtime slot for the user's photo theme. `themeById('custom')` reads
/// it; it is filled from the persisted JSON at startup (see
/// `CustomBackground.restore`) and replaced on every new pick. Null (no
/// photo picked yet, or deleted) falls back to the first catalog theme.
BibleTheme? customBibleTheme;

/// The id of the photo theme — the only non-catalog value `themeId` accepts.
const String customThemeId = 'custom';

BibleTheme themeById(String? id) {
  if (id == customThemeId) return customBibleTheme ?? bibleThemes.first;
  final match = bibleThemes.where((t) => t.id == id).toList();
  return match.isEmpty ? bibleThemes.first : match.first;
}
