import 'package:flutter/material.dart';

import '../../design/shared_cover.dart';
import '../../domain/programmes/programme.dart';

/// Keeps artwork in the fixed video bounds until both player initialization and route
/// entry are ready. The texture stays mounted beneath it, including on return.
class PlaybackCover extends StatefulWidget {
  const PlaybackCover({
    super.key,
    required this.selection,
    required this.ready,
    required this.shared,
  });

  final ProgrammeSelection selection;
  final bool ready;
  final bool shared;

  @override
  State<PlaybackCover> createState() => _PlaybackCoverState();
}

class _PlaybackCoverState extends State<PlaybackCover> {
  Animation<double>? _routeAnimation;
  bool _entered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final animation = ModalRoute.of(context)?.animation;
    if (animation != _routeAnimation) {
      _routeAnimation?.removeStatusListener(_routeStatus);
      _routeAnimation = animation;
      animation?.addStatusListener(_routeStatus);
    }

    _entered |=
        animation == null || animation.status == AnimationStatus.completed;
  }

  void _routeStatus(AnimationStatus status) {
    if (!_entered && status == AnimationStatus.completed) {
      setState(() => _entered = true);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: widget.ready && _entered ? 0 : 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      builder: (context, opacity, _) => SharedCover(
        tag: widget.shared ? 'playback-${widget.selection.ref.key}' : null,
        url: widget.selection.content.cover ?? widget.selection.programme.cover,
        radius: 0,
        opacity: opacity,
      ),
    ),
  );
}
