import 'package:flutter/material.dart';

import '../../design/cover_image.dart';
import '../../domain/downloads/download_task.dart';

class DownloadTaskCard extends StatelessWidget {
  const DownloadTaskCard({
    super.key,
    required this.task,
    required this.pending,
    required this.batchBusy,
    required this.selecting,
    required this.selected,
    required this.canSelect,
    required this.wifiPolicyLabel,
    required this.onToggleSelection,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onPublish,
    required this.onRetry,
    required this.onFileAction,
  });

  final DownloadTask task;
  final bool pending;
  final bool batchBusy;
  final bool selecting;
  final bool selected;
  final bool canSelect;
  final String wifiPolicyLabel;

  final VoidCallback onToggleSelection;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onPublish;
  final VoidCallback onRetry;
  final ValueChanged<String> onFileAction;

  @override
  Widget build(BuildContext context) {
    final busy = pending || batchBusy || selecting;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final status = task.state == DownloadState.finalizing && task.error != null
        ? '文件保存失败'
        : _status(task.state);
    final statusColour =
        (task.error != null && task.state != DownloadState.missing) ||
            task.state == DownloadState.failed
        ? theme.colorScheme.error
        : task.state == DownloadState.completed ||
              task.state == DownloadState.running
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final total = task.totalBytes;
    final progress = total == null || total <= 0
        ? null
        : (task.receivedBytes / total).clamp(0.0, 1.0);
    final actions = _taskActions(task, busy);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: batchBusy || !canSelect ? null : onToggleSelection,
        onTap: selecting && !batchBusy ? onToggleSelection : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _taskHeader(context, task, busy),
              if (task.isActive && task.state != DownloadState.finalizing) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  semanticsLabel: status,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      total == null || total <= 0
                          ? task.receivedBytes == 0
                                ? '大小未知'
                                : '${_bytes(task.receivedBytes)} · 大小未知'
                          : '${_bytes(task.receivedBytes)} / ${_bytes(total)}',
                      style: muted,
                    ),
                    Text(
                      task.wifiOnly ? wifiPolicyLabel : '允许蜂窝网络',
                      style: muted,
                    ),
                  ],
                ),
              ],
              if (task.error != null &&
                  task.state != DownloadState.missing) ...[
                const SizedBox(height: 8),
                Text(
                  task.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _statusIcon(task.state),
                              size: 16,
                              color: statusColour,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                status,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: statusColour,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (task.state == DownloadState.completed)
                          Text('· ${_bytes(task.receivedBytes)}', style: muted),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty || pending)
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...actions,
                        if (pending)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskHeader(BuildContext context, DownloadTask task, bool busy) {
    final theme = Theme.of(context);
    final selection = task.selection;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final contentCover = selection.content.cover;

    final cover = SizedBox(
      width: largeText ? 104 : 88,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CoverImage(
          url: contentCover != null && contentCover.trim().isNotEmpty
              ? contentCover
              : selection.programme.cover,
        ),
      ),
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selection.content.title,
          maxLines: largeText ? null : 3,
          overflow: largeText ? null : TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(
          '${selection.programme.name} · ${selection.broadcast.date} · ${task.quality.label}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (largeText) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [cover, const Spacer(), _taskTrailing(task, busy)]),
          const SizedBox(height: 12),
          details,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cover,
        const SizedBox(width: 12),
        Expanded(child: details),
        _taskTrailing(task, busy),
      ],
    );
  }

  Widget _taskTrailing(DownloadTask task, bool busy) => SizedBox(
    width: 48,
    height: 48,
    child: selecting
        ? Semantics(
            label: '选择 ${task.selection.content.title}',
            child: Checkbox(
              value: selected,
              onChanged: batchBusy ? null : (_) => onToggleSelection(),
            ),
          )
        : !task.isActive
        ? _fileMenu(task, busy)
        : null,
  );

  List<Widget> _taskActions(DownloadTask task, bool busy) => [
    if (task.state == DownloadState.completed)
      TextButton.icon(
        onPressed: busy ? null : onPlay,
        icon: const Icon(Icons.play_arrow),
        label: const Text('播放'),
      ),
    if (task.state == DownloadState.running && task.canResume)
      TextButton.icon(
        onPressed: busy ? null : onPause,
        icon: const Icon(Icons.pause),
        label: const Text('暂停'),
      ),
    if (task.state == DownloadState.paused && task.canResume)
      TextButton.icon(
        onPressed: busy ? null : onResume,
        icon: const Icon(Icons.play_arrow),
        label: const Text('继续下载'),
      ),
    if (task.isActive && task.state != DownloadState.finalizing)
      TextButton(onPressed: busy ? null : onCancel, child: const Text('取消下载')),
    if (task.state == DownloadState.finalizing && task.error != null)
      TextButton.icon(
        onPressed: busy ? null : onPublish,
        icon: const Icon(Icons.publish),
        label: const Text('重试发布'),
      ),
    if ({
      DownloadState.failed,
      DownloadState.interrupted,
      DownloadState.missing,
      DownloadState.cancelled,
    }.contains(task.state))
      TextButton.icon(
        onPressed: busy ? null : onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重新下载'),
      ),
  ];

  Widget _fileMenu(DownloadTask task, bool busy) => PopupMenuButton<String>(
    tooltip: '文件操作',
    enabled: !busy,
    onSelected: onFileAction,
    itemBuilder: (context) => [
      if (task.state == DownloadState.completed) ...[
        const PopupMenuItem(value: 'open', child: Text('使用其他应用打开')),
        const PopupMenuItem(value: 'share', child: Text('分享视频')),
        if (task.fileLocation?.startsWith('documents:') == true)
          const PopupMenuItem(value: 'export', child: Text('存储到“文件”')),
        const PopupMenuItem(value: 'delete', child: Text('删除视频文件')),
      ],
      PopupMenuItem(
        value: 'remove',
        child: Text(
          task.state == DownloadState.completed ? '移除记录（保留文件）' : '移除记录',
        ),
      ),
    ],
  );
}

String _status(DownloadState state) => switch (state) {
  DownloadState.preparing => '准备中',
  DownloadState.queued => '排队中',
  DownloadState.running => '正在下载',
  DownloadState.waiting => '等待系统或网络',
  DownloadState.paused => '已暂停',
  DownloadState.retrying => '等待自动重试',
  DownloadState.finalizing => '正在保存文件',
  DownloadState.completed => '已完成',
  DownloadState.failed => '下载失败',
  DownloadState.cancelled => '已取消',
  DownloadState.interrupted => '下载已中断',
  DownloadState.missing => '文件已移除',
};

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  if (value < 1024 * 1024 * 1024) {
    return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

IconData _statusIcon(DownloadState state) => switch (state) {
  DownloadState.completed => Icons.check_circle_outline_rounded,
  DownloadState.running => Icons.downloading_rounded,
  DownloadState.paused => Icons.pause_circle_outline_rounded,
  DownloadState.failed ||
  DownloadState.interrupted => Icons.error_outline_rounded,
  DownloadState.missing => Icons.folder_off_outlined,
  DownloadState.cancelled => Icons.cancel_outlined,
  DownloadState.finalizing => Icons.save_outlined,
  _ => Icons.schedule_rounded,
};
