import 'package:flutter/material.dart';

class ThemesScreen extends StatelessWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Thèmes')),
      body: Center(
        child: Text(
          'Sélection des 10 fonds (à venir)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
    );
  }
}
