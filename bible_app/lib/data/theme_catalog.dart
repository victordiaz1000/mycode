import 'package:flutter/material.dart';

/// A reading theme: a named palette + a background image (from thème/).
class BibleTheme {
  final String id;
  final String name;
  final String backgroundAsset;
  final Color textColor;
  final Color titleColor;
  final Color verseNumColor;
  final Color accentColor;
  final Color highlightRef; // liseré doré des notes

  const BibleTheme({
    required this.id,
    required this.name,
    required this.backgroundAsset,
    required this.textColor,
    required this.titleColor,
    required this.verseNumColor,
    required this.accentColor,
    required this.highlightRef,
  });

  bool get hasBackground => backgroundAsset.isNotEmpty;
}

/// The 4 named themes of the maquette. Each maps to a background from the
/// 10 fonds in `thème/`, with a palette tuned to that motif's brightness.
const List<BibleTheme> bibleThemes = [
  BibleTheme(
    id: 'vitrail',
    name: 'Vitrail',
    backgroundAsset: 'assets/themes/assyriens.png',
    textColor: Color(0xFF1C1C1C),
    titleColor: Color(0xFF8C6D1F),
    verseNumColor: Color(0xFFB8860B),
    accentColor: Color(0xFF9C7A1E),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'oliveraie',
    name: 'Oliveraie',
    backgroundAsset: 'assets/themes/beige.png',
    textColor: Color(0xFF23321F),
    titleColor: Color(0xFF3E5C33),
    verseNumColor: Color(0xFF527A44),
    accentColor: Color(0xFF3E5C33),
    highlightRef: Color(0xFF8B6F1F),
  ),
  BibleTheme(
    id: 'desert',
    name: 'Désert',
    backgroundAsset: 'assets/themes/sable_gris.png',
    textColor: Color(0xFF3B2E1E),
    titleColor: Color(0xFF8A5A2B),
    verseNumColor: Color(0xFFC0813A),
    accentColor: Color(0xFF8A5A2B),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'nuit',
    name: 'Nuit étoilée',
    backgroundAsset: 'assets/themes/bleu.png',
    textColor: Color(0xFFE6ECF5),
    titleColor: Color(0xFFC9D6F0),
    verseNumColor: Color(0xFF9FB6E8),
    accentColor: Color(0xFF7FA0E0),
    highlightRef: Color(0xFFD4AF37),
  ),
];

/// Returns [themes] background options (all 10 fonds) for free selection.
const List<String> backgroundAssets = [
  'assets/themes/assyriens.png',
  'assets/themes/beige.png',
  'assets/themes/bg.png',
  'assets/themes/blanc.png',
  'assets/themes/bleu.png',
  'assets/themes/bois.png',
  'assets/themes/chocolat.png',
  'assets/themes/gris.png',
  'assets/themes/metal.png',
  'assets/themes/sable_gris.png',
];

BibleTheme themeById(String? id) {
  final match =
      bibleThemes.where((t) => t.id == id).toList();
  return match.isEmpty ? bibleThemes.first : match.first;
}