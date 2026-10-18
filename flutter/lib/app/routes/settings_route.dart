import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/settings_page.dart';
import '../providers.dart';

class SettingsRoute extends ConsumerWidget {
  const SettingsRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final preferences = ref.watch(preferencesProvider);

    return SettingsPage(
      preferences: preferences.value,
      onChanged: ref.read(preferencesProvider.notifier).save,
      onClearCache: services.clearCache,
      onClearHistory: services.history.clear,
      version: services.version,
      supportsDynamicColour: Platform.isAndroid,
      wifiPolicyDescription: Platform.isIOS
          ? '对新任务禁用蜂窝网络，其他非蜂窝连接仍可使用'
          : '仅影响之后创建的任务',
      persistenceError: preferences.error,
      onRetrySave: ref.read(preferencesProvider.notifier).retry,
    );
  }
}
