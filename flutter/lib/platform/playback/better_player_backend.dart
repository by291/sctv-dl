import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/downloads/file_gateway.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';

class BetterPlayerBackend implements PlaybackBackend {
  BetterPlayerBackend({required this.userAgent});

  final String userAgent;

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

    final session = _BetterSession(resolved, userAgent);
    try {
      await session.initialize();
      return session;
    } catch (_) {
      await session.dispose();
      rethrow;
    }
  }
}

class _BetterSession with WidgetsBindingObserver implements PlaybackSession {
  _BetterSession(this.input, this.userAgent)
    : id = 'playback-${++_nextId}',
      controller = BetterPlayerController(
        const BetterPlayerConfiguration(
          autoDispose: false,
          handleLifecycle: false,
          fit: BoxFit.contain,
          controlsConfiguration: BetterPlayerControlsConfiguration(
            showControls: false,
          ),
        ),
      );

  static int _nextId = 0;

  // Bound the requested prefetch window using the upstream API. This is not a
  // byte budget; high-bitrate streams still require the low-memory regression.
  static const _buffering = BetterPlayerBufferingConfiguration(
    minBufferMs: 10000,
    maxBufferMs: 30000,
  );

  final PlaybackInput input;
  final String userAgent;
  final BetterPlayerController controller;
  final GlobalKey surfaceKey = GlobalKey();

  final _changes = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  VideoSource? _source;
  bool _supportsPip = false;

  bool _disposed = false;
  Future<void>? _disposal;

  bool _switching = false;
  bool _playIntent = false;

  PlaybackSnapshot _value = const PlaybackSnapshot();

  @override
  final String id;

  @override
  PlaybackSnapshot get value => _value;

  @override
  Stream<PlaybackSnapshot> get changes => _changes.stream;

  Future<void> initialize() async {
    _source = input.sources.firstOrNull;
    await _prepare(_source, input.initialPosition);

    WidgetsBinding.instance.addObserver(this);
    controller.videoPlayerController!.addListener(_publish);
    controller.setMixWithOthers(false);
    _supportsPip = await controller.isPictureInPictureSupported();
    await controller.pause();

    _publish();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The upstream Android engine has no PiP-exit event. Its higher-level
    // controller reconciles on resume; our application-owned session does too.
    if (!_disposed &&
        defaultTargetPlatform == TargetPlatform.android &&
        state == AppLifecycleState.resumed &&
        controller.videoPlayerController!.value.isPip) {
      final native = controller.videoPlayerController!;
      native.value = native.value.copyWith(isPip: false);
    }
  }

  Future<void> _prepare(VideoSource? source, Duration position) async {
    await controller.setupDataSource(_dataSource(source));

    // setupDataSource resets iOS gravity; retain uncropped rendering on every
    // source change through the native controller's public setter.
    await controller.videoPlayerController!.setAspectRatio('aspect');
    if (position > Duration.zero) await controller.seekTo(position);
  }

  BetterPlayerDataSource _dataSource(VideoSource? source) {
    if (input.localLocation case final String location) {
      final uri = Uri.tryParse(location);
      // The native data source supports content URIs. An explicit format avoids
      // extension guessing for MediaStore IDs, which have no file extension.
      if (uri?.scheme == 'content') {
        return BetterPlayerDataSource.network(
          location,
          videoFormat: BetterPlayerVideoFormat.other,
          bufferingConfiguration: _buffering,
        );
      }
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : location;
      return BetterPlayerDataSource(
        BetterPlayerDataSourceType.file,
        path,
        bufferingConfiguration: _buffering,
      );
    }

    if (source == null || !isAllowedMediaUrl(source.url)) {
      throw const FormatException('Unsupported media source');
    }

    return BetterPlayerDataSource.network(
      source.url,
      headers: {'Referer': 'https://scgc.video.play/', 'User-Agent': userAgent},
      videoFormat: BetterPlayerVideoFormat.other,
      bufferingConfiguration: _buffering,
      useAsmsSubtitles: false,
      useAsmsTracks: false,
      useAsmsAudioTracks: false,
    );
  }

