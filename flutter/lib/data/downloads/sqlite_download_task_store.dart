import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import '../database/record_database.dart';
import 'task_codec.dart';

/// The app supplies the runtime database, which is excluded from backup.
class SqliteDownloadTaskStore implements AtomicDownloadTaskStore {
  SqliteDownloadTaskStore(this.database);
  final RecordDatabase database;
  static const collection = 'downloads';

  @override
  Future<List<DownloadTask>> load() async =>
      (await database.all(collection)).values.map(decodeDownloadTask).toList();
  @override
  Future<void> save(DownloadTask task) =>
      database.write(collection, task.id, encodeDownloadTask(task));
  @override
  Future<bool> reserve(DownloadTask task) => database.transaction(() async {
    final existing = await load();
    if (existing.any(
      (other) =>
          other.id != task.id &&
          other.isActive &&
          other.selection.ref == task.selection.ref &&
          other.quality == task.quality,
    )) {
      return false;
    }
    await save(task);
    return true;
  });
  @override
  Future<void> remove(String id) => database.remove(collection, id);
}
