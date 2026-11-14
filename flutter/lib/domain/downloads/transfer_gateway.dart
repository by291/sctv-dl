import 'download_issue.dart';
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
    this.issueCode,
    this.canResume = false,
  });

  final String attemptId;
  final DownloadState state;
  final int receivedBytes;
  final int? totalBytes;
  final String? fileLocation;
  final String? error;
  final DownloadIssueCode? issueCode;
  final bool canResume;
}

/// Bridges native scheduling and live observations for each download attempt.
abstract interface class TransferGateway {
  /// Listen before initialization to capture observations replayed during recovery.
  Stream<TransferSnapshot> get events;

  /// Delivers download destinations requested by native notification taps.
  Stream<String> get notificationTaps;

  /// Registers callbacks and recovers observations from background execution.
  Future<void> initialize();

  /// Submits a task with the caller's already persisted attempt identity.
  Future<bool> enqueue(DownloadTask task);

  /// Reads the current native attempts without clearing live observations.
  Future<Map<String, TransferSnapshot>> query();

  /// Requests a pause whose final state will arrive through [events].
  Future<bool> pause(String attemptId);

  /// Requests resume of the same native attempt and its partial file.
  Future<bool> resume(String attemptId);

  /// Requests cancellation of pending preparation or of the native attempt.
  Future<bool> cancel(String attemptId);

  /// Releases observation and preflight resources while native transfers continue.
  Future<void> dispose();
}

/// The platform reply failed after enqueue may already have taken effect.
class TransferEnqueueException implements Exception {
  const TransferEnqueueException(this.cause);

  final Object cause;

  @override
  String toString() => 'Native enqueue outcome is unknown: $cause';
}
