import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../domain/downloads/file_gateway.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';
import 'playback_audio_focus.dart';
import 'playback_picture_in_picture.dart';
import 'playback_wakelock.dart';

class VideoPlayerBackend implements PlaybackBackend {
  VideoPlayerBackend({required this.userAgent});

  final String userAgent;
  final _releases = _NativePlayerReleases();

  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    if (input.localLocation == null &&
        (input.sources.isEmpty ||
            input.sources.any((source) => !isAllowedMediaUrl(source.url)))) {
      throw const FormatException('Unsupported media source');
    }

    var resolved = input;
    if (input.localLocation case final String location) {
      final stored = DownloadFileLocation.parse(location);
      final path = switch (stored) {
        ContentFileLocation(:final uri) => uri.toString(),
        PrivateFileLocation(:final documents, :final relativePath) =>
          '${(documents ? await getApplicationDocumentsDirectory() : await getApplicationSupportDirectory()).path}/$relativePath',
      };

      resolved = PlaybackInput(
        title: input.title,
        sources: input.sources,
        selection: input.selection,
        initialPosition: input.initialPosition,
        localLocation: path,
        preferredQuality: input.preferredQuality,
      );
    }

    await _releases.waitForPending();
    final session = _VideoSession(resolved, userAgent, _releases);
    try {
      await session.initialize();
      return session;
    } catch (error, stack) {
      try {
        await session.dispose();
      } catch (cleanup, cleanupStack) {
        developer.log(
          'Playback opening cleanup failed',
          error: cleanup,
          stackTrace: cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }
}

class _VideoSession with WidgetsBindingObserver implements PlaybackSession {
  _VideoSession(this.input, this.userAgent, this._releases)
    : id = 'playback-${++_nextId}' {
    _pip = PlaybackPictureInPicture(
      onChanged: (active) {
        _inPip = active;
        if (!active && !_playIntent) {
          unawaited(_audio?.deactivate().catchError(_reportError));
        }
        _publish();
      },
      play: play,
      pause: pause,
      onError: _reportError,
    );
  }

  static int _nextId = 0;
  final PlaybackInput input;
  final String userAgent;
  final _NativePlayerReleases _releases;
  final surface = ValueNotifier<VideoPlayerController?>(null);
  final _changes = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _wakelock = PlaybackWakelock();
  late final PlaybackPictureInPicture _pip;
  PlaybackAudioFocus? _audio;

  VideoPlayerController? _controller;
  VideoSource? _source;
  PlaybackSnapshot _value = const PlaybackSnapshot();
  bool _supportsPip = false;
  bool _inPip = false;
  bool _disposed = false;
  bool _switching = false;
  bool _playIntent = false;
  Future<void> _playbackWrites = Future.value();
  int _pendingPlaybackWrites = 0;
  int _playbackRevision = 0;
  Completer<void>? _sourceSettled;
  Future<void>? _disposal;
  final _cancelled = Completer<void>();
  bool _nativeReleaseFailed = false;

  @override
  final String id;

  @override
  PlaybackSnapshot get value => _value;

  @override
  Stream<PlaybackSnapshot> get changes => _changes.stream;

  Future<void> initialize() async {
    _audio = PlaybackAudioFocus(
      await AudioSession.instance,
      pause: pause,
      onError: _reportError,
    );
    _source = input.sources.firstOrNull;
    await _replace(_source, input.initialPosition, 1);
    _supportsPip = await _pip.isSupported();
    WidgetsBinding.instance.addObserver(this);
    _publish();
  }

  VideoPlayerController _create(VideoSource? source) {
    // The route owns background pausing; automatic plugin pausing would also
    // stop active PiP. iOS PiP needs the visible AVPlayerLayer of a platform view.
    final options = VideoPlayerOptions(
      // audio_session owns focus, preventing the native player from silently
      // resuming after an interruption. Its configuration remains exclusive.
      mixWithOthers: defaultTargetPlatform == TargetPlatform.android,
      allowBackgroundPlayback: true,
      preventsDisplaySleepDuringVideoPlayback: false,
    );
    final viewType = defaultTargetPlatform == TargetPlatform.iOS
        ? VideoViewType.platformView
        : VideoViewType.textureView;

    if (input.localLocation case final String location) {
      final uri = Uri.tryParse(location);
      if (uri?.scheme == 'content') {
        return VideoPlayerController.contentUri(
          uri!,
          videoPlayerOptions: options,
          viewType: viewType,
        );
      }
      return VideoPlayerController.file(
        File(uri?.scheme == 'file' ? uri!.toFilePath() : location),
        videoPlayerOptions: options,
        viewType: viewType,
      );
    }
    if (source == null || !isAllowedMediaUrl(source.url)) {
      throw const FormatException('Unsupported media source');
    }
    return VideoPlayerController.networkUrl(
      Uri.parse(source.url),
      httpHeaders: {
        'Referer': 'https://scgc.video.play/',
        'User-Agent': userAgent,
      },
      formatHint: VideoFormat.other,
      videoPlayerOptions: options,
      viewType: viewType,
    );
  }

  Future<void> _replace(
    VideoSource? source,
    Duration position,
    double speed,
  ) async {
    final previous = _controller;
    if (_nativeReleaseFailed) {
      throw StateError('The previous decoder could not be released');
    }
    surface.value = null;
    previous?.removeListener(_publish);
    // Official controllers have immutable sources. Waiting for native release
    // keeps two decoders and their forward buffers from overlapping on a switch.
    if (previous != null) await _releaseNative(previous);
    _controller = null;
    if (_disposed) return;

    final next = _create(source);
    _controller = next;
    next.addListener(_publish);
    // Disposal cancels our wait even if the decoder never reports readiness.
    // Native disposal still owns cancellation of its transport and allocation.
    final expired = Completer<void>();
    final deadline = Timer(const Duration(seconds: 30), () {
      expired.completeError(TimeoutException('Video initialization timed out'));
    });
    try {
      await Future.any([next.initialize(), _cancelled.future, expired.future]);
    } finally {
      deadline.cancel();
    }
    if (_disposed) return;

    await _audio?.configure();
    if (position > Duration.zero) await next.seekTo(position);
    await next.setPlaybackSpeed(speed);
    if (_disposed) return;
    surface.value = next;
  }

  void _publish() {
    final native = _controller?.value;
    if (_disposed || _switching || native == null) return;
    // AVKit's system controls change AVPlayer directly. The official plugin
    // reports the rate but does not restart its Dart position timer or update
    // its native play intent. Reconcile only iOS PiP transitions: Android's
    // isPlaying also becomes false during buffering and must not become pause.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _inPip &&
        _pendingPlaybackWrites == 0 &&
        native.isPlaying != _value.playing &&
        native.isPlaying != _playIntent) {
      unawaited(_setPlaying(native.isPlaying).catchError(_reportError));
    }
    final duration = native.duration;
    final ended =
        native.isCompleted ||
        duration > Duration.zero && native.position >= duration;
    if (ended && _playIntent) {
      _playIntent = false;
      unawaited(_audio?.deactivate().catchError(_reportError));
    }
    _value = PlaybackSnapshot(
      initialized: native.isInitialized,
      playing: native.isPlaying || (_playIntent && native.isBuffering),
      buffering: native.isBuffering,
      position: native.position,
      duration: duration > Duration.zero ? duration : null,
      speed: native.playbackSpeed,
      source: _source,
      error: native.errorDescription,
      supportsPip: _supportsPip,
      inPip: _inPip,
      ended: ended,
    );
    _updateWakelock();
    _changes.add(_value);
  }

  void _reportError(Object error, StackTrace stack) {
    if (!_disposed) _changes.addError(error, stack);
  }

  void _updateWakelock() {
    final state = WidgetsBinding.instance.lifecycleState;
    unawaited(
      _wakelock
          .setEnabled(
            !_disposed &&
                value.playing &&
                !_inPip &&
                (state == null || state == AppLifecycleState.resumed),
          )
          .catchError(_reportError),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _updateWakelock();

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _setPlaying(true);
  }

  @override
  Future<void> pause() async {
    await _setPlaying(false);
  }

  Future<void> _setPlaying(bool playing) {
    _playIntent = playing;
    final revision = ++_playbackRevision;
    final native = _controller;
    if (_disposed || native == null || (_switching && playing)) {
      return Future.value();
    }
    _pendingPlaybackWrites++;
    final write = _playbackWrites.then((_) async {
      try {
        if (_disposed ||
            native != _controller ||
            revision != _playbackRevision) {
          return;
        }
        if (playing) {
          await _audio?.activate();
          if (_disposed || revision != _playbackRevision) return;
          if (native.value.isCompleted ||
              native.value.position >= native.value.duration) {
            await native.seekTo(Duration.zero);
          }
          if (!_disposed && revision == _playbackRevision) await native.play();
        } else {
          await native.pause();
          if (!_inPip) await _audio?.deactivate();
        }
      } finally {
        _pendingPlaybackWrites--;
      }
    });
    _playbackWrites = write.catchError((Object _) {});
    return write;
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_disposed && !_switching) await _controller?.seekTo(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!_disposed && !_switching) await _controller?.setPlaybackSpeed(speed);
  }

  @override
  Future<void> selectSource(VideoSource source) async {
    if (_disposed || _switching || source.url == _source?.url) return;
    if (!input.sources.any((candidate) => candidate.url == source.url) ||
        !isAllowedMediaUrl(source.url)) {
      throw const FormatException('Source was not part of this selection');
    }
    if (_inPip) {
      throw StateError('Exit picture in picture before changing quality');
    }

    final previous = _source!;
    final position = value.position;
    final speed = value.speed;
    final playing = _playIntent && !value.ended;
    _switching = true;
    final settled = _sourceSettled = Completer<void>();
    try {
      await _playbackWrites;
      await _pip.release();
      await _restore(source, position, speed, playing);
      if (!_disposed) _source = source;
    } catch (error) {
      if (!_disposed) {
        try {
          await _restore(previous, position, speed, playing);
        } catch (rollback) {
          _reportError(rollback, StackTrace.current);
          throw StateError(
            'Quality switch failed: $error; restoring previous source failed: $rollback',
          );
        }
      }
      rethrow;
    } finally {
      _switching = false;
      settled.complete();
      _sourceSettled = null;
      _publish();
    }
  }

  Future<void> _restore(
    VideoSource source,
    Duration position,
    double speed,
    bool playing,
  ) async {
    await _replace(source, position, speed);
    if (!_disposed && playing && _playIntent) {
      await _audio?.activate();
      if (!_disposed && _playIntent) await _controller?.play();
    }
  }

  @override
  Future<void> enterPictureInPicture() async {
    final native = _controller;
    if (_disposed || _switching || !_supportsPip || native == null) {
      throw StateError('Picture in picture is unavailable');
    }
    final wasPlaying = value.playing;
    try {
      // AVKit requires a playing layer to enter. Restore an explicit paused
      // intent after entry (or failure), rather than inheriting plugin autoplay.
      if (defaultTargetPlatform == TargetPlatform.iOS && !wasPlaying) {
        await play();
      }
      await _pip.enter(native, input.title);
    } finally {
      if (!wasPlaying) await pause();
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _disposed = true;
    _cancelled.complete();
    _playIntent = false;
    WidgetsBinding.instance.removeObserver(this);
    await _sourceSettled?.future;
    await _playbackWrites;
    final native = _controller;
    native?.removeListener(_publish);
    (Object, StackTrace)? failure;
    Future<void> cleanup(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }

    await cleanup(_pip.release);
    if (native != null && !_releases.hasStarted(native)) {
      await cleanup(native.pause);
    }
    await cleanup(() async {
      if (native != null) await _releaseNative(native);
    });
    await cleanup(() => _wakelock.setEnabled(false));
    await cleanup(() async => _audio?.dispose());
    await cleanup(_changes.close);
    surface.dispose();
    if (failure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _releaseNative(VideoPlayerController controller) async {
    // video_player 2.14 leaves its creation completer pending if native
    // allocation throws. Bound cleanup so opening/rollback can report the
    // original error instead of leaving the route permanently loading.
    try {
      await _releases.release(controller);
    } catch (_) {
      // A timeout is not proof of release. Fail closed: this session must never
      // allocate a replacement while the old native release is unconfirmed.
      _nativeReleaseFailed = true;
      rethrow;
    }
  }
}

/// Keeps release ownership beyond a route/session failure. Upstream's second
/// dispose returns early, so retries must join the original native completion.
class _NativePlayerReleases {
  final _operations = Expando<Future<void>>();
  final _pending = <Future<void>>{};

  bool hasStarted(VideoPlayerController controller) =>
      _operations[controller] != null;

  Future<void> release(VideoPlayerController controller) {
    var operation = _operations[controller];
    if (operation == null) {
      operation = controller.dispose();
      _operations[controller] = operation;
      _pending.add(operation);
      final owned = operation;
      unawaited(
        operation.then(
          (_) {
            _pending.remove(owned);
          },
          onError: (Object _, StackTrace _) {
            // Keep failed releases as a barrier: failure is not confirmation that
            // transport, buffers and the native decoder have been released.
          },
        ),
      );
    }
    return operation.timeout(const Duration(seconds: 5));
  }

  Future<void> waitForPending() async {
    await Future.wait(_pending).timeout(const Duration(seconds: 5));
  }
}

class PlaybackSurface extends StatelessWidget {
  const PlaybackSurface({super.key, required this.session});
  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    final native = session;
    if (native is! _VideoSession) {
      throw ArgumentError('Unsupported playback session');
    }
    return ValueListenableBuilder(
      valueListenable: native.surface,
      builder: (context, controller, _) => controller == null
          ? const SizedBox.expand()
          : ValueListenableBuilder(
              valueListenable: controller,
              builder: (context, value, child) => Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio,
                  child: child,
                ),
              ),
              child: VideoPlayer(controller, key: ObjectKey(controller)),
            ),
    );
  }
}
