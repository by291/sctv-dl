import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';

enum PlayerControlHold { interaction, accessibility, focus, seek, menu }

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
      if (speed != 1) {
        try {
          await opened.setSpeed(speed);
        } catch (error) {
          message = '播放速度恢复失败：$error';
        }
      }
      if (_released || generation != _generation) {
        await opened.dispose();
        return;
      }
      session = opened;
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
    if (snapshot.initialized && snapshot.error == null) _lastUsable = snapshot;
    value = snapshot;
    if (_released) {
      if (!snapshot.inPip) unawaited(_disposeSession());
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

  Future<void> setSpeed(double speed) =>
      _action(() async => session?.setSpeed(speed));

  Future<void> selectSource(VideoSource source) async {
    if (switchingSource || session == null || value.source?.url == source.url) {
      return;
    }
    switchingSource = true;
    showControls();
    try {
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
    if (hold) {
      _controlHolds.add(reason);
    } else {
      _controlHolds.remove(reason);
    }
    showControls();
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
    if (!value.inPip) await session?.pause();
    _saveHistory();
    await flushHistory();
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    ++_generation;
    _hideTimer?.cancel();
    _saveHistory();
    await flushHistory();
    if (!value.inPip) await _disposeSession();
  }

  Future<void> _disposeSession() async {
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
