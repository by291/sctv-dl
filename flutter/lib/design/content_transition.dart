import 'package:flutter/material.dart';
import 'package:sliver_tools/sliver_tools.dart';

Duration motionDuration(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

/// Retains outgoing content until its replacement covers the same region.
/// Sliver mode keeps grids lazy instead of nesting a shrink-wrapped viewport.
class ContentTransition extends StatefulWidget {
  const ContentTransition({
    super.key,
    required this.child,
    required this.background,
    this.milliseconds = 140,
  }) : sliver = false;
  const ContentTransition.sliver({
    super.key,
    required this.child,
    required this.background,
    this.milliseconds = 140,
  }) : sliver = true;

  final Widget child;
  final Color background;
  final int milliseconds;
  final bool sliver;

  @override
  State<ContentTransition> createState() => _ContentTransitionState();
}

class _ContentTransitionState extends State<ContentTransition> {
  late final _entries = <({int id, Widget child})>[
    (id: 0, child: widget.child),
  ];
  int _serial = 0;

  @override
  void didUpdateWidget(ContentTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(oldWidget.child, widget.child)) {
      _entries[_entries.length - 1] = (
        id: _entries.last.id,
        child: widget.child,
      );
    } else if (MediaQuery.disableAnimationsOf(context)) {
      _entries
        ..clear()
        ..add((id: ++_serial, child: widget.child));
    } else {
      _entries.add((id: ++_serial, child: widget.child));
    }
  }

  void _settled() {
    if (!mounted || _entries.length < 2) return;
    setState(() {
      final current = _entries.last;
      _entries
        ..clear()
        ..add(current);
    });
  }

  @override
  Widget build(BuildContext context) => RetainedFadeStack(
    index: _entries.length - 1,
    milliseconds: widget.milliseconds,
    sliver: widget.sliver,
    expand: false,
    background: widget.background,
    onSettled: _settled,
    children: [
      for (final entry in _entries)
        KeyedSubtree(key: ValueKey(entry.id), child: entry.child),
    ],
  );
}

/// Keeps one instance of each child, including Navigator and input state.
/// Blending weights are sampled before retargeting, so rapid changes continue
/// from the displayed mixture rather than making a partial layer fully opaque.
class RetainedFadeStack extends StatefulWidget {
  const RetainedFadeStack({
    super.key,
    required this.index,
    required this.children,
    this.milliseconds = 200,
    this.sliver = false,
    this.expand = true,
    this.background,
    this.onSettled,
    this.travelDistance = 0,
  });

  final int index;
  final List<Widget> children;
  final int milliseconds;
  final bool sliver;
  final bool expand;
  final Color? background;
  final VoidCallback? onSettled;
  final double travelDistance;

  @override
  State<RetainedFadeStack> createState() => _RetainedFadeStackState();
}

class _RetainedFadeStackState extends State<RetainedFadeStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(vsync: this, value: 1)..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _animation.isCompleted) widget.onSettled?.call();
          });
        }
      });
  late int _target = widget.index;
  late List<double> _start = [
    for (var i = 0; i < widget.children.length; i++) i == widget.index ? 1 : 0,
  ];

  late List<double> _startOffsets = List.filled(widget.children.length, 0);
  late List<double> _endOffsets = List.filled(widget.children.length, 0);
  double get _progress => widget.travelDistance == 0
      ? Curves.easeOutCubic.transform(_animation.value)
      : Curves.fastOutSlowIn.transform(_animation.value);
  List<double> get _offsets => [
    for (var i = 0; i < _startOffsets.length; i++)
      _startOffsets[i] + (_endOffsets[i] - _startOffsets[i]) * _progress,
  ];

  List<double> get _weights {
    final t = _progress;
    return [
      for (var i = 0; i < _start.length; i++)
        _start[i] * (1 - t) + (i == _target ? t : 0),
    ];
  }

  void _finish() {
    _target = widget.index;
    _start = [
      for (var i = 0; i < widget.children.length; i++) i == _target ? 1 : 0,
    ];
    _startOffsets = List.filled(widget.children.length, 0);
    _endOffsets = List.filled(widget.children.length, 0);
    _animation.value = 1;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _finish();
  }

  @override
  void didUpdateWidget(RetainedFadeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.children.length < oldWidget.children.length ||
        MediaQuery.disableAnimationsOf(context)) {
      _finish();
    } else if (oldWidget.index != widget.index ||
        oldWidget.children.length != widget.children.length) {
      _startOffsets = _offsets;
      _start = _weights;
      while (_start.length < widget.children.length) {
        _start.add(0);
        _startOffsets.add(0);
      }
      final direction = widget.index > _target ? 1.0 : -1.0;
      if (_start[widget.index] == 0) {
        _startOffsets[widget.index] = direction * widget.travelDistance;
      }
      _endOffsets = [
        for (var i = 0; i < widget.children.length; i++)
          i == widget.index ? 0 : -direction * widget.travelDistance,
      ];
      _target = widget.index;
      _animation.duration = motionDuration(context, widget.milliseconds);
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final weights = _weights;
      final offsets = _offsets;
      var covered = 0.0;
      final layers = <Widget>[];
      for (var i = 0; i < widget.children.length; i++) {
        covered += weights[i];
        // Convert normalized mixture weights to source-over alpha. The first
        // visible layer is opaque, so no frame exposes an empty backing surface.
        final opacity = covered == 0
            ? 0.0
            : (weights[i] / covered).clamp(0.0, 1.0);
        final active = i == widget.index;
        final hidden = weights[i] == 0 && !active;
        final background =
            widget.background ?? Theme.of(context).scaffoldBackgroundColor;
        final content = TickerMode(
          enabled: active,
          child: HeroMode(
            enabled: active,
            child: ExcludeFocus(excluding: !active, child: widget.children[i]),
          ),
        );
        final layer = widget.sliver
            ? SliverOffstage(
                offstage: hidden,
                sliver: SliverIgnorePointer(
                  ignoring: !active,
                  sliver: SliverSemantics(
                    excludeSemantics: !active,
                    sliver: SliverOpacity(
                      opacity: opacity,
                      sliver: SliverStack(
                        children: [
                          SliverPositioned.fill(
                            child: ColoredBox(color: background),
                          ),
                          content,
                        ],
                      ),
                    ),
                  ),
                ),
              )
            : Offstage(
                offstage: hidden,
                child: IgnorePointer(
                  ignoring: !active,
                  child: ExcludeSemantics(
                    excluding: !active,
                    child: Opacity(
                      opacity: opacity,
                      child: ColoredBox(
                        color: background,
                        child: Transform.translate(
                          offset: Offset(offsets[i], 0),
                          child: content,
                        ),
                      ),
                    ),
                  ),
                ),
              );
        layers.add(
          KeyedSubtree(
            key: widget.children[i].key ?? ValueKey(i),
            child: layer,
          ),
        );
      }
      return widget.sliver
          ? SliverStack(children: layers)
          : Stack(
              fit: widget.expand ? StackFit.expand : StackFit.loose,
              alignment: Alignment.topLeft,
              clipBehavior: widget.travelDistance == 0
                  ? Clip.none
                  : Clip.hardEdge,
              children: layers,
            );
    },
  );
}
