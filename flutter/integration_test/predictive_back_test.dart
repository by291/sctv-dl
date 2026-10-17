import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

/// Run with tool/verify_predictive_back.py on a disposable Android device.
/// The host injects touchscreen events; this test never synthesizes back-channel
/// messages, so popGestureInProgress proves the system reached Flutter.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'system predictive back cancels and commits without losing state',
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
        final deadline = DateTime.now().add(const Duration(seconds: 45));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.pump();
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
          'screenshotName': 'android-predictive-$name',
          'bytes': bytes!.buffer.asUint8List().toList(),
        });
      }

      await waitFor(() => services.library.hasSnapshot);
      await tester.pumpAndSettle();
      final libraryScroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      libraryScroll.jumpTo(35);
      await tester.pumpAndSettle();
      await capture('library-before');

      for (final sample in [
        (name: 'grid', edge: 'left', featured: false, scrolled: false),
        (name: 'exploration', edge: 'right', featured: true, scrolled: false),
        (name: 'scrolled', edge: 'right', featured: false, scrolled: true),
      ]) {
        final edge = sample.edge;
        final label = '${sample.name}-$edge';
        final source = sample.featured
            ? find.text('查看节目')
            : find.byType(ProgrammeCard).first;
        final sourceBounds = tester.getRect(source);
        await tester.tap(source);
        await tester.pumpAndSettle();
        final archive = find.byType(ArchivePage);
        await waitFor(
          () =>
              !tester.widget<ArchivePage>(archive).controller.loadingDates &&
              !tester.widget<ArchivePage>(archive).controller.loadingContents,
        );
        final state = tester.state(archive);
        final route = ModalRoute.of(tester.element(archive))!;
        final navigator = route.navigator!;
        final archiveScroll = tester
            .widget<CustomScrollView>(
              find.descendant(
                of: archive,
                matching: find.byType(CustomScrollView),
              ),
            )
            .controller!;
        // Exercise a visible cover and a clipped cover on the same real route.
        if (sample.scrolled) {
          archiveScroll.jumpTo(
            200.clamp(0, archiveScroll.position.maxScrollExtent).toDouble(),
          );
          await tester.pump();
        }
        final archiveOffset = archiveScroll.offset;
        final beforeBounds = tester.getRect(archive);
        double archiveOpacity() => tester
            .widget<Opacity>(
              find.ancestor(of: archive, matching: find.byType(Opacity)),
            )
            .opacity;
        await capture('$label-before');
        for (final outcome in ['cancel', 'commit']) {
          debugPrint('PREDICTIVE_READY:${sample.name}:$edge:$outcome');
          await waitFor(
            // OS callbacks can update the controller before its next frame.
            // Wait for the rendered phase as well as the input progress.
            () =>
                route.popGestureInProgress &&
                route.animation!.value < .6 &&
                archiveOpacity() == 0,
          );
          expect(tester.state(archive), same(state));
          final draggedBounds = tester.getRect(archive);
          expect(
            archiveOpacity(),
            0,
            reason: 'After the exit phase the archive must reveal the library',
          );
          final library = find.byType(LibraryPage);
          final libraryOpacity = tester
              .widget<Opacity>(
                find.ancestor(of: library, matching: find.byType(Opacity)).last,
              )
              .opacity;
          expect(libraryOpacity, greaterThan(0));
          expect(libraryOpacity, lessThan(1));
          expect(draggedBounds.size, beforeBounds.size);
          expect(draggedBounds.top, beforeBounds.top);
          expect(
            draggedBounds.left,
            edge == 'left'
                ? greaterThan(beforeBounds.left)
                : lessThan(beforeBounds.left),
          );
          expect(
            find.byKey(const ValueKey('programme-cover-flight')),
            sample.scrolled ? findsNothing : findsOneWidget,
          );
          await capture('$label-$outcome-drag');
          final animation = route.animation!;
          final settlingProgress = <double>[animation.value];
          void recordProgress() => settlingProgress.add(animation.value);
          animation.addListener(recordProgress);
          debugPrint('PREDICTIVE_CAPTURED:${sample.name}:$edge:$outcome');
          await waitFor(() => !navigator.userGestureInProgress);
          animation.removeListener(recordProgress);
          await tester.pumpAndSettle();
          if (outcome == 'cancel') {
            expect(tester.state(archive), same(state));
            expect(tester.getRect(archive), beforeBounds);
            expect(archiveScroll.offset, archiveOffset);
          } else {
            expect(archive, findsNothing);
            expect(libraryScroll.offset, 35);
            expect(tester.getRect(source), sourceBounds);
            for (var i = 1; i < settlingProgress.length; i++) {
              expect(
                settlingProgress[i],
                lessThanOrEqualTo(settlingProgress[i - 1] + .001),
              );
            }
          }
          await capture('$label-$outcome-after');
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    skip:
        !Platform.isAndroid ||
        !const bool.fromEnvironment('PREDICTIVE_BACK_SMOKE'),
  );
}
