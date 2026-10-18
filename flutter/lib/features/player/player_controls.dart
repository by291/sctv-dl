import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/theme.dart';
import 'playback_controller.dart';
import 'player_control_button.dart';
import 'player_transport_controls.dart';

/// Controls stay inside the pinned video surface, including fullscreen errors
/// and menus. The native decoder is owned by the page's playback controller.
class PlayerControls extends StatelessWidget {
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
                  child: PlayerControlButton(
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
                child: PlayerTransportControls(
                  controller: controller,
                  fullscreen: fullscreen,
                  onFullscreen: onFullscreen,
                  availableHeight: constraints.maxHeight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
