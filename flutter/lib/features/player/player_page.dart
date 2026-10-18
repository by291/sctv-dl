import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/playback/player_environment.dart';
import '../../domain/programmes/programme.dart';
import 'playback_controller.dart';
import 'playback_cover.dart';
import 'player_controls.dart';
import 'player_gestures.dart';
import 'player_window_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.input,
    required this.backend,
    required this.surfaceBuilder,
    required this.history,
    this.onDownload,
    this.environment,
    this.systemVolume,
  });

  final PlayerEnvironment? environment;
  final Widget? systemVolume;
  final PlaybackInput input;
  final PlaybackBackend backend;
  final Widget Function(PlaybackSession) surfaceBuilder;
  final HistoryRepository history;
  final Future<void> Function()? onDownload;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final PlaybackController controller;

  bool fullscreen = false;
  bool downloading = false;
  bool accessibleNavigation = false;
  bool controlsFocused = false;

  final detailsScroll = ScrollController();
  final window = PlayerWindowController();

  final surfaceKey = GlobalKey();
  final surfacePointers = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    controller = PlaybackController(
      input: widget.input,
      backend: widget.backend,
      history: widget.history,
    );

    FocusManager.instance.addHighlightModeListener(_highlightChanged);
    unawaited(controller.initialize());
  }

  void _highlightChanged(FocusHighlightMode mode) => _updateFocusHold();

  void _updateFocusHold() {
    controller.holdControls(
      controlsFocused &&
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional,
      reason: PlayerControlHold.focus,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    controller.holdControls(
      accessibleNavigation,
      reason: PlayerControlHold.accessibility,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) controller.foreground();
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      unawaited(controller.background());
    }
  }

  Future<void> _toggleFullscreen() async {
    await controller.cancelGestures();
    if (!mounted) return;

    setState(() => fullscreen = !fullscreen);
    controller.showControls();
    await _setFullscreenWindow(fullscreen);
  }

  Future<void> _setFullscreenWindow(bool enabled) async {
    try {
      await window.setFullscreen(enabled);
    } catch (error, stack) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法调整播放窗口：$error')));
      } else {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'playback',
            context: ErrorDescription('while restoring the player window'),
          ),
        );
      }
    }
  }

  Future<void> _download() async {
    if (downloading) return;

    setState(() => downloading = true);

    try {
      await widget.onDownload?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法创建下载：$error')));
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeHighlightModeListener(_highlightChanged);

    if (window.needsRestoration) {
      unawaited(_setFullscreenWindow(false));
    }

    // Navigator disposes a popped route after its leave transition completes.
    // Gesture cancellation never reaches here; PiP is retained by the controller.
    detailsScroll.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final selection = widget.input.selection;
      final surface = _surface();
      final inPip = controller.value.inPip;
      final videoOnly = fullscreen || inPip;

      return PopScope<Object?>(
        canPop: !fullscreen || inPip,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) {
            unawaited(controller.commitExit());
          } else if (fullscreen && !inPip) {
            unawaited(_toggleFullscreen());
          }
        },
        child: Scaffold(
          backgroundColor: videoOnly ? Colors.black : null,
          appBar: videoOnly ? null : AppBar(title: const Text('播放')),
          body: videoOnly
              ? (inPip ? surface : SafeArea(child: surface))
              : SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final surfaceHeight = math.min(
                        constraints.maxHeight,
                        math.max(
                          MediaQuery.textScalerOf(context).scale(1) >= 1.5
                              ? 208.0
                              : 176.0,
                          math.min(
                            constraints.maxWidth * 9 / 16,
                            constraints.maxHeight * .65,
                          ),
                        ),
                      );

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: surfaceHeight, child: surface),
                          Expanded(
                            child: SingleChildScrollView(
                              key: const PageStorageKey('player-details'),
                              controller: detailsScroll,
                              child: _details(selection),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      );
    },
  );

  String? get _qualityFallbackNotice {
    final preferred = widget.input.preferredQuality;
    final actual = controller.value.source?.quality;
    if (preferred == null ||
        actual == null ||
        widget.input.sources.any((source) => source.quality == preferred)) {
      return null;
    }

    return '未提供${preferred.label}画质，已使用${actual.label}';
  }

  Widget _details(ProgrammeSelection? selection) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          widget.input.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (selection != null) ...[
          const SizedBox(height: 12),
          Text(
            '${selection.programme.name} · ${selection.broadcast.date}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        if (_qualityFallbackNotice case final String notice) ...[
          const SizedBox(height: 12),
          Text(notice),
        ],
        if (widget.input.initialPosition > Duration.zero) ...[
          const SizedBox(height: 12),
          Text('上次看到 ${_time(widget.input.initialPosition)}，播放后继续'),
          TextButton(
            onPressed: () => controller.seek(Duration.zero),
            child: const Text('从头播放'),
          ),
        ],
        if (widget.input.localLocation != null)
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('本地视频')),
        if (widget.onDownload != null &&
            widget.input.localLocation == null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: downloading ? null : _download,
              icon: const Icon(Icons.download_outlined, size: 20),
              label: Text(downloading ? '正在创建下载…' : '下载节目'),
            ),
          ),
        ],
        if (controller.message case final String message)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );

  Widget _surface() {
    final value = controller.value;
    final session = controller.session;

    return Container(
      key: surfaceKey,
      color: Colors.black,
      child: Focus(
        onKeyEvent: (_, _) {
          controller.showControls();
          return KeyEventResult.ignored;
        },
        onFocusChange: (focused) {
          controlsFocused = focused;
          _updateFocusHold();
        },
        child: MouseRegion(
          onHover: (_) => controller.showControls(),
          child: Semantics(
            label: value.inPip ? null : '显示播放控件',
            onTap: value.inPip ? null : controller.showControls,
            child: Listener(
              onPointerDown: (event) {
                surfacePointers.add(event.pointer);
                // Observe every video descendant without entering its gesture
                // arena, including native controls and the transport slider.
                if (surfacePointers.length > 1) {
                  unawaited(controller.cancelGestures());
                  controller.showControls();
                }
              },
              onPointerUp: (event) => surfacePointers.remove(event.pointer),
              onPointerCancel: (event) => surfacePointers.remove(event.pointer),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (session != null) widget.surfaceBuilder(session),
                  if (!value.inPip && widget.input.selection != null)
                    PlaybackCover(
                      selection: widget.input.selection!,
                      ready: value.firstFrameRendered,
                      shared: !fullscreen,
                    ),
                  if (!value.inPip) ...[
                    PlayerGestures(
                      controller: controller,
                      fullscreen: fullscreen,
                      environment: widget.environment,
                    ),
                    if (fullscreen &&
                        controller.controlsVisible &&
                        widget.systemVolume != null)
                      Positioned(
                        top: 4,
                        left: 24,
                        child: _SystemVolumeInteraction(
                          controller: controller,
                          child: widget.systemVolume!,
                        ),
                      ),
                    if (controller.loading ||
                        value.buffering ||
                        controller.switchingSource)
                      Center(
                        child: CircularProgressIndicator(
                          color: Theme.of(context).colorScheme.primary,
                          semanticsLabel: '正在缓冲视频',
                        ),
                      ),
                    if (controller.controlsVisible)
                      PlayerControls(
                        controller: controller,
                        fullscreen: fullscreen,
                        onFullscreen: _toggleFullscreen,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _time(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 32);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');

    return '$minutes:$remainder';
  }
}

/// Keeps the public native volume view alive for the complete interaction.
class _SystemVolumeInteraction extends StatefulWidget {
  const _SystemVolumeInteraction({
    required this.controller,
    required this.child,
  });

  final PlaybackController controller;
  final Widget child;

  @override
  State<_SystemVolumeInteraction> createState() =>
      _SystemVolumeInteractionState();
}

class _SystemVolumeInteractionState extends State<_SystemVolumeInteraction> {
  final pointers = <int>{};
  bool focused = false;

  void updateHold() => widget.controller.holdControls(
    pointers.isNotEmpty || focused,
    reason: PlayerControlHold.systemVolume,
  );

  @override
  void dispose() {
    widget.controller.detachControlHold(PlayerControlHold.systemVolume);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (value) {
      focused = value;
      updateHold();
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) {
        pointers.add(event.pointer);
        updateHold();
      },
      onPointerUp: (event) {
        pointers.remove(event.pointer);
        updateHold();
      },
      onPointerCancel: (event) {
        pointers.remove(event.pointer);
        updateHold();
      },
      child: widget.child,
    ),
  );
}
