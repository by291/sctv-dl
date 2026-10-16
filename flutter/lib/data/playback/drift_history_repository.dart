import '../../domain/playback/history_repository.dart';
import '../../domain/programmes/programme.dart';
import '../database/record_database.dart';
import '../programmes/programme_codec.dart';

class DriftHistoryRepository implements HistoryRepository {
  DriftHistoryRepository(this._database);

  final RecordDatabase _database;
  Future<void> _writes = Future<void>.value();

  Future<void> _serialize(Future<void> Function() action) {
    final saved = _writes.then((_) => _database.transaction(action));
    _writes = saved.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return saved;
  }

  @override
  Future<List<ViewingEntry>> loadHistory() async =>
      _decodeRows(await _database.all('viewing_history'));

  @override
  Stream<List<ViewingEntry>> watchHistory() =>
      _database.watch('viewing_history').map(_decodeRows);

  @override
  Future<void> save(ViewingEntry entry) => _serialize(() async {
    if (entry.position.isNegative || (entry.duration?.isNegative ?? false)) {
      throw const FormatException('Invalid viewing position');
    }
    final duration = entry.duration;
    final completed =
        entry.completed ||
        (duration != null &&
            duration > Duration.zero &&
            entry.position.inMicroseconds >= duration.inMicroseconds * .95);
    await _database.write('viewing_history', entry.selection.ref.key, {
      'version': 1,
      'selection': encodeSelection(entry.selection),
      'positionUs': entry.position.inMicroseconds,
      'durationUs': duration?.inMicroseconds,
      'viewedAt': entry.viewedAt.toUtc().toIso8601String(),
      'completed': completed,
    });
    final all = await loadHistory();
    for (final stale in all.skip(500)) {
      await _database.remove('viewing_history', stale.selection.ref.key);
    }
  });

  @override
  Future<void> remove(ContentRef ref) =>
      _serialize(() => _database.remove('viewing_history', ref.key));

  @override
  Future<void> clear() =>
      _serialize(() => _database.clearCollection('viewing_history'));

  List<ViewingEntry> _decodeRows(Map<String, Map<String, Object?>> rows) {
    final entries = <ViewingEntry>[];
    for (final row in rows.values) {
      try {
        final selection = decodeSelection(
          Map<String, Object?>.from(row['selection'] as Map),
        );
        final position = row['positionUs'] as int;
        final duration = row['durationUs'] as int?;
        if (position < 0 || (duration != null && duration < 0)) continue;
        entries.add(
          ViewingEntry(
            selection: selection,
            position: Duration(microseconds: position),
            duration: duration == null
                ? null
                : Duration(microseconds: duration),
            viewedAt: DateTime.parse(row['viewedAt'] as String),
            completed: row['completed'] == true,
          ),
        );
      } on FormatException {
        // One obsolete or damaged row must not hide other usable history.
        continue;
      } on TypeError {
        continue;
      }
    }
    entries.sort((a, b) {
      final time = b.viewedAt.compareTo(a.viewedAt);
      return time == 0
          ? a.selection.ref.key.compareTo(b.selection.ref.key)
          : time;
    });
    return List.unmodifiable(entries);
  }
}
