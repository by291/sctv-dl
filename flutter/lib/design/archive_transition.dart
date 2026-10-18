import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A gesture already supplies progress; easing it again makes the cover lag
/// behind the finger. Keep this mapping through settlement to avoid a jump
/// when the finger lifts, and ease only time-driven navigation.
class ArchiveMotionCurve extends Curve {
  const ArchiveMotionCurve(this.navigator);

  final NavigatorState navigator;

  @override
  double transformInternal(double t) =>
      navigator.userGestureInProgress ? t : Curves.fastOutSlowIn.transform(t);
}

/// Complements the departing page with artwork during a video return.
double archiveOutgoingOpacity(double elapsed) =>
    1 - const Cubic(.4, 0, 1, 1).transform((elapsed / .35).clamp(0.0, 1.0));

/// Shared secondary-page motion with the previous route retained underneath.
class ArchiveTransitionPage<T> extends Page<T> {
  const ArchiveTransitionPage({
    super.key,
    super.name,
    super.restorationId,
    required this.child,
  });

  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) => _ArchiveRoute<T>(
    page: this,
    cupertino: Theme.of(context).platform == TargetPlatform.iOS,
  );
}

class _ArchiveRoute<T> extends MaterialPageRoute<T> {
  _ArchiveRoute({
    required ArchiveTransitionPage<T> page,
    required this.cupertino,
  }) : super(
         settings: page,
         builder: (context) =>
             (ModalRoute.of(context)!.settings as ArchiveTransitionPage<T>)
                 .child,
         allowSnapshotting: false,
       );

  final bool cupertino;
  late final _backObserver = _AndroidBackGestureObserver(this);

  @override
  void install() {
    super.install();
    if (!cupertino) WidgetsBinding.instance.addObserver(_backObserver);
  }

  final _motion = ValueNotifier<(bool returning, double direction)>((false, 1));
  NavigatorState? _gestureNavigator;
  AnimationStatusListener? _settleListener;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  // Delegate the other half of this transition to the retained route. This
  // includes the navigation bar and preserves the library's original layout.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      cupertino ? super.delegatedTransition : _buildPreviousTransition;

  Widget _buildPreviousTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => _ArchivePageMotion(
    animation: secondaryAnimation,
    motion: _motion,
    navigator: navigator!,
    previous: true,
    child: child ?? const SizedBox.shrink(),
  );

  @override
  bool didPop(T? result) {
    // A return during entry reverses that partial fade, rather than switching
    // to a different opacity at the same progress. Gestures retain their edge.
    if (!cupertino &&
        !navigator!.userGestureInProgress &&
        controller!.isCompleted) {
      _motion.value = (true, 1);
    }

    return super.didPop(result);
  }

  void _restoreInterruptedGesture() {
    // An asynchronous navigation can cover the archive mid-gesture. Flutter
    // only restores the current route; finish this retained page's animation
    // too, or returning from the new page would reveal a half-faded archive.
    if (isActive && !isCurrent) controller?.forward();
  }

  @override
  void handleStartBackGesture({double progress = 0.0, double direction = 1}) {
    _motion.value = (true, direction);
    _gestureNavigator = navigator;
    super.handleStartBackGesture(progress: progress);
  }

  void _finishBackGesture() {
    final navigation = _gestureNavigator;
    if (navigation == null) return;

    _gestureNavigator = null;

    final listener = _settleListener;
    if (listener != null) controller?.removeStatusListener(listener);
    _settleListener = null;

    navigation.didStopUserGesture();
  }

