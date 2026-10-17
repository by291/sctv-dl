import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

/// Profile rendering with uniform route progress, separately from OS input
/// delivery. Run with --profile --no-dds and ARCHIVE_MOTION_PROFILE=true.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('profile warmed shared-cover dragging', (tester) async {
    final services = await bootstrapServices();
    await tester.pumpWidget(SctvApp(services: services));
    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      expect(ready(), isTrue);
    }

    await waitFor(() => services.library.hasSnapshot);
    await tester.pumpAndSettle();
    for (final featured in [false, true]) {
      await tester.tap(
        featured ? find.text('查看节目') : find.byType(ProgrammeCard).first,
      );
      await tester.pumpAndSettle();
      final archive = find.byType(ArchivePage);
      await waitFor(
        () =>
            !tester.widget<ArchivePage>(archive).controller.loadingDates &&
            !tester.widget<ArchivePage>(archive).controller.loadingContents,
      );
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(archive))!;
      Future<void> drag() async {
        route.handleStartBackGesture(progress: 1);
        for (var step = 1; step <= 90; step++) {
          final progress = step <= 45 ? step / 50 : (90 - step) / 50;
          route.handleUpdateBackGestureProgress(progress: 1 - progress);
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
        route.handleCancelBackGesture();
        await tester.pumpAndSettle();
      }

      await drag(); // Warm image, text and raster caches before measurement.
      final key = featured ? 'exploration' : 'catalogue';
      await binding.watchPerformance(() async {
        for (var run = 0; run < 3; run++) {
          await drag();
        }
      }, reportKey: key);
      final report = binding.reportData![key] as Map<String, dynamic>;
      final summary = {
        for (final field in [
          'frame_count',
          'average_frame_build_time_millis',
          '90th_percentile_frame_build_time_millis',
          'worst_frame_build_time_millis',
          'average_frame_rasterizer_time_millis',
          '90th_percentile_frame_rasterizer_time_millis',
          'worst_frame_rasterizer_time_millis',
          'missed_frame_build_budget_count',
          'missed_frame_rasterizer_budget_count',
        ])
          field: report[field],
      };
      debugPrint('MOTION_PROFILE:$key:${jsonEncode(summary)}');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, skip: !const bool.fromEnvironment('ARCHIVE_MOTION_PROFILE'));
}
