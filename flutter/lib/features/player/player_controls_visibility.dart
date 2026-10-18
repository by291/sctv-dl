import 'dart:async';

import 'package:flutter/foundation.dart';

enum PlayerControlHold {
  interaction,
  accessibility,
  focus,
  seek,
  menu,
  gesture,
  systemVolume,
}

/// Owns inactivity timing and independent holds from controls and gestures.
class PlayerControlsVisibility {
  PlayerControlsVisibility({required this.onChanged});

  final VoidCallback onChanged;

  final _holds = <PlayerControlHold>{};
  Timer? _hideTimer;
  bool visible = true;
  bool _stopped = false;

  bool hold(bool held, PlayerControlHold reason) =>
      held ? _holds.add(reason) : _holds.remove(reason);

  bool detach(PlayerControlHold reason) => _holds.remove(reason);

  void show() {
    visible = true;
    _hideTimer?.cancel();
  }

  void toggle() {
    visible = !visible;
    _hideTimer?.cancel();
  }

  void update({required bool uninterruptedPlayback}) {
    if (_stopped) return;

    if (!uninterruptedPlayback || _holds.isNotEmpty) {
      show();
    } else if (visible && !(_hideTimer?.isActive ?? false)) {
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        visible = false;
        onChanged();
      });
    }
  }

  void cancelTimer() => _hideTimer?.cancel();

  void dispose() {
    _stopped = true;
    _hideTimer?.cancel();
  }
}
