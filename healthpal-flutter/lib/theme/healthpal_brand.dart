import 'package:flutter/material.dart';

class HealthPalLogo extends StatelessWidget {
  const HealthPalLogo({super.key, this.size = 42, this.borderRadius = 14});

  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        'assets/icon_app.png',
        key: const Key('healthpal-logo'),
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
