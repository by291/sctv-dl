import 'dart:async';

import 'package:sctv_dl_mobile/domain/playback/player_environment.dart';

class Environment implements PlayerEnvironment {
  final read = Completer<double>();
  double current = .4;
  @override
  bool get supportsVolumeDrag => true;
  @override
  Future<double> brightness() => read.future;
  @override
  Future<double> beginBrightness() => brightness();
  @override
  Future<void> setBrightness(double value) async {
    current = value;
  }

  @override
  Future<void> restoreBrightness() async {
    current = .4;
  }

  @override
  Future<double> volume() async => .5;
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<bool> needsGestureHint() async => true;
  @override
  Future<void> acknowledgeGestureHint() async {}
}
