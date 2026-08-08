import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: Center(
        child: Text(
          'Catalogue, version & lexique par défaut (à venir)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
