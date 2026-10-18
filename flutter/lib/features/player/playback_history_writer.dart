import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';

/// Owns checkpoint throttling and write ordering for one accepted selection.
class PlaybackHistoryWriter {
  PlaybackHistoryWriter({
    required this.selection,
    required this.repository,
    required this.now,
    required this.onError,
  });

  final ProgrammeSelection? selection;
  final HistoryRepository repository;
  final DateTime Function() now;
  final void Function(Object) onError;

  Future<void> _writes = Future.value();
  DateTime? _lastProgressSave;
  Duration _lastSavedPosition = Duration.zero;

  void saveAdvancingProgress(PlaybackSnapshot snapshot) {
    if (snapshot.playing &&
        snapshot.position > _lastSavedPosition &&
        (_lastProgressSave == null ||
            now().difference(_lastProgressSave!) >=
                const Duration(seconds: 5))) {
      save(snapshot);
    }
  }

  void save(PlaybackSnapshot snapshot) {
    final accepted = selection;
    if (accepted == null || !snapshot.initialized) return;

    final duration = snapshot.duration;
    final viewedAt = now();
    final entry = ViewingEntry(
      selection: accepted,
      position: snapshot.position,
      duration: duration,
      viewedAt: viewedAt,
      completed:
          snapshot.ended ||
          duration != null &&
              duration > Duration.zero &&
              snapshot.position.inMilliseconds >= duration.inMilliseconds * .95,
    );

    _lastProgressSave = viewedAt;
    _lastSavedPosition = snapshot.position;

    // Serialize saves so an older progress write cannot replace exit progress.
    // A repository failure is reported without poisoning later checkpoints.
    _writes = _writes.then((_) => repository.save(entry)).catchError(onError);
  }

  Future<void> flush() => _writes;
}
