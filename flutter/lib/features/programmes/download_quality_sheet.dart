import 'package:flutter/material.dart';

import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';

Future<DownloadBatchResult?> showDownloadQualitySheet(
  BuildContext context, {
  required List<ProgrammeSelection> selections,
  required DownloadRepository downloads,
  required bool wifiOnly,
  String wifiPolicyLabel = '仅使用 Wi-Fi',
}) async {
  if (selections.isEmpty) return null;
  final options = <VideoQuality>{
    for (final selection in selections)
      for (final source in videoSources(selection.content)) source.quality,
  };
  final quality = await showModalBottomSheet<VideoQuality>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('下载清晰度', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('已选择 ${selections.length} 项节目'),
          if (selections.length > 1)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('缺少所选清晰度的节目将使用可用版本，文件名显示实际清晰度。'),
            ),
          const SizedBox(height: 12),
          for (final option in VideoQuality.values)
            if (options.contains(option))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.download_outlined),
                title: Text(option.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, option),
              ),
          const SizedBox(height: 8),
          Text(
            wifiOnly ? '本次任务$wifiPolicyLabel' : '本次任务允许使用移动网络',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
  // Dismissing the chooser never creates a durable task or starts preflight.
  if (quality == null) return null;
  return downloads.start(selections, quality, wifiOnly: wifiOnly);
}

String downloadResultLabel(DownloadBatchResult result) {
  final parts = <String>['已加入 ${result.taskIds.length} 项'];
  if (result.duplicates > 0) parts.add('${result.duplicates} 项已在下载');
  if (result.fallbacks > 0) parts.add('${result.fallbacks} 项使用可用清晰度');
  if (result.failures.isNotEmpty) {
    parts.add('${result.failures.length} 项失败：${result.failures.first.message}');
  }
  return parts.join('，');
}
