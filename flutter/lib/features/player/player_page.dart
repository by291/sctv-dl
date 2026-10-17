import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/theme.dart';
import '../../domain/playback/history_repository.dart';
import '../../domain/playback/playback_backend.dart';
import '../../domain/programmes/programme.dart';
import 'playback_controller.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.input,
    required this.backend,
    required this.surfaceBuilder,
    required this.history,
    this.onDownload,
  });
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
  double? seeking;
  final surfaceKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = PlaybackController(
      input: widget.input,
      backend: widget.backend,
      history: widget.history,
    );
    unawaited(controller.initialize());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    controller.holdControls(accessibleNavigation);
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
    setState(() => fullscreen = !fullscreen);
    // Orientation follows the device throughout; only the visible window chrome
    // changes, so leaving fullscreen never overwrites an OS orientation choice.
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
    controller.showControls();
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
    if (fullscreen) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    // Navigator disposes a popped route after its leave transition completes.
    // Gesture cancellation never reaches here; PiP is retained by the controller.
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !fullscreen,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) {
        unawaited(controller.commitExit());
      } else if (fullscreen) {
        unawaited(_toggleFullscreen());
      }
    },
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final selection = widget.input.selection;
        final surface = _surface();
        return Scaffold(
          backgroundColor: fullscreen ? Colors.black : null,
          appBar: fullscreen ? null : AppBar(title: const Text('播放')),
          body: fullscreen
              ? SafeArea(child: surface)
              : SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final surfaceHeight = math.min(
                        constraints.maxHeight,
                        math.max(
                          96.0,
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
                              child: _details(selection),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        );
      },
    ),
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
        if (controller.value.source case final source?) ...[
          const SizedBox(height: 12),
          Text('当前画质：${source.quality.label}'),
          if (_qualityFallbackNotice case final String notice) Text(notice),
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
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            onPressed: downloading ? null : _download,
            icon: const Icon(Icons.download_outlined),
            label: Text(downloading ? '正在创建下载…' : '下载当前节目'),
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
        if (controller.canRetry)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试播放'),
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
      child: MouseRegion(
        onHover: (_) => controller.showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.showControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (session != null) widget.surfaceBuilder(session),
              if (controller.loading ||
                  value.buffering ||
                  controller.switchingSource)
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    semanticsLabel: '正在缓冲视频',
                  ),
                ),
              if (value.error case final String error when !controller.loading)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '播放失败：$error',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              if (controller.controlsVisible) _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    final value = controller.value;
    final duration = value.duration;
    final enabled =
        value.initialized &&
        value.error == null &&
        !controller.loading &&
        !controller.switchingSource &&
        !controller.canRetry;
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final controlsTheme = buildAppTheme(Brightness.dark);
    final accent = controlsTheme.colorScheme.primary;
    return Focus(
      onFocusChange: (focused) =>
          controller.holdControls(focused || accessible),
      child: Theme(
        data: controlsTheme.copyWith(
          iconTheme: const IconThemeData(color: Colors.white),
          iconButtonTheme: IconButtonThemeData(
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .12),
            ),
          ),
          sliderTheme: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: Colors.white.withValues(alpha: .3),
            thumbColor: accent,
            overlayColor: accent.withValues(alpha: .16),
            trackHeight: 3,
          ),
          popupMenuTheme: PopupMenuThemeData(
            color: controlsTheme.colorScheme.surfaceContainerLow.withValues(
              alpha: .96,
            ),
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        child: DefaultTextStyle(
          style: controlsTheme.textTheme.bodyMedium!.copyWith(
            color: Colors.white,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxHeight < 250 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.5;
              final actions = <Widget>[
                if (compact)
                  IconButton.filledTonal(
                    tooltip: value.playing ? '暂停' : '播放',
                    onPressed: enabled ? controller.togglePlayback : null,
                    icon: Icon(value.playing ? Icons.pause : Icons.play_arrow),
                  ),
                _option<double>(
                  label: '${value.speed}×',
                  tooltip: '播放速度',
                  enabled: enabled,
                  values: const [.5, .75, 1, 1.25, 1.5, 1.75, 2],
                  describe: (speed) => '$speed×',
                  selected: value.speed,
                  onSelected: controller.setSpeed,
                ),
                if (widget.input.localLocation == null &&
                    widget.input.sources.length > 1)
                  _option<VideoSource>(
                    label: value.source?.quality.label ?? '画质',
                    tooltip: '视频画质',
                    enabled: enabled,
                    values: widget.input.sources,
                    describe: (source) => source.quality.label,
                    selected: value.source,
                    onSelected: controller.selectSource,
                  ),
                if (value.supportsPip)
                  IconButton(
                    tooltip: '画中画',
                    onPressed: enabled
                        ? controller.enterPictureInPicture
                        : null,
                    icon: const Icon(Icons.picture_in_picture_alt),
                  ),
                IconButton(
                  tooltip: fullscreen ? '退出全屏' : '全屏',
                  onPressed: _toggleFullscreen,
                  icon: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                ),
              ];
              return DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Column(
                  children: [
                    if (compact)
                      const Spacer()
                    else
                      Expanded(
                        child: Center(
                          child: IconButton.filledTonal(
                            tooltip: value.playing ? '暂停' : '播放',
                            onPressed: enabled
                                ? controller.togglePlayback
                                : null,
                            iconSize: compact ? 28 : 40,
                            icon: Icon(
                              value.playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Text(
                            _time(
                              Duration(
                                milliseconds:
                                    seeking?.round() ??
                                    value.position.inMilliseconds,
                              ),
                            ),
                            textScaler: TextScaler.noScaling,
                          ),
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: duration == null
                                  ? 1
                                  : duration.inMilliseconds.toDouble().clamp(
                                      1,
                                      double.infinity,
                                    ),
                              value:
                                  (seeking ??
                                          value.position.inMilliseconds
                                              .toDouble())
                                      .clamp(
                                        0,
                                        duration?.inMilliseconds.toDouble() ??
                                            1,
                                      ),
                              semanticFormatterCallback: (milliseconds) =>
                                  _time(
                                    Duration(
                                      milliseconds: milliseconds.round(),
                                    ),
                                  ),
                              onChangeStart: enabled && duration != null
                                  ? (_) => controller.holdControls(true)
                                  : null,
                              onChanged: enabled && duration != null
                                  ? (position) =>
                                        setState(() => seeking = position)
                                  : null,
                              onChangeEnd: enabled && duration != null
                                  ? (position) async {
                                      await controller.seek(
                                        Duration(
                                          milliseconds: position.round(),
                                        ),
                                      );
                                      if (mounted) {
                                        setState(() => seeking = null);
                                      }
                                      controller.holdControls(accessible);
                                    }
                                  : null,
                            ),
                          ),
                          Text(
                            duration == null ? '--:--' : _time(duration),
                            textScaler: TextScaler.noScaling,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 48,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _option<T>({
    required String label,
    required String tooltip,
    required bool enabled,
    required List<T> values,
    required String Function(T) describe,
    required T? selected,
    required Future<void> Function(T) onSelected,
  }) => PopupMenuButton<T>(
    tooltip: tooltip,
    enabled: enabled,
    initialValue: selected,
    position: PopupMenuPosition.over,
    offset: const Offset(0, -48),
    constraints: const BoxConstraints(
      minWidth: 120,
      maxWidth: 220,
      maxHeight: 280,
    ),
    onOpened: () => controller.holdControls(true),
    onCanceled: () =>
        controller.holdControls(MediaQuery.accessibleNavigationOf(context)),
    onSelected: (value) async {
      await onSelected(value);
      if (mounted) controller.holdControls(accessibleNavigation);
    },
    itemBuilder: (_) => [
      for (final value in values)
        PopupMenuItem(
          value: value,
          child: Row(
            children: [
              Expanded(child: Text(describe(value))),
              if (value == selected) const Icon(Icons.check_rounded, size: 18),
            ],
          ),
        ),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label),
        ),
      ),
    ),
  );

  String _time(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 32);
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}
