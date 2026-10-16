import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';

import 'playback_controller_test.dart' as fixtures;

void main() {
  testWidgets('large text keeps title download and player controls reachable', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          onDownload: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.byTooltip('播放'), findsOneWidget);
    expect(find.byTooltip('视频画质'), findsOneWidget);
    final elapsed = tester.renderObject<RenderParagraph>(find.text('00:00'));
    expect(elapsed.text.style!.color, Colors.white);
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
