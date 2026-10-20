import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// A readable glass surface for floating action bars.
class IosGlassSurface extends StatelessWidget {
  const IosGlassSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GlassContainer(
      shape: const LiquidRoundedSuperellipse(borderRadius: 28),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      settings: LiquidGlassSettings(
        bodyMode: GlassBodyMode.clear,
        glassColor: theme.colorScheme.surface.withValues(alpha: 0.62),
        blur: 14,
        thickness: 20,
        refractiveIndex: 1.35,
        saturation: 0.8,
        chromaticAberration: 0,
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
