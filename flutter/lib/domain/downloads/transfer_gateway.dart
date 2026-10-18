import 'download_task.dart';

/// A native observation always identifies the caller's preallocated attempt.
class TransferSnapshot {
  const TransferSnapshot({
    required this.attemptId,
    required this.state,
    this.receivedBytes = 0,
    this.totalBytes,
    this.fileLocation,
    this.error,
    this.canResume = false,
  });

  final String attemptId;
  final DownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final String? fileLocation;
  final String? error;
  final bool canResume;
}

abstract interface class TransferGateway {
  Stream<TransferSnapshot> get events;
  Stream<String> get notificationTaps;

  Future<void> initialize();

  Future<bool> enqueue(DownloadTask task);
  Future<Map<String, TransferSnapshot>> query();
  Future<bool> pause(String attemptId);
  Future<bool> resume(String attemptId);
  Future<bool> cancel(String attemptId);

  Future<void> dispose();
}

/// The platform reply failed after enqueue may already have taken effect.
class TransferEnqueueException implements Exception {
  const TransferEnqueueException(this.cause);

  final Object cause;

  @override
  String toString() => 'Native enqueue outcome is unknown: $cause';
}
