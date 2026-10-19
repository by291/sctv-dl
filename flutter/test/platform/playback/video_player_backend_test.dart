import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/platform/playback/video_player_backend.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

const first = VideoSource(
  quality: VideoQuality.standard,
  url: 'https://fscgc.scgchc.com/first.mp4',
);
const second = VideoSource(
  quality: VideoQuality.smooth,
  url: 'https://fscgc.scgchc.com/second.mp4',
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativePlayerFixture native;
  final wake = WakeFixture();
  final pip = PipFixture();
  setUpAll(() {
    native = NativePlayerFixture();
    wakelockPlusPlatformInstance = wake;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pip_kit'), pip.handle);
    VideoPlayerPlatform.instance = native;
  });
  setUp(() {
    debugDefaultTargetPlatformOverride = null;
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    wake.enabledValue = false;
    pip.calls.clear();
    pip.accept = true;
    native.sources.clear();
    native.seeks.clear();
    native.createCalls = 0;
    native.disposeCalls = 0;
    native.reject = null;
    native.failPause = false;
    native.createFailure = false;
    pip.enterGate = null;
    native.disposeDelay = null;
    native.activePlayers = 0;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  tearDownAll(() => native.close());
  test('buffering does not turn a quality change into a user pause', () async {
    final session = await VideoPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first, second]));
    await session.play();
    native.latestEvents.add(
      VideoEvent(eventType: VideoEventType.bufferingStart),
    );
    native.latestEvents.add(
      VideoEvent(
        eventType: VideoEventType.isPlayingStateUpdate,
        isPlaying: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.value.buffering, isTrue);
    await session.selectSource(second);
    expect(session.value.playing, isTrue);
    await session.dispose();
  });

  test(
    'resume seeks after initialization and survives a source switch',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test').open(
        const PlaybackInput(
          title: 'Resume',
          sources: [first, second],
          initialPosition: Duration(seconds: 42),
        ),
      );
      expect(session.value.initialized, isTrue);
      expect(native.seeks, [const Duration(seconds: 42)]);
      expect(session.value.position, const Duration(seconds: 42));
      expect(session.value.playing, isFalse);
      await session.selectSource(second);
      expect(native.seeks, List.filled(2, const Duration(seconds: 42)));
      expect(session.value.position, const Duration(seconds: 42));
      await session.dispose();
    },
  );

  test(
    'content URI uses the native local source without network headers',
    () async {
      const uri = 'content://media/external/downloads/123';
      final session = await VideoPlayerBackend(userAgent: 'test').open(
        const PlaybackInput(title: 'Local', sources: [], localLocation: uri),
      );
      expect(native.sources.single.uri, uri);
      expect(native.sources.single.sourceType, DataSourceType.contentUri);
      expect(native.sources.single.httpHeaders, isEmpty);
      await session.dispose();
    },
  );

  testWidgets('fits the video inside its surface without stretching', (
    tester,
  ) async {
    final session = (await tester.runAsync(
      () =>
          VideoPlayerBackend(userAgent: 'sctv-dl/test')
              .open(const PlaybackInput(title: 'Title', sources: [first])),
    ))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(session.dispose);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.square(
            dimension: 300,
            child: PlaybackSurface(session: session),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(VideoPlayer)), const Size(300, 168.75));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(session.dispose);
  });
  test('passes isolated media headers and starts paused', () async {
    final session = await VideoPlayerBackend(userAgent: 'sctv-dl/test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    expect(native.sources.single.httpHeaders, {
      'Referer': 'https://scgc.video.play/',
      'User-Agent': 'sctv-dl/test',
    });
    expect(session.value.playing, isFalse);
    await session.dispose();
    expect(native.disposeCalls, 1);
  });
  test(
    'switch preserves position speed and play intent and rolls back failure',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first, second]));
      await session.seek(const Duration(seconds: 12));
      await session.setSpeed(1.5);
      await session.play();
      await session.selectSource(second);
      expect(session.value.source, second);
      expect(session.value.position, const Duration(seconds: 12));
      expect(session.value.speed, 1.5);
      expect(session.value.playing, isTrue);
      native.reject = first.url;
      await expectLater(
        session.selectSource(first),
        throwsA(isA<PlatformException>()),
      );
      expect(session.value.source, second);
      expect(session.value.position, const Duration(seconds: 12));
      expect(native.activePlayers, 1);
      await session.dispose();
    },
  );
  test('play after completion restarts at zero before resuming', () async {
    final session = await VideoPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    await session.seek(const Duration(seconds: 100));
    native.latestEvents.add(VideoEvent(eventType: VideoEventType.completed));
    await Future<void>.delayed(Duration.zero);
    expect(session.value.ended, isTrue);
    await session.play();
    expect(session.value.position, Duration.zero);
    expect(session.value.playing, isTrue);
    await session.dispose();
  });

  test(
    'background pause while switching cancels the preserved play intent',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first, second]));
      await session.play();
      final pending = Completer<void>();
      native.setupDelay = pending.future;
      final switching = session.selectSource(second);
      await Future<void>.delayed(Duration.zero);
      await session.pause();
      pending.complete();
      await switching;
      expect(session.value.playing, isFalse);
      await session.dispose();
    },
  );
  test(
    'pause failure still releases native handles and closes observations',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]));
      var closed = false;
      final subscription = session.changes.listen(
        (_) {},
        onDone: () => closed = true,
      );
      native.failPause = true;

      await expectLater(session.dispose(), throwsStateError);
      await Future<void>.delayed(Duration.zero);

      expect(native.disposeCalls, 1);
      expect(closed, isTrue);
      await expectLater(session.dispose(), throwsStateError);
      expect(native.disposeCalls, 1);
      await subscription.cancel();
    },
  );

  test(
    'repeated disposal waits for the same native release completion',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]));
      final pending = Completer<void>();
      native.disposeDelay = pending.future;
      final firstRelease = session.dispose();
      var secondCompleted = false;
      final secondRelease = session.dispose().then(
        (_) => secondCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(secondCompleted, isFalse);
      pending.complete();
      await firstRelease;
      await secondRelease;
      expect(native.disposeCalls, 1);
    },
  );

  test('quality replacement waits for native release before allocating another decoder', () async {
    final session = await VideoPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first, second]));
    final released = Completer<void>();
    native.disposeDelay = released.future;
    final switching = session.selectSource(second);
    await Future<void>.delayed(Duration.zero);
    expect(native.createCalls, 1);
    expect(native.activePlayers, 1);
    released.complete();
    await switching;
    expect(native.createCalls, 2);
    expect(native.activePlayers, 1);
    await session.dispose();
    expect(native.activePlayers, 0);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform PiP observes native entry and exit on the same player',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final session = await VideoPlayerBackend(userAgent: 'test')
            .open(const PlaybackInput(title: 'Title', sources: [first]));
        await session.play();
        await session.enterPictureInPicture();
        expect(session.value.inPip, isTrue);
        expect(session.value.playing, isTrue);
        expect(native.createCalls, 1);
        final config =
            pip.calls.firstWhere((call) => call.method == 'configure').arguments
                as Map;
        expect(config['mode'], 'video');
        expect(config['autoEnter'], isFalse);
        await pip.report(false);
        expect(session.value.inPip, isFalse);
        expect(session.value.playing, isTrue);
        await session.dispose();
        expect(native.activePlayers, 0);
      },
    );
  }

  test(
    'PiP rejection preserves a paused iOS session and releases the window',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      pip.accept = false;
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]));
      await expectLater(session.enterPictureInPicture(), throwsStateError);
      expect(session.value.playing, isFalse);
      expect(session.value.inPip, isFalse);
      await session.dispose();
    },
  );

  test(
    'screen lock follows foreground playback and is released with the session',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]));
      expect(wake.enabledValue, isFalse);
      await session.play();
      await Future<void>.delayed(Duration.zero);
      expect(wake.enabledValue, isTrue);
      await session.enterPictureInPicture();
      await Future<void>.delayed(Duration.zero);
      expect(wake.enabledValue, isFalse);
      await pip.report(false);
      await session.dispose();
      expect(wake.enabledValue, isFalse);
    },
  );

  test(
    'exit cancels pending initialization without waiting for media readiness',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first, second]));
      final ready = Completer<void>();
      native.setupDelay = ready.future;
      final switching = session.selectSource(second);
      await Future<void>.delayed(Duration.zero);
      final disposed = session.dispose();
      await switching;
      await disposed.timeout(const Duration(seconds: 1));
      expect(native.activePlayers, 0);
      ready.complete();
    },
  );

  test(
    'iOS system PiP play resumes progress and survives a quality switch',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first, second]));
      await session.enterPictureInPicture();
      expect(session.value.playing, isFalse);
      native.positions[native.createCalls] = const Duration(seconds: 20);
      native.latestEvents.add(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 650));
      expect(session.value.position, const Duration(seconds: 20));
      await pip.report(false);
      await session.selectSource(second);
      expect(session.value.playing, isTrue);
      expect(session.value.position, const Duration(seconds: 20));
      await session.dispose();
    },
  );

  test(
    'release during Android PiP entry closes the system window before disposal',
    () async {
      final session = await VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]));
      final pending = Completer<void>();
      pip.enterGate = pending.future;
      final entering = session.enterPictureInPicture();
      await Future<void>.delayed(Duration.zero);
      final disposal = session.dispose();
      pending.complete();
      await entering;
      await disposal;
      expect(session.value.inPip, isFalse);
      expect(native.activePlayers, 0);
    },
  );

  test('native allocation failure reports its original cause without hanging cleanup', () async {
    native.createFailure = true;
    await expectLater(
      VideoPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first]))
          .timeout(const Duration(seconds: 7)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'allocation',
        ),
      ),
    );
  });

  test('an unconfirmed release blocks a new route until the original native disposal finishes', () async {
    final backend = VideoPlayerBackend(userAgent: 'test');
    final session = await backend.open(
      const PlaybackInput(title: 'Title', sources: [first, second]),
    );
    final released = Completer<void>();
    native.disposeDelay = released.future;
    await expectLater(session.selectSource(second), throwsStateError);

    final opening = backend.open(
      const PlaybackInput(title: 'Retry', sources: [first]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(native.createCalls, 1);
    expect(native.disposeCalls, 1);
    released.complete();
    final replacement = await opening;
    expect(native.activePlayers, 1);
    await session.dispose();
    expect(native.disposeCalls, 1);
    await replacement.dispose();
    expect(native.activePlayers, 0);
  });

  test('stopping the Android PiP Activity pauses without waiting for another background event', () async {
    final session = await VideoPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    await session.play();
    await session.enterPictureInPicture();
    final delivered = Completer<void>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'dev.sctvdl.flutter/picture_in_picture',
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('stopped'),
          ),
          (_) => delivered.complete(),
        );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
    expect(session.value.playing, isFalse);
    await pip.report(false);
    expect(session.value.playing, isFalse);
    await session.dispose();
  });

  test('rejects unapproved media before native creation', () async {
    await expectLater(
      VideoPlayerBackend(userAgent: 'test').open(
        const PlaybackInput(
          title: 'Title',
          sources: [
            VideoSource(
              quality: VideoQuality.standard,
              url: 'https://example.com/video.mp4',
            ),
          ],
        ),
      ),
      throwsFormatException,
    );
    expect(native.createCalls, 0);
  });
}

