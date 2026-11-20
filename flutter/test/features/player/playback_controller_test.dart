import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/features/player/playback_controller.dart';

import '../../support/playback_fixtures.dart';

void main() {
  test(
    'starts paused and saves progress with completion at ninety five percent',
    () async {
      final session = FakeSession();
      final history = MemoryHistory();
      var now = DateTime(2026);
      final controller = PlaybackController(
        input: input,
        backend: FakeBackend(session),
        history: history,
        now: () => now,
      );
      await controller.initialize();
      expect(session.playCalls, 0);
      session.emit(playing: true, position: const Duration(seconds: 10));
      await controller.flushHistory();
      expect(history.entries.length, 1);
      now = now.add(const Duration(seconds: 4));
      session.emit(playing: true, position: const Duration(seconds: 14));
      await controller.flushHistory();
      expect(history.entries.length, 1);
      now = now.add(const Duration(seconds: 1));
      session.emit(playing: true, position: const Duration(seconds: 95));
      await controller.flushHistory();
      expect(history.entries.last.completed, isTrue);
      await controller.release();
      controller.dispose();
    },
  );

  test('ordinary background pauses while explicit picture in picture retains playback', () async {
    final session = FakeSession();
    final controller = PlaybackController(
      input: input,
      backend: FakeBackend(session),
      history: MemoryHistory(),
    );
    await controller.initialize();
    session.emit(playing: true);
    await controller.background();
    expect(session.pauseCalls, 1);
    session.emit(playing: true, inPip: true);
    await controller.background();
    expect(session.pauseCalls, 1);
    await controller.release();
    expect(session.disposeCalls, 0);
    session.emit(inPip: false);
    await Future<void>.delayed(Duration.zero);
    expect(session.disposeCalls, 1);
    controller.dispose();
  });

  test(
    'failed PiP request pauses if backgrounding raced the request',
    () async {
      final session = FakeSession();
      final pip = Completer<void>();
      session.pipResult = pip.future;
      final controller = PlaybackController(
        input: input,
        backend: FakeBackend(session),
        history: MemoryHistory(),
      );
      await controller.initialize();
      session.emit(playing: true);
      final request = controller.enterPictureInPicture();
      await controller.background();
      expect(session.pauseCalls, 0);
      pip.completeError(StateError('PiP rejected'));
      await request;
      expect(session.pauseCalls, 1);
      expect(controller.value.playing, isFalse);
      await controller.release();
      controller.dispose();
    },
  );

  test('native error retry replaces the failed session and restores playback intent', () async {
    final first = FakeSession();
    final replacement = FakeSession();
    final backend = SequenceBackend([first, replacement]);
    final controller = PlaybackController(
      input: input,
      backend: backend,
      history: MemoryHistory(),
    );
    await controller.initialize();
    first.emit(
      playing: true,
      position: const Duration(seconds: 12),
      speed: 1.5,
    );
    first.emit(
      error: 'Decoder failed',
      position: const Duration(seconds: 12),
      speed: 1.5,
    );
    expect(controller.canRetry, isTrue);
    await controller.retry();
    expect(first.disposeCalls, 1);
    expect(controller.session, same(replacement));
    expect(controller.value.position, const Duration(seconds: 12));
    expect(controller.value.speed, 1.5);
    expect(controller.value.playing, isTrue);
    expect(controller.canRetry, isFalse);
    await controller.release();
    controller.dispose();
  });

  test('retry remains paused when playback failed while paused', () async {
    final first = FakeSession();
    final controller = PlaybackController(
      input: input,
      backend: SequenceBackend([first, FakeSession()]),
      history: MemoryHistory(),
    );
    await controller.initialize();
    first.emit(position: const Duration(seconds: 12));
    first.emit(error: 'Decoder failed');
    await controller.retry();
    expect(controller.value.playing, isFalse);
    expect(controller.value.position, const Duration(seconds: 12));
    await controller.release();
    controller.dispose();
  });

  test('a replacement opened after route release is disposed without restoring speed', () async {
    final first = FakeSession();
    final replacement = FakeSession();
    final backend = RetryBackend(first);
    final controller = PlaybackController(
      input: input,
      backend: backend,
      history: MemoryHistory(),
    );
    await controller.initialize();
    first.emit(playing: true, speed: 1.5);
    first.emit(error: 'Decoder failed');

    final retry = controller.retry();
    await backend.replacementRequested.future;
    await controller.release();
    backend.replacement.complete(replacement);
    await retry;

    expect(replacement.value.speed, 1);
    expect(replacement.disposeCalls, 1);
    controller.dispose();
  });

  test('backgrounding during retry cancels the earlier play intent', () async {
    final first = FakeSession();
    final replacement = FakeSession();
    final backend = RetryBackend(first);
    final controller = PlaybackController(
      input: input,
      backend: backend,
      history: MemoryHistory(),
    );
    await controller.initialize();
    first.emit(playing: true);
    first.emit(error: 'Decoder failed');
    final retry = controller.retry();
    await Future<void>.delayed(Duration.zero);
    await controller.background();
    backend.replacement.complete(replacement);
    await retry;
    expect(controller.value.playing, isFalse);
    expect(replacement.playCalls, 0);
    await controller.release();
    controller.dispose();
  });

  test('committed exit saves progress even when native pause fails', () async {
    final session = FakeSession()..failPause = true;
    final history = MemoryHistory();
    final controller = PlaybackController(
      input: input,
      backend: FakeBackend(session),
      history: history,
    );
    await controller.initialize();
    session.emit(position: const Duration(seconds: 42));

    await controller.commitExit();

    expect(history.entries.last.position, const Duration(seconds: 42));
    expect(controller.message, contains('Pause failed'));
    await controller.release();
    expect(session.disposeCalls, 1);
    controller.dispose();
  });

  test('repeated release waits until session cleanup finishes', () async {
    final session = FakeSession();
    final pending = Completer<void>();
    session.disposeDelay = pending.future;
    final controller = PlaybackController(
      input: input,
      backend: FakeBackend(session),
      history: MemoryHistory(),
    );
    await controller.initialize();
    final first = controller.release();
    var completed = false;
    final second = controller.release().then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    pending.complete();
    await first;
    await second;
    expect(session.disposeCalls, 1);
    controller.dispose();
  });

  testWidgets('closing a menu cannot release the accessibility hold', (
    tester,
  ) async {
    final session = FakeSession();
    final controller = PlaybackController(
      input: input,
      backend: FakeBackend(session),
      history: MemoryHistory(),
    );
    await controller.initialize();
    session.emit(playing: true);
    controller.holdControls(
      held: true,
      reason: PlayerControlHold.accessibility,
    );
    controller.holdControls(held: true, reason: PlayerControlHold.menu);
    controller.holdControls(held: false, reason: PlayerControlHold.menu);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isTrue);
    controller.holdControls(
      held: false,
      reason: PlayerControlHold.accessibility,
    );
    await tester.pump(const Duration(milliseconds: 3501));
    expect(controller.controlsVisible, isFalse);
    await tester.runAsync(controller.release);
    controller.dispose();
  });

  test(
    'stream failures also expose retry for an otherwise initialized session',
    () async {
      final failed = FakeSession();
      final replacement = FakeSession();
      final controller = PlaybackController(
        input: input,
        backend: SequenceBackend([failed, replacement]),
        history: MemoryHistory(),
      );
      await controller.initialize();
      failed.events.addError(StateError('Native stream failed'));
      expect(controller.canRetry, isTrue);
      await controller.retry();
      expect(controller.session, same(replacement));
      await controller.release();
      controller.dispose();
    },
  );

  test('stale initialization releases only its old native session', () async {
    final old = FakeSession();
    final completer = Completer<PlaybackSession>();
    final controller = PlaybackController(
      input: input,
      backend: DelayedBackend(completer.future),
      history: MemoryHistory(),
    );
    final loading = controller.initialize();
    await controller.release();
    completer.complete(old);
    await loading;
    expect(old.disposeCalls, 1);
    expect(controller.session, isNull);
    controller.dispose();
  });

  test(
    'failed quality switch keeps previous source with actionable feedback',
    () async {
      final session = FakeSession()..failSwitch = true;
      final controller = PlaybackController(
        input: input,
        backend: FakeBackend(session),
        history: MemoryHistory(),
      );
      await controller.initialize();
      await controller.selectSource(smooth);
      expect(controller.value.source, standard);
      expect(controller.message, contains('画质'));
      expect(session.disposeCalls, 0);
      await controller.release();
      controller.dispose();
    },
  );

  testWidgets('controls hide only during uninterrupted playback', (
    tester,
  ) async {
    final session = FakeSession();
    final controller = PlaybackController(
      input: input,
      backend: FakeBackend(session),
      history: MemoryHistory(),
    );
    await controller.initialize();
    session.emit(playing: true);
    await tester.pump(const Duration(milliseconds: 3501));
    expect(controller.controlsVisible, isFalse);
    controller.showControls();
    controller.holdControls(held: true);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.controlsVisible, isTrue);
    controller.holdControls(held: false);
    session.emit(playing: false);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.controlsVisible, isTrue);
    await tester.runAsync(controller.release);
    controller.dispose();
  });
}

class RetryBackend implements PlaybackBackend {
  RetryBackend(this.first);
  final FakeSession first;
  final replacement = Completer<PlaybackSession>();
  final replacementRequested = Completer<void>();
  bool opened = false;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    if (opened) {
      replacementRequested.complete();
      return replacement.future;
    }
    opened = true;
    return first;
  }
}
