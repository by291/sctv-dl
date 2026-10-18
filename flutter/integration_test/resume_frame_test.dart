import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/design/archive_transition.dart';
import 'package:sctv_dl_mobile/design/shared_cover.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/features/player/playback_cover.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/platform/playback/better_player_backend.dart';

import '../test/features/player/playback_controller_test.dart'
    show MemoryHistory, selection;

/// The host supplies an H264 fixture: red for 0–10s, green for 10–30s.
/// Sampling the native texture catches an opening-frame flash hidden by
/// metadata-only assertions. Route scrubbing also checks live texture retention.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const encoded = String.fromEnvironment('PLAYBACK_FIXTURE_BASE64');
  testWidgets(
    'resume reveals the target frame and retains it on cancelled return',
    (tester) async {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/Downloads/resume-frame.mp4');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(base64Decode(encoded));
      addTearDown(() => file.delete());
      final backend = _RecordingBackend();
      final boundaryKey = GlobalKey();
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
            navigatorKey: nav,
            theme: ThemeData(platform: TargetPlatform.android),
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 160,
                  height: 90,
                  child: SharedCover(tag: 'playback-1/2/3', url: null),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final source = tester.getRect(find.byType(SharedCover));
      final route = ArchiveTransitionPage<void>(
        child: PlayerPage(
          input: const PlaybackInput(
            title: 'Resume frame fixture',
            sources: [],
            selection: selection,
            localLocation: 'documents:Downloads/resume-frame.mp4',
            initialPosition: Duration(seconds: 12),
          ),
          backend: backend,
          history: MemoryHistory(),
          surfaceBuilder: (session) => PlaybackSurface(session: session),
        ),
      ).createRoute(nav.currentContext!) as PageRoute<void>;
      nav.currentState!.push(route);
      await tester.pump();

      Future<List<int>> sampleVideo() async {
        final rect = tester.getRect(find.byType(PlaybackCover));
        final image =
            await (boundaryKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final x = (rect.left + rect.width * .25).round();
        final y = (rect.top + rect.height * .3).round();
        final index = (y * image.width + x) * 4;
        final rgb = [
          data.getUint8(index),
          data.getUint8(index + 1),
          data.getUint8(index + 2),
        ];
        image.dispose();
        return rgb;
      }

      final poster = find.descendant(
        of: find.byType(PlaybackCover),
        matching: find.byType(SharedCover),
      );
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      var samples = 0;
      do {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 16));
        final rgb = await sampleVideo();
        expect(
          rgb[0] > 160 && rgb[1] < 80,
          isFalse,
          reason: 'The red opening frame must never escape the poster: $rgb',
        );
        samples++;
      } while (DateTime.now().isBefore(deadline) &&
          (poster.evaluate().isEmpty ||
              tester.widget<SharedCover>(poster).opacity > 0));
      expect(samples, greaterThan(1));
      expect(tester.widget<SharedCover>(poster).opacity, 0);
      await tester.pumpAndSettle();
      final rgb = await sampleVideo();
      expect(rgb[0], lessThan(80));
      expect(rgb[1], greaterThan(160));
      final session = backend.session!;
      expect(session.value.position, const Duration(seconds: 12));
      expect(session.value.playing, isFalse);
      final bounds = tester.getRect(find.byType(PlaybackCover));
      final playerState = tester.state(find.byType(PlayerPage));
      route.handleStartBackGesture(progress: 1);
      await tester.pump();
      for (final progress in [.9, .6, .9]) {
        route.handleUpdateBackGestureProgress(progress: progress);
        await tester.pump();
        expect(
          find.byKey(const ValueKey('programme-cover-flight')),
          findsOneWidget,
        );
        expect(session.value.position, const Duration(seconds: 12));
      }
      route.handleCancelBackGesture();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(PlayerPage)), same(playerState));
      expect(tester.getRect(find.byType(PlaybackCover)), bounds);
      expect(backend.opens, 1);
      expect(session.value.playing, isFalse);
      expect((await sampleVideo())[1], greaterThan(160));
      final image =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      image.dispose();
      binding.reportData = {
        'screenshots': [
          {
            'screenshotName': 'android-resume-cancelled',
            'bytes': bytes.toList(),
          },
        ],
      };
      route.handleStartBackGesture(progress: 1);
      await tester.pump();
      route.handleUpdateBackGestureProgress(progress: .5);
      await tester.pump();
      route.handleCommitBackGesture();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsNothing);
      expect(tester.getRect(find.byType(SharedCover)), source);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
    skip: !Platform.isAndroid || encoded.isEmpty,
  );
}

class _RecordingBackend implements PlaybackBackend {
  final delegate = BetterPlayerBackend(userAgent: 'sctv-dl/resume-test');
  PlaybackSession? session;
  int opens = 0;
  @override
  Future<PlaybackSession> open(PlaybackInput input) async {
    opens++;
    return session = await delegate.open(input);
  }
}
