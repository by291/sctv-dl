import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/player_environment.dart';
import 'package:sctv_dl_mobile/features/player/player_environment_controller.dart';

void main() {
  test(
    'leaving fullscreen rejects late brightness reads without changing window',
    () async {
      final environment = Environment();
      final controller = PlayerEnvironmentController(environment);
      final entering = controller.enterFullscreen();
      final leaving = controller.leaveFullscreen();
      environment.read.complete(.4);
      await Future.wait([entering, leaving]);
      expect(environment.current, .4);
      expect(controller.brightnessValue, isNull);
    },
  );
  test('resuming waits for restoration before capturing the gesture brightness base', () async {
    final environment = RestoringEnvironment();
    final controller = PlayerEnvironmentController(environment);
    await controller.enterFullscreen();
    await controller.changeBrightness(.3);
    final leaving = controller.leaveFullscreen();
    await environment.restoring.future;

    final entering = controller.enterFullscreen();
    await Future<void>.delayed(Duration.zero);
    final prematureBase = controller.brightnessValue;
    environment.restoreGate.complete();
    await Future.wait([leaving, entering]);

    expect(prematureBase, isNull);
    expect(controller.brightnessValue, .4);
    await controller.changeBrightness(.1);
    expect(environment.current, .5);
    await controller.leaveFullscreen();
  });

  test(
    'brightness writes finish before restoring the entering value',
    () async {
      final environment = Environment()..read.complete(.4);
      final controller = PlayerEnvironmentController(environment);
      await controller.enterFullscreen();
      await controller.changeBrightness(.3);
      expect(environment.current, .7);
      await controller.leaveFullscreen();
      expect(environment.current, .4);
    },
  );
}

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

class RestoringEnvironment extends Environment {
  final restoring = Completer<void>();
  final restoreGate = Completer<void>();

  @override
  Future<double> beginBrightness() async => current;

  @override
  Future<void> restoreBrightness() async {
    if (!restoring.isCompleted) restoring.complete();
    await restoreGate.future;
    current = .4;
  }
}
