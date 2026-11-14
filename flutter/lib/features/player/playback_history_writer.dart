import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';

const _checkpointInterval = Duration(seconds: 5);

/// Owns checkpoint throttling and write ordering for one accepted selection.
class PlaybackHistoryWriter {
  PlaybackHistoryWriter({
    required this.selection,
    required HistoryRepository repository,
    required this.now,
    required this.onError,
  }) : _saveCheckpoint = selection == null
           ? null
           : repository.openSession(selection.ref);

  final ProgrammeSelection? selection;
  final SaveViewingCheckpoint? _saveCheckpoint;
  final DateTime Function() now;
  final void Function(Object) onError;

  Future<void> _writes = Future.value();
  DateTime? _lastProgressSave;
  Duration _lastSavedPosition = Duration.zero;

  /// Records advancing playback after the checkpoint interval has elapsed.
  void saveAdvancingProgress(PlaybackSnapshot snapshot) {
    final lastSave = _lastProgressSave;
    final isDue =
        lastSave == null || now().difference(lastSave) >= _checkpointInterval;
    if (snapshot.playing && snapshot.position > _lastSavedPosition && isDue) {
      save(snapshot);
    }
  }

  /// Queues an immediate checkpoint for a pause, seek, background or exit.
  void save(PlaybackSnapshot snapshot) {
    final accepted = selection;
    final saveCheckpoint = _saveCheckpoint;
    if (accepted == null || saveCheckpoint == null || !snapshot.initialized) {
      return;
    }

    final viewedAt = now();
    final entry = ViewingEntry(
      selection: accepted,
      position: snapshot.position,
      duration: snapshot.duration,
      viewedAt: viewedAt,
      completed: snapshot.ended,
    );

    _lastProgressSave = viewedAt;
    _lastSavedPosition = snapshot.position;

    // Serialize saves so an older progress write cannot replace exit progress.
    // A repository failure is reported without poisoning later checkpoints.
    _writes = _writes.then((_) => saveCheckpoint(entry)).catchError(onError);
  }

  /// Waits for all checkpoints that have been queued so far.
  Future<void> flush() => _writes;
}
