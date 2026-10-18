/// Window effects are independent of playback sessions and their PiP lifetime.
abstract interface class PlayerEnvironment {
  bool get supportsVolumeDrag;

  Future<double> brightness();
  Future<double> beginBrightness();
  Future<void> setBrightness(double value);
  Future<void> restoreBrightness();

  Future<double> volume();
  Future<void> setVolume(double value);

  Future<bool> needsGestureHint();
  Future<void> acknowledgeGestureHint();
}
