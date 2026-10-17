import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'content_transition.dart';

/// The page owns this overlay: it never inserts a global entry or changes the
/// scroll viewport. Covered routes and inactive retained tabs cannot keep it.
class PendingUpdateOverlay extends StatelessWidget {
  const PendingUpdateOverlay({
    super.key,
    required this.visible,
    required this.onUpdate,
    required this.child,
    this.anchor,
    this.targetAnchor = Alignment.bottomCenter,
    this.anchorOffset = const Offset(0, 8),
  });

  final bool visible;
  final VoidCallback onUpdate;
  final Widget child;
  final LayerLink? anchor;
  final Alignment targetAnchor;
  final Offset anchorOffset;

  @override
  Widget build(BuildContext context) {
    final active =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    final notice = IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSwitcher(
            duration: motionDuration(context, 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, -.12),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: visible
                ? PendingUpdateNotice(onPressed: onUpdate)
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) => ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (active)
              if (anchor case final link?)
                Positioned.fill(
                  // Compositing follows the list entrance without measuring it
                  // after a frame or inserting space into the scroll layout.
                  child: CompositedTransformFollower(
                    link: link,
                    showWhenUnlinked: false,
                    targetAnchor: targetAnchor,
                    followerAnchor: Alignment.topCenter,
                    offset: anchorOffset,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: notice,
                      ),
                    ),
                  ),
                )
              else
                Positioned(
                  top: math.min(56, math.max(0, constraints.maxHeight - 64)),
                  left: 16,
                  right: 16,
                  child: Center(child: notice),
                ),
          ],
        ),
      ),
    );
  }
}

class PendingUpdateNotice extends StatelessWidget {
  const PendingUpdateNotice({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Tooltip(
        message: '有新内容，点击更新',
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: colours.onPrimaryContainer,
            backgroundColor: colours.primaryContainer,
            shadowColor: colours.shadow.withValues(alpha: .16),
            elevation: 3,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            shape: const StadiumBorder(),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            textStyle: const TextStyle(
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.refresh_rounded, size: 16),
              SizedBox(width: 6),
              Flexible(child: Text('发现新内容', textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
  }
}
