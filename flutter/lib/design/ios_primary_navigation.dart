import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'theme.dart';

class IosPrimaryNavigation extends StatelessWidget {
  const IosPrimaryNavigation({
    super.key,
    required this.selectedIndex,
    required this.activeDownloads,
    required this.onSelected,
  });

  final int selectedIndex;
  final int activeDownloads;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    // Own the home-indicator inset here; the shell publishes the full
    // extent to retained pages so their last items can scroll clear of it.
    return SafeArea(
      top: false,
      child: Align(
        heightFactor: 1,
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassContentAwareBrightness(
            builder: (context, brightness, darkAmount) {
              final selected = Color.lerp(
                appPrimaryBlue,
                appPrimaryBlueOnDark,
                darkAmount,
              )!;
              final foreground = Color.lerp(
                const Color(0xFF303B49),
                const Color(0xFFF2F5FA),
                darkAmount,
              )!;

              // A light neutral tint softens mixed artwork without hiding the
              // backdrop; foreground contrast follows the sampled brightness.
              return GlassTabBar.bottom(
                selectedIndex: selectedIndex,
                onTabSelected: onSelected,
                verticalPadding: 8,
                settings: LiquidGlassSettings(
                  bodyMode: GlassBodyMode.clear,
                  glassColor: Color.lerp(
                    const Color(0x78F6F8FA),
                    const Color(0x78202832),
                    darkAmount,
                  )!,
                  blur: 7,
                  thickness: 26,
                  refractiveIndex: 1.5,
                  ambientStrength: 0.6,
                  saturation: 1,
                  chromaticAberration: 0.005,
                  lightIntensity: 0.6,
                ),
                magnification: 1.08,
                indicatorColor: selected.withValues(alpha: 0.16),
                selectedIconColor: selected,
                selectedLabelColor: selected,
                unselectedIconColor: foreground,
                unselectedLabelColor: foreground,
                tabs: [
                  const GlassTab(icon: Icon(CupertinoIcons.tv), label: '节目库'),
                  GlassTab(
                    icon: Badge(
                      isLabelVisible: activeDownloads > 0,
                      label: Text('$activeDownloads'),
                      child: const Icon(CupertinoIcons.arrow_down_circle),
                    ),
                    label: '下载',
                    semanticLabel: activeDownloads > 0
                        ? '下载，$activeDownloads 项进行中'
                        : '下载',
                  ),
                  const GlassTab(icon: Icon(CupertinoIcons.gear), label: '设置'),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
