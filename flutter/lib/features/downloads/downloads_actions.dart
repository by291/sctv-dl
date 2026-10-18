import 'package:flutter/material.dart';

import '../../domain/downloads/download_task.dart';
import 'download_management.dart';
import 'downloads_controller.dart';

/// Dialogs and feedback belong to the page lifetime; durable file effects stay
/// with the repository even if a dialog's page is removed while it is open.
class DownloadsActions {
  DownloadsActions({
    required this.controller,
    required this.context,
    required this.isMounted,
    required this.onPlayLocal,
  });

  final DownloadsController controller;
  final BuildContext context;
  final bool Function() isMounted;
  final ValueChanged<DownloadTask> onPlayLocal;

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

  Future<void> runBatch(
    DownloadAction action,
    List<DownloadTask> selected,
  ) async {
    final result = await controller.runBatch(
      action,
      selected,
      (targets) => _confirmBatch(action, targets),
    );
    if (result == null || !isMounted() || !context.mounted) return;

    final details = [
      '${action.label}：已处理 ${result.succeeded.length} 项',
      if (result.skipped.isNotEmpty) '${result.skipped.length} 项状态已变化，已跳过',
      if (result.failures.isNotEmpty)
        '${result.failures.length} 项失败，可重新选择操作：${result.failures.values.first}',
    ];

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(details.join('；'))));
  }

  Future<void> perform(String id, Future<void> Function() action) async {
    try {
      await controller.perform(id, action);
    } catch (error) {
      if (isMounted() && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> play(DownloadTask task) async {
    await controller.repository.reconcile();

    final current = (await controller.repository.loadTasks())
        .where((value) => value.id == task.id)
        .firstOrNull;
    if (current == null ||
        current.state != DownloadState.completed ||
        current.fileLocation == null) {
      throw StateError('文件已不可用，请重新下载');
    }

    if (isMounted()) onPlayLocal(current);
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

    if (confirmed == true) await controller.repository.deleteFile(task.id);
  }

  Future<void> fileAction(String action, DownloadTask task) async {
    switch (action) {
      case 'open':
        await controller.repository.openFile(task.id);
      case 'share':
        await controller.repository.shareFile(task.id);
      case 'export':
        final exported = await controller.repository.exportFile(task.id);
        if (exported && isMounted() && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('视频已导出')));
        }
      case 'delete':
        await _delete(task);
      case 'remove':
        await controller.repository.remove(task.id);
    }
  }
}
