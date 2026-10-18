import 'package:flutter/material.dart';

import '../../domain/settings/preferences.dart';
import 'settings_choice_tile.dart';
import 'settings_section.dart';

class SettingsAppearanceSection extends StatelessWidget {
  const SettingsAppearanceSection({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.supportsDynamicColour,
  });

  final Preferences preferences;
  final Future<void> Function(Preferences) onChanged;
  final bool supportsDynamicColour;

  @override
  Widget build(BuildContext context) => SettingsSection(
    label: '外观',
    children: [
      SettingsChoiceTile<AppThemeMode>(
        title: '主题',
        sheetTitle: '选择主题',
        leadingIcon: Icons.palette_outlined,
        current: preferences.theme,
        values: AppThemeMode.values,
        label: _themeLabel,
        icon: (mode) => switch (mode) {
          AppThemeMode.system => Icons.brightness_auto_outlined,
          AppThemeMode.light => Icons.light_mode_outlined,
          AppThemeMode.dark => Icons.dark_mode_outlined,
        },
        onSelected: (mode) => onChanged(preferences.copyWith(theme: mode)),
      ),
      if (supportsDynamicColour)
        SwitchListTile(
          secondary: settingsLeading(context, Icons.color_lens_outlined),
          title: const Text('系统动态配色'),
          subtitle: const Text('使用系统壁纸提供的主题颜色'),
          value: preferences.dynamicColour,
          onChanged: (value) =>
              onChanged(preferences.copyWith(dynamicColour: value)),
        ),
    ],
  );
}

String _themeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => '跟随系统',
  AppThemeMode.light => '浅色',
  AppThemeMode.dark => '深色',
};
