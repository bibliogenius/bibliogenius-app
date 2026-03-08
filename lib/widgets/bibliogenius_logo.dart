import 'package:flutter/material.dart';

class BiblioGeniusLogo extends StatelessWidget {
  final double size;
  final Color color;

  const BiblioGeniusLogo({
    super.key,
    this.size = 24.0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logo_white.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
  }
}
