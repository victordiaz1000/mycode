import 'package:flutter/material.dart';

/// `#fff3b0` → [Color]. Le fallback historique est l'ambre de la première
/// palette de surlignage : une valeur corrompue en base peint ambre plutôt
/// que de faire échouer le rendu du chapitre.
Color hexToColor(String hex) {
  final v = int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0xFFF3B0;
  return Color(0xFF000000 | v);
}