  void _finishWhenSettled() {
    if (_gestureNavigator == null) return;

    if (!(controller?.isAnimating ?? false)) {
      _finishBackGesture();
      return;
    }

    _settleListener = (status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _finishBackGesture();
      }
    };
    controller!.addStatusListener(_settleListener!);
  }

  @override
  void handleCancelBackGesture() {
    if (_gestureNavigator == null) return;

    _restoreInterruptedGesture();
    if (isCurrent) controller?.forward();
    _finishWhenSettled();
  }

  @override
  void handleCommitBackGesture() {
    if (_gestureNavigator == null) return;

    _restoreInterruptedGesture();

    // The default predictive commit resets the controller to 1. Keep the actual
    // route clock at the release position so the page and Hero both continue
    // from the same frame. Navigator.pop still owns route removal and disposal.
    if (isCurrent) navigator?.pop();
    _finishWhenSettled();
  }

  @override
  void dispose() {
    // Removal can interrupt dragging or cancellation before the controller's
    // terminal status. Release the retained navigator's input lock either way.
    _finishBackGesture();
    if (!cupertino) WidgetsBinding.instance.removeObserver(_backObserver);

    _motion.dispose();
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (cupertino) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        this,
        context,
        reduced ? const AlwaysStoppedAnimation(1.0) : animation,
        reduced ? const AlwaysStoppedAnimation(0.0) : secondaryAnimation,
        child,
      );
    }

    return _ArchivePageMotion(
      animation: animation,
      motion: _motion,
      navigator: navigator!,
      previous: false,
      child: child,
    );
  }
}

/// System back events drive the same slide/fade as ordinary archive navigation.
/// Flutter still owns route eligibility, gesture completion and route disposal.
class _AndroidBackGestureObserver with WidgetsBindingObserver {
  _AndroidBackGestureObserver(this.route);

  // Route lifetime is stable when a delegated transition replaces its widget
  // subtree. Removing a widget-owned observer mid-drag makes the system commit
  // fall back to popping the newly opened page instead of settling this one.
  final _ArchiveRoute<dynamic> route;

  @override
  bool handleStartBackGesture(PredictiveBackEvent event) {
    if (event.isButtonEvent || !route.isCurrent || !route.popGestureEnabled) {
      return false;
    }

    route.handleStartBackGesture(
      progress: 1 - event.progress,
      direction: event.swipeEdge == SwipeEdge.left ? 1 : -1,
    );
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent event) {
    route.handleUpdateBackGestureProgress(progress: 1 - event.progress);
  }

  @override
  void handleCancelBackGesture() => route.handleCancelBackGesture();

  @override
  void handleCommitBackGesture() => route.handleCommitBackGesture();
}

/// Both pages seek one route clock, including a reversed/cancelled gesture.
/// The outgoing content fades in the first 35%; incoming content follows in
/// the remaining 65%, as in the Kotlin client's destination transition.
class _ArchivePageMotion extends StatelessWidget {
  const _ArchivePageMotion({
    required this.animation,
    required this.motion,
    required this.navigator,
    required this.previous,
    required this.child,
  });

  final Animation<double> animation;
  final ValueNotifier<(bool returning, double direction)> motion;
  final NavigatorState navigator;
  final bool previous;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      animation,
      motion,
      navigator.userGestureInProgressNotifier,
    ]),
    child: child,
    builder: (context, child) {
      final reduced = MediaQuery.disableAnimationsOf(context);
      final (returning, direction) = motion.value;
      final progress = animation.value;
      final elapsed = returning ? 1 - progress : progress;
      final incoming = returning == previous;
      final opacity = reduced
          ? 1.0
          : incoming
          ? const Cubic(
              0,
              0,
              .2,
              1,
            ).transform(((elapsed - .35) / .65).clamp(0.0, 1.0))
          : archiveOutgoingOpacity(elapsed);
      final travel = ArchiveMotionCurve(navigator).transform(progress);

      final translated = Transform.translate(
        offset: Offset(
          reduced ? 0 : 30 * (previous ? -travel : 1 - travel) * direction,
          0,
        ),
        child: Opacity(opacity: opacity, child: child),
      );

      // The fade-through gap deliberately has no page content, but always has
      // an opaque, stationary theme surface beneath the shared-cover overlay.
      return previous
          ? ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: translated,
            )
          : translated;
    },
  );
}
