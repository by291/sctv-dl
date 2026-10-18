import '../../domain/playback/player_environment.dart';

/// Serializes window mutations independently of the native playback session.
class PlayerEnvironmentController {
  PlayerEnvironmentController(this.environment);

  final PlayerEnvironment environment;

  double? brightnessValue;
  int _generation = 0;
  Future<void> _changes = Future.value();

  Future<void> enterFullscreen() async {
    final generation = ++_generation;

    // A resumed route must capture its base after the previous window's queued
    // restoration, rather than retaining an override that is about to be reset.
    _changes = _changes.catchError((Object _) {}).then((_) async {
      if (generation != _generation) return;

      final initial = await environment.beginBrightness();
      if (generation != _generation) return;

      brightnessValue = initial;
    });
    await _changes;
  }

  Future<void> changeBrightness(double delta) async {
    final current = brightnessValue;
    if (current == null) return;

    final target = (current + delta).clamp(0.0, 1.0);
    brightnessValue = target;

    final generation = _generation;
    _changes = _changes.catchError((Object _) {}).then((_) async {
      if (generation == _generation) await environment.setBrightness(target);
    });
    await _changes;
  }

  Future<void> leaveFullscreen() async {
    ++_generation;
    brightnessValue = null;

    // Already started writes finish before restoration; queued stale writes skip.
    _changes = _changes.catchError((Object _) {}).then((_) async {
      await environment.restoreBrightness();
    });
    await _changes;
  }
}
