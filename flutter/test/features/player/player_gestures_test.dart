import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sctv_dl_mobile/features/player/player_controls.dart';
import 'package:sctv_dl_mobile/features/player/player_gestures.dart';
import 'package:sctv_dl_mobile/features/player/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';

import 'playback_controller_test.dart' as fixtures;
import 'player_gesture_controller_test.dart' as gesture_fixtures;
import 'player_environment_controller_test.dart' as environment_fixtures;

void main() {
  testWidgets('pending speed restoration cannot release a newer gesture hold', (
    tester,
  ) async {
    final session = gesture_fixtures.RestoreBlockedSession();
    final player = PlaybackController(
      input: fixtures.input,
      backend: fixtures.FakeBackend(session),
      history: fixtures.MemoryHistory(),
    );
    await player.initialize();
    await player.setSpeed(1.25);
    session.emit(playing: true, speed: 1.25);
    await player.beginTemporarySpeed();
    session.blockRestore = true;
    final restoring = player.endTemporarySpeed();
    await tester.pump();
    player.holdControls(true, reason: PlayerControlHold.gesture);
    session.restoreGate.complete();
    await restoring;
    await tester.pump(const Duration(seconds: 4));
    expect(player.controlsVisible, isTrue);
    player.holdControls(false, reason: PlayerControlHold.gesture);
    await tester.pump(const Duration(seconds: 4));
    expect(player.controlsVisible, isFalse);
    await tester.runAsync(player.release);
    player.dispose();
  });

  testWidgets(
    'pending seek completion does not release a newer seek preview hold',
    (tester) async {
      final session = DelayedSeekSession();
      final player = PlaybackController(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
      );
      await player.initialize();
      session.emit(playing: true);
      player.previewSeek(.1);
      final first = player.finishSeek(commit: true);
      player.previewSeek(.2);
      session.write.complete();
      await first;
      await tester.pump(const Duration(seconds: 4));
      expect(player.controlsVisible, isTrue);
      expect(player.seekPreview, const Duration(seconds: 20));
      await player.finishSeek(commit: false);
      await tester.pump(const Duration(seconds: 4));
      expect(player.controlsVisible, isFalse);
      await tester.runAsync(player.release);
      player.dispose();
    },
  );

  testWidgets(
    'second pointer on a transport button cancels seek and speed boost',
    (tester) async {
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byKey(const ValueKey('video')));
      final gesture = await tester.startGesture(point, pointer: 1);
      await gesture.moveBy(const Offset(40, 0));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump();
      final second = await tester.startGesture(
        tester.getCenter(find.byTooltip('全屏')),
        pointer: 2,
      );
      await tester.pump();
      await gesture.up();
      await second.cancel();
      await tester.pumpAndSettle();
      expect(session.seekCalls, 0);
      session.emit(playing: true);
      await tester.pump();
      final hold = await tester.startGesture(point, pointer: 3);
      await tester.pump(const Duration(milliseconds: 650));
      expect(session.value.speed, 2);
      final control = await tester.startGesture(
        tester.getCenter(find.byTooltip('全屏')),
        pointer: 4,
      );
      await tester.pump();
      expect(session.value.speed, 1);
      await hold.up();
      await control.up();
      await tester.pumpAndSettle();
      expect(find.byTooltip('退出全屏'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a released volume write cannot own or finish the next brightness drag',
    (tester) async {
      final environment = DelayedVolumeEnvironment()..read.complete(.4);
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            environment: environment,
            surfaceBuilder: (_) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      session.emit(playing: true);
      await tester.pump();
      final surface = tester.getRect(find.byKey(const ValueKey('video')));
      final volume = await tester.startGesture(
        Offset(surface.width * .75, surface.center.dy),
      );
      await volume.moveBy(const Offset(0, -30));
      await volume.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(environment.started, isTrue);
      await volume.up();
      await tester.pump();
      final brightness = await tester.startGesture(
        Offset(surface.width * .25, surface.center.dy),
      );
      await brightness.moveBy(const Offset(0, -30));
      await brightness.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(environment.current, greaterThan(.4));
      environment.write.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(PlayerControls), findsOneWidget);
      await brightness.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(find.textContaining('亮度'), findsOneWidget);
      await brightness.up();
      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(PlayerControls), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'native system volume remains mounted while pointer or focus owns it',
    (tester) async {
      final session = fixtures.FakeSession();
      final volumeFocus = FocusNode();
      addTearDown(volumeFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            systemVolume: Focus(
              focusNode: volumeFocus,
              child: const SizedBox(
                key: ValueKey('native-volume'),
                width: 180,
                height: 48,
              ),
            ),
            surfaceBuilder: (_) => const ColoredBox(color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      session.emit(playing: true);
      await tester.pump();
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('native-volume'))),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('native-volume')), findsOneWidget);
      await pointer.cancel();
      await tester.pump();
      volumeFocus.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('native-volume')), findsOneWidget);
      volumeFocus.unfocus();
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const ValueKey('native-volume')), findsNothing);
      final player = tester
          .widget<PlayerGestures>(find.byType(PlayerGestures))
          .controller;
      player.showControls();
      await tester.pump();
      final active = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('native-volume'))),
      );
      tester.widget<PlayerControls>(find.byType(PlayerControls)).onFullscreen();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await active.cancel();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'initial fullscreen gesture mount acquires brightness and restores it after drag disposal',
    (tester) async {
      final session = fixtures.FakeSession();
      final player = PlaybackController(
        input: fixtures.input,
        backend: fixtures.FakeBackend(session),
        history: fixtures.MemoryHistory(),
      );
      await player.initialize();
      final environment = environment_fixtures.Environment()..read.complete(.4);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox.expand(
            child: PlayerGestures(
              controller: player,
              fullscreen: true,
              environment: environment,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.getRect(find.byType(PlayerGestures));
      final gesture = await tester.startGesture(
        Offset(surface.left + surface.width * .25, surface.center.dy),
      );
      await gesture.moveBy(const Offset(0, -25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(environment.current, greaterThan(.4));
      expect(find.textContaining('亮度'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(environment.current, .4);
      await tester.runAsync(player.release);
      player.dispose();
    },
  );
  testWidgets(
    'touch focus does not hold controls but keyboard mode does without refocusing',
    (tester) async {
      final focusManager = FocusManager.instance;
      final previousStrategy = focusManager.highlightStrategy;
      focusManager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      addTearDown(() => focusManager.highlightStrategy = previousStrategy);
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) => const ColoredBox(
              key: ValueKey('focus-video'),
              color: Colors.black,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final focus = Focus.of(
        tester.element(find.byKey(const ValueKey('focus-video'))),
      );
      session.emit(playing: true);
      await tester.pump();
      final player = tester
          .widget<PlayerControls>(find.byType(PlayerControls))
          .controller;
      player.toggleControls();
      focus.requestFocus();
      await tester.pump();
      expect(player.controlsVisible, isFalse);
      focusManager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(player.controlsVisible, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'inline vertical surface drag remains available to enclosing scroll',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: [
              SizedBox(
                height: 500,
                child: PlayerPage(
                  input: fixtures.input,
                  backend: fixtures.FakeBackend(session),
                  history: fixtures.MemoryHistory(),
                  surfaceBuilder: (_) => const ColoredBox(
                    key: ValueKey('video'),
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 1200),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragFrom(
        tester.getCenter(find.byKey(const ValueKey('video'))),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(20));
      expect(session.seekCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'slow volume drag accumulates quantized steps and respects physical changes',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final environment = QuantizedEnvironment()..read.complete(.4);
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(fixtures.FakeSession()),
            history: fixtures.MemoryHistory(),
            environment: environment,
            surfaceBuilder: (_) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('全屏'));
      await tester.pumpAndSettle();
      final surface = tester.getRect(find.byKey(const ValueKey('video')));
      final gesture = await tester.startGesture(
        Offset(surface.left + surface.width * .75, surface.center.dy),
      );
      await gesture.moveBy(const Offset(0, -25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -25));
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await gesture.moveBy(const Offset(0, -3));
        await tester.pump();
      }
      expect(environment.level, greaterThan(.5));
      environment.level = .8;
      for (var i = 0; i < 15; i++) {
        await gesture.moveBy(const Offset(0, -3));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(environment.level, greaterThan(.8));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'blank double tap toggles playback and horizontal cancel never seeks',
    (tester) async {
      final session = fixtures.FakeSession();
      await tester.pumpWidget(
        MaterialApp(
          home: PlayerPage(
            input: fixtures.input,
            backend: fixtures.FakeBackend(session),
            history: fixtures.MemoryHistory(),
            surfaceBuilder: (_) =>
                const ColoredBox(key: ValueKey('video'), color: Colors.black),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final point = tester.getCenter(find.byKey(const ValueKey('video')));
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(session.value.playing, isTrue);
      final hold = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 650));
      expect(session.value.speed, 2);
      tester.binding.handleMetricsChanged();
      await tester.pump();
      expect(
        session.value.speed,
        2,
        reason: "Unchanged metrics must not cancel a gesture",
      );
      await hold.up();
      await tester.pumpAndSettle();
      expect(session.value.speed, 1);
      final gesture = await tester.startGesture(point);
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(session.seekCalls, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}

class QuantizedEnvironment extends environment_fixtures.Environment {
  double level = .5;
  @override
  Future<double> volume() async => level;
  @override
  Future<void> setVolume(double value) async {
    level = (value * 15).round() / 15;
  }
}

class DelayedVolumeEnvironment extends QuantizedEnvironment {
  final write = Completer<void>();
  bool started = false;
  @override
  Future<void> setVolume(double value) async {
    started = true;
    await write.future;
    await super.setVolume(value);
  }
}

class DelayedSeekSession extends fixtures.FakeSession {
  final write = Completer<void>();
  @override
  Future<void> seek(Duration position) async {
    await write.future;
    seekCalls++;
    emit(playing: true, position: position);
  }
}
