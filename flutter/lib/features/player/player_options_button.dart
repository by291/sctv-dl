import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'playback_controller.dart';

/// Anchors an in-surface menu and retains its controls hold until it closes.
class PlayerOptionsButton<T> extends StatefulWidget {
  const PlayerOptionsButton({
    super.key,
    required this.controller,
    required this.label,
    required this.width,
    required this.tooltip,
    required this.enabled,
    required this.values,
    required this.describe,
    required this.selected,
    required this.onSelected,
    required this.height,
  });

  final PlaybackController controller;
  final String label;
  final double width;
  final String tooltip;
  final bool enabled;
  final List<T> values;
  final String Function(T) describe;
  final T? selected;
  final Future<void> Function(T) onSelected;
  final double height;

  @override
  State<PlayerOptionsButton<T>> createState() => _PlayerOptionsButtonState<T>();
}

class _PlayerOptionsButtonState<T> extends State<PlayerOptionsButton<T>> {
  PlaybackController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge!;

    return Builder(
      builder: (buttonContext) => Tooltip(
        message: widget.tooltip,
        child: SizedBox(
          width: widget.width,
          height: 48,
          child: Material(
            type: MaterialType.transparency,
            child: IconButton(
              onPressed: widget.enabled
                  ? () => _showOptions(
                      buttonContext,
                      values: widget.values,
                      describe: widget.describe,
                      selected: widget.selected,
                      onSelected: widget.onSelected,
                      height: widget.height,
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
                    widget.label,
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

  Future<void> _showOptions(
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
}
