import 'dart:async';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/playback/playback_backend.dart';
import '../../domain/downloads/file_gateway.dart';
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

class _BetterSession implements PlaybackSession {
  _BetterSession(this.input, this.userAgent)
    : id = 'playback-${++_nextId}',
      controller = BetterPlayerController(
        const BetterPlayerConfiguration(
          autoPlay: false,
          autoDispose: false,
          handleLifecycle: false,
          fit: BoxFit.contain,
          aspectRatioIOS: AspectRatioTypeIOS.aspect,
          aspectRatio: 16 / 9,
          controlsConfiguration: BetterPlayerControlsConfiguration(
            showControls: false,
          ),
        ),
      );
  static int _nextId = 0;
  final PlaybackInput input;
  final String userAgent;
  final BetterPlayerController controller;
  final GlobalKey surfaceKey = GlobalKey();
  final _changes = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  VideoSource? _source;
  bool _supportsPip = false;
  bool _disposed = false;
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
    await controller.setupDataSource(_dataSource(_source));
    controller.videoPlayerController!.addListener(_publish);
    await controller.videoPlayerController!.setMixWithOthers(false);
    _supportsPip = await controller.isPictureInPictureSupported();
    await controller.pause();
    if (input.initialPosition > Duration.zero) {
      await controller.seekTo(input.initialPosition);
    }
    _publish();
  }

  BetterPlayerDataSource _dataSource(VideoSource? source) {
    if (input.localLocation case final String location) {
      final uri = Uri.tryParse(location);
      final path = uri?.scheme == 'file' ? uri!.toFilePath() : location;
      return BetterPlayerDataSource.file(path);
    }
    if (source == null || !isAllowedMediaUrl(source.url)) {
      throw const FormatException('Unsupported media source');
    }
    return BetterPlayerDataSource.network(
      source.url,
      headers: {'Referer': 'https://scgc.video.play/', 'User-Agent': userAgent},
      videoFormat: BetterPlayerVideoFormat.other,
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
      await controller.play();
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
      // setupDataSource reuses the native decoder, so rollback restores the old
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
    await controller.setupDataSource(_dataSource(source));
    await controller.seekTo(position);
    await controller.setSpeed(speed);
    if (playing && _playIntent) await controller.play();
  }

  @override
  Future<void> enterPictureInPicture() async {
    if (!_supportsPip || surfaceKey.currentContext == null) {
      throw StateError('Picture in picture is unavailable');
    }
    // Call the low-level API to avoid the package creating its own fullscreen
    // route. This surface and session remain owned by our original route.
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
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    controller.videoPlayerController?.removeListener(_publish);
    await controller.pause();
    final native = controller.videoPlayerController;
    controller.dispose(forceDispose: true);
    await native?.dispose();
    await _changes.close();
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
      child: BetterPlayer(controller: native.controller),
    );
  }
}
