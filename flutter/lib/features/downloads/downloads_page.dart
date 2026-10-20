import 'dart:async';

import 'package:flutter/material.dart';

import '../../design/primary_page_scaffold.dart';
import '../../design/state_panel.dart';
import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import 'download_management.dart';
import 'download_task_card.dart';
import 'downloads_actions.dart';
import 'downloads_controller.dart';

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
  late DownloadsController _controller;

  DownloadsActions get _actions => DownloadsActions(
    controller: _controller,
    context: context,
    isMounted: () => mounted,
    onPlayLocal: widget.onPlayLocal,
  );

  @override
  void initState() {
    super.initState();

    _controller = DownloadsController(widget.repository);
    _tasks = _controller.watchTasks();
  }

  @override
  void didUpdateWidget(DownloadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.repository != widget.repository) {
      _controller.dispose();
      _controller = DownloadsController(widget.repository);
      _tasks = _controller.watchTasks();
    }
  }

  void _retryObservation() => setState(() => _tasks = _controller.watchTasks());

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => StreamBuilder<List<DownloadTask>>(
      stream: _tasks,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? const <DownloadTask>[];
        final visible = _controller.visibleTasks(tasks);
        final selected = visible
            .where((task) => _controller.selected.contains(task.id))
            .toList();

        final ready = snapshot.hasData && !snapshot.hasError;
        final batchEnabled =
            ready &&
            selected.isNotEmpty &&
            !_controller.batchBusy &&
            _controller.pending.isEmpty &&
            DownloadAction.values.any(
              (action) => selected.any(action.supports),
            );
        final batchColour = batchEnabled
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: .38);

        return PopScope(
          canPop: !_controller.selecting,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _controller.leaveSelection();
          },
          child: PrimaryPageScaffold(
            appBar: AppBar(
              toolbarHeight: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                  ? 88
                  : 64,
              leading: _controller.selecting
                  ? IconButton(
                      tooltip: '退出批量管理',
                      onPressed: _controller.batchBusy
                          ? null
                          : _controller.leaveSelection,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              title: Text(
                _controller.selecting ? '已选择 ${selected.length} 项' : '下载',
              ),
              actions: [
                if (!_controller.selecting)
                  IconButton(
                    tooltip: '批量管理',
                    onPressed:
                        ready && tasks.isNotEmpty && _controller.pending.isEmpty
                        ? _controller.enterSelection
                        : null,
                    icon: const Icon(Icons.checklist_rounded),
                  ),
              ],
            ),
            bodyBuilder: (context, insets) => SafeArea(
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
                                  key: ValueKey(
                                    'download-filter-${filter.name}',
                                  ),
                                  label: Text(
                                    '${filter.label} ${tasks.where(filter.includes).length}',
                                  ),
                                  selected: _controller.filter == filter,
                                  onSelected: _controller.batchBusy
                                      ? null
                                      : (_) => _controller.changeFilter(filter),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_controller.selecting)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: TextButton.icon(
                              onPressed:
                                  !ready ||
                                      visible.isEmpty ||
                                      _controller.batchBusy
                                  ? null
                                  : () => _controller.toggleAll(visible),
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
            bottomNavigationBar: _controller.selecting
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
                              _controller.batchPhase ==
                                      DownloadBatchPhase.running
                                  ? '正在处理…'
                                  : '仅操作所选任务',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          if (_controller.batchPhase ==
                              DownloadBatchPhase.running)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          PopupMenuButton<DownloadAction>(
                            tooltip: '批量操作',
                            enabled: batchEnabled,
                            onSelected: (action) =>
                                unawaited(_actions.runBatch(action, selected)),
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
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
    ),
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

    final empty =
        snapshot.data!.isEmpty && _controller.filter == DownloadFilter.all;

    return RefreshIndicator(
      onRefresh: () => _actions.perform('refresh', widget.repository.reconcile),
      child: ListView(
        key: PageStorageKey('downloads-${_controller.filter.name}'),
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
              _section(filter.label, visible.where(filter.includes).length),
              ...visible.where(filter.includes).map(_taskCard),
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _taskCard(DownloadTask task) => DownloadTaskCard(
    key: ValueKey(task.id),
    task: task,
    pending: _controller.pending.contains(task.id),
    batchBusy: _controller.batchBusy,
    selecting: _controller.selecting,
    selected: _controller.selected.contains(task.id),
    canSelect: _controller.pending.isEmpty,
    wifiPolicyLabel: widget.wifiPolicyLabel,
    onToggleSelection: () => _controller.toggleSelection(task),
    onPlay: () =>
        unawaited(_actions.perform(task.id, () => _actions.play(task))),
    onPause: () => unawaited(
      _actions.perform(task.id, () => widget.repository.pause(task.id)),
    ),
    onResume: () => unawaited(
      _actions.perform(task.id, () => widget.repository.resume(task.id)),
    ),
    onCancel: () => unawaited(
      _actions.perform(task.id, () => widget.repository.cancel(task.id)),
    ),
    onPublish: () => unawaited(
      _actions.perform(task.id, () => widget.repository.publish(task.id)),
    ),
    onRetry: () => unawaited(
      _actions.perform(task.id, () => widget.repository.retry(task.id)),
    ),
    onFileAction: (action) => unawaited(
      _actions.perform(task.id, () => _actions.fileAction(action, task)),
    ),
  );
}
