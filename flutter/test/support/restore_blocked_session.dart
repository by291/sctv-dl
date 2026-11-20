import 'dart:async';

import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

import 'playback_fixtures.dart';

class RestoreBlockedSession extends FakeSession {
  bool blockRestore = false;
  bool failRestore = false;
  final restoreStarted = Completer<void>();
  final restoreGate = Completer<void>();
  final transitionSpeeds = <double>[];
  @override
  Future<void> setSpeed(double speed) async {
    if (blockRestore && speed == 1.25) {
      if (!restoreStarted.isCompleted) {
        restoreStarted.complete();
      }
      await restoreGate.future;
      if (failRestore) {
        throw StateError('Native restore rejected');
      }
    }
    await super.setSpeed(speed);
  }

  @override
  Future<void> selectSource(VideoSource source) async {
    final captured = value.speed;
    transitionSpeeds.add(captured);
    await Future<void>.delayed(Duration.zero);
    await super.setSpeed(captured);
  }

  @override
  Future<void> enterPictureInPicture() async {
    final speed = value.speed;
    transitionSpeeds.add(speed);
    emit(playing: true, inPip: true, speed: speed);
  }

  @override
  Future<void> dispose() async {
    transitionSpeeds.add(value.speed);
    await super.dispose();
  }
}
