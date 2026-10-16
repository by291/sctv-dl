import 'dart:async';

import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => SafeArea(
    child: StreamBuilder<List<DownloadTask>>(
      stream: _tasks,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  const Text('无法读取下载记录'),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: TextAlign.center),
                  TextButton(
                    onPressed: _retryObservation,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(semanticsLabel: '正在读取下载记录'),
          );
        }
        final tasks = snapshot.data!;
        if (tasks.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download_outlined, size: 48),
                  SizedBox(height: 16),
                  Text('还没有下载任务'),
                  SizedBox(height: 8),
                  Text('从栏目回看中选择视频，下载后可离线观看。', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        final active = tasks.where((task) => task.isActive).toList();
        final finished = tasks.where((task) => !task.isActive).toList();
        return RefreshIndicator(
          onRefresh: widget.repository.reconcile,
          child: ListView(
            key: const PageStorageKey('downloads'),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              const Text(
                '下载',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('传输由系统调度；返回应用时会核对任务与文件。'),
              if (active.isNotEmpty) ...[
                _section('进行中', active.length),
                ...active.map(_tile),
              ],
              if (finished.isNotEmpty) ...[
                _section('已结束', finished.length),
                ...finished.map(_tile),
              ],
            ],
          ),
        );
      },
    ),
  );
  Widget _section(String title, int count) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      '$title · $count',
      style: Theme.of(context).textTheme.titleMedium,
    ),
  );
  Widget _tile(DownloadTask task) {
    final busy = _pending.contains(task.id);
    final running = task.state == DownloadState.running;
    final total = task.totalBytes;
    final progress = total == null || total <= 0
        ? null
        : (task.receivedBytes / total).clamp(0.0, 1.0);
    return Card(
      key: ValueKey(task.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              task.selection.content.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${task.selection.programme.name} · ${task.selection.broadcast.date} · ${task.quality.label}',
            ),
            const SizedBox(height: 8),
            Text(
              '${_status(task.state)} · ${task.wifiOnly ? widget.wifiPolicyLabel : '允许蜂窝网络'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (task.isActive && task.state != DownloadState.finalizing) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                semanticsLabel: _status(task.state),
              ),
              const SizedBox(height: 6),
              Text(
                total == null
                    ? task.receivedBytes == 0
                          ? '大小未知'
                          : '${_bytes(task.receivedBytes)} · 大小未知'
                    : '${_bytes(task.receivedBytes)} / ${_bytes(total)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (task.state == DownloadState.completed) ...[
              const SizedBox(height: 6),
              Text(
                _bytes(task.receivedBytes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (task.error != null) ...[
              const SizedBox(height: 8),
              Text(
                task.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (task.state == DownloadState.completed)
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => unawaited(_perform(task.id, () => _play(task))),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('播放'),
                  ),
                if (running && task.canResume)
                  IconButton(
                    tooltip: '暂停',
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _perform(
                              task.id,
                              () => widget.repository.pause(task.id),
                            ),
                          ),
                    icon: const Icon(Icons.pause),
                  ),
                if (task.state == DownloadState.paused && task.canResume)
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _perform(
                              task.id,
                              () => widget.repository.resume(task.id),
                            ),
                          ),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('继续下载'),
                  ),
                if (task.isActive && task.state != DownloadState.finalizing)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _perform(
                              task.id,
                              () => widget.repository.cancel(task.id),
                            ),
                          ),
                    child: const Text('取消下载'),
                  ),
                if (task.state == DownloadState.finalizing &&
                    task.error != null)
                  TextButton.icon(
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            _perform(
                              task.id,
                              () => widget.repository.publish(task.id),
                            ),
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
                            _perform(
                              task.id,
                              () => widget.repository.retry(task.id),
                            ),
                          ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新下载'),
                  ),
                if (!task.isActive)
                  PopupMenuButton<String>(
                    tooltip: '文件操作',
                    enabled: !busy,
                    onSelected: (action) => unawaited(
                      _perform(task.id, () => _fileAction(action, task)),
                    ),
                    itemBuilder: (context) => [
                      if (task.state == DownloadState.completed) ...[
                        const PopupMenuItem(
                          value: 'open',
                          child: Text('使用其他应用打开'),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: Text('分享视频'),
                        ),
                        if (task.fileLocation?.startsWith('documents:') == true)
                          const PopupMenuItem(
                            value: 'export',
                            child: Text('存储到“文件”'),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除视频文件'),
                        ),
                      ],
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('移除记录（保留文件）'),
                      ),
                    ],
                  ),
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
      ),
    );
  }
}

String _status(DownloadState state) => switch (state) {
  DownloadState.preparing => '准备中',
  DownloadState.queued => '排队中',
  DownloadState.running => '正在下载',
  DownloadState.waiting => '等待系统或网络',
  DownloadState.paused => '已暂停',
  DownloadState.retrying => '等待自动重试',
  DownloadState.finalizing => '正在发布文件',
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
