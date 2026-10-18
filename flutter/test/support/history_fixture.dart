import 'dart:async';

import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

class MemoryHistory implements HistoryRepository {
  MemoryHistory(Iterable<ViewingEntry> initial) : entries = [...initial];

  final List<ViewingEntry> entries;
  final _changes = StreamController<List<ViewingEntry>>.broadcast();
  int removals = 0;

  @override
  Future<List<ViewingEntry>> loadHistory() async => List.unmodifiable(entries);

  @override
  Stream<List<ViewingEntry>> watchHistory() async* {
    yield List.unmodifiable(entries);
    yield* _changes.stream;
  }

  @override
  Future<void> remove(ContentRef ref) async {
    removals++;
    entries.removeWhere((entry) => entry.selection.ref == ref);
    _changes.add(List.unmodifiable(entries));
  }

  @override
  Future<void> clear() async {
    entries.clear();
    _changes.add(const []);
  }

  @override
  Future<void> save(ViewingEntry entry) async {
    entries.removeWhere((value) => value.selection.ref == entry.selection.ref);
    entries.insert(0, entry);
    _changes.add(List.unmodifiable(entries));
  }

  Future<void> close() => _changes.close();
}

ViewingEntry historyEntry({
  required String id,
  required DateTime viewedAt,
  Duration position = const Duration(minutes: 1, seconds: 32),
  Duration? duration = const Duration(minutes: 4, seconds: 2),
  bool completed = false,
  String? title,
}) => ViewingEntry(
  selection: ProgrammeSelection(
    programme: const Programme(id: '1', name: '四川新闻联播'),
    // The broadcast date deliberately differs from the viewing date.
    broadcast: const BroadcastDate(id: '2', date: '2025-09-26'),
    content: ProgrammeContent(id: id, title: title ?? '新闻片段 $id'),
  ),
  position: position,
  duration: duration,
  completed: completed,
  viewedAt: viewedAt,
);
