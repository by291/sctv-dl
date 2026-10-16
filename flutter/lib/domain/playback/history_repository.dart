import '../programmes/programme.dart';

class ViewingEntry {
  const ViewingEntry({
    required this.selection,
    required this.position,
    required this.viewedAt,
    this.duration,
    this.completed = false,
  });

  final ProgrammeSelection selection;
  final Duration position;
  final Duration? duration;
  final DateTime viewedAt;
  final bool completed;
}

abstract interface class HistoryRepository {
  Future<List<ViewingEntry>> loadHistory();
  Stream<List<ViewingEntry>> watchHistory();
  Future<void> save(ViewingEntry entry);
  Future<void> remove(ContentRef ref);
  Future<void> clear();
}