class NativePlayerFixture extends VideoPlayerPlatform {
  final sources = <DataSource>[];
  final seeks = <Duration>[];
  final events = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  String? reject;
  Future<void>? setupDelay;
  Future<void>? disposeDelay;
  bool failPause = false;
  bool createFailure = false;
  int createCalls = 0;
  int disposeCalls = 0;
  int activePlayers = 0;

  StreamController<VideoEvent> get latestEvents => events[createCalls]!;

  Future<void> close() async {
    for (final stream in events.values) {
      await stream.close();
    }
  }

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (createFailure) {
      throw PlatformException(
        code: 'allocation',
        message: 'Cannot allocate decoder',
      );
    }
    final id = ++createCalls;
    activePlayers++;
    sources.add(options.dataSource);
    positions[id] = Duration.zero;
    events[id] = StreamController<VideoEvent>();
    final delay = setupDelay;
    setupDelay = null;
    unawaited(
      Future<void>(() async {
        await delay;
        if (!events.containsKey(id)) return;
        if (options.dataSource.uri == reject) {
          events[id]!.addError(
            PlatformException(
              code: 'fixture',
              message: 'Fixture refused source',
            ),
          );
        } else {
          events[id]!.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: const Duration(seconds: 100),
              size: const Size(1280, 720),
            ),
          );
        }
      }),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    disposeCalls++;
    await disposeDelay;
    activePlayers--;
    await events.remove(playerId)?.close();
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {
    if (failPause) throw StateError('Pause failed');
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration value) async {
    positions[playerId] = value;
    seeks.add(value);
  }

  @override
  Future<Duration> getPosition(int playerId) async => positions[playerId]!;
  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}

class WakeFixture extends WakelockPlusPlatformInterface {
  bool enabledValue = false;
  @override
  Future<bool> get enabled async => enabledValue;
  @override
  Future<void> toggle({required bool enable}) async => enabledValue = enable;
}

class PipFixture {
  final calls = <MethodCall>[];
  bool accept = true;
  Future<void>? enterGate;

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    if (call.method == 'enter' && accept) {
      await enterGate;
      await report(true);
    }
    // Android release only clears window parameters; it does not close PiP.
    if (call.method == 'exit') await report(false);
    return call.method == 'enter' ? accept : true;
  }

  Future<void> report(bool active) async {
    final done = Completer<void>();
    final android = defaultTargetPlatform == TargetPlatform.android;
    // This is a native-to-Dart event, independent of foreground lifecycle.
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          android ? 'dev.sctvdl.flutter/picture_in_picture' : 'pip_kit',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(android ? 'changed' : 'onStatus', active),
          ),
          (_) => done.complete(),
        );
    await done.future;
  }
}
