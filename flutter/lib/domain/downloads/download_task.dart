import '../programmes/programme.dart';

enum DownloadState {
  preparing,
  queued,
  running,
  waiting,
  paused,
  retrying,
  finalizing,
  completed,
  failed,
  cancelled,
  interrupted,
  missing,
}

class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.attemptId,
    required this.selection,
    required this.requestedQuality,
    required this.quality,
    required this.url,
    required this.filename,
    required this.wifiOnly,
    required this.state,
    required this.createdAt,
    this.receivedBytes = 0,
    this.totalBytes,
    this.fileLocation,
    this.privateLocation,
    this.error,
    this.canResume = false,
    this.revision = 0,
  });

  /// Stable record identity across explicit retries.
  final String id;

  /// Native correlation and artifact identity, replaced for every retry.
  final String attemptId;

  final ProgrammeSelection selection;
  final VideoQuality requestedQuality;
  final VideoQuality quality;
  final String url;
  final String filename;
  final bool wifiOnly;

  final DownloadState state;
  final DateTime createdAt;
  final int receivedBytes;
  final int? totalBytes;

  /// Verified published URI or relative Documents location for playback.
  final String? fileLocation;

  /// App-owned recovery source, retained until publication commits and cleanup
  /// succeeds. On iOS this may name the same file as [fileLocation].
  final String? privateLocation;

  final String? error;
  final bool canResume;

  /// Durable transition revision within this record, including attempt changes.
  final int revision;

  bool get isActive => switch (state) {
    DownloadState.preparing ||
    DownloadState.queued ||
    DownloadState.running ||
    DownloadState.waiting ||
    DownloadState.paused ||
    DownloadState.retrying ||
    DownloadState.finalizing => true,
    _ => false,
  };

  bool get transferFinished => switch (state) {
    DownloadState.finalizing ||
    DownloadState.completed ||
    DownloadState.failed ||
    DownloadState.cancelled ||
    DownloadState.interrupted ||
    DownloadState.missing => true,
    _ => false,
  };

  DownloadTask copyWith({
    String? attemptId,
    ProgrammeSelection? selection,
    VideoQuality? quality,
    String? url,
    String? filename,
    DownloadState? state,
    int? receivedBytes,
    Object? totalBytes = _unchanged,
    Object? fileLocation = _unchanged,
    Object? privateLocation = _unchanged,
    Object? error = _unchanged,
    bool? canResume,
    int? revision,
  }) => DownloadTask(
    id: id,
    attemptId: attemptId ?? this.attemptId,
    selection: selection ?? this.selection,
    requestedQuality: requestedQuality,
    quality: quality ?? this.quality,
    url: url ?? this.url,
    filename: filename ?? this.filename,
    wifiOnly: wifiOnly,
    state: state ?? this.state,
    createdAt: createdAt,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: identical(totalBytes, _unchanged)
        ? this.totalBytes
        : totalBytes as int?,
    fileLocation: identical(fileLocation, _unchanged)
        ? this.fileLocation
        : fileLocation as String?,
    privateLocation: identical(privateLocation, _unchanged)
        ? this.privateLocation
        : privateLocation as String?,
    error: identical(error, _unchanged) ? this.error : error as String?,
    canResume: canResume ?? this.canResume,
    revision: revision ?? this.revision,
  );
}

const _unchanged = Object();

class DownloadFailure {
  const DownloadFailure({required this.contentId, required this.message});

  final String contentId;
  final String message;
}

class DownloadBatchResult {
  const DownloadBatchResult({
    this.taskIds = const [],
    this.duplicates = 0,
    this.fallbacks = 0,
    this.failures = const [],
  });

  final List<String> taskIds;
  final int duplicates;
  final int fallbacks;
  final List<DownloadFailure> failures;
}
