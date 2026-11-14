/// Stable identifiers carried alongside diagnostics in durable download records.
enum DownloadIssueCode {
  fileBusy('A file operation already owns this task'),
  taskChanged('The download task has changed'),
  batchLimit('The batch exceeds the download limit'),
  noSource('The selection has no downloadable video'),
  enqueueFailed('Could not enqueue the native download'),
  missingPublication('The native transfer did not report a file location'),
  missingTransfer('The native download is no longer scheduled'),
  fileMissing('The downloaded file is missing'),
  cannotPause('The download cannot be paused in its current state'),
  pauseFailed('The native download did not pause'),
  cannotResume('The download cannot be resumed in its current state'),
  missingResumeData('Native resume data is unavailable'),
  transferFinished('The native transfer has already finished'),
  cancelFailed('The native download did not cancel'),
  cancelCleanupFailed('Could not clean up the cancelled download'),
  cannotRetry('The download cannot be retried in its current state'),
  sourceUnavailable('The original video source is unavailable'),
  retryCleanupFailed('Could not clean up the previous download attempt'),
  duplicate('Another task is downloading this video at the same quality'),
  cannotPublish('The download has no file awaiting publication'),
  publicationFailed('Could not publish the downloaded file'),
  privateCleanupFailed(
    'Could not clean up the private copy of the published file',
  ),
  taskActive('The download must finish or be cancelled before removal'),
  fileUnavailable('The task has no published file'),
  fileDeleted('The downloaded file was deleted'),
  deleteFailed('Could not delete the downloaded file'),
  exportUnsupported('The current platform does not support file export'),
  downloadFailed('The download failed');

  const DownloadIssueCode(this.diagnostic);

  final String diagnostic;
}

/// Reports a download failure with an English diagnostic and its original cause.
class DownloadIssue extends StateError {
  DownloadIssue(this.code, {this.cause})
    : super(cause == null ? code.diagnostic : '${code.diagnostic}: $cause');

  final DownloadIssueCode code;
  final Object? cause;
}
