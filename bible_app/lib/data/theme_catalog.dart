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
    id: 'papyrus',
    name: 'Papyrus',
    backgroundAsset: 'assets/themes/blanc.png',
    textColor: Color(0xFF3D2C1B),
    titleColor: Color(0xFF6B4F32),
    verseNumColor: Color(0xFF8B6D3F),
    accentColor: Color(0xFF9C7A4D),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'sepia',
    name: 'Sépia',
    backgroundAsset: 'assets/themes/chocolat.png',
    textColor: Color(0xFF2E200F),
    titleColor: Color(0xFF5B3E22),
    verseNumColor: Color(0xFF7F5A31),
    accentColor: Color(0xFF8A6A3A),
    highlightRef: Color(0xFFB8860B),
  ),
  BibleTheme(
    id: 'forest',
    name: 'Forêt',
    backgroundAsset: 'assets/themes/bois.png',
    textColor: Color(0xFF23321F),
    titleColor: Color(0xFF33543A),
    verseNumColor: Color(0xFF49724F),
    accentColor: Color(0xFF3E5C33),
    highlightRef: Color(0xFF8B6F1F),
  ),
  BibleTheme(
    id: 'minimal',
    name: 'Minimal',
    backgroundAsset: '',
    textColor: Color(0xFF111111),
    titleColor: Color(0xFF222222),
    verseNumColor: Color(0xFF666666),
    accentColor: Color(0xFF0A84FF),
    highlightRef: Color(0xFFD4AF37),
  ),
  BibleTheme(
    id: 'removed_nocturne',
    name: 'REMOVED',
    backgroundAsset: '',
    textColor: Color(0xFF000000),
    titleColor: Color(0xFF000000),
    verseNumColor: Color(0xFF000000),
    accentColor: Color(0xFF000000),
    highlightRef: Color(0xFF000000),
  ),
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
    id: 'beige',
    name: 'Beige',
    backgroundAsset: 'assets/themes/beige.png',
    textColor: Color(0xFF322715),
    titleColor: Color(0xFF5A4A2C),
    verseNumColor: Color(0xFF7A6440),
    accentColor: Color(0xFF8A6C3A),
    highlightRef: Color(0xFFB28617),
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
    id: 'removed_nuit',
    name: 'REMOVED',
    backgroundAsset: '',
    textColor: Color(0xFF000000),
    titleColor: Color(0xFF000000),
    verseNumColor: Color(0xFF000000),
    accentColor: Color(0xFF000000),
    highlightRef: Color(0xFF000000),
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