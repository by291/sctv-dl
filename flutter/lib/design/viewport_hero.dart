import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A scrolled-out image must not escape its clip into the navigation overlay.
/// Measure after layout without scrolling or changing the child's geometry.
class ViewportHero extends StatefulWidget {
  const ViewportHero({super.key, required this.child});

  final Widget child;

  @override
  State<ViewportHero> createState() => _ViewportHeroState();
}

class _ViewportHeroState extends State<ViewportHero> {
  ScrollPosition? _position;
  bool _visible = false;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_scheduleCheck);
      _position = position;
      position?.addListener(_scheduleCheck);
    }

    _scheduleCheck();
  }

  @override
  void didUpdateWidget(ViewportHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (_scheduled) return;

    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;

      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;

      final viewport = RenderAbstractViewport.maybeOf(box);
      final bounds = viewport == null
          ? null
          : MatrixUtils.transformRect(
              box.getTransformTo(viewport),
              Offset.zero & box.size,
            );
      final visible =
          bounds == null ||
          viewport!.paintBounds.inflate(.5).contains(bounds.topLeft) &&
              viewport.paintBounds.inflate(.5).contains(bounds.bottomRight);

      if (visible != _visible) setState(() => _visible = visible);
    });
  }

  @override
  void dispose() {
    _position?.removeListener(_scheduleCheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      HeroMode(enabled: _visible, child: widget.child);
}
