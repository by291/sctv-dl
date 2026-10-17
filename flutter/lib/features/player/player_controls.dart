import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/theme.dart';
import '../../domain/programmes/programme.dart';
import 'playback_controller.dart';

/// Controls stay inside the pinned video surface, including fullscreen errors
/// and menus. The native decoder is owned by the page's playback controller.
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onFullscreen,
  });

  final PlaybackController controller;
  final bool fullscreen;
  final VoidCallback onFullscreen;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends State<PlayerControls> {
  static const speeds = <double>[.75, 1, 1.25, 1.5, 2];
  double? seeking;
  PlaybackController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme(Brightness.dark);
    final accent = theme.colorScheme.primary;
    final feedback = ButtonStyle(
      overlayColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return Colors.white.withValues(alpha: .16);
        }
        if (states.contains(WidgetState.focused)) {
          return Colors.white.withValues(alpha: .12);
        }
        if (states.contains(WidgetState.hovered)) {
          return Colors.white.withValues(alpha: .08);
        }
        return Colors.transparent;
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      splashFactory: InkRipple.splashFactory,
    );
    final value = controller.value;
    final enabled =
        value.initialized &&
        !controller.loading &&
        !controller.switchingSource &&
        !controller.canRetry;
    return Theme(
      data: theme.copyWith(
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white54,
            backgroundColor: Colors.transparent,
          ).merge(feedback),
        ),
        textButtonTheme: TextButtonThemeData(style: feedback),
        sliderTheme: SliderThemeData(
          activeTrackColor: accent,
          inactiveTrackColor: Colors.white.withValues(alpha: .3),
          thumbColor: accent,
          overlayColor: accent.withValues(alpha: .16),
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
      ),
      child: DefaultTextStyle(
        style: theme.textTheme.labelMedium!.copyWith(color: Colors.white),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 144,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB8000000)],
                      ),
                    ),
                  ),
                ),
              ),
              if (value.supportsPip) ...[
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 64,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x73000000), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _iconButton(
                    tooltip: '画中画',
                    icon: Icons.picture_in_picture_alt_outlined,
                    onPressed: enabled
                        ? controller.enterPictureInPicture
                        : null,
                  ),
                ),
              ],
              if (controller.canRetry)
                Positioned(
                  top: 8,
                  left: 16,
                  right: value.supportsPip ? 60 : 16,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(48, constraints.maxHeight - 64),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.error ?? controller.message ?? '视频暂时无法播放',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: TextButton(
                              onPressed: controller.retry,
                              child: const Text('重试播放'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: LayoutBuilder(
                  builder: (context, row) {
                    final sources = controller.input.localLocation == null
                        ? controller.input.sources
                        : const <VideoSource>[];
                    final speedWidth = _controlWidth(
                      context,
                      speeds.map(_speed),
                    );
                    // Loading and ready states share the same slot; metadata
                    // must not shift adjacent actions when the label changes.
                    final qualityWidth = sources.isEmpty
                        ? 0.0
                        : _controlWidth(context, [
                            '画质',
                            ...sources.map((source) => source.quality.label),
                          ]);
                    // Keep a useful seek target at large text sizes. Only those
                    // constrained layouts scroll; ordinary phone widths fit one row.
                    final timeWidth = _timeSlotWidth(context);
                    final width = math.max(
                      row.maxWidth,
                      80 + speedWidth + qualityWidth + timeWidth * 2 + 80,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        height: 48,
                        child: Row(
                          children: [
                            _iconButton(
                              tooltip: value.playing ? '暂停' : '播放',
                              onPressed: enabled
                                  ? controller.togglePlayback
                                  : null,
                              icon: value.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                            ),
                            Expanded(
                              child: _progress(context, enabled, timeWidth),
                            ),
                            _option<double>(
                              context,
                              label: _speed(controller.selectedSpeed),
                              width: speedWidth,
                              tooltip: '播放速度',
                              enabled: enabled,
                              values: speeds,
                              describe: _speed,
                              selected: controller.selectedSpeed,
                              onSelected: controller.setSpeed,
                              height: constraints.maxHeight,
                            ),
                            if (sources.isNotEmpty)
                              _option<VideoSource>(
                                context,
                                label: value.source?.quality.label ?? '画质',
                                width: qualityWidth,
                                tooltip: '视频画质',
                                enabled: enabled,
                                values: sources,
                                describe: (source) => source.quality.label,
                                selected: value.source,
                                onSelected: controller.selectSource,
                                height: constraints.maxHeight,
                              ),
                            _iconButton(
                              tooltip: widget.fullscreen ? '退出全屏' : '全屏',
                              onPressed: widget.onFullscreen,
                              icon: widget.fullscreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _timeStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelLarge!
      .copyWith(
        color: Colors.white,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  double _timeSlotWidth(BuildContext context) {
    // Reserve the total duration's digit count before playback reaches it. Both
    // labels keep their width as digits change, including the hour boundary.
    final value = controller.value;
    final longest = math.max(
      value.duration?.inMilliseconds ?? 0,
      math.max(value.position.inMilliseconds, seeking?.round() ?? 0),
    );
    final template = _time(Duration(milliseconds: longest))
        .replaceAll(RegExp(r'\d'), '8');
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      text: TextSpan(text: template, style: _timeStyle(context)),
    )..layout();
    final width = painter.width + 8;
    painter.dispose();
    return width;
  }

  Widget _progress(BuildContext context, bool enabled, double timeWidth) {
    final value = controller.value;
    final duration = value.duration;
    final maximum = math.max(1.0, duration?.inMilliseconds.toDouble() ?? 1);
    final canSeek = enabled && duration != null && duration > Duration.zero;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _time(
                    Duration(
                      milliseconds:
                          seeking?.round() ?? value.position.inMilliseconds,
                    ),
                  ),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  style: _timeStyle(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                max: maximum,
                value: (seeking ?? value.position.inMilliseconds.toDouble())
                    .clamp(0, maximum),
                semanticFormatterCallback: (position) =>
                    _time(Duration(milliseconds: position.round())),
                onChangeStart: canSeek
                    ? (_) => controller.holdControls(
                        true,
                        reason: PlayerControlHold.seek,
                      )
                    : null,
                onChanged: canSeek
                    ? (position) => setState(() => seeking = position)
                    : null,
                onChangeEnd: canSeek
                    ? (position) async {
                        try {
                          await controller.seek(
                            Duration(milliseconds: position.round()),
                          );
                        } finally {
                          if (mounted) setState(() => seeking = null);
                          controller.holdControls(
                            false,
                            reason: PlayerControlHold.seek,
                          );
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: timeWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  duration == null ? '--:--' : _time(duration),
                  textAlign: TextAlign.left,
                  maxLines: 1,
                  style: _timeStyle(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
  }) => SizedBox(
    width: 40,
    height: 48,
    child: Material(
      type: MaterialType.transparency,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ),
  );

  double _controlWidth(BuildContext context, Iterable<String> labels) {
    // Reserve the widest label so changing speed does not resize the seek track.
    final painter = TextPainter(
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    var width = 40.0;
    for (final label in labels) {
      painter.text = TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge,
      );
      painter.layout();
      width = math.max(width, painter.width + 8);
    }
    painter.dispose();
    return width;
  }

  Widget _option<T>(
    BuildContext context, {
    required String label,
    required double width,
    required String tooltip,
    required bool enabled,
    required List<T> values,
    required String Function(T) describe,
    required T? selected,
    required Future<void> Function(T) onSelected,
    required double height,
  }) {
    final style = Theme.of(context).textTheme.labelLarge!;
    return Builder(
      builder: (buttonContext) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: width,
          height: 48,
          child: Material(
            type: MaterialType.transparency,
            child: IconButton(
              onPressed: enabled
                  ? () => _showOptions(
                      buttonContext,
                      values: values,
                      describe: describe,
                      selected: selected,
                      onSelected: onSelected,
                      height: height,
                      style: style,
                    )
                  : null,
              style: const ButtonStyle(
                foregroundColor: WidgetStatePropertyAll(Colors.white),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
              icon: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    style: style.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showOptions<T>(
    BuildContext buttonContext, {
    required List<T> values,
    required String Function(T) describe,
    required T? selected,
    required Future<void> Function(T) onSelected,
    required double height,
    required TextStyle style,
  }) async {
    controller.holdControls(true, reason: PlayerControlHold.menu);
    final overlay =
        Navigator.of(buttonContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final anchor = buttonContext.findRenderObject()! as RenderBox;
    final available = math.max(48.0, height - 64);
    final menuHeight = math.min(values.length, (available / 48).floor()) * 48.0;
    final menuWidth = MediaQuery.textScalerOf(buttonContext).scale(1) >= 1.5
        ? 112.0
        : 72.0;
    final accent = Theme.of(buttonContext).colorScheme.primary;
    final route = ModalRoute.of(buttonContext);
    try {
      final chosen = await showMenu<T>(
        context: buttonContext,
        initialValue: selected,
        color: Colors.black.withValues(alpha: .6),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        menuPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        constraints: BoxConstraints.tightFor(
          width: menuWidth,
          height: menuHeight,
        ),
        popUpAnimationStyle: const AnimationStyle(
          duration: Duration(milliseconds: 150),
          reverseDuration: Duration(milliseconds: 100),
        ),
        positionBuilder: (_, constraints) {
          final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
          return RelativeRect.fromSize(
            Rect.fromLTWH(
              origin.dx + (anchor.size.width - menuWidth) / 2,
              origin.dy - menuHeight - 4,
              menuWidth,
              menuHeight,
            ),
            constraints.biggest,
          );
        },
        items: [
          for (final value in values)
            PopupMenuItem<T>(
              value: value,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Semantics(
                selected: value == selected,
                child: Center(
                  child: Text(
                    describe(value),
                    maxLines: 1,
                    style: style.copyWith(
                      color: value == selected ? accent : Colors.white,
                      fontWeight: value == selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
      if (chosen != null && mounted && route?.isCurrent == true) {
        await onSelected(chosen);
      }
    } finally {
      controller.holdControls(false, reason: PlayerControlHold.menu);
    }
  }

  String _speed(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';

  String _time(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 1 << 32);
    final minutes = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600
        ? '${seconds ~/ 3600}:$minutes:$remainder'
        : '$minutes:$remainder';
  }
}
