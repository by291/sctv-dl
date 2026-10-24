import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as transfers;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/platform/playback/playback_picture_in_picture.dart';
import 'package:sctv_dl_mobile/platform/playback/video_player_backend.dart';
import 'package:video_player/video_player.dart';

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
    final controller = _trackController(
      VideoPlayerController.networkUrl(
        Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
        formatHint: VideoFormat.other,
        httpHeaders: {
          'Referer': 'https://scgc.video.play/',
          'User-Agent': 'okhttp/4.12.0',
        },
      ),
    );
    final opening = controller.initialize();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: VideoPlayer(controller))),
    );
    await tester.runAsync(() => opening.timeout(const Duration(seconds: 30)));
    expect(controller.value.isInitialized, isTrue);
    expect(controller.value.isPlaying, isFalse);
    await tester.runAsync(() async {
      await controller.seekTo(const Duration(seconds: 1));
      await controller.setPlaybackSpeed(1.5);
      await controller.play();
      // Native rendering can fail after initialization; require sustained play.
      await Future<void>.delayed(const Duration(seconds: 3));
      await controller.pause();
    });
    expect(controller.value.errorDescription, isNull);
    expect(controller.value.playbackSpeed, 1.5);
    expect(headers, isNotEmpty);
    expect(
      headers.every(
        (request) =>
            request['Referer'] == 'https://scgc.video.play/' &&
            request['User-Agent'] == 'okhttp/4.12.0',
      ),
      isTrue,
    );
    expect(controller.value.position, greaterThan(const Duration(seconds: 2)));
    await tester.pumpWidget(const SizedBox());
  }, skip: encoded.isEmpty);

  testWidgets('native playback follows the upstream HTTP redirect policy', (
    tester,
  ) async {
    final before = headers.length;
    final controller = _trackController(
      VideoPlayerController.networkUrl(
        Uri.parse('http://127.0.0.1:${server.port}/redirect.mp4'),
        formatHint: VideoFormat.other,
      ),
    );
    final opening = controller.initialize().timeout(
      const Duration(seconds: 30),
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: VideoPlayer(controller))),
    );
    await tester.runAsync(() async {
      await opening;
    });
    expect(headers.length, greaterThan(before));
    expect(controller.value.isInitialized, isTrue);
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
      final session = await tester.runAsync(
        () => VideoPlayerBackend().open(
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
      () => VideoPlayerBackend().open(
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

  testWidgets('system PiP enters and exits on the same native player', (
    tester,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/Downloads/pip-fixture.mp4');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    final session = (await tester.runAsync(
      () => VideoPlayerBackend().open(
        const PlaybackInput(
          title: 'PiP fixture',
          sources: [],
          localLocation: 'documents:Downloads/pip-fixture.mp4',
        ),
      ),
    ))!;
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => PlaybackPipHost(child: child!),
        home: Scaffold(body: PlaybackSurface(session: session)),
      ),
    );
    await tester.pumpAndSettle();
    if (!session.value.supportsPip) {
      markTestSkipped('Picture in picture is unavailable on this runtime');
      await tester.pumpWidget(const SizedBox());
      return;
    }
    final native = tester
        .widget<VideoPlayer>(find.byType(VideoPlayer))
        .controller;
    await tester.runAsync(() async {
      await session.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      await session.enterPictureInPicture();
    });
    await tester.pump();
    expect(session.value.inPip, isTrue);
    expect(
      tester
          .widgetList<VideoPlayer>(find.byType(VideoPlayer))
          .every((view) => identical(view.controller, native)),
      isTrue,
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
      await PlaybackPictureInPicture.exit();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (session.value.inPip && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    expect(session.value.inPip, isFalse);
    expect(session.value.playing, isTrue);
    await session.pause();
    await tester.pumpWidget(const SizedBox());
  }, skip: encoded.isEmpty);
}

VideoPlayerController _trackController(VideoPlayerController controller) {
  addTearDown(controller.dispose);
  return controller;
}
