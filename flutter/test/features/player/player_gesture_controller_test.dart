import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/player/playback_controller.dart';

import 'playback_controller_test.dart' as fixtures;

void main() {
  test('release owns disposal until restored snapshot and native operation both finish', () async {
    final session = SnapshotBeforeRestoreSession();
    final player = PlaybackController(
      input: fixtures.input,
      backend: fixtures.FakeBackend(session),
      history: fixtures.MemoryHistory(),
    );
    await player.initialize();
    await player.setSpeed(1.25);
    session.emit(playing: true, speed: 1.25);
    await player.beginTemporarySpeed();
    session.blockRestore = true;
    final restoration = player.endTemporarySpeed();
    await session.restoreStarted.future;
    var released = false;
    final release = player.release().then((_) => released = true);
    session.publishGate.complete();
    await session.restorePublished.future;
    await Future<void>.delayed(Duration.zero);
    expect(
      session.disposalStarts,
      0,
      reason: 'A native snapshot does not complete its speed operation',
    );
    expect(released, isFalse);
    session.finishRestore.complete();
    await restoration;
    await session.disposalStarted.future;
    expect(session.disposalStarts, 1);
    expect(
      released,
      isFalse,
      reason: 'Release must await native disposal completion',
    );
    session.finishDisposal.complete();
    await release;
    expect(session.disposeCalls, 1);
    expect(session.value.speed, 1.25);
    player.dispose();
  });
  for (final operation in ['source', 'pip', 'release']) {
    test(
      '$operation waits for an already pending restoration after long press release',
      () async {
        final session = RestoreBlockedSession();
        final player = PlaybackController(
          input: fixtures.input,
          backend: fixtures.FakeBackend(session),
          history: fixtures.MemoryHistory(),
        );
        await player.initialize();
        await player.setSpeed(1.25);
        session.emit(playing: true, speed: 1.25);
        await player.beginTemporarySpeed();
        session.blockRestore = true;
        final restoration = player.endTemporarySpeed();
        await session.restoreStarted.future;
        expect(player.temporarySpeed, isFalse);
        final transition = switch (operation) {
          'source' => player.selectSource(fixtures.smooth),
          'pip' => player.enterPictureInPicture(),
          _ => player.release(),
        };
        await Future<void>.delayed(Duration.zero);
        expect(
          session.transitionSpeeds,
          isEmpty,
          reason: 'Native transition must wait for selected speed restoration',
        );
        session.restoreGate.complete();
        await Future.wait([restoration, transition]);
        expect(session.transitionSpeeds, [1.25]);
        expect(player.selectedSpeed, 1.25);
        expect(session.value.speed, 1.25);
        if (operation == 'pip') session.emit(speed: 1.25);
        await player.release();
        player.dispose();
      },
    );
  }
  for (final operation in ['source', 'pip']) {
    test(
      'failed restore prevents $operation from capturing temporary speed',
      () async {
        final session = RestoreBlockedSession()..failRestore = true;
        final player = PlaybackController(
          input: fixtures.input,
          backend: fixtures.FakeBackend(session),
          history: fixtures.MemoryHistory(),
        );
        await player.initialize();
        await player.setSpeed(1.25);
        session.emit(playing: true, speed: 1.25);
        await player.beginTemporarySpeed();
        session.blockRestore = true;
        final restoration = player.endTemporarySpeed();
        await session.restoreStarted.future;
        final transition = operation == 'source'
            ? player.selectSource(fixtures.smooth)
            : player.enterPictureInPicture();
        session.restoreGate.complete();
        await Future.wait([restoration, transition]);
        expect(session.transitionSpeeds, isEmpty);
        expect(player.selectedSpeed, 1.25);
        expect(player.message, isNotNull);
        await player.release();
        expect(session.disposeCalls, 1);
        player.dispose();
      },
    );
  }
  test('failed pending restoration drains cancellation and later speed commands recover', () async {
    final session = RestoreBlockedSession()..failRestore = true;
    final player = PlaybackController(
      input: fixtures.input,
      backend: fixtures.FakeBackend(session),
      history: fixtures.MemoryHistory(),
    );
    await player.initialize();
    await player.setSpeed(1.25);
    session.emit(playing: true, speed: 1.25);
    await player.beginTemporarySpeed();
    session.blockRestore = true;
    final restoration = player.endTemporarySpeed();
    await session.restoreStarted.future;
    final cancellation = player.cancelGestures();
    var cancelled = false;
    unawaited(cancellation.then((_) => cancelled = true));
    await Future<void>.delayed(Duration.zero);
    expect(cancelled, isFalse);
    session.restoreGate.complete();
    await Future.wait([restoration, cancellation]);
    expect(player.selectedSpeed, 1.25);
    expect(player.message, isNotNull);
    session.blockRestore = false;
    await player.setSpeed(1.5);
    expect(session.value.speed, 1.5);
    await player.release();
    player.dispose();
  });
  test('unknown durations reject seeking and long videos use a two-minute full-width range', () async {
    final session = fixtures.FakeSession();
    final player = PlaybackController(
      input: fixtures.input,
      backend: fixtures.FakeBackend(session),
      history: fixtures.MemoryHistory(),
    );
    await player.initialize();
    session.emit(duration: null);
    player.previewSeek(.5);
    expect(player.seekPreview, isNull);
    session.emit(duration: Duration.zero);
    player.previewSeek(.5);
    await player.finishSeek(commit: true);
    expect(session.seekCalls, 0);
    session.emit(
      duration: const Duration(minutes: 10),
      position: const Duration(minutes: 5),
    );
    player.previewSeek(.5);
    expect(player.seekPreview, const Duration(minutes: 6));
    await player.release();
    player.dispose();
  });
  test(
    'source requests are guarded while delayed boost restoration drains',
    () async {
      final session = DelayedSpeedSession();
      final player = PlaybackController(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
      );
      await player.initialize();
      await player.setSpeed(1.25);
      session.emit(playing: true, speed: 1.25);
      final boost = player.beginTemporarySpeed();
      await Future<void>.delayed(Duration.zero);
      final first = player.selectSource(fixtures.smooth);
      final second = player.selectSource(fixtures.smooth);
      session.pending.complete();
      await Future.wait([boost, first, second]);
      expect(session.switchCalls, 1);
      expect(session.speedAtSwitch, 1.25);
      await player.release();
      player.dispose();
    },
  );
  test(
    'seek cancellation never commits and release commits bounded preview once',
    () async {
      final session = fixtures.FakeSession();
      final player = PlaybackController(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
      );
      await player.initialize();
      session.emit(position: const Duration(seconds: 50));
      player.previewSeek(.25);
      expect(player.seekPreview, const Duration(seconds: 75));
      await player.finishSeek(commit: false);
      expect(session.seekCalls, 0);
      player.previewSeek(2);
      expect(player.seekPreview, const Duration(seconds: 100));
      await player.finishSeek(commit: true);
      expect(session.seekCalls, 1);
      expect(session.value.position, const Duration(seconds: 100));
      await player.release();
      player.dispose();
    },
  );
  test(
    'delayed boost completion is followed by restoration of selected speed',
    () async {
      final session = DelayedSpeedSession();
      final player = PlaybackController(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
      );
      await player.initialize();
      await player.setSpeed(1.25);
      session.emit(playing: true, speed: 1.25);
      final boost = player.beginTemporarySpeed();
      await Future<void>.delayed(Duration.zero);
      final restore = player.endTemporarySpeed();
      session.pending.complete();
      await Future.wait([boost, restore]);
      expect(session.value.speed, 1.25);
      expect(player.selectedSpeed, 1.25);
      await player.release();
      player.dispose();
    },
  );
}

