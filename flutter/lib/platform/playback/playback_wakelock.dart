import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

/// Shares the OS screen lock across sessions that can overlap during PiP exit.
class PlaybackWakelock {
  static final _owners = <PlaybackWakelock>{};
  static Future<void> _writes = Future.value();

  Future<void> setEnabled(bool enabled) {
    final changed = enabled ? _owners.add(this) : _owners.remove(this);
    if (!changed) return _writes;

    final write = _writes.then(
      (_) => WakelockPlus.toggle(enable: _owners.isNotEmpty),
    );
    // Each caller observes its own failure; a rejected write must not prevent
    // later sessions from releasing or reacquiring the screen lock.
    _writes = write.catchError((Object _) {});
    return write;
  }
}
