import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:background_downloader/background_downloader.dart' as transfers;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/platform/playback/better_player_backend.dart';

/// Supply a small, independently generated H264 MP4 through PLAYBACK_FIXTURE_BASE64.
/// The fixture is neither a full live video download nor a packaged product asset.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('PLAYBACK_FIXTURE_BASE64');
  final headers = <Map<String, String>>[];
  late HttpServer server;
  late List<int> bytes;
  setUpAll(() async {
    if (encoded.isEmpty) return;
    bytes = base64Decode(encoded);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/redirect.mp4') {
        request.response.statusCode = HttpStatus.found;
        request.response.headers.set(HttpHeaders.locationHeader, '/video.mp4');
        await request.response.close();
        return;
      }
      headers.add({
        'Referer': request.headers.value('Referer') ?? '',
        'User-Agent': request.headers.value('User-Agent') ?? '',
        'Range': request.headers.value('Range') ?? '',
      });
      final range = RegExp(r'bytes=(\d+)-(\d*)')
          .firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
      final start = int.parse(range?[1] ?? '0');
      final end =
          int.tryParse(range?[2] ?? '')?.clamp(0, bytes.length - 1) ??
          bytes.length - 1;
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      if (start >= bytes.length) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      } else {
        if (range != null) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${bytes.length}',
          );
        }
        request.response.contentLength = end - start + 1;
        request.response.add(bytes.sublist(start, end + 1));
      }
      await request.response.close();
    });
  });
  tearDownAll(() async {
    if (encoded.isNotEmpty) await server.close(force: true);
  });

  testWidgets('native fixture decodes with media headers seek and speed', (
    tester,
  ) async {
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoDispose: false,
        handleLifecycle: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
    );
    addTearDown(() async {
      final native = controller.videoPlayerController;
      controller.dispose(forceDispose: true);
      await native?.dispose();
    });
    final opening = controller.setupDataSource(
      BetterPlayerDataSource.network(
        'http://127.0.0.1:${server.port}/video.mp4',
        videoFormat: BetterPlayerVideoFormat.other,
        headers: {
          'Referer': 'https://scgc.video.play/',
          'User-Agent': 'sctv-dl/integration',
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BetterPlayer(controller: controller)),
      ),
    );
    await tester.runAsync(() => opening.timeout(const Duration(seconds: 30)));
    expect(controller.videoPlayerController!.value.initialized, isTrue);
    expect(controller.videoPlayerController!.value.isPlaying, isFalse);
    await tester.runAsync(() async {
      await controller.seekTo(const Duration(seconds: 1));
      await controller.setSpeed(1.5);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await controller.pause();
    });
    expect(controller.videoPlayerController!.value.speed, 1.5);
    expect(headers, isNotEmpty);
    expect(
      headers.every(
        (request) =>
            request['Referer'] == 'https://scgc.video.play/' &&
            request['User-Agent'] == 'sctv-dl/integration',
      ),
      isTrue,
    );
    expect(
      controller.videoPlayerController!.value.position,
      greaterThanOrEqualTo(const Duration(seconds: 1)),
    );
    // Media3 can buffer this 25 KiB fixture before seeking, so it need not issue
    // a second HTTP request. The iOS resource loader always makes bounded ranges.
    if (Platform.isIOS) {
      expect(
        headers.any((request) => request['Range']!.startsWith('bytes=')),
        isTrue,
      );
    }
    controller.dispose(forceDispose: true);
    await tester.pumpWidget(const SizedBox());
  }, skip: encoded.isEmpty);

  testWidgets('native playback rejects HTTP redirects', (tester) async {
    final before = headers.length;
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoDispose: false,
        handleLifecycle: false,
      ),
    );
    final opening = expectLater(
      controller
          .setupDataSource(
            BetterPlayerDataSource.network(
              'http://127.0.0.1:${server.port}/redirect.mp4',
              videoFormat: BetterPlayerVideoFormat.other,
            ),
          )
          .timeout(const Duration(seconds: 30)),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'VideoError',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BetterPlayer(controller: controller)),
      ),
    );
    await tester.runAsync(() async {
      await opening;
    });
    expect(
      headers.length,
      before,
      reason: 'The redirect destination must never be contacted',
    );
    controller.dispose(forceDispose: true);
    await tester.pumpWidget(const SizedBox());
  }, skip: encoded.isEmpty);

  testWidgets(
    'local backend resolves a current sandbox path and remains paused',
    (tester) async {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Downloads/playback-fixture.mp4');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final session = await tester.runAsync(
        () => BetterPlayerBackend(userAgent: 'test').open(
          const PlaybackInput(
            title: 'Fixture',
            sources: [],
            localLocation: 'documents:Downloads/playback-fixture.mp4',
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AspectRatio(
              aspectRatio: 16 / 9,
              child: PlaybackSurface(session: session!),
            ),
          ),
        ),
      );
      expect(session.value.initialized, isTrue);
      expect(session.value.playing, isFalse);
      await tester.runAsync(session.dispose);
      await tester.pumpWidget(const SizedBox());
      await file.delete();
    },
    skip: encoded.isEmpty,
  );
  testWidgets('Android published content URI plays without a filesystem path', (
    tester,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/playback-content-${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    await file.writeAsBytes(bytes);
    final uri = await transfers.FileDownloader().uri.moveFileToSharedStorage(
      file.uri,
      transfers.SharedStorage.downloads,
      directory: 'sctv-dl',
      mimeType: 'video/mp4',
    );
    expect(uri?.scheme, 'content');
    addTearDown(() async {
      if (uri != null) {
        await const MethodChannel('dev.sctvdl.flutter/files')
            .invokeMethod<bool>('delete', {'location': uri.toString()});
      }
      if (await file.exists()) await file.delete();
    });
    final session = await tester.runAsync(
      () => BetterPlayerBackend(userAgent: 'test').open(
        PlaybackInput(
          title: 'Public fixture',
          sources: const [],
          localLocation: uri.toString(),
        ),
      ),
    );
    addTearDown(() => session?.dispose());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AspectRatio(
            aspectRatio: 16 / 9,
            child: PlaybackSurface(session: session!),
          ),
        ),
      ),
    );
    expect(session.value.initialized, isTrue);
    expect(session.value.playing, isFalse);
    await tester.runAsync(() async {
      await session.play();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await session.pause();
    });
    expect(session.value.position, greaterThan(Duration.zero));
    await tester.runAsync(session.dispose);
    await tester.pumpWidget(const SizedBox());
  }, skip: encoded.isEmpty || !Platform.isAndroid);

  testWidgets('explicit iOS PiP enters and exits on the same native player', (
    tester,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/Downloads/pip-fixture.mp4');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final controller = BetterPlayerController(
      const BetterPlayerConfiguration(
        autoDispose: false,
        handleLifecycle: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControls: false,
        ),
      ),
    );
    addTearDown(() async {
      final native = controller.videoPlayerController;
      controller.dispose(forceDispose: true);
      await native?.dispose();
    });
    final opening = controller.setupDataSource(
      BetterPlayerDataSource.file(file.path),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BetterPlayer(controller: controller)),
      ),
    );
    await tester.runAsync(() => opening);
    if (!await controller.isPictureInPictureSupported()) {
      controller.dispose(forceDispose: true);
      await file.delete();
      markTestSkipped('Picture in picture is unavailable on this simulator');
      return;
    }
    final native = controller.videoPlayerController!;
    final identity = native.textureId;
    Future<void> waitForPip(bool expected) {
      final ready = Completer<void>();
      void changed() {
        if (native.value.isPip == expected && !ready.isCompleted) {
          ready.complete();
        }
      }

      native.addListener(changed);
      changed();
      return ready.future
          .timeout(const Duration(seconds: 8))
          .whenComplete(() => native.removeListener(changed));
    }

    await tester.runAsync(() async {
      await controller.setLooping(true);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final entered = waitForPip(true);
      await native.enablePictureInPicture(
        left: 0,
        top: 0,
        width: 320,
        height: 180,
      );
      await entered;
      expect(native.textureId, identity);
      final exited = waitForPip(false);
      await native.disablePictureInPicture();
      await exited;
      await controller.pause();
    });
    expect(controller.videoPlayerController, same(native));
    controller.dispose(forceDispose: true);
    await native.dispose();
    await tester.pumpWidget(const SizedBox());
    await file.delete();
  }, skip: encoded.isEmpty || !Platform.isIOS);
}
