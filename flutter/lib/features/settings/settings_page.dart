import 'package:flutter/material.dart';

import '../../domain/settings/preferences.dart';
import 'settings_appearance_section.dart';
import 'settings_playback_section.dart';
import 'settings_section.dart';
import 'settings_storage_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.onClearCache,
    required this.onClearHistory,
    required this.version,
    this.supportsDynamicColour = false,
    this.persistenceError,
    this.onRetrySave,
    this.wifiPolicyDescription = '仅影响之后创建的任务',
  });

  final Preferences preferences;
  final Future<void> Function(Preferences) onChanged;
  final Future<void> Function() onClearCache;
  final Future<void> Function() onClearHistory;
  final String version;
  final bool supportsDynamicColour;
  final String? persistenceError;
  final Future<void> Function()? onRetrySave;
  final String wifiPolicyDescription;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 88 : 64,
      title: const Text('设置'),
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListTileTheme(
            data: ListTileThemeData(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              minLeadingWidth: 24,
              horizontalTitleGap: 12,
              iconColor: Theme.of(context).iconTheme.color,
              titleTextStyle: Theme.of(context).textTheme.bodyLarge,
              subtitleTextStyle: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
            ),
            child: ListView(
              key: const PageStorageKey('settings'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (persistenceError case final error?)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '设置暂未保存：$error',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                        if (onRetrySave != null)
                          TextButton(
                            onPressed: onRetrySave,
                            child: const Text('重试保存'),
                          ),
                      ],
                    ),
                  ),
                SettingsAppearanceSection(
                  preferences: preferences,
                  onChanged: onChanged,
                  supportsDynamicColour: supportsDynamicColour,
                ),
                SettingsPlaybackSection(
                  preferences: preferences,
                  onChanged: onChanged,
                ),
                SettingsStorageSection(
                  preferences: preferences,
                  onChanged: onChanged,
                  onClearCache: onClearCache,
                  onClearHistory: onClearHistory,
                  wifiPolicyDescription: wifiPolicyDescription,
                ),
                SettingsSection(
                  label: '关于',
                  children: [
                    ListTile(
                      leading: settingsLeading(context, Icons.live_tv_rounded),
                      title: const Text('蜀台回看'),
                      subtitle: Text('版本 $version'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
