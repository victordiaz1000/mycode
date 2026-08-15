import 'package:flutter/material.dart';

import '../widgets/premium_style.dart';

/// Réglages — destination de la coquille. Pour l'instant un panneau premium qui
/// annonce ce qui viendra (catalogue des versions, version & lexique par
/// défaut) sans prétendre être des réglages fonctionnels.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = premiumPalette(context);
    return Scaffold(
      backgroundColor: kPremiumBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: p.textDark,
        centerTitle: true,
        title: Text(
          'Réglages',
          style: premiumText(context, 18, FontWeight.w800, p.textDark),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: premiumShadow(
                  p.primaryDark,
                  opacity: 0.06,
                  blur: 18,
                  offset: const Offset(0, 8),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: p.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.tune, size: 30, color: p.primary),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Catalogue, version & lexique par défaut (à venir)',
                    textAlign: TextAlign.center,
                    style: premiumText(context, 17, FontWeight.w700, p.textDark),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Cette section prendra en charge le catalogue des versions '
                    'téléchargeables ainsi que la version de lecture et le '
                    'lexique appliqués par défaut.',
                    textAlign: TextAlign.center,
                    style: premiumText(context, 13, FontWeight.w500, p.textGrey, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}