import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/playback/player_environment.dart';
import 'playback_controller.dart';
import 'player_environment_controller.dart';

enum _Drag { seek, brightness, volume }

/// This layer sits beneath controls, so buttons and sliders own their arenas.
class PlayerGestures extends StatefulWidget {
  const PlayerGestures({
    super.key,
    required this.controller,
    required this.fullscreen,
    this.environment,
  });

  final PlaybackController controller;
  final bool fullscreen;
  final PlayerEnvironment? environment;

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures>
    with WidgetsBindingObserver {
  PlayerEnvironmentController? effects;

  final pointers = <int>{};
  Offset origin = Offset.zero;
  Offset movement = Offset.zero;
  _Drag? drag;
  bool blocked = false;
  int generation = 0;
  int playerEpoch = 0;

  Size? viewSize;
  double? pixelRatio;

  Future<void> volumeChanges = Future.value();

  String? hud;
  Timer? hudTimer;
  Timer? hintTimer;

  PlaybackController get player => widget.controller;

  @override
  void initState() {
    super.initState();

    effects = widget.environment == null
        ? null
        : PlayerEnvironmentController(widget.environment!);

    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    viewSize = view.physicalSize;
    pixelRatio = view.devicePixelRatio;
    WidgetsBinding.instance.addObserver(this);

    playerEpoch = player.gestureEpoch;
    player.addListener(_playerChanged);

    if (widget.fullscreen) _run(_enter());
  }

  void _playerChanged() {
    if (playerEpoch == player.gestureEpoch) return;

    playerEpoch = player.gestureEpoch;
    generation++;
    blocked = true;
    drag = null;
    if (mounted) setState(() => hud = null);
  }

  void _run(Future<void> work) {
    final token = generation;
    unawaited(
      work.catchError((Object error) {
        if (mounted && token == generation) {
          setState(() => hud = '调整失败');
        }
      }),
    );
  }

  @override
  void didUpdateWidget(covariant PlayerGestures old) {
    super.didUpdateWidget(old);

    if (old.fullscreen != widget.fullscreen) {
      _cancel();
      if (widget.fullscreen) {
        _run(_enter());
      } else {
        _run(effects?.leaveFullscreen() ?? Future.value());
      }
    }
  }

  Future<void> _enter() async {
    final token = generation;
    await effects?.enterFullscreen();
    if (!mounted || !widget.fullscreen || token != generation) return;

    _scheduleHint();
  }

  void _scheduleHint() {
    hintTimer?.cancel();
    final token = generation;
    hintTimer = Timer(const Duration(milliseconds: 700), () {
      _run(() async {
        if (!mounted ||
            !widget.fullscreen ||
            token != generation ||
            MediaQuery.accessibleNavigationOf(context)) {
          return;
        }

        final needed = await widget.environment?.needsGestureHint() ?? false;
        if (!mounted || !widget.fullscreen || token != generation || !needed) {
          return;
        }

        _show(
          widget.environment?.supportsVolumeDrag == true
              ? '双击播放 · 横滑进度 · 长按 2×\n左侧亮度 · 右侧音量'
              : '双击播放 · 横滑进度 · 长按 2×\n左侧亮度 · 音量使用顶部滑块',
        );
        await widget.environment?.acknowledgeGestureHint();
      }());
    });
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (viewSize == view.physicalSize && pixelRatio == view.devicePixelRatio) {
      return;
    }

    viewSize = view.physicalSize;
    pixelRatio = view.devicePixelRatio;

    _cancel();
    if (widget.fullscreen) _scheduleHint();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();

    // An inactive window can remain visible during OS focus changes. Cancel
    // its gesture, but keep brightness ownership until it actually backgrounds.
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _run(effects?.leaveFullscreen() ?? Future.value());
    } else if (state == AppLifecycleState.resumed && widget.fullscreen) {
      _run(_enter());
    }
  }