  void _publish() {
    if (_disposed || _switching) return;

    final native = controller.videoPlayerController!.value;
    final duration = native.duration;

    _value = PlaybackSnapshot(
      initialized: native.initialized,
      playing: native.isPlaying,
      buffering: native.isBuffering,
      position: native.position,
      duration: duration != null && duration > Duration.zero ? duration : null,
      speed: native.speed,
      source: _source,
      error: native.errorDescription,
      supportsPip: _supportsPip,
      inPip: native.isPip,
      ended:
          duration != null &&
          duration > Duration.zero &&
          native.position >= duration,
    );
    _changes.add(_value);
  }

  @override
  Future<void> play() async {
    if (!_disposed) {
      _playIntent = true;
      if (value.ended) await controller.seekTo(Duration.zero);
      if (!_disposed && _playIntent) await controller.play();
      _publish();
    }
  }

  @override
  Future<void> pause() async {
    if (!_disposed) {
      _playIntent = false;
      await controller.pause();
      _publish();
    }
  }

  @override
  Future<void> seek(Duration position) async {
    if (!_disposed) {
      await controller.seekTo(position);
      _publish();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (!_disposed) {
      await controller.setSpeed(speed);
      _publish();
    }
  }

  @override
  Future<void> selectSource(VideoSource source) async {
    if (_disposed || _switching || source.url == _source?.url) return;
    if (!input.sources.any((candidate) => candidate.url == source.url) ||
        !isAllowedMediaUrl(source.url)) {
      throw const FormatException('Source was not part of this selection');
    }

    final previous = _source!;
    final position = value.position;
    final speed = value.speed;
    final playing = value.playing;

    _switching = true;
    try {
      await _restore(source, position, speed, playing);

      _source = source;
    } catch (error) {
      // Source changes reuse the native decoder, so rollback restores the old
      // source explicitly rather than claiming its discarded buffer survived.
      try {
        await _restore(previous, position, speed, playing);
      } catch (rollback) {
        throw StateError(
          'Quality switch failed: $error; restoring previous source failed: $rollback',
        );
      }

      rethrow;
    } finally {
      _switching = false;
      _publish();
    }
  }

  Future<void> _restore(
    VideoSource source,
    Duration position,
    double speed,
    bool playing,
  ) async {
    await controller.pause();
    await _prepare(source, position);
    await controller.setSpeed(speed);
    if (playing && _playIntent) await controller.play();
  }

  @override
  Future<void> enterPictureInPicture() async {
    if (!_supportsPip || surfaceKey.currentContext == null) {
      throw StateError('Picture in picture is unavailable');
    }

    // The engine enters PiP without creating a package-owned fullscreen route.
    // This surface and session remain owned by our original route.
    final box = surfaceKey.currentContext!.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);

    final activated = Completer<void>();
    final observation = changes.listen((snapshot) {
      if (snapshot.inPip && !activated.isCompleted) {
        activated.complete();
      }
    });

    try {
      await controller.videoPlayerController!.enablePictureInPicture(
        left: Platform.isIOS ? origin.dx : 0,
        top: Platform.isIOS ? origin.dy : 0,
        width: box.size.width,
        height: box.size.height,
      );
      _publish();
      if (!value.inPip) {
        await activated.future.timeout(const Duration(seconds: 3));
      }
    } finally {
      await observation.cancel();
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _disposeOnce();

  Future<void> _disposeOnce() async {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    final native = controller.videoPlayerController;
    native?.removeListener(_publish);
    (Object, StackTrace)? failure;

    Future<void> cleanup(FutureOr<void> Function() action) async {
      try {
        await action();
      } catch (error, stack) {
        failure ??= (error, stack);
      }
    }

    await cleanup(controller.pause);

    // The wrapper disposes synchronously and starts unobserved native futures.
    // Transfer its native handle to this session so replacement awaits release.
    controller.videoPlayerController = null;
    await cleanup(() => controller.dispose(forceDispose: true));
    await cleanup(() async => native?.dispose());
    await cleanup(_changes.close);

    if (failure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}

class PlaybackSurface extends StatelessWidget {
  const PlaybackSurface({super.key, required this.session});

  final PlaybackSession session;

  @override
  Widget build(BuildContext context) {
    final native = session;
    if (native is! _BetterSession) {
      throw ArgumentError('Unsupported playback session');
    }

    return SizedBox.expand(
      key: native.surfaceKey,
      child: ValueListenableBuilder(
        valueListenable: native.controller.videoPlayerController!,
        builder: (context, value, child) => Center(
          child: AspectRatio(aspectRatio: value.aspectRatio, child: child),
        ),
        child: BetterPlayer(controller: native.controller),
      ),
    );
  }
}
