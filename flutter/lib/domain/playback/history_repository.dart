import '../programmes/programme.dart';

const _viewingCompletionFraction = .95;

/// A checkpoint saved by an individual playback session.
typedef SaveViewingCheckpoint = Future<void> Function(ViewingEntry entry);

/// The last known viewing position and completion for one programme item.
class ViewingEntry {
  const ViewingEntry({
    required this.selection,
    required this.position,
    required this.viewedAt,
    this.duration,
    bool completed = false,
  }) : _wasCompleted = completed;

  final ProgrammeSelection selection;
  final Duration position;
  final Duration? duration;
  final DateTime viewedAt;
  final bool _wasCompleted;

  bool get completed {
    final total = duration;
    return _wasCompleted ||
        (total != null &&
            total > Duration.zero &&
            position.inMicroseconds >=
                total.inMicroseconds * _viewingCompletionFraction);
  }
}

/// Stores and observes local viewing history across playback routes.
abstract interface class HistoryRepository {
  /// Loads the newest saved entries first.
  Future<List<ViewingEntry>> loadHistory();

  /// Observes the current entries and subsequent durable changes.
  Stream<List<ViewingEntry>> watchHistory();

  /// Opens a checkpoint writer that is invalidated by a successful removal or clear.
  SaveViewingCheckpoint openSession(ContentRef ref);

  /// Removes this entry and invalidates its earlier sessions.
  Future<void> remove(ContentRef ref);

  /// Clears all entries and invalidates all earlier sessions.
  Future<void> clear();
}
