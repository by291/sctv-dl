import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/cover_image.dart';
import '../../design/state_panel.dart';
import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({
    super.key,
    required this.repository,
    required this.onPlayLocal,
    this.wifiPolicyLabel = '仅 Wi-Fi（iOS：禁用蜂窝网络）',
  });
  final DownloadRepository repository;
  final void Function(DownloadTask task) onPlayLocal;
  final String wifiPolicyLabel;

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  late Stream<List<DownloadTask>> _tasks;
  final _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _tasks = widget.repository.watchTasks();
  }

  @override
  void didUpdateWidget(DownloadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      _tasks = widget.repository.watchTasks();
    }
  }

  void _retryObservation() =>
      setState(() => _tasks = widget.repository.watchTasks());
  Future<void> _perform(String id, Future<void> Function() action) async {
    if (!_pending.add(id)) return;
    setState(() {});
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _pending.remove(id));
    }
  }

  Future<void> _play(DownloadTask task) async {
    await widget.repository.reconcile();
    final current = (await widget.repository.loadTasks())
        .where((value) => value.id == task.id)
        .firstOrNull;
    if (current == null ||
        current.state != DownloadState.completed ||
        current.fileLocation == null) {
      throw StateError('文件已不可用，请重新下载');
    }
    if (mounted) widget.onPlayLocal(current);
  }

  Future<void> _delete(DownloadTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除视频文件？'),
        content: Text('将删除“${task.selection.content.title}”的本地视频，保留下载记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除文件'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.repository.deleteFile(task.id);
  }

  Future<void> _fileAction(String action, DownloadTask task) async {
    switch (action) {
      case 'open':
        await widget.repository.openFile(task.id);
      case 'share':
        await widget.repository.shareFile(task.id);
      case 'export':
        final exported = await widget.repository.exportFile(task.id);
        if (exported && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('视频已导出')));
        }
      case 'delete':
        await _delete(task);
      case 'remove':
        await widget.repository.remove(task.id);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5 ? 88 : 64,
      title: const Text('下载'),
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: StreamBuilder<List<DownloadTask>>(
            stream: _tasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _state(
                  StatePanel(
                    title: '无法读取下载记录',
                    message: '${snapshot.error}',
                    icon: Icons.cloud_off_outlined,
                    onAction: _retryObservation,
                  ),
                );
              }
              if (!snapshot.hasData) return const PageSkeleton(count: 3);
              final tasks = snapshot.data!;
              if (tasks.isEmpty) {
                return _state(
                  const StatePanel(
                    title: '还没有下载任务',
                    message: '在节目回看中选择视频下载，随时离线观看。',
                    icon: Icons.download_outlined,
                  ),
                );
              }
              final active = tasks
                  .where((task) => task.isActive && !_needsAttention(task))
                  .toList();
              final completed = tasks
                  .where((task) => task.state == DownloadState.completed)
                  .toList();
              final unfinished = tasks.where(_needsAttention).toList();
              final removed = tasks
                  .where((task) => task.state == DownloadState.missing)
                  .toList();
              return RefreshIndicator(
                onRefresh: () =>
                    _perform('refresh', widget.repository.reconcile),
                child: ListView(
                  key: const PageStorageKey('downloads'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    if (active.isNotEmpty) ...[
                      _section('进行中', active.length),
                      ...active.map(_tile),
                    ],
                    if (unfinished.isNotEmpty) ...[
                      _section('未完成', unfinished.length),
                      ...unfinished.map(_tile),
                    ],
                    if (completed.isNotEmpty) ...[
                      _section('已完成', completed.length),
                      ...completed.map(_tile),
                    ],
                    if (removed.isNotEmpty) ...[
                      _section('已移除', removed.length),
                      ...removed.map(_tile),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _state(Widget child) => CustomScrollView(
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );

  bool _needsAttention(DownloadTask task) =>
      (!task.isActive &&
          task.state != DownloadState.completed &&
          task.state != DownloadState.missing) ||
      (task.state == DownloadState.finalizing && task.error != null);

  Widget _section(String title, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
    child: Text(
      '$title · $count',
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _tile(DownloadTask task) {
    final busy = _pending.contains(task.id);
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
      key: ValueKey(task.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _taskHeader(task, busy),
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
                    task.wifiOnly ? widget.wifiPolicyLabel : '允许蜂窝网络',
                    style: muted,
                  ),
                ],
              ),
            ],
            if (task.error != null && task.state != DownloadState.missing) ...[
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
                if (actions.isNotEmpty || busy)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 4,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...actions,
                      if (busy)
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
    );
  }

  Widget _taskHeader(DownloadTask task, bool busy) {
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
          Row(
            children: [
              cover,
              const Spacer(),
              if (!task.isActive) _fileMenu(task, busy),
            ],
          ),
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
        if (!task.isActive) _fileMenu(task, busy),
      ],
    );
  }

  List<Widget> _taskActions(DownloadTask task, bool busy) => [
    if (task.state == DownloadState.completed)
      TextButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(_perform(task.id, () => _play(task))),
        icon: const Icon(Icons.play_arrow),
        label: const Text('播放'),
      ),
    if (task.state == DownloadState.running && task.canResume)
      TextButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(
                _perform(task.id, () => widget.repository.pause(task.id)),
              ),
        icon: const Icon(Icons.pause),
        label: const Text('暂停'),
      ),
    if (task.state == DownloadState.paused && task.canResume)
      TextButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(
                _perform(task.id, () => widget.repository.resume(task.id)),
              ),
        icon: const Icon(Icons.play_arrow),
        label: const Text('继续下载'),
      ),
    if (task.isActive && task.state != DownloadState.finalizing)
      TextButton(
        onPressed: busy
            ? null
            : () => unawaited(
                _perform(task.id, () => widget.repository.cancel(task.id)),
              ),
        child: const Text('取消下载'),
      ),
    if (task.state == DownloadState.finalizing && task.error != null)
      TextButton.icon(
        onPressed: busy
            ? null
            : () => unawaited(
                _perform(task.id, () => widget.repository.publish(task.id)),
              ),
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
        onPressed: busy
            ? null
            : () => unawaited(
                _perform(task.id, () => widget.repository.retry(task.id)),
              ),
        icon: const Icon(Icons.refresh),
        label: const Text('重新下载'),
      ),
  ];

  Widget _fileMenu(DownloadTask task, bool busy) => PopupMenuButton<String>(
    tooltip: '文件操作',
    enabled: !busy,
    onSelected: (action) =>
        unawaited(_perform(task.id, () => _fileAction(action, task))),
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
