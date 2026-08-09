import 'dart:async';

import 'package:flutter/material.dart';

/// Full-screen brand image shown at launch, then replaced by [child].
///
/// `assets/brand/splash.png` is the écran de démarrage from `logobym/`. The
/// [duration] is the minimum time it stays on screen ; the real boot continues
/// underneath (tabs, preferences, library) so the transition never feels early.
class SplashScreen extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const SplashScreen({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2200),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (!mounted) return;
      setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Scaffold(
      body: ColoredBox(
        color: Colors.white,
        child: Image.asset(
          'assets/brand/splash.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}