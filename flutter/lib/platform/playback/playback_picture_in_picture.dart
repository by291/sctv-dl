import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pip_kit/pip_kit.dart';
import 'package:video_player/video_player.dart';

/// Owns the single system PiP window and retains its original video controller.
/// Uses pip_kit's public platform API; Android's authoritative Activity callback
/// is delivered on our own channel, independently of plugin implementation.
class PlaybackPictureInPicture {
  PlaybackPictureInPicture({
    required this.onChanged,
    required this.play,
    required this.pause,
    required this.onError,
  }) {
    _platform.setHandlers(
      onStatus: (active) {
        if (defaultTargetPlatform != TargetPlatform.android) {
          _status.value = active;
        }
      },
      onAction: (action) {
        final owner = _owner;
        if (owner == null || !_status.value) return;
        final operation = switch (action) {
          'play' => owner.play,
          'pause' => owner.pause,
          _ => null,
        };
        if (operation != null) unawaited(operation().catchError(owner.onError));
      },
    );
    _androidEvents.setMethodCallHandler((call) async {
      if (call.method == 'changed') _status.value = call.arguments == true;
      if (call.method == 'stopped') {
        final owner = _owner;
        if (owner != null) unawaited(owner.pause().catchError(owner.onError));
      }
    });
  }

  static final PipPlatform _platform = MethodChannelPipPlatform();
  static const _androidEvents = MethodChannel(
    'dev.sctvdl.flutter/picture_in_picture',
  );
  static final _status = ValueNotifier(false);
  static final _video = ValueNotifier<VideoPlayerController?>(null);
  static PlaybackPictureInPicture? _owner;

  final void Function(bool) onChanged;
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final void Function(Object, StackTrace) onError;
  bool _observing = false;
  Future<void>? _entry;

  Future<bool> isSupported() => _platform.isSupported();

  static Future<bool> exit() => _platform.exit();

  Future<void> enter(VideoPlayerController video, String title) =>
      _entry ??= _enter(video, title).whenComplete(() => _entry = null);

  Future<void> _enter(VideoPlayerController video, String title) async {
    if (_owner != this && _status.value) {
      throw StateError('Another playback session owns picture in picture');
    }
    if (_owner != this) await _owner?.release();
    _owner = this;
    if (!_observing) {
      _observing = true;
      _status.addListener(_statusChanged);
    }
    _video.value = video;
    try {
      final ready = await _platform.configure({
        ...PipOptions(
          aspectRatio: PipAspectRatio.fromSize(video.value.size),
          title: title,
          actions: const [
            PipAction(id: 'play', label: '播放', icon: PipActionIcon.play),
            PipAction(id: 'pause', label: '暂停', icon: PipActionIcon.pause),
          ],
        ).toMap(),
        'mode': 'video',
      });
      if (!ready) {
        throw StateError('The video layer is not ready for picture in picture');
      }
      // AVKit can discover the layer before it becomes eligible for PiP.
      // Retry this explicit request within a bounded readiness window; never
      // arm automatic entry or manufacture a successful native status.
      var accepted = await _platform.enter();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!accepted &&
          !_status.value &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        accepted = await _platform.enter();
      }
      if (!accepted && !_status.value) {
        throw StateError('The system declined picture in picture');
      }
      await _waitForStatus(true);
    } catch (_) {
      await _disarm();
      rethrow;
    }
  }

  void _statusChanged() {
    if (_owner == this) onChanged(_status.value);
  }

  Future<void> _waitForStatus(bool active) async {
    if (_status.value == active) return;
    final settled = Completer<void>();
    void observe() {
      if (_status.value == active && !settled.isCompleted) settled.complete();
    }

    _status.addListener(observe);
    try {
      await settled.future.timeout(const Duration(seconds: 3));
    } finally {
      _status.removeListener(observe);
    }
  }

  Future<void> _disarm() async {
    if (_owner != this) return;
    if (_status.value) {
      // Android release only clears parameters, so leave the system window
      // before dropping its content or releasing the original decoder.
      final accepted = await exit();
      if (!accepted && _status.value) {
        throw StateError('The system declined picture-in-picture exit');
      }
      await _waitForStatus(false);
    }
    await _platform.release();
    _video.value = null;
    _owner = null;
    onChanged(false);
  }

  Future<void> release() async {
    try {
      await _entry;
    } catch (_) {
      // Entry's caller owns its failure; cleanup must still run.
    }
    if (_observing) _status.removeListener(_statusChanged);
    _observing = false;
    await _disarm();
  }
}

/// Android shrinks the whole Activity; cover the mounted app with the same
/// decoder's texture while PiP retains a session beyond its route's lifetime.
class PlaybackPipHost extends StatelessWidget {
  const PlaybackPipHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      PlaybackPictureInPicture._status,
      PlaybackPictureInPicture._video,
    ]),
    builder: (context, child) {
      final video = PlaybackPictureInPicture._video.value;
      return Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          child!,
          if (defaultTargetPlatform == TargetPlatform.android &&
              PlaybackPictureInPicture._status.value &&
              video != null)
            ColoredBox(
              color: const Color(0xff000000),
              child: Center(
                child: AspectRatio(
                  aspectRatio: video.value.aspectRatio,
                  child: VideoPlayer(video),
                ),
              ),
            ),
        ],
      );
    },
    child: child,
  );
}
