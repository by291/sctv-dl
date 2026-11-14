import '../../domain/playback/history_repository.dart';
import '../../domain/programmes/programme.dart';
import '../database/record_database.dart';
import '../programmes/programme_codec.dart';

const _historyCollection = 'viewing_history';
const _historyLimit = 500;

class DriftHistoryRepository implements HistoryRepository {
  DriftHistoryRepository(this._database);

  final RecordDatabase _database;

  Future<void> _writes = Future<void>.value();
  int _clearGeneration = 0;
  final _removalGenerations = <ContentRef, int>{};

  Future<void> _serialize(Future<void> Function() action) {
    final saved = _writes.then((_) => action());
    _writes = saved.then<void>((_) {}, onError: (Object _, StackTrace _) {});

    return saved;
  }

  @override
  Future<List<ViewingEntry>> loadHistory() async =>
      _decodeRows(await _database.all(_historyCollection));

  @override
  Stream<List<ViewingEntry>> watchHistory() =>
      _database.watch(_historyCollection).map(_decodeRows);

  @override
  SaveViewingCheckpoint openSession(ContentRef ref) {
    final clearGeneration = _clearGeneration;
    final removalGeneration = _removalGenerations[ref];

    return (entry) => _serialize(() async {
      // A player can queue a checkpoint before its deletion reaches this lane.
      // Check the session's identity here, after earlier deletions have committed.
      if (clearGeneration != _clearGeneration ||
          removalGeneration != _removalGenerations[ref]) {
        return;
      }

      if (entry.selection.ref != ref) {
        throw ArgumentError(
          'Viewing checkpoint does not belong to this session',
        );
      }

      await _database.transaction(() => _save(entry));
    });
  }

  Future<void> _save(ViewingEntry entry) async {
    if (entry.position.isNegative || (entry.duration?.isNegative ?? false)) {
      throw const FormatException('Invalid viewing position');
    }

    await _database.write(_historyCollection, entry.selection.ref.key, {
      'version': 1,
      'selection': encodeSelection(entry.selection),
      'positionUs': entry.position.inMicroseconds,
      'durationUs': entry.duration?.inMicroseconds,
      'viewedAt': entry.viewedAt.toUtc().toIso8601String(),
      'completed': entry.completed,
    });

    final all = await loadHistory();
    for (final stale in all.skip(_historyLimit)) {
      await _database.remove(_historyCollection, stale.selection.ref.key);
    }
  }

  @override
  Future<void> remove(ContentRef ref) => _serialize(() async {
    await _database.remove(_historyCollection, ref.key);
    _removalGenerations.update(
      ref,
      (generation) => generation + 1,
      ifAbsent: () => 1,
    );
  });

  @override
  Future<void> clear() => _serialize(() async {
    await _database.clearCollection(_historyCollection);
    _clearGeneration++;
    _removalGenerations.clear();
  });

  List<ViewingEntry> _decodeRows(Map<String, Map<String, Object?>> rows) {
    final entries = <ViewingEntry>[];
    for (final row in rows.values) {
      try {
        final selection = decodeSelection(
          Map<String, Object?>.from(row['selection'] as Map),
        );
        final position = row['positionUs'] as int;
        final duration = row['durationUs'] as int?;
        if (position < 0 || (duration != null && duration < 0)) {
          continue;
        }

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

    entries.sort((left, right) {
      final time = right.viewedAt.compareTo(left.viewedAt);
      return time == 0
          ? left.selection.ref.key.compareTo(right.selection.ref.key)
          : time;
    });

    return List.unmodifiable(entries);
  }
}
