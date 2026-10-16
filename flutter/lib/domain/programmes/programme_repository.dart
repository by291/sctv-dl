import 'programme.dart';

class RequestScope {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const RequestCancelled();
  }
}

class RequestCancelled implements Exception {
  const RequestCancelled();
}

class ProgrammeSnapshot<T> {
  const ProgrammeSnapshot({
    required this.items,
    required this.revision,
    required this.fetchedAt,
  });
  final List<T> items;
  final String revision;
  final DateTime fetchedAt;
}

abstract interface class ProgrammeRepository {
  Future<ProgrammeSnapshot<Programme>?> cachedProgrammes();
  Future<ProgrammeSnapshot<Programme>> refreshProgrammes({RequestScope? scope});
  Future<ProgrammeSnapshot<BroadcastDate>?> cachedDates(String programmeId);
  Future<ProgrammeSnapshot<BroadcastDate>> refreshDates(
    String programmeId, {
    RequestScope? scope,
  });
  Future<ProgrammeSnapshot<ProgrammeContent>?> cachedContents(
    String programmeId,
    String dateId,
  );
  Future<ProgrammeSnapshot<ProgrammeContent>> refreshContents(
    String programmeId,
    String dateId, {
    RequestScope? scope,
  });
  Future<void> clearCache();
}
