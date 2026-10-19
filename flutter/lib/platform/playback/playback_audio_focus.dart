import 'dart:async';

import 'package:audio_session/audio_session.dart';

/// Owns focus and interruption subscriptions. An interruption clears playback
/// intent; neither focus recovery nor reconnecting headphones resumes playback.
class PlaybackAudioFocus {
  PlaybackAudioFocus(
    this.session, {
    required this.pause,
    required this.onError,
  }) {
    _interruptions = session.interruptionEventStream.listen((event) {
      if (event.begin) _pauseForInterruption();
    });
    _noisy = session.becomingNoisyEventStream.listen(
      (_) => _pauseForInterruption(),
    );
  }

  static PlaybackAudioFocus? _owner;
  static Future<void> _transitions = Future.value();
  static int _revision = 0;
  final AudioSession session;
  final Future<void> Function() pause;
  final void Function(Object, StackTrace) onError;
  late final StreamSubscription<AudioInterruptionEvent> _interruptions;
  late final StreamSubscription<void> _noisy;
  bool _disposed = false;

  Future<void> configure() => session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionMode: AVAudioSessionMode.moviePlayback,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.movie,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ),
  );

  void _pauseForInterruption() {
    if (_owner == this) unawaited(pause().catchError(onError));
  }

  Future<void> activate() async {
    if (_disposed) throw StateError('Audio owner was disposed');
    final previous = _owner;
    final revision = ++_revision;
    _owner = this;
    try {
      // Pause outside the native lane: it may itself await deactivate(). A
      // reservation can change while this settles, so recheck before acquiring.
      if (previous != this) await previous?.pause();
      _requireOwnership(revision);
      final operation = _transitions.then((_) async {
        _requireOwnership(revision);
        if (!await session.setActive(true)) {
          throw StateError('Audio focus was denied');
        }
        _requireOwnership(revision);
      });
      _transitions = operation.catchError((Object _) {});
      await operation;
    } catch (_) {
      if (_owner == this && revision == _revision) _owner = null;
      rethrow;
    }
  }

  void _requireOwnership(int revision) {
    if (_disposed || _owner != this || revision != _revision) {
      throw StateError('Audio playback was superseded');
    }
  }

  Future<void> deactivate() {
    if (_owner != this) return Future.value();
    _owner = null;
    ++_revision;
    final operation = _transitions.then((_) async {
      // A later activation has already reserved focus and will configure it
      // after this lane drains; do not abandon that incoming owner's request.
      if (_owner == null) await session.setActive(false);
    });
    _transitions = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _interruptions.cancel();
    await _noisy.cancel();
    await deactivate();
  }
}
