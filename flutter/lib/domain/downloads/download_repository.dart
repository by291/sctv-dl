import '../programmes/programme.dart';
import 'download_task.dart';

abstract interface class DownloadRepository {
  Future<List<DownloadTask>> loadTasks();
  Stream<List<DownloadTask>> watchTasks();
  Future<DownloadBatchResult> start(
    List<ProgrammeSelection> selections,
    VideoQuality quality, {
    required bool wifiOnly,
  });
  Future<void> reconcile();
  Future<void> pause(String id);
  Future<void> resume(String id);
  Future<void> cancel(String id);
  Future<void> retry(String id);
  Future<void> remove(String id);
  Future<void> deleteFile(String id);
  Future<void> publish(String id);
  Future<void> openFile(String id);
  Future<void> shareFile(String id);
  Future<bool> exportFile(String id);
  Future<void> dispose();
}

abstract interface class DownloadTaskStore {
  Future<List<DownloadTask>> load();
  Future<void> save(DownloadTask task);
  Future<void> remove(String id);
}

/// Implementations reserve an active content/actual-quality identity atomically.
abstract interface class AtomicDownloadTaskStore implements DownloadTaskStore {
  Future<bool> reserve(DownloadTask task);
}
