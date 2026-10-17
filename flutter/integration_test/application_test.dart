import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sctv_dl_mobile/app/app.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/design/theme.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_repository.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/downloads/downloads_page.dart';
import 'package:sctv_dl_mobile/features/player/player_page.dart';
import 'package:sctv_dl_mobile/features/programmes/archive_page.dart';
import 'package:sctv_dl_mobile/features/programmes/library_page.dart';

/// This opt-in smoke journey uses the production composition and live metadata.
/// It never creates a live download; native transfers have controlled fixtures.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('LIVE_APPLICATION_SMOKE');

  testWidgets('production composition browses archives and opens paused media', (
    tester,
  ) async {
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

    Future<void> capture(String name, {bool settle = true}) async {
      // Allow visible artwork to settle without making upstream image failures
      // fail the browsing journey. The captured fallback remains useful evidence.
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (settle && DateTime.now().isBefore(deadline)) {
        final covers = find.byType(CachedNetworkImage).evaluate();
        final pending = covers.any(
          (element) => find
              .descendant(
                of: find.byWidget(element.widget),
                matching: find.byType(RawImage),
              )
              .evaluate()
              .isEmpty,
        );
        if (!pending) break;
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (settle) await tester.pump(const Duration(milliseconds: 500));
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
    expect(find.byType(TabBar), findsNothing);
    final explorationBounds = tester.getRect(find.text('栏目探索'));
    await tester.tap(find.byTooltip('只看收藏'));
    await tester.pump(const Duration(milliseconds: 60));
    await capture('favourites-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('还没有收藏'), findsOneWidget);
    await capture('favourites-empty');
    expect(tester.getRect(find.text('栏目探索')), explorationBounds);
    await tester.tap(find.byTooltip('显示全部栏目'));
    await tester.pump(const Duration(milliseconds: 300));
    final shuffleBounds = tester.getRect(find.text('换一个'));
    await tester.tap(find.text('换一个'));
    await tester.pump(const Duration(milliseconds: 60));
    await capture('exploration-transition', settle: false);
    expect(tester.getRect(find.text('换一个')), shuffleBounds);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getRect(find.text('换一个')), shuffleBounds);
    await tester.tap(find.text('查看节目'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('programme-cover-flight')),
      findsOneWidget,
    );
    await capture('exploration-enter-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 400));
    if (Platform.isIOS) {
      final gesture = await tester.startGesture(const Offset(1, 350));
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(70, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.byKey(const ValueKey('programme-cover-flight')),
        findsOneWidget,
      );
      await capture('archive-gesture-transition', settle: false);
      await gesture.moveBy(const Offset(-60, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ArchivePage), findsOneWidget);
    }
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('programme-cover-flight')),
      findsOneWidget,
    );
    await capture('exploration-return-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 400));
    final programme = services.library.programmes.firstWhere(
      (item) => item.name.contains('四川新闻'),
      orElse: () => services.library.programmes.first,
    );
    await tester.tap(find.byTooltip('搜索栏目'));
    await tester.pump(const Duration(milliseconds: 60));
    await capture('search-transition', settle: false);
    await tester
        .enterText(find.byType(TextField), programme.name)
        .timeout(const Duration(seconds: 10));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(ProgrammeCard), findsOneWidget);
    await capture('search');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final libraryBounds = tester.getRect(find.byType(ProgrammeCard));
    await tester.tap(find.byType(ProgrammeCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey('programme-cover-flight')),
      findsOneWidget,
    );
    await capture('archive-enter-transition', settle: false);
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
    await tester.tap(find.byTooltip('批量下载'));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('archive-selection');
    await tester.tap(find.text('全选'));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('archive-selected');
    await tester.tap(find.byTooltip('退出批量选择'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('更多日期'));
    await tester.pump(const Duration(milliseconds: 400));
    await capture('dates');
    await tester.tapAt(const Offset(10, 80));
    await tester.pump(const Duration(milliseconds: 400));

    final playable = archive.controller.fullEpisodes.isNotEmpty
        ? archive.controller.fullEpisodes.first
        : archive.controller.clips.first;
    final title = find.text(playable.title).last;
    await tester.ensureVisible(title);
    final playbackArchiveBounds = tester.getRect(find.byType(ArchivePage));
    final playbackScroll = tester
        .widget<CustomScrollView>(
          find.descendant(
            of: find.byType(ArchivePage),
            matching: find.byType(CustomScrollView),
          ),
        )
        .controller!;
    final playbackScrollOffset = playbackScroll.offset;
    await tester.tap(title);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await capture('player-enter-transition', settle: false);
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
    final pressed = await tester.startGesture(
      tester.getCenter(find.byTooltip('播放速度')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    await capture('player-pressed', settle: false);
    await pressed.cancel();
    await tester.pumpAndSettle();
    if (Platform.isAndroid) {
      final controlsY = tester.getCenter(find.byTooltip('播放速度')).dy;
      expect(tester.getCenter(find.byType(Slider)).dy, controlsY);
      await tester.tap(find.byTooltip('全屏'));
      await waitFor(
        () => tester.view.physicalSize.width > tester.view.physicalSize.height,
      );
      await capture('player-fullscreen');
      expect(
        tester.getCenter(find.byType(Slider)).dy,
        tester.getCenter(find.byTooltip('播放速度')).dy,
      );
      await tester.tap(find.byTooltip('退出全屏'));
      await waitFor(
        () => tester.view.physicalSize.width < tester.view.physicalSize.height,
      );
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await capture('player-return-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getRect(find.byType(ArchivePage)), playbackArchiveBounds);
    expect(playbackScroll.offset, playbackScrollOffset);
    final archiveScroll = tester
        .widget<CustomScrollView>(
          find.descendant(
            of: find.byType(ArchivePage),
            matching: find.byType(CustomScrollView),
          ),
        )
        .controller!;
    archiveScroll.jumpTo(
      500.0.clamp(0, archiveScroll.position.maxScrollExtent),
    );
    await tester.pump();
    final coverWasClipped = archiveScroll.offset > 8;
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    if (coverWasClipped) {
      expect(
        find.byKey(const ValueKey('programme-cover-flight')),
        findsNothing,
      );
    }
    await capture('archive-return-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.getRect(find.byType(ProgrammeCard)), libraryBounds);
    await tester.tap(find.text('下载').last);
    await tester.pump(const Duration(milliseconds: 60));
    await capture('navigation-transition', settle: false);
    await tester.pump(const Duration(milliseconds: 500));
    await capture('downloads');
    await tester.tap(find.text('设置').last);
    await tester.pump(const Duration(milliseconds: 500));
    await capture('settings');
    await tester.tap(find.text('主题'));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('theme-picker');
    await tester.tap(find.text('深色').last);
    await tester.pump(const Duration(milliseconds: 500));
    await capture('settings-dark');
    await tester.tap(find.text('节目库').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('library-dark');
    await tester.tap(find.byTooltip('观看历史'));
    await tester.pump(const Duration(milliseconds: 500));
    await capture('history-dark');
    await tester.tap(find.byType(BackButton));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('搜索栏目'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), programme.name);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.tap(find.byType(ProgrammeCard));
    await waitFor(() => find.byType(ArchivePage).evaluate().isNotEmpty);
    await capture('archive-dark');
    await tester.tap(find.byTooltip('批量下载'));
    await tester.pump(const Duration(milliseconds: 300));
    await capture('archive-selection-dark');
    expect(tester.takeException(), isNull);

    // Presentation-only fixtures exercise populated download cards without
    // starting a transfer or claiming native transfer validation.
    final fixture = _PresentationDownloads([
      for (final state in [
        DownloadState.running,
        DownloadState.completed,
        DownloadState.failed,
        DownloadState.missing,
      ])
        DownloadTask(
          id: state.name,
          attemptId: state.name,
          selection: ProgrammeSelection(
            programme: programme,
            broadcast: archive.controller.selectedDate!,
            content: playable,
          ),
          requestedQuality: VideoQuality.standard,
          quality: VideoQuality.standard,
          url: 'https://example.invalid/presentation.mp4',
          filename: 'presentation.mp4',
          wifiOnly: true,
          state: state,
          createdAt: DateTime(2026, 10, 17),
          receivedBytes: state == DownloadState.completed ? 83886080 : 33554432,
          totalBytes: 83886080,
          canResume: state == DownloadState.running,
          error: state == DownloadState.failed
              ? '网络连接中断，请重新下载。'
              : state == DownloadState.missing
              ? '文件已删除'
              : null,
        ),
    ]);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: ProviderScope(
            child: MaterialApp(
              key: ValueKey(brightness),
              theme: buildAppTheme(brightness),
              home: DownloadsPage(
                repository: fixture,
                onPlayLocal: (_) {},
                wifiPolicyLabel: Platform.isIOS ? '仅 Wi-Fi（禁用蜂窝网络）' : '仅 Wi-Fi',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await capture('downloads-fixture-${brightness.name}');
      await tester.scrollUntilVisible(find.text('播放'), 200);
      await capture('downloads-completed-${brightness.name}');
      await tester.scrollUntilVisible(find.text('已移除 · 1'), 200);
      await capture('downloads-removed-${brightness.name}');
      expect(find.text('文件已删除'), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 500));
  }, skip: !enabled);
}

class _PresentationDownloads implements DownloadRepository {
  _PresentationDownloads(this.tasks);
  final List<DownloadTask> tasks;
  @override
  Stream<List<DownloadTask>> watchTasks() => Stream.value(tasks);
  @override
  Future<void> reconcile() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