class DelayedSpeedSession extends fixtures.FakeSession {
  int switchCalls = 0;
  double? speedAtSwitch;
  @override
  Future<void> selectSource(VideoSource source) async {
    switchCalls++;
    speedAtSwitch = value.speed;
  }

  final pending = Completer<void>();
  @override
  Future<void> setSpeed(double speed) async {
    if (speed == 2) await pending.future;
    await super.setSpeed(speed);
  }
}

class RestoreBlockedSession extends fixtures.FakeSession {
  bool blockRestore = false;
  bool failRestore = false;
  final restoreStarted = Completer<void>();
  final restoreGate = Completer<void>();
  final transitionSpeeds = <double>[];
  @override
  Future<void> setSpeed(double speed) async {
    if (blockRestore && speed == 1.25) {
      if (!restoreStarted.isCompleted) restoreStarted.complete();
      await restoreGate.future;
      if (failRestore) throw StateError('Native restore rejected');
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

class SnapshotBeforeRestoreSession extends fixtures.FakeSession {
  bool blockRestore = false;
  int disposalStarts = 0;
  final restoreStarted = Completer<void>();
  final publishGate = Completer<void>();
  final restorePublished = Completer<void>();
  final finishRestore = Completer<void>();
  final disposalStarted = Completer<void>();
  final finishDisposal = Completer<void>();
  @override
  Future<void> setSpeed(double speed) async {
    if (blockRestore && speed == 1.25) {
      restoreStarted.complete();
      await publishGate.future;
      await super.setSpeed(speed);
      restorePublished.complete();
      await finishRestore.future;
    } else {
      await super.setSpeed(speed);
    }
  }

  @override
  Future<void> dispose() async {
    disposalStarts++;
    disposalStarted.complete();
    await finishDisposal.future;
    await super.dispose();
  }
}
