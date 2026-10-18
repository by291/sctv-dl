import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/archive_transition.dart';
import 'package:sctv_dl_mobile/design/shared_cover.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';

import 'playback_controller_test.dart' as fixtures;

void main() {
  testWidgets('fullscreen exit restores the window after a platform failure', (
    tester,
  ) async {
    final orientations = <Object?>[];
    var fail = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(call.arguments);
          if (fail) {
            fail = false;
            throw PlatformException(
              code: 'orientation',
              message: 'Window failed',
            );
          }
        }
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
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
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
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Window failed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();

    expect(orientations.last, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed fullscreen exit retains restoration until page disposal',
    (tester) async {
      final orientations = <Object?>[];
      final modes = <Object?>[];
      var failExit = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            orientations.add(call.arguments);
            if ((call.arguments as List<Object?>).isEmpty && failExit) {
              failExit = false;
              throw PlatformException(
                code: 'orientation',
                message: 'Exit failed',
              );
            }
          }
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(fixtures.FakeSession()),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('退出全屏'));
      await tester.pumpAndSettle();
      final modesAfterExit = modes.toList();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(orientations, [
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
        <Object?>[],
        <Object?>[],
      ]);
      expect(modesAfterExit.last, 'SystemUiMode.edgeToEdge');
      expect(modes.last, 'SystemUiMode.edgeToEdge');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an inline-only player does not reset OS window policies on disposal',
    (tester) async {
      final windowRequests = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations' ||
              call.method == 'SystemChrome.setEnabledSystemUIMode') {
            windowRequests.add(call.method);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(fixtures.FakeSession()),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(windowRequests, isEmpty);
    },
  );

  testWidgets('return cover complements video and reverses without seeking', (
    tester,
  ) async {
    final session = fixtures.FakeSession()
      ..emit(position: const Duration(seconds: 42));
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: ThemeData(platform: TargetPlatform.android),
        home: const Scaffold(
          body: SizedBox(
            width: 160,
            height: 90,
            child: SharedCover(tag: 'playback-1/2/3', url: null),
          ),
        ),
      ),
    );
    final route = ArchiveTransitionPage<void>(
      child: PlayerPage(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
        surfaceBuilder: (_) => const ColoredBox(color: Colors.green),
      ),
    ).createRoute(nav.currentContext!) as PageRoute<void>;
    nav.currentState!.push(route);
    await tester.pumpAndSettle();
    final page = find.byType(PlayerPage);
    final state = tester.state(page);
    final bounds = tester.getRect(page);
    route.handleStartBackGesture(progress: 1);
    await tester.pump();
    for (final progress in [.9, .8, .9]) {
      route.handleUpdateBackGestureProgress(progress: progress);
      await tester.pump();
      final flight = find.byKey(const ValueKey('programme-cover-flight'));
      expect(flight, findsOneWidget);
      final poster = tester
          .widget<Opacity>(
            find.descendant(of: flight, matching: find.byType(Opacity)).first,
          )
          .opacity;
      final video = tester
          .widgetList<Opacity>(
            find.ancestor(of: page, matching: find.byType(Opacity)),
          )
          .fold(1.0, (value, opacity) => value * opacity.opacity);
      expect(poster + video, closeTo(1, .001));
      expect(session.value.position, const Duration(seconds: 42));
    }
    route.handleCancelBackGesture();
    await tester.pumpAndSettle();
    expect(tester.state(page), same(state));
    expect(tester.getRect(page), bounds);
    expect(session.pauseCalls, 0);
    expect(session.disposeCalls, 0);
    expect(session.seekCalls, 0);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(session.disposeCalls, 1);
  });

  testWidgets(
    'an initialized player waits for route entry before revealing video',
    (tester) async {
      final session = fixtures.FakeSession()..emit(initialized: true);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: nav, home: const Scaffold()),
      );
      nav.currentState!.push(
        ArchiveTransitionPage<void>(
          child: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ).createRoute(nav.currentContext!),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget<SharedCover>(find.byType(SharedCover)).opacity, 1);
      await tester.pumpAndSettle();
      expect(tester.widget<SharedCover>(find.byType(SharedCover)).opacity, 0);
      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.widget<SharedCover>(find.byType(SharedCover)).opacity, 0);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('player retains a cover while native initialization is pending', (
    tester,
  ) async {
    final session = fixtures.FakeSession()..emit(initialized: false);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SharedCover), findsOneWidget);
    final bounds = tester.getRect(find.byType(SharedCover));
    session.emit();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(find.byType(SharedCover)), bounds);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<SharedCover>(find.byType(SharedCover)).opacity, 0);
    expect(tester.getRect(find.byType(SharedCover)), bounds);
    session.emit(buffering: true);
    await tester.pump();
    expect(tester.widget<SharedCover>(find.byType(SharedCover)).opacity, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('large text keeps title download and player controls reachable', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var downloads = 0;
    final session = fixtures.FakeSession();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: PlayerPage(
          input: fixtures.input,
          backend: fixtures.FakeBackend(session),
          history: fixtures.MemoryHistory(),
          surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          onDownload: () async {
            downloads++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('视频画质'), findsOneWidget);
    final elapsed = tester.renderObject<RenderParagraph>(find.text('00:00'));
    expect(elapsed.text.style!.color, Colors.white);
    final download = find.widgetWithText(FilledButton, '下载节目');
    await tester.ensureVisible(download);
    await tester.tap(download);
    await tester.pumpAndSettle();
    expect(downloads, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('short landscape keeps controls visible while context scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = fixtures.FakeSession();
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          input: fixtures.input,
          backend: fixtures.FakeBackend(session),
          history: fixtures.MemoryHistory(),
          surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          onDownload: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byTooltip('全屏')).bottom, lessThanOrEqualTo(300));
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byTooltip('全屏')).top, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'cancelled interactive return retains the playing native session',
    (tester) async {
      final session = fixtures.FakeSession();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      navigator.currentState!.push(
        CupertinoPageRoute<void>(
          builder: (_) => PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      session.emit(playing: true);
      final gesture = await tester.startGesture(const Offset(1, 180));
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(-100, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(PlayerPage), findsOneWidget);
      expect(session.disposeCalls, 0);
      expect(session.pauseCalls, 0);
      expect(session.value.playing, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a post-initialization native error exposes retry and replaces the session',
    (tester) async {
      final failed = fixtures.FakeSession();
      final replacement = fixtures.FakeSession();
      Object? displayed;
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.SequenceBackend([failed, replacement]),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (session) {
              displayed = session;
              return const ColoredBox(color: Colors.black);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      failed.emit(error: 'Decoder failed');
      await tester.pumpAndSettle();
      final retry = find.text('重试播放');
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(failed.disposeCalls, 1);
      expect(displayed, same(replacement));
      expect(find.text('重试播放'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('committed pop pauses before transition and disposes after it', (
    tester,
  ) async {
    final session = fixtures.FakeSession();
    final navigator = GlobalKey<NavigatorState>();
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
    session.emit(playing: true);
    navigator.currentState!.pop();
    await tester.pump();
    expect(session.pauseCalls, greaterThan(0));
    expect(session.disposeCalls, 0);
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(session.disposeCalls, 1);
  });
}
