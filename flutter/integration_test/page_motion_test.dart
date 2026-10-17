import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/design/shared_cover.dart';
import 'package:sctv_dl_mobile/features/player/playback_cover.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/history_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

/// Uses real native paused video and host-injected edge gestures. No transfers.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'player and history retain geometry through system back gestures',
    (tester) async {
      final services = await bootstrapServices();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: SctvApp(services: services),
        ),
      );
      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        binding.reportData ??= <String, Object?>{};
        final screenshots = binding.reportData!.putIfAbsent(
          'screenshots',
          () => <Object?>[],
        ) as List<Object?>;
        screenshots.add({
          'screenshotName': 'android-motion-$name',
          'bytes': bytes!.buffer.asUint8List().toList(),
        });
      }

      double opacity(Finder page) => tester
          .widgetList<Opacity>(
            find.ancestor(of: page, matching: find.byType(Opacity)),
          )
          .fold(1.0, (value, item) => value * item.opacity);

      await waitFor(() => services.library.hasSnapshot);
      await tester.pumpAndSettle();
      final library = find.byType(LibraryPage);
      final router = GoRouter.of(tester.element(library));
      for (final name in ['player', 'history']) {
        for (final edge in ['left', 'right']) {
          Finder previous = library;
          ScrollController? scroll;
          double? offset;
          if (name == 'player') {
            await tester.tap(find.byType(ProgrammeCard).first);
            await tester.pumpAndSettle();
            previous = find.byType(ArchivePage);
            await waitFor(() {
              final controller = tester
                  .widget<ArchivePage>(previous)
                  .controller;
              return !controller.loadingDates &&
                  !controller.loadingContents &&
                  controller.contents.isNotEmpty;
            });
            final controller = tester.widget<ArchivePage>(previous).controller;
            final playable =
                controller.fullEpisodes.firstOrNull ?? controller.clips.first;
            final title = find.text(playable.title).last;
            await tester.ensureVisible(
              find.ancestor(of: title, matching: find.byType(Card)).first,
            );
            await tester.pumpAndSettle();
            scroll = tester
                .widget<CustomScrollView>(
                  find.descendant(
                    of: previous,
                    matching: find.byType(CustomScrollView),
                  ),
                )
                .controller!;
            offset = scroll.offset;
            await tester.tap(title);
            await waitFor(() => find.byType(PlayerPage).evaluate().isNotEmpty);
            final poster = find.descendant(
              of: find.byType(PlaybackCover),
              matching: find.byType(SharedCover),
            );
            await waitFor(
              () => tester.widget<SharedCover>(poster).opacity == 0,
            );
            expect(find.byTooltip('暂停'), findsNothing);
          } else {
            router.push('/history');
          }
          await tester.pumpAndSettle();
          final page = name == 'player'
              ? find.byType(PlayerPage)
              : find.byType(HistoryPage);
          final state = tester.state(page);
          final bounds = tester.getRect(page);
          final route = ModalRoute.of(tester.element(page))!;
          final navigator = route.navigator!;
          await capture('$name-$edge-before');
          for (final outcome in ['cancel', 'commit']) {
            debugPrint('PREDICTIVE_READY:$name:$edge:$outcome');
            await waitFor(
              () =>
                  route.popGestureInProgress &&
                  route.animation!.value < .6 &&
                  opacity(page) == 0,
            );
            expect(tester.state(page), same(state));
            expect(tester.getSize(page), bounds.size);
            expect(tester.getRect(page).top, bounds.top);
            expect(opacity(previous), greaterThan(0));
            expect(opacity(previous), lessThan(1));
            if (name == 'player') {
              expect(
                find.byKey(const ValueKey('programme-cover-flight')),
                findsOneWidget,
              );
            }
            await capture('$name-$edge-$outcome-drag');
            debugPrint('PREDICTIVE_CAPTURED:$name:$edge:$outcome');
            await waitFor(() => !navigator.userGestureInProgress);
            await tester.pumpAndSettle();
            if (outcome == 'cancel') {
              expect(tester.state(page), same(state));
              expect(tester.getRect(page), bounds);
              if (name == 'player') {
                final poster = find.descendant(
                  of: find.byType(PlaybackCover),
                  matching: find.byType(SharedCover),
                );
                expect(tester.widget<SharedCover>(poster).opacity, 0);
              }
            } else {
              expect(page, findsNothing);
              if (scroll != null) expect(scroll.offset, offset);
            }
            await capture('$name-$edge-$outcome-settled');
          }
          if (name == 'player') {
            router.pop();
            await tester.pumpAndSettle();
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('PREDICTIVE_BACK_SMOKE'),
  );
}
