import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Blur only after scrolling, so artwork below the header cannot bleed into
/// an otherwise empty header through the blur kernel at the top of a page.
class ScrollUnderHeader extends StatefulWidget {
  const ScrollUnderHeader({
    super.key,
    required this.height,
    required this.color,
    required this.child,
  });

  final double height;
  final Color color;
  final Widget child;

  @override
  State<ScrollUnderHeader> createState() => _ScrollUnderHeaderState();
}

class _ScrollUnderHeaderState extends State<ScrollUnderHeader> {
  final _scrolledViewports = <ScrollableState>{};
  bool _scrolledUnder = false;

  void _update(ScrollMetrics metrics, int depth, BuildContext? context) {
    if (depth != 0 || metrics.axis != Axis.vertical || context == null) return;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return;

    // Wide layouts have independent panes beneath the same header.
    if (metrics.pixels > metrics.minScrollExtent + 0.5) {
      _scrolledViewports.add(scrollable);
    } else {
      _scrolledViewports.remove(scrollable);
    }
    _refresh();
  }

  void _refresh() {
    _scrolledViewports.removeWhere((scrollable) => !scrollable.mounted);
    final scrolledUnder = _scrolledViewports.isNotEmpty;
    if (_scrolledUnder != scrolledUnder) {
      setState(() => _scrolledUnder = scrolledUnder);
    }
  }

  @override
  void didUpdateWidget(covariant ScrollUnderHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A responsive layout can remove a pane without another scroll event.
    if (_scrolledViewports.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollMetricsNotification>(
    onNotification: (notification) {
      _update(notification.metrics, notification.depth, notification.context);
      return false;
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _update(notification.metrics, notification.depth, notification.context);
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.height,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  enabled: _scrolledUnder,
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: ColoredBox(
                    color: widget.color.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
