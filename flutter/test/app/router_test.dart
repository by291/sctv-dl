import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sctv_dl_mobile/app/providers.dart';
import 'package:sctv_dl_mobile/app/router.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/features/downloads/downloads_page.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_repository.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';

import '../support/fakes.dart';

const programme = Programme(id: '1', name: 'News');
const broadcast = BroadcastDate(id: '2', date: '2026-10-16');
const content = ProgrammeContent(
  id: '3',
  title: 'Accepted news',
  video: 'https://fscgc.scgchc.com/standard.mp4',
  smoothVideo: 'https://fscgc.scgchc.com/smooth.mp4',
);
const selection = ProgrammeSelection(
  programme: programme,
  broadcast: broadcast,
  content: content,
);

DownloadTask localTask() => DownloadTask(
  id: 'task-one',
  attemptId: 'attempt-one',
  selection: selection,
  requestedQuality: VideoQuality.standard,
  quality: VideoQuality.standard,
  url: content.video!,
  filename: 'news.mp4',
  wifiOnly: false,
  state: DownloadState.completed,
  createdAt: DateTime.utc(2026, 10, 16),
  fileLocation: 'documents:Downloads/news.mp4',
);

void main() {
  for (final local in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'playback coordinates both pages local=$local reduced=$reduced',
        (tester) async {
          final harness = RouteHarness();
          harness.downloads.tasks = [localTask()];
          await harness.mount(
            tester,
            local ? '/downloads' : '/programme/1',
            reducedMotion: reduced,
          );
          await tester.pumpAndSettle();
          final previous = find.byType(
            local ? DownloadsPage : ArchivePage,
            skipOffstage: false,
          );
          final before = tester.getRect(previous);
          final previousState = tester.element(previous);
          double opacity(Finder page) => tester
              .widgetList<Opacity>(
                find.ancestor(
                  of: page,
                  matching: find.byType(Opacity, skipOffstage: false),
                ),
              )
              .fold(1.0, (value, widget) => value * widget.opacity);
          if (local) {
            unawaited(harness.router.push('/local/task-one'));
          } else {
            tester.widget<ArchivePage>(previous).onPlay(selection);
          }
          for (var i = 0; i < 5; i++) {
            await tester.pump();
          }
          final player = find.byType(PlayerPage);
          expect(player, findsOneWidget);
          final route = ModalRoute.of(tester.element(player))!;
          await tester.pump(const Duration(milliseconds: 75));
          expect(
            opacity(previous),
            reduced ? 1 : allOf(greaterThan(0), lessThan(1)),
          );
          expect(opacity(player), reduced ? 1 : 0);
          expect(tester.getRect(previous).top, before.top);
          expect(tester.getSize(previous), before.size);
          await tester.pump(const Duration(milliseconds: 75));
          expect(opacity(previous), reduced ? 1 : 0);
          expect(
            opacity(player),
            reduced ? 1 : allOf(greaterThan(0), lessThan(1)),
          );
          await tester.pump(const Duration(milliseconds: 200));
          final playerBounds = tester.getRect(player);
          route.handleStartBackGesture(progress: .5);
          await tester.pump();
          expect(opacity(player), reduced ? 1 : 0);
          expect(
            opacity(previous),
            reduced ? 1 : allOf(greaterThan(0), lessThan(1)),
          );
          route.handleCancelBackGesture();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.getRect(player), playerBounds);
          expect(opacity(player), 1);
          harness.router.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 75));
          expect(
            opacity(player),
            reduced ? 1 : allOf(greaterThan(0), lessThan(1)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(player, findsNothing);
          expect(tester.element(previous), same(previousState));
          expect(tester.getRect(previous), before);
          expect(tester.takeException(), isNull);
          await harness.close(tester);
        },
      );
    }
  }
  for (final cancelling in [false, true]) {
    testWidgets(
      'removing a gesturing archive releases input cancelling=$cancelling',
      (tester) async {
        final harness = RouteHarness();
        await harness.mount(tester, '/');
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ProgrammeCard));
        await tester.pumpAndSettle();
        final route = ModalRoute.of(tester.element(find.byType(ArchivePage)))!;
        final navigation = route.navigator!;

        route.handleStartBackGesture(progress: .55);
        await tester.pump();
        if (cancelling) route.handleCancelBackGesture();
        harness.router.go('/downloads');
        await tester.pumpAndSettle();

        expect(find.byType(ArchivePage), findsNothing);
        expect(navigation.userGestureInProgress, isFalse);
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        expect(harness.router.state.uri.path, '/settings');
        expect(tester.takeException(), isNull);
        await harness.close(tester);
      },
    );
  }
  for (final ending in ['cancelBackGesture', 'commitBackGesture']) {
    testWidgets('archive recovers when another route interrupts $ending', (
      tester,
    ) async {
      final harness = RouteHarness();
      await harness.mount(tester, '/');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProgrammeCard));
      await tester.pumpAndSettle();
      final archive = find.byType(ArchivePage);
      final route = ModalRoute.of(tester.element(archive))!;
      final bounds = tester.getRect(archive);
      Future<void> event(String method, [double? progress]) async {
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

      await event('startBackGesture', 0);
      await event('updateBackGestureProgress', .45);
      harness.router.push('/history');
      await tester.pump();
      await event(ending);
      await tester.pumpAndSettle();
      harness.router.pop();
      await tester.pumpAndSettle();
      expect(route.animation!.value, 1);
      expect(tester.getRect(archive), bounds);
      await event('startBackGesture', 0);
      expect(route.popGestureInProgress, isTrue);
      await event('cancelBackGesture');
      await tester.pumpAndSettle();
      await harness.close(tester);
    });
  }
  for (final edge in [0, 1]) {
    for (final reduced in [false, true]) {
      for (final featured in [false, true]) {
        testWidgets(
          'Android predictive back cancels and commits edge=$edge reduced=$reduced featured=$featured',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final harness = RouteHarness();
            await harness.mount(tester, '/', reducedMotion: reduced);
            await tester.pumpAndSettle();
            final libraryScroll = tester
                .widget<CustomScrollView>(find.byType(CustomScrollView))
                .controller!;
            libraryScroll.jumpTo(35);
            await tester.pump();
            final source = featured
                ? find.text('查看节目')
                : find.byType(ProgrammeCard);
            final sourceBounds = tester.getRect(source);
            final coverTag = '${featured ? 'exploration' : 'catalogue'}-1';
            final sourceHero = find.byWidgetPredicate(
              (widget) => widget is Hero && widget.tag == coverTag,
            );
            final sourceCover = reduced ? null : tester.getRect(sourceHero);
            await tester.tap(source);
            await tester.pumpAndSettle();
            final archive = find.byType(ArchivePage);
            final archiveState = tester.state(archive);
            final archiveBounds = tester.getRect(archive);
            final route = ModalRoute.of(tester.element(archive))!;
            final archiveCover = reduced ? null : tester.getRect(sourceHero);

            Future<void> gesture(String method, [double? progress]) async {
              await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
                'flutter/backgesture',
                const StandardMethodCodec().encodeMethodCall(
                  MethodCall(
                    method,
                    progress == null
                        ? null
                        : <String, Object>{
                            'touchOffset': <double>[
                              edge == 0
                                  ? 5 + 180 * progress
                                  : 385 - 180 * progress,
                              350 + 90 * progress,
                            ],
                            'progress': progress,
                            'swipeEdge': edge,
                          },
                  ),
                ),
                (_) {},
              );
              await tester.pump();
            }

            await gesture('startBackGesture', 0);
            double? previousDistance;
            var previousRotation = 0.0;
            for (final progress in [.1, .2, .3, .4, .5, .6, .7, .8]) {
              await gesture('updateBackGestureProgress', progress);
              if (!reduced) {
                final flightBounds = tester.getRect(
                  find.byKey(const ValueKey('programme-cover-flight')),
                );
                final distance =
                    (flightBounds.center - sourceCover!.center).distance;
                final expectedBounds = Rect.lerp(
                  archiveCover,
                  sourceCover,
                  progress,
                )!;
                expect(
                  (flightBounds.center - expectedBounds.center).distance,
                  lessThan(.01),
                  reason: 'The cover must follow system progress without easing during a drag',
                );
                if (previousDistance != null) {
                  expect(distance, lessThan(previousDistance));
                }
                previousDistance = distance;
                final rotation = tester
                    .widget<Transform>(
                      find
                          .descendant(
                            of: find.byKey(
                              const ValueKey('programme-cover-flight'),
                            ),
                            matching: find.byType(Transform),
                          )
                          .first,
                    )
                    .transform
                    .entry(1, 0);
                if (featured) {
                  expect(rotation, lessThan(previousRotation));
                } else {
                  expect(rotation, 0);
                }
                previousRotation = rotation;
                expect(
                  flightBounds.width,
                  lessThanOrEqualTo(
                    sourceCover.width > archiveCover!.width
                        ? sourceCover.width
                        : archiveCover.width,
                  ),
                );
              }
            }
            await gesture('updateBackGestureProgress', 0.45);
            expect(route.popGestureInProgress, isTrue);
            expect(tester.state(archive), same(archiveState));
            expect(
              find.byKey(const ValueKey('programme-cover-flight')),
              reduced ? findsNothing : findsOneWidget,
            );
            expect(
              tester.getRect(archive),
              reduced ? archiveBounds : isNot(archiveBounds),
            );
            final draggedBounds = tester.getRect(archive);
            expect(draggedBounds.size, archiveBounds.size);
            expect(draggedBounds.top, archiveBounds.top);
            if (!reduced) {
              expect(
                draggedBounds.left,
                edge == 0
                    ? greaterThan(archiveBounds.left)
                    : lessThan(archiveBounds.left),
              );
            }
            await gesture('updateBackGestureProgress', 0.08);
            await gesture('cancelBackGesture');
            await tester.pumpAndSettle();
            expect(harness.router.state.uri.path, '/programme/1');
            expect(tester.state(archive), same(archiveState));
            expect(tester.getRect(archive), archiveBounds);
            if (!reduced) expect(tester.getRect(sourceHero), archiveCover);
            expect(route.popGestureInProgress, isFalse);

            final controller = tester.widget<ArchivePage>(archive).controller;
            controller.enterSelection();
            await tester.pumpAndSettle();
            await gesture('startBackGesture', 0);
            expect(route.popGestureInProgress, isFalse);
            await gesture('commitBackGesture');
            await tester.pumpAndSettle();
            expect(controller.selectionMode, isFalse);
            expect(tester.state(archive), same(archiveState));

            await gesture('startBackGesture', 0);
            await gesture('updateBackGestureProgress', 0.65);
            expect(route.popGestureInProgress, isTrue);
            final releaseBounds = tester.getRect(archive);
            final flight = find.byKey(const ValueKey('programme-cover-flight'));
            final releaseCover = reduced ? null : tester.getRect(flight);
            final releaseProgress = route.animation!.value;
            await gesture('commitBackGesture');
            expect(route.animation!.value, releaseProgress);
            expect(tester.getRect(archive), releaseBounds);
            if (!reduced) expect(tester.getRect(flight), releaseCover);
            await tester.pump(const Duration(milliseconds: 32));
            final settlingBounds = tester.getRect(archive);
            expect(settlingBounds.size, archiveBounds.size);
            if (!reduced) {
              expect(
                (settlingBounds.left - archiveBounds.left).abs(),
                greaterThan((releaseBounds.left - archiveBounds.left).abs()),
              );
            }
            await tester.pumpAndSettle();
            expect(harness.router.state.uri.path, '/');
            expect(libraryScroll.offset, 35);
            expect(tester.getRect(source), sourceBounds);
            if (!reduced) expect(tester.getRect(sourceHero), sourceCover);
            expect(tester.takeException(), isNull);
            await harness.close(tester);
          },
        );
      }
    }
  }
  for (final featured in [false, true]) {
    testWidgets(
      'archive cover flies both ways and restores library featured=$featured',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final harness = RouteHarness();
        await harness.mount(tester, '/');
        await tester.pumpAndSettle();
        final libraryScroll = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        libraryScroll.jumpTo(35);
        await tester.pump();
        final offset = libraryScroll.offset;
        final source = featured
            ? find.text('查看节目')
            : find.byType(ProgrammeCard);
        final sourceBounds = tester.getRect(source);
        await tester.tap(source);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        final flight = find.byKey(const ValueKey('programme-cover-flight'));
        expect(flight, findsOneWidget);
        expect(find.byType(ArchivePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        final forwardBounds = tester.getRect(flight);
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getRect(flight), isNot(forwardBounds));
        await tester.pumpAndSettle();
        expect(flight, findsNothing);

        harness.router.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(flight, findsOneWidget);
        await tester.pumpAndSettle();
        expect(libraryScroll.offset, offset);
        expect(tester.getRect(source), sourceBounds);
        expect(tester.takeException(), isNull);
        await harness.close(tester);
      },
    );
  }

  for (final reduced in [false, true]) {
    testWidgets('archive supports iOS edge return reduced=$reduced', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = RouteHarness();
      await harness.mount(
        tester,
        '/',
        platform: TargetPlatform.iOS,
        reducedMotion: reduced,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProgrammeCard));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(1, 350));
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('programme-cover-flight')),
        reduced ? findsNothing : findsOneWidget,
      );
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, '/programme/1');
      expect(find.byType(ArchivePage), findsOneWidget);
      await tester.dragFrom(const Offset(1, 350), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, '/');
      expect(find.byType(ProgrammeCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await harness.close(tester);
    });
  }
  testWidgets(
    'an early archive return leaves the original library position intact',
    (tester) async {
      final harness = RouteHarness();
      await harness.mount(tester, '/');
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(ProgrammeCard));
      await tester.tap(find.byType(ProgrammeCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      harness.router.pop();
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(ProgrammeCard)), before);
      expect(
        find.byKey(const ValueKey('programme-cover-flight')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await harness.close(tester);
    },
  );

  testWidgets('reduced motion opens the archive without a moving cover', (
    tester,
  ) async {
    final harness = RouteHarness();
    await harness.mount(tester, '/', reducedMotion: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProgrammeCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.byType(ArchivePage), findsOneWidget);
    expect(find.byKey(const ValueKey('programme-cover-flight')), findsNothing);
    final bounds = tester.getRect(find.byType(ArchivePage));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getRect(find.byType(ArchivePage)), bounds);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ProgrammeCard), findsOneWidget);
    await harness.close(tester);
  });

  testWidgets('replacing the archive updates the displayed programme', (
    tester,
  ) async {
    final harness = RouteHarness();
    await harness.mount(tester, '/');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProgrammeCard));
    await tester.pumpAndSettle();
    harness.router.replace(
      '/programme/9',
      extra: const Programme(id: '9', name: 'Another programme'),
    );
    await tester.pumpAndSettle();
    final archive = tester.widget<ArchivePage>(find.byType(ArchivePage));
    expect(archive.controller.programme.id, '9');
    expect(find.text('Another programme'), findsWidgets);
    await harness.close(tester);
  });

  testWidgets(
    'returning from a scrolled archive does not resurrect its hidden cover',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final harness = RouteHarness();
      harness.programmes.contents['2'] = snapshot([
        for (var i = 0; i < 20; i++)
          ProgrammeContent(id: '$i', title: 'Clip $i'),
      ], 'long archive');
      await harness.mount(tester, '/');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ProgrammeCard));
      await tester.pumpAndSettle();
      final scroll = tester
          .widget<CustomScrollView>(
            find.descendant(
              of: find.byType(ArchivePage),
              matching: find.byType(CustomScrollView),
            ),
          )
          .controller!;
      scroll.jumpTo(500);
      await tester.pump();
      harness.router.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(
        find.byKey(const ValueKey('programme-cover-flight')),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProgrammeCard), findsOneWidget);
      await harness.close(tester);
    },
  );

  for (final completed in [false, true]) {
    testWidgets('history resumes its exact entry with completed=$completed', (
      tester,
    ) async {
      final harness = RouteHarness();
      harness.history.entries.add(
        ViewingEntry(
          selection: selection,
          position: const Duration(seconds: 38),
          completed: completed,
          viewedAt: DateTime.utc(2026),
        ),
      );
      await harness.mount(tester, '/');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索栏目'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'missing catalogue');
      await tester.tap(find.byTooltip('观看历史'));
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, '/history');
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.text('Accepted news'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(harness.backend.inputs.single.selection, same(selection));
      expect(
        harness.backend.inputs.single.initialPosition,
        completed ? Duration.zero : const Duration(seconds: 38),
      );
      harness.router.pop();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, '/');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'missing catalogue',
      );
      expect(find.text('没有找到相关栏目'), findsOneWidget);
      await harness.close(tester);
    });
  }

  testWidgets(
    'history search and scroll survive leaving and reopening the route',
    (tester) async {
      final harness = RouteHarness();
      for (var i = 0; i < 30; i++) {
        harness.history.entries.add(
          ViewingEntry(
            selection: ProgrammeSelection(
              programme: programme,
              broadcast: broadcast,
              content: ProgrammeContent(id: '$i', title: 'News episode $i'),
            ),
            position: const Duration(seconds: 38),
            viewedAt: DateTime.utc(2026),
          ),
        );
      }
      await harness.mount(tester, '/');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('观看历史'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('搜索观看记录'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'News episode');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final offset = tester
          .widget<ListView>(find.byType(ListView))
          .controller!
          .offset;
      expect(offset, greaterThan(0));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(harness.router.state.uri.path, '/');
      await tester.tap(find.byTooltip('观看历史'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'News episode',
      );
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        closeTo(offset, 1),
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await harness.close(tester);
    },
  );

  testWidgets('leaving an archive cancels its metadata resolution', (
    tester,
  ) async {
    final harness = RouteHarness();
    harness.programmes.cachedCatalogue = null;
    harness.programmes.catalogueReply =
        Completer<ProgrammeSnapshot<Programme>>();
    await harness.mount(tester, '/programme/1');
    expect(harness.programmes.catalogueCalls, 1);

    harness.router.go('/settings');
    await tester.pumpAndSettle();
    expect(harness.programmes.catalogueScope?.isCancelled, isTrue);
    harness.programmes.catalogueReply!.complete(snapshot([programme], 'late'));
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsWidgets);
    expect(tester.takeException(), isNull);
    await harness.close(tester);
  });

  testWidgets(
    'leaving a restored player cancels date resolution and stops later requests',
    (tester) async {
      final harness = RouteHarness();
      harness.programmes.savedDates = null;
      harness.programmes.dateReply =
          Completer<ProgrammeSnapshot<BroadcastDate>>();
      await harness.mount(tester, '/play/1/2/3');
      expect(harness.programmes.dateCalls, 1);

      harness.router.go('/settings');
      await tester.pumpAndSettle();
      expect(harness.programmes.dateScope?.isCancelled, isTrue);
      harness.programmes.dateReply!.complete(snapshot([broadcast], 'late'));
      await tester.pumpAndSettle();
      expect(harness.programmes.contentReads, 0);
      expect(harness.backend.inputs, isEmpty);
      await harness.close(tester);
    },
  );

  testWidgets(
    'a late cached read cannot start network work after the player is disposed',
    (tester) async {
      final harness = RouteHarness();
      final cachedDates = Completer<ProgrammeSnapshot<BroadcastDate>?>();
      harness.programmes.delayedDateCache = cachedDates.future;
      await harness.mount(tester, '/play/1/2/3');

      harness.router.go('/settings');
      await tester.pumpAndSettle();
      cachedDates.complete(null);
      await tester.pumpAndSettle();
      expect(harness.programmes.dateCalls, 0);
      expect(harness.backend.inputs, isEmpty);
      await harness.close(tester);
    },
  );

  testWidgets(
    'restored online playback resolves the current quality preference',
    (tester) async {
      final harness = RouteHarness();
      harness.history.entries.add(
        ViewingEntry(
          selection: selection,
          position: const Duration(seconds: 38),
          viewedAt: DateTime.utc(2026),
        ),
      );
      await harness.container
          .read(preferencesProvider.notifier)
          .save(const Preferences(quality: VideoQuality.smooth));
      await harness.mount(tester, '/play/1/2/3');

      expect(
        harness.backend.inputs.single.sources.first.quality,
        VideoQuality.smooth,
      );
      expect(
        harness.backend.inputs.single.preferredQuality,
        VideoQuality.smooth,
      );
      expect(harness.backend.inputs.single.selection?.ref, selection.ref);
      expect(
        harness.backend.inputs.single.initialPosition,
        const Duration(seconds: 38),
      );
      await harness.close(tester);
    },
  );

  testWidgets('ordinary archive playback resumes shared viewing history', (
    tester,
  ) async {
    final harness = RouteHarness();
    harness.history.entries.add(
      ViewingEntry(
        selection: selection,
        position: const Duration(seconds: 38),
        viewedAt: DateTime.utc(2026),
      ),
    );
    await harness.mount(tester, '/programme/1');
    await tester.tap(find.text('Accepted news'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(
      harness.backend.inputs.single.initialPosition,
      const Duration(seconds: 38),
    );
    expect(
      harness.backend.inputs.single.preferredQuality,
      VideoQuality.standard,
    );
    await harness.close(tester);
  });

  testWidgets(
    'archive playback reports history failures at the action boundary',
    (tester) async {
      final harness = RouteHarness();
      harness.history.loadError = StateError('fixture storage unavailable');
      await harness.mount(tester, '/programme/1');
      await tester.tap(find.text('Accepted news'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(find.textContaining('观看进度'), findsOneWidget);
      expect(harness.backend.inputs, isEmpty);
      expect(tester.takeException(), isNull);
      await harness.close(tester);
    },
  );

  testWidgets(
    'download playback navigates with its durable local task identity',
    (tester) async {
      final harness = RouteHarness();
      harness.downloads.tasks = [localTask()];
      harness.history.entries.add(
        ViewingEntry(
          selection: selection,
          position: const Duration(seconds: 38),
          viewedAt: DateTime.utc(2026),
        ),
      );
      await harness.mount(tester, '/downloads');
      await tester.tap(find.text('播放'));
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }

      expect(harness.router.state.uri.path, '/local/task-one');
      expect(
        harness.backend.inputs.single.initialPosition,
        const Duration(seconds: 38),
      );
      await harness.close(tester);
    },
  );

  testWidgets(
    'restored local playback stays local without metadata or route extras',
    (tester) async {
      final harness = RouteHarness();
      harness.downloads.tasks = [localTask()];
      harness.history.entries.add(
        ViewingEntry(
          selection: selection,
          position: const Duration(seconds: 38),
          viewedAt: DateTime.utc(2026),
        ),
      );
      await harness.mount(tester, '/local/task-one');

      expect(
        harness.backend.inputs.single.localLocation,
        'documents:Downloads/news.mp4',
      );
      expect(harness.backend.inputs.single.sources, isEmpty);
      expect(
        harness.backend.inputs.single.initialPosition,
        const Duration(seconds: 38),
      );
      expect(harness.programmes.catalogueCalls, 0);
      expect(harness.programmes.contentReads, 0);
      expect(harness.downloads.reconciliations, 1);
      await harness.close(tester);
    },
  );

  testWidgets(
    'completed content replays from zero in restored local playback',
    (tester) async {
      final harness = RouteHarness();
      harness.downloads.tasks = [localTask()];
      harness.history.entries.add(
        ViewingEntry(
          selection: selection,
          position: const Duration(seconds: 100),
          completed: true,
          viewedAt: DateTime.utc(2026),
        ),
      );
      await harness.mount(tester, '/local/task-one');

      expect(harness.backend.inputs.single.initialPosition, Duration.zero);
      await harness.close(tester);
    },
  );

  testWidgets(
    'a missing restored local file fails without falling back online',
    (tester) async {
      final harness = RouteHarness();
      harness.downloads.tasks = [
        localTask().copyWith(state: DownloadState.missing),
      ];
      await harness.mount(tester, '/local/task-one');

      expect(find.textContaining('下载文件'), findsOneWidget);
      expect(harness.backend.inputs, isEmpty);
      expect(harness.programmes.catalogueCalls, 0);
      expect(harness.programmes.contentReads, 0);
      await harness.close(tester);
    },
  );

  testWidgets(
    'retained shell rebuilds do not resubscribe to task observation',
    (tester) async {
      final harness = RouteHarness();
      await harness.mount(tester, '/downloads');
      final subscriptions = harness.downloads.subscriptions;
      expect(subscriptions, 2);

      harness.router.go('/settings');
      await tester.pumpAndSettle();
      expect(harness.downloads.subscriptions, subscriptions);
      await harness.close(tester);
    },
  );
}

class RouteHarness {
  final programmes = RouteProgrammes()
    ..cachedCatalogue = snapshot([programme], 'catalogue')
    ..savedDates = snapshot([broadcast], 'dates')
    ..contents['2'] = snapshot([content], 'contents');
  final user = FakeUserRepository();
  final downloads = RouteDownloads();
  final backend = CapturingBackend();
  final history = RouteHistory();
  late final services = AppServices(
    programmes: programmes,
    user: user,
    history: history,
    downloads: downloads,
    playback: backend,
    initialPreferences: const Preferences(),
    initialFavourites: const {},
    version: 'test',
    coverCache: UnusedCoverCache(),
  );
  late final GoRouter router = createAppRouter(services);
  late final container = ProviderContainer(
    overrides: [servicesProvider.overrideWithValue(services)],
  );
  bool _closed = false;

  Future<void> mount(
    WidgetTester tester,
    String location, {
    TargetPlatform platform = TargetPlatform.android,
    bool reducedMotion = false,
  }) async {
    addTearDown(() => close(tester));
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          restorationScopeId: 'route-tests',
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
          routerConfig: router,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    if (_closed) return;
    _closed = true;
    await tester.pumpWidget(const SizedBox());
    for (final pending in backend.pending) {
      pending.complete(RoutePlaybackSession());
    }
    await tester.pump();
    router.dispose();
    container.dispose();
    await services.dispose();
    await user.close();
  }
}

class RouteProgrammes extends FakeProgrammeRepository {
  Completer<ProgrammeSnapshot<Programme>>? catalogueReply;
  Completer<ProgrammeSnapshot<BroadcastDate>>? dateReply;
  Future<ProgrammeSnapshot<BroadcastDate>?>? delayedDateCache;
  RequestScope? catalogueScope;
  RequestScope? dateScope;
  int catalogueCalls = 0;
  int dateCalls = 0;
  int contentReads = 0;

  @override
  Future<ProgrammeSnapshot<Programme>> refreshProgrammes({
    RequestScope? scope,
  }) async {
    catalogueCalls++;
    catalogueScope = scope;
    return await (catalogueReply?.future ??
        super.refreshProgrammes(scope: scope));
  }

  @override
  Future<ProgrammeSnapshot<BroadcastDate>?> cachedDates(
    String programmeId,
  ) async => await (delayedDateCache ?? super.cachedDates(programmeId));

  @override
  Future<ProgrammeSnapshot<BroadcastDate>> refreshDates(
    String programmeId, {
    RequestScope? scope,
  }) async {
    dateCalls++;
    dateScope = scope;
    return await (dateReply?.future ??
        super.refreshDates(programmeId, scope: scope));
  }

  @override
  Future<ProgrammeSnapshot<ProgrammeContent>?> cachedContents(
    String programmeId,
    String dateId,
  ) async {
    contentReads++;
    return super.cachedContents(programmeId, dateId);
  }
}

class RouteDownloads implements DownloadRepository {
  List<DownloadTask> tasks = [];
  final changes = StreamController<List<DownloadTask>>.broadcast();
  int subscriptions = 0;
  int reconciliations = 0;

  @override
  Future<List<DownloadTask>> loadTasks() async => tasks;

  @override
  Stream<List<DownloadTask>> watchTasks() => Stream.multi((controller) {
    subscriptions++;
    controller.add(tasks);
    final subscription = changes.stream.listen(controller.add);
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<void> reconcile() async {
    reconciliations++;
  }

  @override
  Future<void> dispose() => changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CapturingBackend implements PlaybackBackend {
  final inputs = <PlaybackInput>[];
  final pending = <Completer<PlaybackSession>>[];

  @override
  Future<PlaybackSession> open(PlaybackInput input) {
    inputs.add(input);
    final session = Completer<PlaybackSession>();
    pending.add(session);
    return session.future;
  }
}

class RouteHistory implements HistoryRepository {
  final entries = <ViewingEntry>[];
  Object? loadError;

  @override
  Future<List<ViewingEntry>> loadHistory() async {
    if (loadError case final error?) throw error;
    return entries;
  }

  @override
  Future<void> save(ViewingEntry entry) async => entries.add(entry);

  @override
  Stream<List<ViewingEntry>> watchHistory() => Stream.value(entries);

  @override
  Future<void> remove(ContentRef ref) async =>
      entries.removeWhere((entry) => entry.selection.ref == ref);

  @override
  Future<void> clear() async => entries.clear();
}

class RoutePlaybackSession implements PlaybackSession {
  @override
  String get id => 'route-playback';
  @override
  PlaybackSnapshot get value => const PlaybackSnapshot();
  @override
  Stream<PlaybackSnapshot> get changes => const Stream.empty();
  @override
  Future<void> dispose() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> selectSource(VideoSource source) async {}
  @override
  Future<void> enterPictureInPicture() async {}
}

class UnusedCoverCache implements BaseCacheManager {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
