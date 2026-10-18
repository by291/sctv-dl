import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/player/playback_controller.dart';

const standard = VideoSource(
  quality: VideoQuality.standard,
  url: 'https://media.example/standard.mp4',
);
const smooth = VideoSource(
  quality: VideoQuality.smooth,
  url: 'https://media.example/smooth.mp4',
);
const selection = ProgrammeSelection(
  programme: Programme(id: '1', name: 'Programme'),
  broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
  content: ProgrammeContent(id: '3', title: 'Title'),
);
const input = PlaybackInput(
  title: 'Title',
  sources: [standard, smooth],
  selection: selection,
);

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
    controller.holdControls(true, reason: PlayerControlHold.accessibility);
    controller.holdControls(true, reason: PlayerControlHold.menu);
    controller.holdControls(false, reason: PlayerControlHold.menu);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.controlsVisible, isTrue);
    controller.holdControls(false, reason: PlayerControlHold.accessibility);
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
    controller.holdControls(true);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.controlsVisible, isTrue);
    controller.holdControls(false);
    session.emit(playing: false);
    await tester.pump(const Duration(seconds: 10));
    expect(controller.controlsVisible, isTrue);
    await tester.runAsync(controller.release);
    controller.dispose();
  });
}

class FakeBackend implements PlaybackBackend {
  FakeBackend(this.session);
  final PlaybackSession session;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async => session;
}

class SequenceBackend implements PlaybackBackend {
  SequenceBackend(this.sessions);
  final List<FakeSession> sessions;
  var next = 0;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    final session = sessions[next++];
    session.emit(position: input.initialPosition);
    return session;
  }
}

class DelayedBackend implements PlaybackBackend {
  DelayedBackend(this.result);
  final Future<PlaybackSession> result;
  @override
  Future<PlaybackSession> open(PlaybackInput input) => result;
}

class FakeSession implements PlaybackSession {
  final events = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  @override
  final id = 'fake';
  @override
  PlaybackSnapshot value = const PlaybackSnapshot(
    initialized: true,
    source: standard,
    duration: Duration(seconds: 100),
    supportsPip: true,
  );
  int playCalls = 0;
  int seekCalls = 0;
  int pauseCalls = 0;
  int disposeCalls = 0;
  bool failSwitch = false;
  bool failPause = false;
  Future<void>? disposeDelay;
  Future<void>? pipResult;
  void emit({
    bool playing = false,
    bool inPip = false,
    bool buffering = false,
    Duration? duration = const Duration(seconds: 100),
    Duration position = Duration.zero,
    double speed = 1,
    bool initialized = true,
    String? error,
  }) {
    value = PlaybackSnapshot(
      initialized: initialized,
      error: error,
      speed: speed,
      source: standard,
      duration: duration,
      playing: playing,
      inPip: inPip,
      buffering: buffering,
      position: position,
      supportsPip: true,
    );
    events.add(value);
  }

  @override
  Stream<PlaybackSnapshot> get changes => events.stream;
  @override
  Future<void> play() async {
    playCalls++;
    emit(playing: true, position: value.position, speed: value.speed);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (failPause) throw StateError('Pause failed');
    emit(position: value.position, speed: value.speed);
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    emit(position: position);
  }

  @override
  Future<void> setSpeed(double speed) async => emit(
    playing: value.playing,
    position: value.position,
    inPip: value.inPip,
    speed: speed,
  );
  @override
  Future<void> selectSource(VideoSource source) async {
    if (failSwitch) throw StateError('unavailable');
  }

  @override
  Future<void> enterPictureInPicture() async {
    if (pipResult case final Future<void> pending) {
      await pending;
      return;
    }
    emit(playing: true, inPip: true);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await disposeDelay;
    await events.close();
  }
}

class MemoryHistory implements HistoryRepository {
  final entries = <ViewingEntry>[];
  @override
  Future<void> save(ViewingEntry entry) async => entries.add(entry);
  @override
  Future<List<ViewingEntry>> loadHistory() async => entries;
  @override
  Stream<List<ViewingEntry>> watchHistory() => const Stream.empty();
  @override
  Future<void> remove(ContentRef ref) async {}
  @override
  Future<void> clear() async => entries.clear();
}

class RetryBackend implements PlaybackBackend {
  RetryBackend(this.first);
  final FakeSession first;
  final replacement = Completer<PlaybackSession>();
  bool opened = false;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    if (opened) return replacement.future;
    opened = true;
    return first;
  }
}
