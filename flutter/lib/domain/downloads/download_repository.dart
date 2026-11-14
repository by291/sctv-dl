import '../programmes/programme.dart';
import 'download_task.dart';

/// Owns durable download records and coordinates their native transfers and files.
abstract interface class DownloadRepository {
  /// Loads the records after recovering persisted and native state.
  Future<List<DownloadTask>> loadTasks();

  /// Observes the durable state without missing updates during initial loading.
  Stream<List<DownloadTask>> watchTasks();

  /// Reserves and submits each eligible selection, returning per-item failures.
  Future<DownloadBatchResult> start(
    List<ProgrammeSelection> selections,
    VideoQuality quality, {
    required bool wifiOnly,
  });

  /// Refreshes native state and waits for file work already in progress.
  Future<void> reconcile();

  /// Requests a pause for a resumable transfer.
  Future<void> pause(String id);

  /// Resumes the same native attempt if its resume data is available.
  Future<void> resume(String id);

  /// Stops the current attempt and owns cleanup of its partial file.
  Future<void> cancel(String id);

  /// Resolves the source again and creates a new download attempt.
  Future<void> retry(String id);

  /// Removes an inactive record while preserving any completed file.
  Future<void> remove(String id);

  /// Removes the published file while preserving the download record.
  Future<void> deleteFile(String id);

  /// Publishes a finished transfer from its retained recovery source.
  Future<void> publish(String id);

  /// Opens the published file using a platform handler.
  Future<void> openFile(String id);

  /// Shares the published file using the system share sheet.
  Future<void> shareFile(String id);

  /// Exports a copy of the published file and returns false on user cancellation.
  Future<bool> exportFile(String id);

  /// Waits for accepted file effects and their durable commits to finish.
  Future<void> dispose();
}

/// Persists download records across launches.
abstract interface class DownloadTaskStore {
  /// Loads persisted records.
  Future<List<DownloadTask>> load();

  /// Writes a record under its stable task identity.
  Future<void> save(DownloadTask task);

  /// Removes the persisted record without touching its files.
  Future<void> remove(String id);
}

/// Implementations reserve an active content/actual-quality identity atomically.
abstract interface class AtomicDownloadTaskStore implements DownloadTaskStore {
  /// Writes [task] only if no other record owns its active content and quality.
  Future<bool> reserve(DownloadTask task);
}
