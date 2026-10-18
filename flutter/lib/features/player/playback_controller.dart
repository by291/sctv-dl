import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';
import 'playback_history_writer.dart';
import 'player_controls_visibility.dart';

export 'player_controls_visibility.dart' show PlayerControlHold;

/// Owns one pinned playback route. A committed route exit releases its session
/// after the transition; an active PiP session retains ownership until it stops.
class PlaybackController extends ChangeNotifier {
  PlaybackController({
    required this.input,
    required this.backend,
    required this.history,
    DateTime Function()? now,
  }) {
    _controls = PlayerControlsVisibility(onChanged: _notify);
    _historyWriter = PlaybackHistoryWriter(
      selection: input.selection,
      repository: history,
      now: now ?? DateTime.now,
      onError: (error) {
        message = '观看记录保存失败：$error';
        _notify();
      },
    );
  }

  final PlaybackInput input;
  final PlaybackBackend backend;
  final HistoryRepository history;

  late final PlayerControlsVisibility _controls;
  late final PlaybackHistoryWriter _historyWriter;

  PlaybackSession? session;
  PlaybackSnapshot value = const PlaybackSnapshot();
  String? message;
  bool loading = false;
  bool switchingSource = false;

  bool _released = false;
  Future<void>? _releaseCompletion;
  Future<void>? _sessionDisposal;
  bool _disposed = false;

  bool _pipRequested = false;
  bool _retainedForPip = false;
  bool _backgrounded = false;
  bool _exiting = false;

  int _generation = 0;
  StreamSubscription<PlaybackSnapshot>? _subscription;
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
    _controls.detach(PlayerControlHold.gesture);

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

  bool get controlsVisible => _controls.visible;
  set controlsVisible(bool visible) => _controls.visible = visible;

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
    _controls.cancelTimer();
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
      if (_retainedForPip && !snapshot.inPip) {
        unawaited(_disposeSession().catchError(_reportCleanupFailure));
      }
      return;
    }

    if (wasPlaying && !snapshot.playing || snapshot.ended) _saveHistory();
    _historyWriter.saveAdvancingProgress(snapshot);

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
    final changed = _controls.hold(hold, reason);
    if (!changed) return;

    showControls();
  }

  /// Detaching a held control only releases ownership. Its disposal may happen
  /// while the widget tree is locked, so visibility notifications stay with the
  /// already scheduled hide timer rather than rebuilding the disposing tree.
  void detachControlHold(PlayerControlHold reason) {
    if (_controls.detach(reason)) _updateVisibility();
  }

  void toggleControls() {
    if (_released) return;

    _controls.toggle();
    _updateVisibility();
    _notify();
  }

  void showControls() {
    if (_released) return;

    _controls.show();
    _updateVisibility();
    _notify();
  }

  void _updateVisibility() {
    if (_released) return;

    _controls.update(
      uninterruptedPlayback:
          value.playing &&
          !value.buffering &&
          value.error == null &&
          message == null &&
          !loading &&
          !switchingSource,
    );
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

  void _saveHistory() => _historyWriter.save(value);

  Future<void> flushHistory() => _historyWriter.flush();

  /// Called only after navigation commits, never from a speculative back gesture.
  Future<void> commitExit() async {
    _exiting = true;
    await cancelGestures();

    try {
      if (!value.inPip) await session?.pause();
    } catch (error) {
      message = '无法暂停播放：$error';
      _notify();
    }

    // A failed native pause must not discard the committed route's checkpoint.
    _saveHistory();
    await flushHistory();
  }

  Future<void> release() => _releaseCompletion ??= _releaseOnce();

  Future<void> _releaseOnce() async {
    _released = true;
    if (seekPreview != null || temporarySpeed || _pendingSpeedChanges > 0) {
      await cancelGestures();
    }

    ++_generation;
    _controls.dispose();

    _saveHistory();
    await flushHistory();

    if (value.inPip) {
      _retainedForPip = true;
    } else {
      try {
        await _disposeSession();
      } catch (error) {
        _reportCleanupFailure(error);
      }
    }
  }

  void _reportCleanupFailure(Object error) {
    message = '播放资源释放失败：$error';
    if (_disposed) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          library: 'playback',
          context: ErrorDescription('while releasing the playback route'),
        ),
      );
    } else {
      _notify();
    }
  }

  Future<void> _disposeSession() {
    final pending = _sessionDisposal;
    if (pending != null) return pending;

    final disposal = _disposeOwnedSession();
    _sessionDisposal = disposal;
    return disposal.whenComplete(() => _sessionDisposal = null);
  }

  Future<void> _disposeOwnedSession() async {
    _retainedForPip = false;
    final owned = session;
    session = null;
    final observation = _subscription;
    _subscription = null;

    // Subscription and native resources have independent cleanup obligations.
    try {
      await observation?.cancel();
    } finally {
      await owned?.dispose();
    }
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
