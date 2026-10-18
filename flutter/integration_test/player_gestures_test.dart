import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/platform/playback/better_player_backend.dart';
import 'package:sctv_dl_mobile/platform/playback/native_player_environment.dart';

import '../test/features/player/playback_controller_test.dart'
    show MemoryHistory;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('PLAYBACK_FIXTURE_BASE64');
  const iosSimulator = bool.fromEnvironment('IOS_SIMULATOR');
  testWidgets(
    'native gestures preserve speed, cancel seek, restore brightness and retain decoder',
    (tester) async {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Downloads/player-gestures.mp4');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(encoded));
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      final backend = RecordingBackend();
      final environment = NativePlayerEnvironment();
      final initialBrightness = await environment.brightness();
      await environment.setBrightness(
        initialBrightness < .8
            ? initialBrightness + .15
            : initialBrightness - .15,
      );
      final brightnessProbe = await environment.brightness();
      debugPrint(
        'BRIGHTNESS_PROBE initial=$initialBrightness actual=$brightnessProbe',
      );
      await environment.restoreBrightness();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: const PlaybackInput(
              title: 'Gesture fixture',
              sources: [],
              localLocation: 'documents:Downloads/player-gestures.mp4',
            ),
            backend: backend,
            history: MemoryHistory(),
            environment: environment,
            systemVolume: Platform.isIOS ? const NativeSystemVolume() : null,
            surfaceBuilder: (session) => PlaybackSurface(session: session),
          ),
        ),
      );
      Future<void> waitFor(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      await waitFor(() => backend.session?.value.initialized == true);
      await tester.pumpAndSettle();
      final session = backend.session!;
      Offset blank() => tester.getCenter(find.byType(PlaybackSurface));
      await tester.tapAt(blank());
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(blank());
      await waitFor(
        () =>
            session.value.playing &&
            !session.value.buffering &&
            session.value.position > Duration.zero,
      );
      await tester.pump(const Duration(milliseconds: 600));
      await waitFor(() => !session.value.buffering);
      if (find.byTooltip('暂停').evaluate().isEmpty) {
        await tester.tapAt(blank());
        await tester.pump(const Duration(milliseconds: 350));
      }
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tapAt(blank());
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('暂停'), findsNothing);
      await tester.tapAt(blank());
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('播放速度'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.25×').last);
      await waitFor(() => session.value.speed == 1.25);
      await tester.pump(const Duration(milliseconds: 600));
      final hold = await tester.startGesture(blank());
      await tester.pump(const Duration(milliseconds: 650));
      await waitFor(() => session.value.speed == 2);
      await hold.up();
      await waitFor(() => session.value.speed == 1.25);
      await tester.tap(find.byTooltip('暂停'));
      await waitFor(() => !session.value.playing);
      final position = session.value.position;
      final cancel = await tester.startGesture(blank());
      await cancel.moveBy(const Offset(30, 0));
      await tester.pump();
      await cancel.moveBy(const Offset(60, 0));
      await tester.pump();
      await cancel.cancel();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        (session.value.position - position).abs(),
        lessThan(const Duration(seconds: 1)),
      );
      final seek = await tester.startGesture(blank());
      await seek.moveBy(const Offset(30, 0));
      await tester.pump();
      await seek.moveBy(const Offset(70, 0));
      await tester.pump();
      await seek.up();
      await waitFor(
        () => session.value.position > position + const Duration(seconds: 1),
      );
      expect(session.value.playing, isFalse);
      await tester.tap(find.byTooltip('全屏'));
      await waitFor(
        () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      await tester.pumpAndSettle();
      if (Platform.isIOS) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is UiKitView &&
                widget.viewType == 'dev.sctvdl.flutter/system_volume',
          ),
          findsOneWidget,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await tester.pump();
      final rectangle = tester.getRect(find.byType(PlaybackSurface));
      final brightness = await tester.startGesture(
        Offset(rectangle.left + rectangle.width * .25, rectangle.center.dy),
      );
      final direction = initialBrightness < .8 ? -1.0 : 1.0;
      await brightness.moveBy(Offset(0, direction * 25));
      await tester.pump();
      await brightness.moveBy(Offset(0, direction * 80));
      await tester.pump();
      await brightness.up();
      await tester.pump(const Duration(milliseconds: 350));
      final changedBrightness = await environment.brightness();
      if (Platform.isIOS && iosSimulator) {
        // UIScreen.brightness is a no-op on the owned simulator, confirmed by
        // the direct native probe above. Keep the gesture/HUD assertions real.
        expect(find.textContaining('亮度'), findsOneWidget);
        debugPrint(
          'IOS_SIMULATOR_BRIGHTNESS_UNVERIFIED initial=$initialBrightness probe=$brightnessProbe afterGesture=$changedBrightness',
        );
      } else {
        expect((changedBrightness - initialBrightness).abs(), greaterThan(.02));
      }
      if (environment.supportsVolumeDrag) {
        final originalVolume = await environment.volume();
        addTearDown(() => environment.setVolume(originalVolume));
        final volumeGesture = await tester.startGesture(
          Offset(rectangle.left + rectangle.width * .75, rectangle.center.dy),
        );
        final volumeDirection = originalVolume < .8 ? -1.0 : 1.0;
        await volumeGesture.moveBy(Offset(0, volumeDirection * 25));
        await tester.pump();
        await volumeGesture.moveBy(Offset(0, volumeDirection * 80));
        await tester.pump();
        await volumeGesture.up();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          (await environment.volume() - originalVolume).abs(),
          greaterThan(.02),
        );
      }
      debugPrint('PLAYER_GESTURE_FULLSCREEN_READY');
      await Future<void>.delayed(const Duration(seconds: 4));
      await tester.tap(find.byTooltip('退出全屏'));
      // Exiting unlocks the OS orientation policy. iOS may remain landscape.
      await waitFor(() => find.text('Gesture fixture').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      expect(await environment.brightness(), closeTo(initialBrightness, .02));
      expect(backend.opens, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    skip: encoded.isEmpty,
  );
}

class RecordingBackend implements PlaybackBackend {
  PlaybackSession? session;
  int opens = 0;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    opens++;
    return session = await BetterPlayerBackend(userAgent: 'sctv-dl/integration')
        .open(input);
  }
}
