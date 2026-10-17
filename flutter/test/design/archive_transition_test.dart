import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/archive_transition.dart';

void main() {
  testWidgets('both pages fade through the Android phase boundary', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    const detailKey = ValueKey('detail');
    const homeKey = ValueKey('home');
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(key: homeKey),
      ),
    );
    final home = find.byKey(homeKey, skipOffstage: false);
    final homeBounds = tester.getRect(home);
    final route = const ArchiveTransitionPage<void>(
      child: Scaffold(key: detailKey),
    ).createRoute(navigator.currentContext!) as PageRoute<void>;
    navigator.currentState!.push(route);
    await tester.pump();
    final detail = find.byKey(detailKey);
    double opacity(Finder page) => tester
        .widget<Opacity>(
          find.ancestor(of: page, matching: find.byType(Opacity)).last,
        )
        .opacity;
    double incoming(double p) =>
        const Cubic(0, 0, .2, 1).transform(((p - .35) / .65).clamp(0.0, 1.0));
    double outgoing(double p) =>
        1 - const Cubic(.4, 0, 1, 1).transform((p / .35).clamp(0.0, 1.0));

    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(detail), 0);
    expect(opacity(home), closeTo(outgoing(.25), .001));
    await tester.pump(const Duration(milliseconds: 30));
    expect(opacity(detail), closeTo(0, .001));
    expect(opacity(home), closeTo(0, .001));
    await tester.pump(const Duration(milliseconds: 45));
    expect(opacity(detail), closeTo(incoming(.5), .001));
    expect(opacity(home), 0);
    await tester.pumpAndSettle();
    final detailBounds = tester.getRect(detail);

    Future<void> gesture(String method, [double? progress]) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(
            method,
            progress == null
                ? null
                : <String, Object>{
                    'touchOffset': <double>[5 + 180 * progress, 350],
                    'progress': progress,
                    'swipeEdge': 0,
                  },
          ),
        ),
        (_) {},
      );
      await tester.pump();
    }

    await gesture('startBackGesture', 0);
    for (final p in [.1, .2, .35, .5, .8, .5, .2, .75]) {
      await gesture('updateBackGestureProgress', p);
      expect(opacity(detail), closeTo(outgoing(p), .001));
      expect(opacity(home), closeTo(incoming(p), .001));
      expect(tester.getRect(detail).left, closeTo(30 * p, .001));
      expect(tester.getRect(home).left, closeTo(-30 * (1 - p), .001));
      expect(tester.getSize(detail), detailBounds.size);
      expect(tester.getSize(home), homeBounds.size);
    }
    final cancelOpacity = opacity(home);
    final cancelBounds = tester.getRect(home);
    await gesture('cancelBackGesture');
    expect(opacity(home), cancelOpacity);
    expect(tester.getRect(home), cancelBounds);
    await tester.pumpAndSettle();
    expect(tester.getRect(detail), detailBounds);
    expect(opacity(detail), 1);

    await gesture('startBackGesture', 0);
    await gesture('updateBackGestureProgress', .2);
    final releaseOpacity = opacity(detail);
    final releaseBounds = tester.getRect(detail);
    await gesture('commitBackGesture');
    expect(opacity(detail), releaseOpacity);
    expect(tester.getRect(detail), releaseBounds);
    await tester.pumpAndSettle();
    expect(tester.getRect(home), homeBounds);

    navigator.currentState!.push(
      const ArchiveTransitionPage<void>(child: Scaffold(key: detailKey))
          .createRoute(navigator.currentContext!),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(detail), closeTo(outgoing(.25), .001));
    expect(opacity(home), 0);
    await tester.pump(const Duration(milliseconds: 75));
    expect(opacity(detail), 0);
    expect(opacity(home), closeTo(incoming(.5), .001));
    await tester.pumpAndSettle();
    expect(tester.getRect(home), homeBounds);
  });

  testWidgets(
    'an early pop reverses the current fade without switching phases',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: navigator, home: const Scaffold()),
      );
      const key = ValueKey('detail');
      navigator.currentState!.push(
        const ArchiveTransitionPage<void>(child: Scaffold(key: key))
            .createRoute(navigator.currentContext!),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final detail = find.byKey(key);
      double opacity() => tester
          .widget<Opacity>(
            find.ancestor(of: detail, matching: find.byType(Opacity)).last,
          )
          .opacity;
      final before = opacity();
      navigator.currentState!.pop();
      await tester.pump();
      expect(opacity(), before);
      await tester.pumpAndSettle();
      expect(detail, findsNothing);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'theme backing covers every transition frame brightness=$brightness',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final surface = brightness == Brightness.light
            ? const Color(0xFFEAF4FA)
            : const Color(0xFF182128);
        final boundaryKey = GlobalKey();
        final navigatorKey = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              theme: ThemeData(
                brightness: brightness,
                scaffoldBackgroundColor: surface,
              ),
              home: const Scaffold(),
            ),
          ),
        );

        Future<void> covered() async {
          final boundary =
              boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final bytes = await tester.runAsync(() async {
            final image = await boundary.toImage();
            final data = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            image.dispose();
            return data!.buffer.asUint8List();
          });
          // Every page uses the theme surface. A missing backing would expose
          // the window during the fade-through gap or at the translated edges.
          for (var y = 10; y < 844; y += 40) {
            for (var x = 10; x < 390; x += 40) {
              final index = (y * 390 + x) * 4;
              expect(
                bytes![index],
                closeTo(surface.r * 255, 1),
                reason: 'Red at $x,$y',
              );
              expect(bytes[index + 1], closeTo(surface.g * 255, 1));
              expect(bytes[index + 2], closeTo(surface.b * 255, 1));
              expect(bytes[index + 3], 255);
            }
          }
        }

        Future<void> frames() async {
          for (var frame = 0; frame < 10; frame++) {
            await tester.pump(const Duration(milliseconds: 32));
            await covered();
          }
          await tester.pumpAndSettle();
        }

        void open() {
          navigatorKey.currentState!.push(
            const ArchiveTransitionPage<void>(child: Scaffold())
                .createRoute(navigatorKey.currentContext!),
          );
        }

        Future<void> gesture(String method, [double? progress]) async {
          await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
            'flutter/backgesture',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall(
                method,
                progress == null
                    ? null
                    : <String, Object>{
                        'touchOffset': <double>[5 + 180 * progress, 350],
                        'progress': progress,
                        'swipeEdge': 0,
                      },
              ),
            ),
            (_) {},
          );
          await tester.pump();
          await covered();
        }

        open();
        await frames();
        await gesture('startBackGesture', 0);
        for (final progress in [.15, .4, .7, .3, .05]) {
          await gesture('updateBackGestureProgress', progress);
        }
        await gesture('cancelBackGesture');
        await frames();
        await gesture('startBackGesture', 0);
        await gesture('updateBackGestureProgress', .6);
        await gesture('commitBackGesture');
        await frames();
        open();
        await frames();
        navigatorKey.currentState!.pop();
        await frames();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
