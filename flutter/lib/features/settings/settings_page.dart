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

  Future<void> _choose<T>(
    BuildContext context, {
    required String title,
    required T current,
    required List<T> values,
    required String Function(T) label,
    required IconData Function(T) icon,
    required Preferences Function(T) update,
  }) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              for (final value in values)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  selected: value == current,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  selectedColor: Theme.of(context)
                      .colorScheme
                      .onSecondaryContainer,
                  leading: _leading(context, icon(value)),
                  title: Text(label(value)),
                  trailing: value == current
                      ? const Icon(Icons.check_rounded)
                      : null,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await onChanged(update(selected));
  }

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
                    child: Text(
                      '设置暂未保存：$error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                _section(context, '外观', [
                  ListTile(
                    leading: _leading(context, Icons.palette_outlined),
                    title: const Text('主题'),
                    subtitle: Text(_themeLabel(preferences.theme)),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _choose<AppThemeMode>(
                      context,
                      title: '选择主题',
                      current: preferences.theme,
                      values: AppThemeMode.values,
                      label: _themeLabel,
                      icon: (mode) => switch (mode) {
                        AppThemeMode.system => Icons.brightness_auto_outlined,
                        AppThemeMode.light => Icons.light_mode_outlined,
                        AppThemeMode.dark => Icons.dark_mode_outlined,
                      },
                      update: (mode) => preferences.copyWith(theme: mode),
                    ),
                  ),
                  if (supportsDynamicColour)
                    SwitchListTile(
                      secondary: _leading(context, Icons.color_lens_outlined),
                      title: const Text('系统动态配色'),
                      subtitle: const Text('使用系统壁纸提供的主题颜色'),
                      value: preferences.dynamicColour,
                      onChanged: (value) =>
                          onChanged(preferences.copyWith(dynamicColour: value)),
                    ),
                ]),
                _section(context, '播放', [
                  ListTile(
                    leading: _leading(context, Icons.high_quality_outlined),
                    title: const Text('默认清晰度'),
                    subtitle: Text(preferences.quality.label),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _choose<VideoQuality>(
                      context,
                      title: '默认清晰度',
                      current: preferences.quality,
                      values: VideoQuality.values,
                      label: (quality) => quality.label,
                      icon: (quality) => quality == VideoQuality.standard
                          ? Icons.high_quality_outlined
                          : Icons.data_saver_off_rounded,
                      update: (quality) =>
                          preferences.copyWith(quality: quality),
                    ),
                  ),
                ]),
                _section(context, '下载与存储', [
                  SwitchListTile(
                    secondary: _leading(context, Icons.wifi_rounded),
                    title: const Text('仅 Wi-Fi 下载'),
                    subtitle: Text(wifiPolicyDescription),
                    value: preferences.wifiOnly,
                    onChanged: (value) =>
                        onChanged(preferences.copyWith(wifiOnly: value)),
                  ),
                  ListTile(
                    leading: _leading(
                      context,
                      Icons.cleaning_services_outlined,
                    ),
                    title: const Text('清理缓存'),
                    subtitle: const Text('保留收藏、观看记录与下载文件'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _clear(
                      context,
                      '清理缓存',
                      '下次浏览时会重新获取栏目和图片。',
                      onClearCache,
                    ),
                  ),
                  ListTile(
                    leading: _leading(context, Icons.history_rounded),
                    title: const Text('清空观看记录'),
                    subtitle: const Text('移除本机观看记录与续播位置'),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => _clear(
                      context,
                      '清空观看记录',
                      '所有本机观看记录和续播位置都会移除。',
                      onClearHistory,
                    ),
                  ),
                ]),
                _section(context, '关于', [
                  ListTile(
                    leading: _leading(context, Icons.live_tv_rounded),
                    title: const Text('蜀台回看'),
                    subtitle: Text('版本 $version'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget? _leading(BuildContext context, IconData icon) =>
      MediaQuery.textScalerOf(context).scale(1) >= 1.5
      ? null
      : Icon(icon, size: 24);

  Widget _section(BuildContext context, String label, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0)
                      Divider(
                        height: 1,
                        indent: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                            ? 16
                            : 52,
                        endIndent: 16,
                      ),
                    children[index],
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

String _themeLabel(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => '跟随系统',
  AppThemeMode.light => '浅色',
  AppThemeMode.dark => '深色',
};
