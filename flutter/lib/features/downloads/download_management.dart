import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';

enum DownloadFilter {
  all('全部'),
  active('下载中'),
  completed('已完成'),
  unfinished('下载失败'),
  cancelled('已取消'),
  removed('已移除');

  const DownloadFilter(this.label);
  final String label;

  bool includes(DownloadTask task) => switch (this) {
    all => true,
    active => task.isActive && !unfinished.includes(task),
    completed => task.state == DownloadState.completed,
    // Interrupted transfers require an explicit retry after native recovery fails.
    unfinished =>
      task.state == DownloadState.failed ||
          task.state == DownloadState.interrupted ||
          (task.state == DownloadState.finalizing && task.error != null),
    cancelled => task.state == DownloadState.cancelled,
    removed => task.state == DownloadState.missing,
  };
}

enum DownloadAction {
  pause('暂停下载'),
  resume('继续下载'),
  retry('重新下载'),
  publish('重试发布'),
  cancel('取消下载'),
  deleteFile('删除视频文件'),
  remove('移除记录');

  const DownloadAction(this.label);
  final String label;

  bool supports(DownloadTask task) => switch (this) {
    pause => task.state == DownloadState.running && task.canResume,
    resume => task.state == DownloadState.paused && task.canResume,
    retry => !task.isActive && task.state != DownloadState.completed,
    publish => task.state == DownloadState.finalizing && task.error != null,
    cancel => task.isActive && task.state != DownloadState.finalizing,
    deleteFile => task.state == DownloadState.completed,
    remove => !task.isActive,
  };

  Future<void> execute(DownloadRepository repository, String id) =>
      switch (this) {
        pause => repository.pause(id),
        resume => repository.resume(id),
        retry => repository.retry(id),
        publish => repository.publish(id),
        cancel => repository.cancel(id),
        deleteFile => repository.deleteFile(id),
        remove => repository.remove(id),
      };
}

class DownloadActionResult {
  final succeeded = <String>[];
  final skipped = <String>[];
  final failures = <String, String>{};
}

/// Native updates may arrive while a confirmation or another operation is
/// pending. Re-read each target and never act on a replacement download attempt.
Future<DownloadActionResult> runDownloadBatch(
  DownloadRepository repository,
  DownloadAction action,
  List<DownloadTask> selected,
) async {
  final result = DownloadActionResult();
  for (final target in selected) {
    try {
      final current = (await repository.loadTasks())
          .where((task) => task.id == target.id)
          .firstOrNull;
      if (current == null ||
          current.attemptId != target.attemptId ||
          !action.supports(current)) {
        result.skipped.add(target.id);
        continue;
      }
      await action.execute(repository, target.id);
      result.succeeded.add(target.id);
    } catch (error) {
      result.failures[target.id] = error.toString();
    }
  }
  return result;
}
