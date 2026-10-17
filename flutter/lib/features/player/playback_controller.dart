import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';

enum PlayerControlHold {
  interaction,
  accessibility,
  focus,
  seek,
  menu,
  gesture,
  systemVolume,
}

/// Owns one pinned playback route. A committed route exit releases its session
/// after the transition; an active PiP session retains ownership until it stops.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.input,
    required this.backend,
    required this.history,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final PlaybackInput input;
  final PlaybackBackend backend;
  final HistoryRepository history;
  final DateTime Function() _now;
  PlaybackSession? session;
  PlaybackSnapshot value = const PlaybackSnapshot();
  String? message;
  bool loading = false;
  bool switchingSource = false;
  bool controlsVisible = true;
  final _controlHolds = <PlayerControlHold>{};
  bool _released = false;
  bool _disposed = false;
  bool _pipRequested = false;
  bool _retainedForPip = false;
  bool _backgrounded = false;
  bool _exiting = false;
  int _generation = 0;
  Timer? _hideTimer;
  StreamSubscription<PlaybackSnapshot>? _subscription;
  Future<void> _historyWrites = Future.value();
  DateTime? _lastProgressSave;
  Duration _lastSavedPosition = Duration.zero;
  PlaybackSnapshot? _lastUsable;
  bool _streamFailed = false;

  int gestureEpoch = 0;
  double selectedSpeed = 1;
  Duration? seekPreview;
  Duration? _seekOrigin;
  bool temporarySpeed = false;
  Future<void> _speedChanges = Future.value();
  int _pendingSpeedChanges = 0;
  Object? _speedFailure;

  void previewSeek(double fraction) {
    final duration = value.duration;
    if (_released || duration == null || duration <= Duration.zero) return;
    _seekOrigin ??= value.position;
    final sensitivity = duration.inMilliseconds.clamp(0, 120000);
    seekPreview = Duration(
      milliseconds: (_seekOrigin!.inMilliseconds + fraction * sensitivity)
          .round()
          .clamp(0, duration.inMilliseconds),
    );
    holdControls(true, reason: PlayerControlHold.seek);
  }

  Future<void> finishSeek({required bool commit}) async {
    final target = seekPreview;
    seekPreview = null;
    _seekOrigin = null;
    // Retire this preview before awaiting a native seek; the next preview owns
    // its own hold even when this write is still pending.
    if (target != null) holdControls(false, reason: PlayerControlHold.seek);
    if (commit && target != null) await seek(target);
  }

  Future<void> _queueSpeed(double speed) {
    final owned = session;
    _pendingSpeedChanges++;
    return _speedChanges = _speedChanges.then((_) async {
      try {
        if (owned == null || owned != session) return;
        await owned.setSpeed(speed);
        if (owned == session) _speedFailure = null;
      } catch (error) {
        if (owned == session) _speedFailure = error;
        if (!_released && owned == session) {
          message = '播放速度调整失败：$error';
          _notify();
        }
      } finally {
        _pendingSpeedChanges--;
      }
    });
  }

  Future<void> beginTemporarySpeed() async {
    if (_released || !value.playing || temporarySpeed) return;
    temporarySpeed = true;
    holdControls(true, reason: PlayerControlHold.gesture);
    await _queueSpeed(2);
  }

  Future<void> endTemporarySpeed() async {
    if (!temporarySpeed) return;
    temporarySpeed = false;
    holdControls(false, reason: PlayerControlHold.gesture);
    await _queueSpeed(selectedSpeed);
  }

  Future<void> cancelGestures() async {
    gestureEpoch++;
    _controlHolds.remove(PlayerControlHold.gesture);
    await finishSeek(commit: false);
    await endTemporarySpeed();
    // Releasing the pointer ends temporary ownership before the native restore
    // settles. Transitions must also drain writes already queued by that release.
    while (_pendingSpeedChanges > 0) {
      await _speedChanges;
    }
  }

  void _requireRestoredSpeed() {
    if (_speedFailure != null) {
      throw StateError('Playback speed could not be restored: $_speedFailure');
    }
  }

  bool get canRetry =>
      !loading && (session == null || value.error != null || _streamFailed);

  Future<void> initialize() => _initialize(input);

  Future<void> _initialize(
    PlaybackInput opening, {
    double speed = 1,
    bool resumePlayback = false,
  }) async {
    if (_released || loading || session != null) return;
    final generation = ++_generation;
    loading = true;
    message = null;
    _notify();
    try {
      final opened = await backend.open(opening);
      Object? openingSpeedFailure;
      if (speed != 1) {
        try {
          await opened.setSpeed(speed);
        } catch (error) {
          openingSpeedFailure = error;
          message = '播放速度恢复失败：$error';
        }
      }
      if (_released || generation != _generation) {
        await opened.dispose();
        return;
      }
      session = opened;
      selectedSpeed = speed;
      _speedFailure = openingSpeedFailure;
      _streamFailed = false;
      _subscription = opened.changes.listen(
        _accept,
        onError: (Object error) {
          _streamFailed = true;
          message = '播放中断，请重试：$error';
          showControls();
        },
      );
      _accept(opened.value);
      if (resumePlayback && !_backgrounded && !_exiting) {
        await opened.play();
      }
    } catch (error) {
      if (!_released && generation == _generation) {
        message = '无法打开视频，请重试：$error';
      }
    } finally {
      if (!_released && generation == _generation) {
        loading = false;
        _updateVisibility();
        _notify();
      }
    }
  }

  Future<void> retry() async {
    if (_released || loading) return;
    loading = true;
    await cancelGestures();
    final resume = _lastUsable;
    final source = resume?.source;
    final sources = source == null
        ? input.sources
        : [
            source,
            ...input.sources.where((candidate) => candidate.url != source.url),
          ];
    final opening = PlaybackInput(
      title: input.title,
      sources: List.unmodifiable(sources),
      selection: input.selection,
      localLocation: input.localLocation,
      preferredQuality: input.preferredQuality,
      initialPosition: resume?.position ?? input.initialPosition,
    );
    loading = true;
    ++_generation;
    _hideTimer?.cancel();
    _notify();
    try {
      // Failed native handles must be released before constructing a replacement.
      // Explicit retry preserves intent, but backgrounding or committed navigation
      // while the replacement opens must still prevent resumed playback.
      await _disposeSession();
    } catch (error) {
      message = '无法释放旧播放资源，请重试：$error';
      loading = false;
      _notify();
      return;
    }
    loading = false;
    if (!_released) {
      await _initialize(
        opening,
        speed: resume?.speed ?? 1,
        resumePlayback: resume?.playing == true,
      );
    }
  }

  void _accept(PlaybackSnapshot snapshot) {
    final wasPlaying = value.playing;
    if (!temporarySpeed && _pendingSpeedChanges == 0 && _speedFailure == null) {
      selectedSpeed = snapshot.speed;
    }
    if (snapshot.initialized && snapshot.error == null) {
      // Resume checkpoints retain position and intent but never temporary speed.
      _lastUsable = PlaybackSnapshot(
        initialized: snapshot.initialized,
        firstFrameRendered: snapshot.firstFrameRendered,
        playing: snapshot.playing,
        buffering: snapshot.buffering,
        position: snapshot.position,
        duration: snapshot.duration,
        speed: selectedSpeed,
        source: snapshot.source,
        supportsPip: snapshot.supportsPip,
        inPip: snapshot.inPip,
        ended: snapshot.ended,
      );
    }
    if (snapshot.inPip && !value.inPip) unawaited(cancelGestures());
    value = snapshot;
    if (temporarySpeed && !snapshot.playing) unawaited(endTemporarySpeed());
    if (_released) {
      // Release owns cleanup until its pending native writes and history settle.
      // Only a session explicitly retained afterwards may dispose on a PiP exit.
      if (_retainedForPip && !snapshot.inPip) unawaited(_disposeSession());
      return;
    }
    if (wasPlaying && !snapshot.playing || snapshot.ended) _saveHistory();
    if (snapshot.playing &&
        snapshot.position > _lastSavedPosition &&
        (_lastProgressSave == null ||
            _now().difference(_lastProgressSave!) >=
                const Duration(seconds: 5))) {
      _saveHistory();
    }
    _updateVisibility();
    _notify();
  }

  Future<void> togglePlayback() => _action(() async {
    if (value.playing) {
      await session?.pause();
      _saveHistory();
    } else {
      await session?.play();
    }
  });

  Future<void> seek(Duration position) => _action(() async {
    await session?.seek(position);
    _saveHistory();
  });

  Future<void> setSpeed(double speed) async {
    selectedSpeed = speed;
    await _queueSpeed(temporarySpeed ? 2 : speed);
    showControls();
  }

  Future<void> selectSource(VideoSource source) async {
    if (switchingSource || session == null || value.source?.url == source.url) {
      return;
    }
    switchingSource = true;
    showControls();
    try {
      await cancelGestures();
      if (_released) return;
      _requireRestoredSpeed();
      await session!.selectSource(source);
      message = null;
    } catch (error) {
      message = '画质切换失败，请重试：$error';
    } finally {
      switchingSource = false;
      _updateVisibility();
      _notify();
    }
  }

  Future<void> enterPictureInPicture() => _action(() async {
    await cancelGestures();
    if (_released) return;
    _requireRestoredSpeed();
    _pipRequested = true;
    try {
      await session?.enterPictureInPicture();
    } finally {
      _pipRequested = false;
      if (_backgrounded && !value.inPip) {
        await session?.pause();
        _saveHistory();
      }
    }
  });

  void foreground() {
    _backgrounded = false;
  }

  Future<void> background() async {
    _backgrounded = true;
    await cancelGestures();
    if (!value.inPip && !_pipRequested) {
      await _action(() async => session?.pause());
    }
    _saveHistory();
    await flushHistory();
  }

  void holdControls(
    bool hold, {
    PlayerControlHold reason = PlayerControlHold.interaction,
  }) {
    // A losing gesture or a removed touch-focused control may release a hold
    // it never owned. Such releases must not undo a surface hide operation.
    final changed = hold
        ? _controlHolds.add(reason)
        : _controlHolds.remove(reason);
    if (!changed) return;
    showControls();
  }

  /// Detaching a held control only releases ownership. Its disposal may happen
  /// while the widget tree is locked, so visibility notifications stay with the
  /// already scheduled hide timer rather than rebuilding the disposing tree.
  void detachControlHold(PlayerControlHold reason) {
    if (_controlHolds.remove(reason)) _updateVisibility();
  }

  void toggleControls() {
    if (_released) return;
    controlsVisible = !controlsVisible;
    _hideTimer?.cancel();
    _updateVisibility();
    _notify();
  }

  void showControls() {
    if (_released) return;
    controlsVisible = true;
    _hideTimer?.cancel();
    _updateVisibility();
    _notify();
  }

  void _updateVisibility() {
    if (_released) return;
    final canHide =
        value.playing &&
        !value.buffering &&
        value.error == null &&
        message == null &&
        _controlHolds.isEmpty &&
        !loading &&
        !switchingSource;
    if (!canHide) {
      _hideTimer?.cancel();
      controlsVisible = true;
    } else if (controlsVisible && !(_hideTimer?.isActive ?? false)) {
      _hideTimer = Timer(const Duration(milliseconds: 3500), () {
        controlsVisible = false;
        _notify();
      });
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_released || session == null) return;
    try {
      await action();
      message = null;
    } catch (error) {
      message = '操作失败，请重试：$error';
    }
    showControls();
  }

  void _saveHistory() {
    final selection = input.selection;
    if (selection == null || !value.initialized) return;
    final duration = value.duration;
    final entry = ViewingEntry(
      selection: selection,
      position: value.position,
      duration: duration,
      viewedAt: _now(),
      completed:
          value.ended ||
          duration != null &&
              duration > Duration.zero &&
              value.position.inMilliseconds >= duration.inMilliseconds * .95,
    );
    _lastProgressSave = _now();
    _lastSavedPosition = value.position;
    // Writes are serialized so an older throttled save cannot replace exit progress.
    _historyWrites = _historyWrites.then((_) => history.save(entry)).catchError(
      (Object error) {
        message = '观看记录保存失败：$error';
        _notify();
      },
    );
  }

  Future<void> flushHistory() => _historyWrites;

  /// Called only after navigation commits, never from a speculative back gesture.
  Future<void> commitExit() async {
    _exiting = true;
    await cancelGestures();
    if (!value.inPip) await session?.pause();
    _saveHistory();
    await flushHistory();
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (seekPreview != null || temporarySpeed || _pendingSpeedChanges > 0) {
      await cancelGestures();
    }
    ++_generation;
    _hideTimer?.cancel();
    _saveHistory();
    await flushHistory();
    if (value.inPip) {
      _retainedForPip = true;
    } else {
      await _disposeSession();
    }
  }

  Future<void> _disposeSession() async {
    _retainedForPip = false;
    final owned = session;
    session = null;
    await _subscription?.cancel();
    _subscription = null;
    await owned?.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(release());
    super.dispose();
  }
}
