import 'package:flutter/services.dart';

/// Serializes OS window policy changes while allowing recovery after failure.
class PlayerWindowController {
  Future<void> _changes = Future.value();
  int _requestRevision = 0;
  bool _needsRestoration = false;

  bool get needsRestoration => _needsRestoration;

  Future<void> setFullscreen(bool enabled) {
    final revision = ++_requestRevision;

    // Platform requests can partly succeed. Keep cleanup ownership independent
    // of the page layout until both OS policies have been restored successfully.
    if (enabled) _needsRestoration = true;

    final change = _changes.then((_) => _applyWindow(enabled, revision));

    // The caller owns this request's error. The queue only owns ordering, and
    // must still execute a later restoration after a rejected platform request.
    _changes = change.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return change;
  }

  Future<void> _applyWindow(bool enabled, int revision) async {
    (Object, StackTrace)? failure;
    try {
      await SystemChrome.setPreferredOrientations(
        enabled
            ? [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : [],
      );
    } catch (error, stack) {
      failure = (error, stack);
    }

    // Orientation and system UI have separate cleanup obligations. A rejected
    // orientation request must not leave the navigation/status bars hidden.
    try {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } catch (error, stack) {
      failure ??= (error, stack);
    }

    if (failure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }

    // A later fullscreen request may already be queued behind this restoration.
    if (!enabled && revision == _requestRevision) _needsRestoration = false;
  }
}
