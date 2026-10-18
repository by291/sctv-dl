import 'package:flutter/material.dart';

import '../../domain/settings/preferences.dart';
import 'settings_section.dart';

/// Owns download policy controls and confirmed destructive storage actions.
class SettingsStorageSection extends StatelessWidget {
  const SettingsStorageSection({
    super.key,
    required this.preferences,
    required this.onChanged,
    required this.onClearCache,
    required this.onClearHistory,
    required this.wifiPolicyDescription,
  });

  final Preferences preferences;
  final Future<void> Function(Preferences) onChanged;
  final Future<void> Function() onClearCache;
  final Future<void> Function() onClearHistory;
  final String wifiPolicyDescription;

  @override
  Widget build(BuildContext context) => SettingsSection(
    label: '下载与存储',
    children: [
      SwitchListTile(
        secondary: settingsLeading(context, Icons.wifi_rounded),
        title: const Text('仅 Wi-Fi 下载'),
        subtitle: Text(wifiPolicyDescription),
        value: preferences.wifiOnly,
        onChanged: (value) => onChanged(preferences.copyWith(wifiOnly: value)),
      ),
      ListTile(
        leading: settingsLeading(context, Icons.cleaning_services_outlined),
        title: const Text('清理缓存'),
        subtitle: const Text('保留收藏、观看记录与下载文件'),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _clear(context, '清理缓存', '下次浏览时会重新获取栏目和图片。', onClearCache),
      ),
      ListTile(
        leading: settingsLeading(context, Icons.history_rounded),
        title: const Text('清空观看记录'),
        subtitle: const Text('移除本机观看记录与续播位置'),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () =>
            _clear(context, '清空观看记录', '所有本机观看记录和续播位置都会移除。', onClearHistory),
      ),
    ],
  );

  Future<void> _clear(
    BuildContext context,
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await action();

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$title完成')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    }
  }
}
