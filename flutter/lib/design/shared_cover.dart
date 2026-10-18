import 'package:flutter/material.dart';

import 'archive_transition.dart';
import 'cover_image.dart';

/// Retained navigation branches must release parked Hero placeholders when
/// another branch replaces the route stack without a return flight.
class SharedCoverScope extends InheritedWidget {
  const SharedCoverScope({
    super.key,
    required this.active,
    required super.child,
  });

  final bool active;

  @override
  bool updateShouldNotify(SharedCoverScope oldWidget) =>
      active != oldWidget.active;
}

/// The source tag distinguishes an exploration cover from the same grid item.
class SharedCover extends StatelessWidget {
  const SharedCover({
    super.key,
    required this.tag,
    required this.url,
    this.rotation = 0,
    this.radius = 12,
    this.frameInset = 0,
    this.aspectRatio = 16 / 9,
    this.opacity = 1,
  });

  final String? tag;
  final String? url;
  final double rotation;
  final double radius;
  final double frameInset;
  final double aspectRatio;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final frame = _CoverFrame(
      url: url,
      rotation: rotation,
      radius: radius,
      frameInset: frameInset,
      aspectRatio: aspectRatio,
      opacity: opacity,
    );
    final active =
        context
            .dependOnInheritedWidgetOfExactType<SharedCoverScope>()
            ?.active ??
        true;
    if (tag == null || !active || MediaQuery.disableAnimationsOf(context)) {
      return frame;
    }

    final curve = Theme.of(context).platform == TargetPlatform.android
        ? ArchiveMotionCurve(Navigator.of(context, rootNavigator: true))
        : Curves.fastOutSlowIn;

    return Hero(
      tag: tag!,
      transitionOnUserGestures: true,
      // Both directions seek the same curve as the archive route, including
      // cancellation. Bounds, rotation and frame styling share this clock.
      curve: curve,
      reverseCurve: curve,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final source = (from.widget as Hero).child as _CoverFrame;
        final target = (to.widget as Hero).child as _CoverFrame;
        final departingRoute = ModalRoute.of(from)?.animation;
        final androidReturn =
            direction == HeroFlightDirection.pop &&
            Theme.of(from).platform == TargetPlatform.android &&
            departingRoute != null;

        return AnimatedBuilder(
          animation: Listenable.merge([
            animation,
            if (androidReturn) departingRoute,
          ]),
          builder: (context, _) {
            final t = direction == HeroFlightDirection.push
                ? animation.value
                : 1 - animation.value;

            return _CoverFrame(
              key: const ValueKey('programme-cover-flight'),
              url: source.url,
              aspectRatio:
                  source.aspectRatio +
                  (target.aspectRatio - source.aspectRatio) * t,
              // A revealed video remains underneath the return flight. Bring
              // its cover back gradually instead of flashing it at drag start.
              opacity:
                  source.opacity +
                  (1 - source.opacity) *
                      (androidReturn
                          ? 1 - archiveOutgoingOpacity(1 - departingRoute.value)
                          : (t / .35).clamp(0, 1)),
              rotation:
                  source.rotation + (target.rotation - source.rotation) * t,
              radius: source.radius + (target.radius - source.radius) * t,
              frameInset:
                  source.frameInset +
                  (target.frameInset - source.frameInset) * t,
            );
          },
        );
      },
      child: frame,
    );
  }
}

class _CoverFrame extends StatelessWidget {
  const _CoverFrame({
    super.key,
    required this.url,
    required this.rotation,
    required this.radius,
    required this.frameInset,
    required this.aspectRatio,
    required this.opacity,
  });

  final String? url;
  final double rotation;
  final double radius;
  final double frameInset;
  final double aspectRatio;
  final double opacity;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: opacity,
    child: Transform.rotate(
      angle: rotation,
      child: Container(
        padding: EdgeInsets.all(frameInset),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: frameInset == 0
              ? null
              : [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow
                        .withValues(alpha: .12 * frameInset / 4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            (radius - frameInset).clamp(0, radius),
          ),
          child: CoverImage(url: url, aspectRatio: aspectRatio),
        ),
      ),
    ),
  );
}