  void _show(String text) {
    hudTimer?.cancel();
    if (!mounted) return;

    setState(() => hud = text);
    hudTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => hud = null);
    });
  }

  void _cancel() {
    hintTimer?.cancel();
    blocked = true;
    generation++;

    final wasDragging = drag != null;
    drag = null;
    if (wasDragging) {
      player.holdControls(false, reason: PlayerControlHold.gesture);
    }

    movement = Offset.zero;
    lastVolume = null;
    volumeRemainder = 0;

    _run(player.cancelGestures());
    playerEpoch = player.gestureEpoch;
    if (mounted) setState(() => hud = null);
  }

  void _down(PointerDownEvent event, Size size) {
    playerEpoch = player.gestureEpoch;
    pointers.add(event.pointer);
    if (pointers.length > 1) {
      blocked = true;
      _cancel();
      return;
    }

    generation++;
    drag = null;
    lastVolume = null;
    volumeRemainder = 0;

    origin = event.localPosition;
    movement = Offset.zero;
    blocked =
        origin.dx < 24 ||
        origin.dx > size.width - 24 ||
        origin.dy < 16 ||
        origin.dy > size.height - 16;
  }

  double volumeRemainder = 0;
  double? lastVolume;

  Future<void> _changeVolume(double delta) async {
    final token = generation;
    volumeChanges = volumeChanges.catchError((Object _) {}).then((_) async {
      if (token != generation) return;

      final current = await widget.environment!.volume();
      if (token != generation) return;

      if (lastVolume != null && (current - lastVolume!).abs() > .001) {
        volumeRemainder = 0;
      }
      final target = (current + volumeRemainder + delta).clamp(0.0, 1.0);

      await widget.environment!.setVolume(target);
      final actual = await widget.environment!.volume();
      if (token != generation) return;

      volumeRemainder = target - actual;
      lastVolume = actual;
      if (mounted) _show('音量 ${(actual * 100).round()}%');
    });
    await volumeChanges;
  }

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  void _updateDrag(DragUpdateDetails details, Size size) {
    if (playerEpoch != player.gestureEpoch) {
      _playerChanged();
      return;
    }
    if (blocked) return;

    movement += details.delta;
    if (drag == null) {
      if (movement.distance < 18) return;
      if (movement.dx.abs() > movement.dy.abs() * 1.2) {
        drag = _Drag.seek;
      } else if (widget.fullscreen &&
          movement.dy.abs() > movement.dx.abs() * 1.2) {
        if (origin.dx < size.width / 2) {
          drag = _Drag.brightness;
        } else if (widget.environment?.supportsVolumeDrag == true) {
          drag = _Drag.volume;
        } else {
          return;
        }
      } else {
        return;
      }
      player.holdControls(true, reason: PlayerControlHold.gesture);
    }

    switch (drag) {
      case _Drag.seek:
        player.previewSeek(movement.dx / size.width);
        final target = player.seekPreview;
        if (target != null) {
          _show(
            '${movement.dx >= 0 ? '+' : '−'}${(movement.dx.abs() / size.width * (player.value.duration!.inSeconds.clamp(0, 120))).round()} 秒 · ${_time(target)} / ${_time(player.value.duration!)}',
          );
        }
      case _Drag.brightness:
        final token = generation;
        _run(() async {
          await effects?.changeBrightness(-details.delta.dy / size.height);
          if (mounted && token == generation && drag == _Drag.brightness) {
            _show('亮度 ${((effects?.brightnessValue ?? 0) * 100).round()}%');
          }
        }());
      case _Drag.volume:
        _run(_changeVolume(-details.delta.dy / size.height));
      case null:
        break;
    }
  }

  Future<void> _finishDrag() async {
    // Pointer ownership ends before native work settles. A new interaction gets
    // its own axis and generation, and old completions cannot release its hold.
    final completedDrag = drag;
    drag = null;
    player.holdControls(false, reason: PlayerControlHold.gesture);

    if (completedDrag == _Drag.seek) await player.finishSeek(commit: true);
    if (completedDrag == _Drag.volume) await volumeChanges;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    player.removeListener(_playerChanged);

    generation++;
    hudTimer?.cancel();
    hintTimer?.cancel();

    unawaited(
      (effects?.leaveFullscreen() ?? Future<void>.value()).catchError(
        (Object _) {},
      ),
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        !MediaQuery.accessibleNavigationOf(context) &&
        !player.value.inPip &&
        player.value.initialized &&
        !player.loading &&
        !player.switchingSource &&
        !player.canRetry;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        return Listener(
          onPointerDown: (event) => _down(event, size),
          onPointerUp: (event) => pointers.remove(event.pointer),
          onPointerCancel: (event) {
            pointers.remove(event.pointer);
            _cancel();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: enabled
                  ? () {
                      if (!blocked) player.toggleControls();
                    }
                  : null,
              onDoubleTap: enabled
                  ? () {
                      if (!blocked) _run(player.togglePlayback());
                    }
                  : null,
              onLongPressStart: enabled
                  ? (_) {
                      if (!blocked) {
                        _run(player.beginTemporarySpeed());
                        if (player.temporarySpeed) _show('2× 快进中');
                      }
                    }
                  : null,
              onLongPressEnd: enabled ? (_) => _cancel() : null,
              onLongPressCancel: enabled
                  ? () {
                      if (player.temporarySpeed) _cancel();
                    }
                  : null,
              onPanUpdate: enabled && widget.fullscreen
                  ? (details) => _updateDrag(details, size)
                  : null,
              onHorizontalDragUpdate: enabled && !widget.fullscreen
                  ? (details) => _updateDrag(details, size)
                  : null,
              onHorizontalDragEnd: enabled && !widget.fullscreen
                  ? (_) => _run(_finishDrag())
                  : null,
              onHorizontalDragCancel: enabled && !widget.fullscreen
                  ? () {
                      if (drag != null) _cancel();
                    }
                  : null,
              onPanEnd: enabled && widget.fullscreen
                  ? (_) => _run(_finishDrag())
                  : null,
              onPanCancel: enabled && widget.fullscreen
                  ? () {
                      if (drag != null) _cancel();
                    }
                  : null,
              child: Stack(
                children: [
                  if (hud != null)
                    Center(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              hud!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
