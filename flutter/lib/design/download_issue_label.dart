import 'dart:developer' as developer;

import '../domain/downloads/download_issue.dart';
import '../domain/downloads/download_task.dart';

/// Displays a localized failure while retaining diagnostics in storage.
String downloadIssueLabel(
  DownloadIssueCode? code, {
  required String fallback,
}) => switch (code) {
  DownloadIssueCode.fileBusy => '此任务正在处理文件，请稍后重试',
  DownloadIssueCode.taskChanged => '任务状态已改变',
  DownloadIssueCode.batchLimit => '每批最多下载 $downloadBatchLimit 项',
  DownloadIssueCode.noSource => '没有可下载的视频',
  DownloadIssueCode.enqueueFailed => '加入下载队列失败，请重试',
  DownloadIssueCode.missingPublication => '下载完成，但无法确认文件位置',
  DownloadIssueCode.missingTransfer => '无法确认原生下载任务，请重试',
  DownloadIssueCode.fileMissing => '文件已被移除，请重新下载',
  DownloadIssueCode.cannotPause => '此任务暂不支持暂停',
  DownloadIssueCode.pauseFailed => '原生任务未能暂停',
  DownloadIssueCode.cannotResume => '此任务无法续传，请重新下载',
  DownloadIssueCode.missingResumeData => '续传数据不可用，请重新下载',
  DownloadIssueCode.transferFinished => '此任务已结束传输',
  DownloadIssueCode.cancelFailed => '原生下载取消失败',
  DownloadIssueCode.cancelCleanupFailed => '取消后的文件清理失败',
  DownloadIssueCode.cannotRetry => '此任务无需重新下载',
  DownloadIssueCode.sourceUnavailable => '视频源已不可用',
  DownloadIssueCode.retryCleanupFailed => '重试前的文件清理失败',
  DownloadIssueCode.duplicate => '此视频已有下载任务',
  DownloadIssueCode.cannotPublish => '此任务没有等待发布的文件',
  DownloadIssueCode.publicationFailed => '文件发布失败，可重试发布',
  DownloadIssueCode.privateCleanupFailed => '视频已保存，但私有副本清理失败',
  DownloadIssueCode.taskActive => '请先完成或取消任务',
  DownloadIssueCode.fileUnavailable => '下载文件不可用，请重新下载',
  DownloadIssueCode.fileDeleted => '文件已删除',
  DownloadIssueCode.deleteFailed => '删除文件失败，请重试',
  DownloadIssueCode.exportUnsupported => '此平台不支持导出',
  DownloadIssueCode.downloadFailed => '下载失败，请重试',
  null => fallback,
};

/// Reports a command failure and returns the corresponding message for the UI.
String reportDownloadError(
  Object error,
  StackTrace? stack, {
  String fallback = '操作失败，请重试',
}) {
  developer.log(
    'Download operation failed',
    name: 'downloads',
    error: error,
    stackTrace: stack,
  );

  return downloadIssueLabel(
    error is DownloadIssue ? error.code : null,
    fallback: fallback,
  );
}
