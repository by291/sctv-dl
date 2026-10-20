import 'package:flutter/material.dart';

import 'ios_glass_surface.dart';
import 'primary_page_scaffold.dart';

class AdaptiveActionBar extends StatelessWidget {
  const AdaptiveActionBar({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: padding,
      child: usesIosGlass(context)
          ? IosGlassSurface(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: child,
              ),
            )
          : child,
    ),
  );
}
