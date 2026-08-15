import 'package:flutter/material.dart';

import '../data/theme_catalog.dart';
import '../data/app_preferences.dart';

/// Provides the currently-selected [BibleTheme] to the widget subtree.
class BibleThemeScope extends StatefulWidget {
  const BibleThemeScope({super.key, required this.child});

  final Widget child;

  @override
  State<BibleThemeScope> createState() => _BibleThemeScopeState();

  /// Public accessor to obtain the active `BibleTheme` from context.
  static BibleTheme of(BuildContext context) => _InheritedBibleTheme.of(context);
}

class _BibleThemeScopeState extends State<BibleThemeScope> {
  late String _themeId;

  @override
  void initState() {
    super.initState();
    _themeId = AppPreferences.themeNotifier.value;
    AppPreferences.themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppPreferences.themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {
      _themeId = AppPreferences.themeNotifier.value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = themeById(_themeId);
    return _InheritedBibleTheme(
      bibleTheme: theme,
      child: widget.child,
    );
  }
}

class _InheritedBibleTheme extends InheritedWidget {
  const _InheritedBibleTheme({required this.bibleTheme, required super.child});

  final BibleTheme bibleTheme;

  static BibleTheme of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<_InheritedBibleTheme>();
    return widget?.bibleTheme ?? bibleThemes.first;
  }

  @override
  bool updateShouldNotify(covariant _InheritedBibleTheme oldWidget) {
    return oldWidget.bibleTheme.id != bibleTheme.id;
  }
}
