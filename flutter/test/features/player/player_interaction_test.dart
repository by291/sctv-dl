import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';

import 'playback_controller_test.dart' as fixtures;

void main() {
  final captureKey = GlobalKey();
  Future<void> mount(
    WidgetTester tester,
    fixtures.FakeSession session, {
    PlaybackInput input = fixtures.input,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            RepaintBoundary(key: captureKey, child: child),
        home: PlayerPage(
          input: input,
          backend: fixtures.FakeBackend(session),
          history: fixtures.MemoryHistory(),
          surfaceBuilder: (_) =>
              const ColoredBox(key: ValueKey('video'), color: Colors.black),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('loading metadata keeps player action bounds fixed', (
    tester,
  ) async {
    final ready = Completer<PlaybackSession>();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          input: fixtures.input,
          backend: fixtures.DelayedBackend(ready.future),
          history: fixtures.MemoryHistory(),
          surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
        ),
      ),
    );
    await tester.pump();
    final labels = ['播放', '播放速度', '视频画质', '全屏'];
    final before = {
      for (final label in labels) label: tester.getRect(find.byTooltip(label)),
    };
    final track = tester.getRect(find.byType(Slider));

    ready.complete(fixtures.FakeSession());
    await tester.pumpAndSettle();

    for (final label in labels) {
      expect(
        tester.getRect(find.byTooltip(label)),
        before[label],
        reason: '$label must not move when metadata arrives',
      );
    }
    expect(tester.getRect(find.byType(Slider)), track);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'every player button paints its pressed feedback above the video',
    (tester) async {
      await mount(
        tester,
        fixtures.FakeSession(),
        input: const PlaybackInput(
          title: 'Title',
          sources: [fixtures.standard],
        ),
      );
      Future<int> brightnessAt(Offset point) async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final local = boundary.globalToLocal(point);
        return (await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final offset =
              (local.dy.floor() * image.width + local.dx.floor()) * 4;
          final brightness =
              data!.getUint8(offset) +
              data.getUint8(offset + 1) +
              data.getUint8(offset + 2);
          image.dispose();
          return brightness;
        }))!;
      }

      for (final label in ['播放', '播放速度', '视频画质', '全屏', '画中画']) {
        final rect = tester.getRect(find.byTooltip(label));
        final sample = Offset(rect.center.dx, rect.top + 8);
        final before = await brightnessAt(sample);
        final press = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 120));
        final after = await brightnessAt(sample);
        expect(
          after,
          greaterThan(before),
          reason: '$label must paint visible press feedback over the video',
        );
        await press.cancel();
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'time labels match option typography and leave room around the track',
    (tester) async {
      await mount(tester, fixtures.FakeSession());
      final elapsed = tester.renderObject<RenderParagraph>(find.text('00:00'));
      final speed = tester.renderObject<RenderParagraph>(find.text('1×'));
      final quality = tester.renderObject<RenderParagraph>(find.text('标准'));
      expect(elapsed.text.style!.fontSize, speed.text.style!.fontSize);
      expect(elapsed.text.style!.fontSize, quality.text.style!.fontSize);
      final track = tester.getRect(find.byType(Slider));
      expect(
        track.left - tester.getRect(find.text('00:00')).right,
        greaterThanOrEqualTo(8),
      );
      expect(
        tester.getRect(find.text('01:40')).left - track.right,
        greaterThanOrEqualTo(8),
      );
    },
  );

  testWidgets(
    'long durations reserve both time slots before playback reaches an hour',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = fixtures.FakeSession();
      await mount(tester, session);
      final shortTrack = tester.getRect(find.byType(Slider));
      session.emit(
        duration: const Duration(hours: 12, minutes: 34, seconds: 56),
      );
      await tester.pumpAndSettle();
      expect(find.text('12:34:56'), findsOneWidget);
      final longTrack = tester.getRect(find.byType(Slider));
      expect(longTrack.width, lessThan(shortTrack.width));
      for (final position in [
        const Duration(minutes: 59, seconds: 59),
        const Duration(hours: 1),
        const Duration(hours: 11, minutes: 11, seconds: 11),
      ]) {
        session.emit(
          position: position,
          duration: const Duration(hours: 12, minutes: 34, seconds: 56),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(Slider)), longTrack);
      }
      expect(find.text('11:11:11'), findsOneWidget);
      expect(
        tester.getRect(find.text('12:34:56')).right,
        lessThan(tester.getRect(find.byTooltip('播放速度')).left),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets('transport and progress share one compact row at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = fixtures.FakeSession();
      await mount(tester, session);
      final slider = tester.getRect(find.byType(Slider));
      final play = tester.getRect(find.byTooltip('播放'));
      final speed = tester.getRect(find.byTooltip('播放速度'));
      final quality = tester.getRect(find.byTooltip('视频画质'));
      final fullscreen = tester.getRect(find.byTooltip('全屏'));
      expect(slider.center.dy, play.center.dy);
      expect(slider.center.dy, speed.center.dy);
      expect(slider.center.dy, quality.center.dy);
      expect(slider.center.dy, fullscreen.center.dy);
      expect(slider.width, greaterThanOrEqualTo(64));
      expect(quality.left, speed.right);
      await tester.tapAt(slider.center);
      await tester.pumpAndSettle();
      expect(session.value.position, greaterThan(Duration.zero));
      expect(session.value.playing, isFalse);
      await tester.ensureVisible(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byTooltip('全屏')).right,
        lessThanOrEqualTo(width),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'surface taps toggle controls only during uninterrupted playback',
    (tester) async {
      final session = fixtures.FakeSession();
      await mount(tester, session);
      final surface = find.byKey(const ValueKey('video'));
      await tester.tapAt(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('播放'), findsOneWidget);
      session.emit(playing: true);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tapAt(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('暂停'), findsNothing);
      await tester.tapAt(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 3501));
      expect(find.byTooltip('暂停'), findsNothing);
      session.emit(buffering: true, playing: true);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('暂停'), findsOneWidget);
    },
  );

  testWidgets(
    'fullscreen requests landscape and back restores window without replacing video',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final session = fixtures.FakeSession();
      await mount(tester, session);
      final surface = tester.element(find.byKey(const ValueKey('video')));
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      );
      expect(find.text('Title'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Title'), findsOneWidget);
      expect(
        tester.element(find.byKey(const ValueKey('video'))),
        same(surface),
      );
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        isEmpty,
      );
      expect(session.disposeCalls, 0);
      expect(session.pauseCalls, 0);
    },
  );

  testWidgets('PiP shows only the same video even while buffering', (
    tester,
  ) async {
    final session = fixtures.FakeSession();
    await mount(tester, session);
    final surface = tester.element(find.byKey(const ValueKey('video')));
    session.emit(playing: true, inPip: true, buffering: true);
    await tester.pump();
    expect(find.text('Title'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.element(find.byKey(const ValueKey('video'))), same(surface));
    session.emit();
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(session.disposeCalls, 0);
  });

  testWidgets(
    'menus stay above controls and keep controls visible until dismissed',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = fixtures.FakeSession();
      await mount(tester, session);
      session.emit(playing: true);
      await tester.pump();
      final speed = find.byTooltip('播放速度');
      final before = tester.getRect(speed);
      await tester.tap(speed);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byTooltip('暂停'), findsOneWidget);
      final menu = find.byType(PopupMenuItem<double>);
      expect(menu, findsNWidgets(5));
      expect(
        tester
            .getRect(
              find
                  .ancestor(
                    of: menu.first,
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
            )
            .top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const ValueKey('video'))).top,
        ),
      );
      expect(
        tester.getRect(menu.hitTestable().last).bottom,
        lessThan(before.top),
      );
      await tester.tap(find.text('1.25×').last);
      await tester.pumpAndSettle();
      expect(session.value.speed, 1.25);
      expect(tester.getRect(speed), before);
      await tester.pump(const Duration(milliseconds: 3501));
      expect(find.byTooltip('暂停'), findsNothing);
    },
  );

  testWidgets(
    'PiP removes the fullscreen back interception without disposing its session',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      session.emit(playing: true, inPip: true);
      await tester.pumpAndSettle();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(PlayerPage), findsNothing);
      expect(session.pauseCalls, 0);
      expect(session.disposeCalls, 0);
      session.emit();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(session.disposeCalls, 1);
    },
  );

  testWidgets('fullscreen return preserves scrolled programme details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      fixtures.FakeSession(),
      input: PlaybackInput(
        title: List.filled(60, 'Long programme title').join(' '),
        sources: const [fixtures.standard],
      ),
    );
    final details = find
        .ancestor(
          of: find.byType(SelectableText),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(details, const Offset(0, -160));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byType(SelectableText));
    await tester.ensureVisible(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(SelectableText)), before);
  });

  testWidgets(
    'single quality opens its current option without restarting playback',
    (tester) async {
      await mount(
        tester,
        fixtures.FakeSession(),
        input: const PlaybackInput(
          title: 'Title',
          sources: [fixtures.standard],
        ),
      );
      expect(find.text('标准'), findsOneWidget);
      await tester.tap(find.text('标准'));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        findsOneWidget,
      );
      expect(find.text('标准'), findsNWidgets(2));
      await tester.tap(find.text('标准').last);
      await tester.pumpAndSettle();
      expect(find.text('标准'), findsOneWidget);
      expect(find.byTooltip('播放'), findsOneWidget);
    },
  );

  testWidgets('fullscreen errors expose retry over the video', (tester) async {
    final session = fixtures.FakeSession();
    await mount(tester, session);
    await tester.tap(find.byTooltip('全屏'));
    await tester.pumpAndSettle();
    session.emit(error: 'Decoder failed');
    await tester.pumpAndSettle();
    expect(find.text('重试播放').hitTestable(), findsOneWidget);
  });
}
