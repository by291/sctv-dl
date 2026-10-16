import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

/// This opt-in smoke journey uses the production composition and live metadata.
/// It never creates a live download; native transfers have controlled fixtures.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('LIVE_APPLICATION_SMOKE');

  testWidgets(
    'production composition browses archives and opens paused media',
    (tester) async {
      final services = await bootstrapServices();
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: SctvApp(services: services),
        ),
      );

      Future<void> waitFor(bool Function() ready) async {
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!ready() && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(ready(), isTrue);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        final surface =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await surface.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/sctv-qa-$name.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        binding.reportData ??= <String, Object?>{};
        final screenshots = binding.reportData!.putIfAbsent(
          'screenshots',
          () => <Object?>[],
        ) as List<Object?>;
        screenshots.add({
          'screenshotName': '${Platform.operatingSystem}-$name',
          'bytes': bytes.buffer.asUint8List().toList(),
        });
        image.dispose();
        debugPrint('Application screenshot: ${file.path}');
      }

      await waitFor(() => services.library.hasSnapshot);
      expect(services.library.programmes, isNotEmpty);
      await capture('library');
      final programme = services.library.programmes.firstWhere(
        (item) => item.name.contains('四川新闻'),
        orElse: () => services.library.programmes.first,
      );
      await tester.tap(find.byTooltip('搜索栏目'));
      await tester.pump();
      await tester
          .enterText(find.byType(TextField), programme.name)
          .timeout(const Duration(seconds: 10));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(ProgrammeCard), findsOneWidget);
      await capture('search');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.tap(find.byType(ProgrammeCard));
      await waitFor(() {
        final pages = tester.widgetList<ArchivePage>(find.byType(ArchivePage));
        return pages.isNotEmpty &&
            !pages.first.controller.loadingDates &&
            !pages.first.controller.loadingContents;
      });
      final archive = tester.widget<ArchivePage>(find.byType(ArchivePage));
      expect(archive.controller.dates, isNotEmpty);
      expect(archive.controller.contents, isNotEmpty);
      await capture('archive');

      final playable = archive.controller.fullEpisodes.isNotEmpty
          ? archive.controller.fullEpisodes.first
          : archive.controller.clips.first;
      final title = find.text(playable.title).last;
      await tester.ensureVisible(title);
      await tester.tap(title);
      await waitFor(() => find.byType(PlayerPage).evaluate().isNotEmpty);
      await waitFor(() {
        final buttons = tester.widgetList<IconButton>(
          find.widgetWithIcon(IconButton, Icons.play_arrow),
        );
        return buttons.any((button) => button.onPressed != null);
      });
      // Initialisation is paused. Decode/seek/speed and redirects use native fixtures.
      expect(find.byTooltip('暂停'), findsNothing);
      await capture('player-paused');
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('下载').last);
      await tester.pump(const Duration(milliseconds: 500));
      await capture('downloads');
      await tester.tap(find.text('设置').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('主题'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('深色').last);
      await tester.pump(const Duration(milliseconds: 500));
      await capture('settings-dark');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 500));
    },
    skip: !enabled,
  );
}
