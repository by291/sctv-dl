import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/programmes/programme.dart';
import 'playback_controller.dart';
import 'player_control_button.dart';
import 'player_options_button.dart';

/// Owns transport layout and the scrub preview independently of session state.
class PlayerTransportControls extends StatefulWidget {
  const PlayerTransportControls({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onFullscreen,
    required this.availableHeight,
  });

  final PlaybackController controller;
  final bool fullscreen;
  final VoidCallback onFullscreen;
  final double availableHeight;

  @override
  State<PlayerTransportControls> createState() =>
      _PlayerTransportControlsState();
}

class _PlayerTransportControlsState extends State<PlayerTransportControls> {
  static const speeds = <double>[.75, 1, 1.25, 1.5, 2];

  double? seeking;

  PlaybackController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final enabled =
        value.initialized &&
        !controller.loading &&
        !controller.switchingSource &&
        !controller.canRetry;

    return LayoutBuilder(
      builder: (context, row) {
        final sources = controller.input.localLocation == null
            ? controller.input.sources
            : const <VideoSource>[];
        final speedWidth = _controlWidth(context, speeds.map(_speed));

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
                PlayerControlButton(
                  tooltip: value.playing ? '暂停' : '播放',
                  onPressed: enabled ? controller.togglePlayback : null,
                  icon: value.playing ? Icons.pause : Icons.play_arrow,
                ),
                Expanded(child: _progress(context, enabled, timeWidth)),
                PlayerOptionsButton<double>(
                  controller: controller,
                  label: _speed(controller.selectedSpeed),
                  width: speedWidth,
                  tooltip: '播放速度',
                  enabled: enabled,
                  values: speeds,
                  describe: _speed,
                  selected: controller.selectedSpeed,
                  onSelected: controller.setSpeed,
                  height: widget.availableHeight,
                ),
                if (sources.isNotEmpty)
                  PlayerOptionsButton<VideoSource>(
                    controller: controller,
                    label: value.source?.quality.label ?? '画质',
                    width: qualityWidth,
                    tooltip: '视频画质',
                    enabled: enabled,
                    values: sources,
                    describe: (source) => source.quality.label,
                    selected: value.source,
                    onSelected: controller.selectSource,
                    height: widget.availableHeight,
                  ),
                PlayerControlButton(
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
