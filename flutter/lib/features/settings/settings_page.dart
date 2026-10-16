import 'package:flutter/material.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/settings/preferences.dart';

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
    this.wifiPolicyDescription = '仅影响之后创建的任务',
  });
  final Preferences preferences;
  final Future<void> Function(Preferences) onChanged;
  final Future<void> Function() onClearCache;
  final Future<void> Function() onClearHistory;
  final String version;
  final bool supportsDynamicColour;
  final String? persistenceError;
  final String wifiPolicyDescription;

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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 88 : 64,
      title: const Text('设置'),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (persistenceError case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '设置暂未保存：$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        _section(context, '外观', [
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题'),
            subtitle: Text(switch (preferences.theme) {
              AppThemeMode.system => '跟随系统',
              AppThemeMode.light => '浅色',
              AppThemeMode.dark => '深色',
            }),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final mode = await showModalBottomSheet<AppThemeMode>(
                context: context,
                showDragHandle: true,
                useSafeArea: true,
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final mode in AppThemeMode.values)
                      ListTile(
                        title: Text(switch (mode) {
                          AppThemeMode.system => '跟随系统',
                          AppThemeMode.light => '浅色',
                          AppThemeMode.dark => '深色',
                        }),
                        trailing: preferences.theme == mode
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, mode),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
              if (mode != null) {
                await onChanged(preferences.copyWith(theme: mode));
              }
            },
          ),
          if (supportsDynamicColour)
            SwitchListTile(
              title: const Text('系统动态配色'),
              subtitle: const Text('使用系统壁纸提供的主题颜色'),
              value: preferences.dynamicColour,
              onChanged: (value) =>
                  onChanged(preferences.copyWith(dynamicColour: value)),
            ),
        ]),
        _section(context, '播放', [
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('默认清晰度'),
            subtitle: Text(preferences.quality.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final quality = await showModalBottomSheet<VideoQuality>(
                context: context,
                showDragHandle: true,
                useSafeArea: true,
                builder: (context) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final quality in VideoQuality.values)
                      ListTile(
                        title: Text(quality.label),
                        trailing: preferences.quality == quality
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, quality),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              );
              if (quality != null) {
                await onChanged(preferences.copyWith(quality: quality));
              }
            },
          ),
        ]),
        _section(context, '下载与存储', [
          SwitchListTile(
            title: const Text('仅 Wi-Fi 下载'),
            subtitle: Text(wifiPolicyDescription),
            value: preferences.wifiOnly,
            onChanged: (value) =>
                onChanged(preferences.copyWith(wifiOnly: value)),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('清理缓存'),
            subtitle: const Text('清理栏目和图片缓存，保留收藏、观看记录与下载文件'),
            onTap: () =>
                _clear(context, '清理缓存', '下次浏览时会重新获取栏目和图片。', onClearCache),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('清空观看记录'),
            onTap: () =>
                _clear(context, '清空观看记录', '所有本机观看记录和续播位置都会移除。', onClearHistory),
          ),
        ]),
        _section(context, '关于', [
          const ListTile(
            leading: Icon(Icons.live_tv_rounded),
            title: Text('蜀台回看'),
            subtitle: Text('sctv-dl · Flutter'),
          ),
          ListTile(title: const Text('版本'), subtitle: Text(version)),
        ]),
      ],
    ),
  );

  Widget _section(BuildContext context, String label, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Card(child: Column(children: children)),
          ],
        ),
      );
}
