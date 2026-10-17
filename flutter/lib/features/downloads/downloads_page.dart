import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/cover_image.dart';
import '../../design/state_panel.dart';
import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import 'download_management.dart';

enum _BatchPhase { idle, confirming, running }

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
  final _selected = <String>{};
  DownloadFilter _filter = DownloadFilter.all;
  bool _selecting = false;
  _BatchPhase _batchPhase = _BatchPhase.idle;
  bool get _batchBusy => _batchPhase != _BatchPhase.idle;

  void _leaveSelection() {
    if (_batchBusy) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelection(DownloadTask task) {
    if (_batchBusy) return;
    setState(() {
      _selecting = true;
      if (!_selected.add(task.id)) _selected.remove(task.id);
    });
  }

  Future<bool> _confirmBatch(
    DownloadAction action,
    List<DownloadTask> tasks,
  ) async {
    final (title, message, confirm) = switch (action) {
      DownloadAction.deleteFile => (
        '删除 ${tasks.length} 个视频文件？',
        '将删除本地视频文件，保留下载记录。之后需要重新下载才能离线观看。',
        '删除文件',
      ),
      DownloadAction.remove => (
        '移除 ${tasks.length} 条下载记录？',
        tasks.any((task) => task.state == DownloadState.completed)
            ? '仅移除下载记录，已下载的视频文件会保留。'
            : '将从下载列表移除所选记录。',
        '移除记录',
      ),
      DownloadAction.cancel => (
        '取消 ${tasks.length} 项下载？',
        '将停止所选下载并清理未完成的文件。',
        '取消下载',
      ),
      _ => ('', '', ''),
    };
    if (title.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _runBatch(
    DownloadAction action,
    List<DownloadTask> selected,
  ) async {
    if (_batchBusy || _pending.isNotEmpty) return;
    final targets = selected.where(action.supports).toList();
    if (targets.isEmpty) return;
    setState(() => _batchPhase = _BatchPhase.confirming);
    try {
      if (!await _confirmBatch(action, targets) || !mounted) return;
      setState(() => _batchPhase = _BatchPhase.running);
      final result = await runDownloadBatch(widget.repository, action, targets);
      if (!mounted) return;
      setState(() {
        _selected.removeAll(result.succeeded);
        _selected.removeAll(result.skipped);
      });
      final details = [
        '${action.label}：已处理 ${result.succeeded.length} 项',
        if (result.skipped.isNotEmpty) '${result.skipped.length} 项状态已变化，已跳过',
        if (result.failures.isNotEmpty)
          '${result.failures.length} 项失败，可重新选择操作：${result.failures.values.first}',
      ];
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(details.join('；'))));
    } finally {
      if (mounted) setState(() => _batchPhase = _BatchPhase.idle);
    }
  }

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
  Widget build(BuildContext context) => StreamBuilder<List<DownloadTask>>(
    stream: _tasks,
    builder: (context, snapshot) {
      final tasks = snapshot.data ?? const <DownloadTask>[];
      final visible = tasks.where(_filter.includes).toList();
      if (snapshot.hasData && !snapshot.hasError) {
        _selected.retainAll(visible.map((task) => task.id));
      }
      final selected = visible
          .where((task) => _selected.contains(task.id))
          .toList();
      final ready = snapshot.hasData && !snapshot.hasError;
      final batchEnabled =
          ready &&
          selected.isNotEmpty &&
          !_batchBusy &&
          _pending.isEmpty &&
          DownloadAction.values.any((action) => selected.any(action.supports));
      final batchColour = batchEnabled
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurface.withValues(alpha: .38);
      return PopScope(
        canPop: !_selecting,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leaveSelection();
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? 88
                : 64,
            leading: _selecting
                ? IconButton(
                    tooltip: '退出批量管理',
                    onPressed: _batchBusy ? null : _leaveSelection,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: Text(_selecting ? '已选择 ${selected.length} 项' : '下载'),
            actions: [
              if (!_selecting)
                IconButton(
                  tooltip: '批量管理',
                  onPressed: ready && tasks.isNotEmpty && _pending.isEmpty
                      ? () => setState(() => _selecting = true)
                      : null,
                  icon: const Icon(Icons.checklist_rounded),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          for (final filter in DownloadFilter.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                key: ValueKey('download-filter-${filter.name}'),
                                label: Text(
                                  '${filter.label} ${tasks.where(filter.includes).length}',
                                ),
                                selected: _filter == filter,
                                onSelected: _batchBusy
                                    ? null
                                    : (_) => setState(() {
                                        _filter = filter;
                                        _selected.clear();
                                      }),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_selecting)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextButton.icon(
                            onPressed: !ready || visible.isEmpty || _batchBusy
                                ? null
                                : () => setState(() {
                                    if (selected.length == visible.length) {
                                      _selected.clear();
                                    } else {
                                      _selected.addAll(
                                        visible.map((task) => task.id),
                                      );
                                    }
                                  }),
                            icon: Icon(
                              selected.isNotEmpty &&
                                      selected.length == visible.length
                                  ? Icons.deselect
                                  : Icons.select_all,
                            ),
                            label: Text(
                              selected.isNotEmpty &&
                                      selected.length == visible.length
                                  ? '取消全选'
                                  : '全选当前列表',
                            ),
                          ),
                        ),
                      ),
                    Expanded(child: _taskList(snapshot, visible)),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: _selecting
              ? SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _batchPhase == _BatchPhase.running
                                ? '正在处理…'
                                : '仅操作所选任务',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (_batchPhase == _BatchPhase.running)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        PopupMenuButton<DownloadAction>(
                          tooltip: '批量操作',
                          enabled: batchEnabled,
                          onSelected: (action) =>
                              unawaited(_runBatch(action, selected)),
                          itemBuilder: (context) => [
                            for (final action in DownloadAction.values)
                              if (selected.any(action.supports))
                                PopupMenuItem(
                                  value: action,
                                  child: Text(
                                    '${action.label} · ${selected.where(action.supports).length}',
                                  ),
                                ),
                          ],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tune_rounded, color: batchColour),
                                const SizedBox(width: 8),
                                Text(
                                  '批量操作',
                                  style: Theme.of(context).textTheme.labelLarge
                                      ?.copyWith(color: batchColour),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        ),
      );
    },
  );

  Widget _taskList(
    AsyncSnapshot<List<DownloadTask>> snapshot,
    List<DownloadTask> visible,
  ) {
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
    final empty = snapshot.data!.isEmpty && _filter == DownloadFilter.all;
    return RefreshIndicator(
      onRefresh: () => _perform('refresh', widget.repository.reconcile),
      child: ListView(
        key: PageStorageKey('downloads-${_filter.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (visible.isEmpty)
            StatePanel(
              title: empty ? '还没有下载任务' : '没有符合筛选的任务',
              message: empty ? '在节目回看中选择视频下载，随时离线观看。' : '可以切换其他筛选查看下载记录。',
              icon: Icons.download_outlined,
            ),
          for (final filter in DownloadFilter.values.where(
            (value) => value != DownloadFilter.all,
          ))
            if (visible.any(filter.includes)) ...[
              _section(
                filter == DownloadFilter.active ? '进行中' : filter.label,
                visible.where(filter.includes).length,
              ),
              ...visible.where(filter.includes).map(_tile),
            ],
        ],
      ),
    );
  }

  Widget _state(Widget child) => CustomScrollView(
    slivers: [SliverFillRemaining(hasScrollBody: false, child: child)],
  );

  Widget _section(String title, int count) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
    child: Text(
      '$title · $count',
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );

  Widget _tile(DownloadTask task) {
    final busy = _pending.contains(task.id) || _batchBusy || _selecting;
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onLongPress: _batchBusy || _pending.isNotEmpty
            ? null
            : () => _toggleSelection(task),
        onTap: _selecting && !_batchBusy ? () => _toggleSelection(task) : null,
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
                  if (actions.isNotEmpty || _pending.contains(task.id))
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ...actions,
                        if (_pending.contains(task.id))
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
    child: _selecting
        ? Semantics(
            label: '选择 ${task.selection.content.title}',
            child: Checkbox(
              value: _selected.contains(task.id),
              onChanged: _batchBusy ? null : (_) => _toggleSelection(task),
            ),
          )
        : !task.isActive
        ? _fileMenu(task, busy)
        : null,
  );

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
