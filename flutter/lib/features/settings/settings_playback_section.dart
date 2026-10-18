import 'package:flutter/material.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/settings/preferences.dart';
import 'settings_choice_tile.dart';
import 'settings_section.dart';

class SettingsPlaybackSection extends StatelessWidget {
  const SettingsPlaybackSection({
    super.key,
    required this.preferences,
    required this.onChanged,
  });

  final Preferences preferences;
  final Future<void> Function(Preferences) onChanged;

  @override
  Widget build(BuildContext context) => SettingsSection(
    label: '播放',
    children: [
      SettingsChoiceTile<VideoQuality>(
        title: '默认清晰度',
        sheetTitle: '默认清晰度',
        leadingIcon: Icons.high_quality_outlined,
        current: preferences.quality,
        values: VideoQuality.values,
        label: (quality) => quality.label,
        icon: (quality) => quality == VideoQuality.standard
            ? Icons.high_quality_outlined
            : Icons.data_saver_off_rounded,
        onSelected: (quality) =>
            onChanged(preferences.copyWith(quality: quality)),
      ),
    ],
  );
}
