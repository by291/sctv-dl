import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/platform/playback/better_player_backend.dart';

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
  setUpAll(() {
    native = NativePlayerFixture();
    VideoPlayerPlatform.instance = native;
  });
  setUp(() {
    native.sources.clear();
    native.seeks.clear();
    native.bufferingConfigurations.clear();
    native.createCalls = 0;
    native.disposeCalls = 0;
    native.reject = null;
    native.failPause = false;
    native.disposeDelay = null;
  });
  tearDownAll(() => native.events.close());
  test(
    'cover readiness waits for native frame output and resets with the source',
    () async {
      final session = await BetterPlayerBackend(userAgent: 'test')
          .open(const PlaybackInput(title: 'Title', sources: [first, second]));
      expect(session.value.initialized, isTrue);
      expect(session.value.firstFrameRendered, isFalse);
      native.events.add(
        VideoEvent(key: null, eventType: VideoEventType.firstFrameRendered),
      );
      expect(session.value.firstFrameRendered, isTrue);
      await session.selectSource(second);
      expect(session.value.firstFrameRendered, isFalse);
      native.events.add(
        VideoEvent(key: null, eventType: VideoEventType.firstFrameRendered),
      );
      expect(session.value.firstFrameRendered, isTrue);
      await session.dispose();
    },
  );
  test('resume prepares the target frame without a second seek', () async {
    final session = await BetterPlayerBackend(userAgent: 'test').open(
      const PlaybackInput(
        title: 'Resume',
        sources: [first, second],
        initialPosition: Duration(seconds: 42),
      ),
    );
    expect(native.sources.single.initialPosition, const Duration(seconds: 42));
    expect(native.seeks, isEmpty);
    expect(session.value.position, const Duration(seconds: 42));
    expect(session.value.firstFrameRendered, isFalse);
    native.events.add(
      VideoEvent(key: null, eventType: VideoEventType.firstFrameRendered),
    );
    expect(session.value.firstFrameRendered, isTrue);
    await session.selectSource(second);
    expect(native.sources.last.initialPosition, const Duration(seconds: 42));
    expect(native.seeks, isEmpty);
    expect(session.value.firstFrameRendered, isFalse);
    await session.dispose();
  });

  test('limits native prefetch time for large programme videos', () async {
    final session = await BetterPlayerBackend(userAgent: 'sctv-dl/test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    expect(
      native.bufferingConfigurations.single.maxBufferMs,
      lessThanOrEqualTo(30000),
    );
    await session.dispose();
  });
  test('passes isolated media headers and starts paused', () async {
    final session = await BetterPlayerBackend(userAgent: 'sctv-dl/test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    expect(native.sources.single.headers, {
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
      final session = await BetterPlayerBackend(userAgent: 'test')
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
        throwsA(isA<StateError>()),
      );
      expect(session.value.source, second);
      expect(session.value.position, const Duration(seconds: 12));
      expect(native.createCalls, 1);
      await session.dispose();
    },
  );
  test('play after completion restarts at zero before resuming', () async {
    final session = await BetterPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    await session.seek(const Duration(seconds: 100));
    native.events.add(
      VideoEvent(key: null, eventType: VideoEventType.completed),
    );
    expect(session.value.ended, isTrue);
    await session.play();
    expect(session.value.position, Duration.zero);
    expect(session.value.playing, isTrue);
    await session.dispose();
  });

  test('seeking a completed paused video to zero never autoplays', () async {
    final session = await BetterPlayerBackend(userAgent: 'test')
        .open(const PlaybackInput(title: 'Title', sources: [first]));
    await session.seek(const Duration(seconds: 100));
    await session.seek(Duration.zero);
    expect(session.value.playing, isFalse);
    await session.dispose();
  });
  test(
    'background pause while switching cancels the preserved play intent',
    () async {
      final session = await BetterPlayerBackend(userAgent: 'test')
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
      final session = await BetterPlayerBackend(userAgent: 'test')
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
      final session = await BetterPlayerBackend(userAgent: 'test')
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

  test('rejects unapproved media before native creation', () async {
    await expectLater(
      BetterPlayerBackend(userAgent: 'test').open(
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
  final events = StreamController<VideoEvent>.broadcast(sync: true);
  final sources = <DataSource>[];
  final seeks = <Duration>[];
  final bufferingConfigurations = <BetterPlayerBufferingConfiguration>[];
  String? reject;
  Future<void>? setupDelay;
  Future<void>? disposeDelay;
  bool failPause = false;
  int createCalls = 0;
  int disposeCalls = 0;
  Duration position = Duration.zero;
  @override
  Future<void> init() async {}
  @override
  Future<int?> create({
    BetterPlayerBufferingConfiguration? bufferingConfiguration,
  }) async {
    createCalls++;
    bufferingConfigurations.add(bufferingConfiguration!);
    return 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) => events.stream;
  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {
    sources.add(dataSource);
    final pending = setupDelay;
    setupDelay = null;
    if (pending != null) await pending;
    if (dataSource.uri == reject) throw StateError('Fixture refused source');
    events.add(
      VideoEvent(
        key: null,
        eventType: VideoEventType.initialized,
        duration: const Duration(seconds: 100),
        size: const Size(1280, 720),
      ),
    );
  }

  @override
  Future<void> dispose(int? textureId) async {
    disposeCalls++;
    await disposeDelay;
  }

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {}
  @override
  Future<void> setLooping(int? textureId, bool looping) async {}
  @override
  Future<void> setVolume(int? textureId, double volume) async {}
  @override
  Future<void> play(int? textureId) async {}
  @override
  Future<void> pause(int? textureId) async {
    if (failPause) throw StateError('Pause failed');
  }

  @override
  Future<void> setSpeed(int? textureId, double speed) async {}
  @override
  Future<void> setAspectRatio(int? textureId, String aspectRatio) async {}
  @override
  Future<void> setTrackParameters(
    int? textureId,
    int? width,
    int? height,
    int? bitrate,
  ) async {}
  @override
  Future<void> seekTo(int? textureId, Duration? value) async {
    position = value ?? Duration.zero;
    seeks.add(position);
  }

  @override
  Future<Duration> getPosition(int? textureId) async => position;
  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async => null;
  @override
  Future<bool?> isPictureInPictureEnabled(int? textureId) async => true;
}
