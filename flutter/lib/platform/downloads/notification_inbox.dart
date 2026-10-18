import 'dart:async';

/// Holds the latest launch destination until the application's router subscribes.
/// A consumed tap is never replayed when a route or activity is rebuilt.
class NotificationInbox {
  NotificationInbox() {
    _events = StreamController<String>.broadcast(onListen: _flush);
  }

  late final StreamController<String> _events;
  String? _pending;

  Stream<String> get events => _events.stream;

  void add(String taskId) {
    if (_events.isClosed) return;

    if (_events.hasListener) {
      _events.add(taskId);
    } else {
      _pending = taskId;
    }
  }

  void _flush() {
    final pending = _pending;
    _pending = null;
    if (pending != null) _events.add(pending);
  }

  Future<void> dispose() async {
    _pending = null;
    await _events.close();
  }
}
