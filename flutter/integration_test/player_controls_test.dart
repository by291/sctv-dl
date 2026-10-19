import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/platform/playback/playback_picture_in_picture.dart';
import 'package:sctv_dl_mobile/platform/playback/video_player_backend.dart';
import 'package:video_player/video_player.dart';

import '../test/features/player/playback_controller_test.dart'
    show MemoryHistory;

/// Uses a generated local MP4. The host restores this disposable Activity from
/// PiP after the PLAYER_PARITY_PIP_READY marker; no user device is involved.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('PLAYBACK_FIXTURE_BASE64');
  const verifyPip =
      bool.fromEnvironment('VERIFY_PIP') ||
      bool.fromEnvironment('VERIFY_ANDROID_PIP');

  testWidgets(
    'native player controls retain the decoder across fullscreen and PiP',
    (tester) async {
      if (Platform.isIOS) {
        addTearDown(() => SystemChrome.setPreferredOrientations([]));
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Downloads/player-controls.mp4');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(encoded));
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final backend = _RecordingBackend();
      final captureKey = GlobalKey();
      final brightness = ValueNotifier(Brightness.light);
      addTearDown(brightness.dispose);
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: ValueListenableBuilder(
            valueListenable: brightness,
            builder: (context, value, child) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildAppTheme(value),
              builder: (context, child) => PlaybackPipHost(child: child!),
              home: child,
            ),
            child: PlayerPage(
              input: const PlaybackInput(
                title: 'Player interaction fixture',
                sources: [],
                localLocation: 'documents:Downloads/player-controls.mp4',
              ),
              backend: backend,
              history: MemoryHistory(),
              surfaceBuilder: (session) => PlaybackSurface(session: session),
            ),
          ),
        ),
      );

      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        final surface =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await surface.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final bytes = data!.buffer.asUint8List();
        binding.reportData ??= <String, Object?>{};
        final screenshots = binding.reportData!.putIfAbsent(
          'screenshots',
          () => <Object?>[],
        ) as List<Object?>;
        screenshots.add({
          'screenshotName': 'android-player-parity-$name',
          'bytes': bytes.toList(),
        });
      }

      await waitFor(() => backend.session?.value.initialized == true);
      await tester.pumpAndSettle();
      final session = backend.session!;
      final native = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer).first)
          .controller;
      final texture = native.playerId;
      final before = tester.getRect(find.byType(PlaybackSurface));
      expect(session.value.playing, isFalse);
      await capture('paused');
      await tester.tap(find.byTooltip('播放'));
      await waitFor(() => session.value.position > Duration.zero);
      await tester.tapAt(tester.getCenter(find.byType(PlaybackSurface)));
      // Single taps settle after the double-tap recognizer's deadline.
      await waitFor(() => find.byTooltip('暂停').evaluate().isEmpty);
      expect(find.byTooltip('暂停'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(PlaybackSurface)));
      await waitFor(() => find.byTooltip('暂停').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pump(const Duration(milliseconds: 400));
      await capture('speed-menu');
      await tester.tap(find.text('1.25×').last);
      await tester.pump(const Duration(milliseconds: 400));
      expect(session.value.speed, 1.25);
      await tester.tap(find.byTooltip('暂停'));
      await tester.pump(const Duration(milliseconds: 400));
      final slider = tester.getRect(find.byType(Slider));
      await tester.tapAt(
        Offset(slider.left + slider.width * .6, slider.center.dy),
      );
      await waitFor(() => session.value.position > const Duration(seconds: 10));
      expect(session.value.playing, isFalse);
      final position = session.value.position;
      await tester.tap(find.byTooltip('全屏'));
      await waitFor(
        () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      await tester.pumpAndSettle();
      expect(find.text('Player interaction fixture'), findsNothing);
      expect(
        tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller,
        same(native),
      );
      expect(
        tester
            .widget<VideoPlayer>(find.byType(VideoPlayer).first)
            .controller
            .playerId,
        texture,
      );
      expect(backend.opens, 1);
      await capture('fullscreen');
      if (Platform.isIOS) {
        // iOS has no system Back action; use the application's exit control.
        await tester.tap(find.byTooltip('退出全屏'));
        await waitFor(
          () => find.text('Player interaction fixture').evaluate().isNotEmpty,
        );

        // Restoring the OS policy need not rotate an iOS simulator immediately.
        // Fix the fixture orientation before comparing the restored geometry.
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      } else {
        await tester.binding.handlePopRoute();
      }
      await waitFor(
        () => tester.view.physicalSize.width < tester.view.physicalSize.height,
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PlaybackSurface)), before);
      expect(session.value.position, position);
      expect(session.value.playing, isFalse);
      brightness.value = Brightness.dark;
      await tester.pumpAndSettle();
      await capture('dark');

      if (verifyPip && session.value.supportsPip) {
        await tester.tap(find.byTooltip('播放'));
        await waitFor(() => session.value.playing);
        await tester.tap(find.byTooltip('画中画'));
        await waitFor(() => session.value.inPip);
        await tester.pump();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller,
          same(native),
        );
        expect(
          tester
              .widget<VideoPlayer>(find.byType(VideoPlayer).first)
              .controller
              .playerId,
          texture,
        );
        debugPrint('PLAYER_PARITY_PIP_READY');
        if (Platform.isIOS) {
          await Future<void>.delayed(const Duration(seconds: 2));
          await PlaybackPictureInPicture.exit();
        }
        await waitFor(() => !session.value.inPip);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer).first).controller,
          same(native),
        );
        expect(
          tester
              .widget<VideoPlayer>(find.byType(VideoPlayer).first)
              .controller
              .playerId,
          texture,
        );
        expect(backend.opens, 1);
        await session.pause();
        await capture('pip-restored');
      }
      await session.pause();
      await session.seek(session.value.duration!);
      await waitFor(() => session.value.ended);
      await tester.pump();
      await tester.tap(find.byTooltip('播放'));
      await waitFor(
        () =>
            session.value.playing &&
            session.value.position > Duration.zero &&
            session.value.position < const Duration(seconds: 5),
      );
      await session.pause();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: encoded.isEmpty,
  );
}

class _RecordingBackend implements PlaybackBackend {
  PlaybackSession? session;
  int opens = 0;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    opens++;
    return session = await VideoPlayerBackend(userAgent: 'sctv-dl/integration')
        .open(input);
  }
}
