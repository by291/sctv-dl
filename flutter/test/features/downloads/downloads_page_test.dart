import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/design/cover_image.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_repository.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/downloads/downloads_page.dart';

Widget host({required Widget home, ThemeData? theme}) => ProviderScope(
  child: MaterialApp(home: home, theme: theme),
);

void main() {
  const selection = ProgrammeSelection(
    programme: Programme(id: '1', name: '四川新闻'),
    broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
    content: ProgrammeContent(id: '3', title: '四川新闻 20261016'),
  );
  DownloadTask task(
    DownloadState state, {
    bool resume = false,
    String id = '1',
    DateTime? createdAt,
  }) => DownloadTask(
    id: id,
    attemptId: 'a1',
    selection: selection,
    requestedQuality: VideoQuality.standard,
    quality: VideoQuality.standard,
    url: 'https://fscgc.scgchc.com/video.mp4',
    filename: 'video-a1.mp4',
    wifiOnly: true,
    state: state,
    createdAt: createdAt ?? DateTime(2026),
    canResume: resume,
    fileLocation: state == DownloadState.completed
        ? 'documents:Downloads/video.mp4'
        : null,
  );

  testWidgets('filters and task groups follow the same management order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = PageRepository([
      task(DownloadState.missing, id: 'removed'),
      task(DownloadState.cancelled, id: 'cancelled'),
      task(DownloadState.failed, id: 'failed'),
      task(DownloadState.paused, id: 'active').copyWith(totalBytes: 100),
      task(DownloadState.completed, id: 'completed'),
    ]);
    addTearDown(repository.close);

    await tester.pumpWidget(
      host(
        home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .map((chip) => (chip.label as Text).data),
      ['全部 5', '下载中 1', '已完成 1', '下载失败 1', '已取消 1', '已移除 1'],
    );
    final sectionLabels = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .where((text) => text?.contains(' · 1') ?? false);
    expect(sectionLabels, [
      '下载中 · 1',
      '已完成 · 1',
      '下载失败 · 1',
      '已取消 · 1',
      '已移除 · 1',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation order survives shuffled records and progress updates', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    DownloadTask transfer(String id, DateTime createdAt, int receivedBytes) =>
        task(DownloadState.running, id: id, createdAt: createdAt).copyWith(
          totalBytes: 100,
          receivedBytes: receivedBytes,
          selection: ProgrammeSelection(
            programme: selection.programme,
            broadcast: selection.broadcast,
            content: ProgrammeContent(id: id, title: 'Transfer $id'),
          ),
        );
    final oldest = transfer('oldest', DateTime(2026, 10, 16), 90);
    final sameTimeB = transfer('b', DateTime(2026, 10, 17), 60);
    final newest = transfer('newest', DateTime(2026, 10, 18), 10);
    final sameTimeA = transfer('a', DateTime(2026, 10, 17), 20);
    final repository = PageRepository([oldest, sameTimeB, newest, sameTimeA]);
    addTearDown(repository.close);
    Iterable<String?> visibleTitles() => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .where((text) => text?.startsWith('Transfer ') ?? false);
    const expected = [
      'Transfer newest',
      'Transfer a',
      'Transfer b',
      'Transfer oldest',
    ];

    await tester.pumpWidget(
      host(
        home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(visibleTitles(), expected);
    expect(repository.tasks.map((task) => task.id), [
      'oldest',
      'b',
      'newest',
      'a',
    ]);

    repository.changes.add([
      sameTimeB.copyWith(receivedBytes: 70, revision: 7),
      sameTimeA.copyWith(receivedBytes: 95, revision: 50),
      oldest.copyWith(receivedBytes: 98, revision: 100),
      newest.copyWith(receivedBytes: 15, revision: 1),
    ]);
    await tester.pumpAndSettle();

    expect(visibleTitles(), expected);
    await tester.tap(find.byKey(const ValueKey('download-filter-active')));
    await tester.pumpAndSettle();
    expect(visibleTitles(), expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter selection removes only visible records and keeps files', (
    tester,
  ) async {
    final repository = PageRepository([
      task(DownloadState.completed, id: 'done'),
      task(DownloadState.missing, id: 'gone'),
      task(DownloadState.running, id: 'running').copyWith(totalBytes: 1000),
    ]);
    await tester.pumpWidget(
      host(
        home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final removed = find.byKey(const ValueKey('download-filter-removed'));
    await tester.ensureVisible(removed);
    await tester.tap(removed);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选当前列表'));
    await tester.pumpAndSettle();
    expect(find.byType(CoverImage), findsOneWidget);
    await tester.tap(find.byTooltip('批量操作'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除视频文件'), findsNothing);
    await tester.tap(find.text('移除记录 · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '移除记录'));
    await tester.pumpAndSettle();
    expect(repository.removed, ['gone']);
    expect(repository.deleted, isEmpty);
    expect(repository.tasks.map((task) => task.id), ['done', 'running']);
    expect(find.text('没有符合筛选的任务'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('batch deletion requires confirmation and preserves records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = PageRepository([task(DownloadState.completed)]);
    await tester.pumpWidget(
      host(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选当前列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除视频文件 · 1'));
    await tester.pumpAndSettle();
    expect(repository.deleted, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, '删除文件'));
    await tester.pumpAndSettle();
    expect(repository.deleted, ['1']);
    expect(repository.removed, isEmpty);
    expect(repository.tasks.single.state, DownloadState.missing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('deleted files have their own group and no failure alert', (
    tester,
  ) async {
    final repository = PageRepository([
      task(DownloadState.missing).copyWith(error: '文件已删除'),
    ]);
    await tester.pumpWidget(
      host(
        home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('已移除 · 1'), findsOneWidget);
    expect(find.text('下载失败 · 1'), findsNothing);
    expect(find.text('文件已删除'), findsNothing);
    expect(find.text('重新下载'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('filter changes clear selection and restore each list position', (
    tester,
  ) async {
    final repository = PageRepository([
      for (var i = 0; i < 20; i++) task(DownloadState.completed, id: '$i'),
      task(DownloadState.missing, id: 'gone'),
    ]);
    await tester.pumpWidget(
      host(
        home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -600));
    await tester.pumpAndSettle();
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    final offset = position().pixels;
    expect(offset, greaterThan(0));
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选当前列表'));
    await tester.pumpAndSettle();
    final removed = find.byKey(const ValueKey('download-filter-removed'));
    await tester.ensureVisible(removed);
    await tester.tap(removed);
    await tester.pumpAndSettle();
    expect(find.text('已选择 0 项'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
    final all = find.byKey(const ValueKey('download-filter-all'));
    await tester.ensureVisible(all);
    await tester.tap(all);
    await tester.pumpAndSettle();
    expect(position().pixels, offset);
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets(
    'completed cards keep file actions reachable without transfer-only policy',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = PageRepository([
        task(DownloadState.completed).copyWith(
          receivedBytes: 224080691,
          selection: const ProgrammeSelection(
            programme: Programme(id: '1', name: '现场快报'),
            broadcast: BroadcastDate(id: '2', date: '2026-10-17'),
            content: ProgrammeContent(id: '3', title: '市场监管总局启动智慧计量监管试点'),
          ),
        ),
      ]);
      DownloadTask? played;
      await tester.pumpWidget(
        host(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: DownloadsPage(
              repository: repository,
              onPlayLocal: (task) => played = task,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CoverImage), findsOneWidget);
      expect(find.textContaining('Wi-Fi'), findsNothing);
      await tester.ensureVisible(find.text('播放'));
      await tester.tap(find.text('播放'));
      await tester.pumpAndSettle();
      expect(played?.id, '1');
      await tester.ensureVisible(find.byTooltip('文件操作'));
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      expect(find.text('分享视频'), findsOneWidget);
      expect(find.text('删除视频文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );

  testWidgets(
    'download header survives empty and observation error states with retry',
    (tester) async {
      final repository = PageRepository([]);
      await tester.pumpWidget(
        host(
          home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
        ),
      );
      await tester.pump();
      expect(find.text('下载'), findsOneWidget);
      repository.changes.addError(StateError('storage unavailable'));
      await tester.pump();
      expect(find.text('下载'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('还没有下载任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );

  testWidgets(
    'native list removal clears selection before the record reappears',
    (tester) async {
      final completed = task(DownloadState.completed);
      final repository = PageRepository([completed]);
      await tester.pumpWidget(
        host(
          home: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('批量管理'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全选当前列表'));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 项'), findsOneWidget);

      repository.changes.add([]);
      await tester.pumpAndSettle();
      expect(find.text('已选择 0 项'), findsOneWidget);
      repository.changes.add([completed]);
      await tester.pumpAndSettle();
      expect(find.text('已选择 0 项'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );

  testWidgets('download actions avoid horizontal cutouts', (tester) async {
    final repository = PageRepository([
      task(DownloadState.running, resume: true),
    ]);
    await tester.pumpWidget(
      host(
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(left: 80, right: 80),
          ),
          child: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(
      tester.getTopLeft(find.text(selection.content.title)).dx,
      greaterThanOrEqualTo(80),
    );
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });

  testWidgets('populated downloads respect the status bar and display cutout', (
    tester,
  ) async {
    final repository = PageRepository([task(DownloadState.running)]);
    await tester.pumpWidget(
      host(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(top: 44)),
          child: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('下载')).dy, greaterThanOrEqualTo(44));
    await tester.pumpWidget(const SizedBox());
    await repository.close();
  });
  testWidgets(
    'unknown totals show indeterminate progress and hide unsupported pause',
    (tester) async {
      final repository = PageRepository([task(DownloadState.running)]);
      await tester.pumpWidget(
        host(
          home: Scaffold(
            body: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
      );
      expect(find.byTooltip('暂停'), findsNothing);
      expect(find.textContaining('仅 Wi-Fi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );
  testWidgets(
    'large text and narrow layouts keep publication retry reachable',
    (tester) async {
      final repository = PageRepository([
        task(DownloadState.finalizing).copyWith(error: '空间不足'),
      ]);
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: DownloadsPage(repository: repository, onPlayLocal: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('重试发布'), findsOneWidget);
      expect(find.text('空间不足'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('重试发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试发布'));
      await tester.pump();
      expect(repository.published, '1');
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );
  testWidgets(
    'completed local playback rechecks availability and export cancellation stays quiet',
    (tester) async {
      final repository = PageRepository([task(DownloadState.completed)]);
      DownloadTask? played;
      await tester.pumpWidget(
        host(
          home: Scaffold(
            body: DownloadsPage(
              repository: repository,
              onPlayLocal: (task) => played = task,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('播放'));
      await tester.pump();
      expect(played?.id, '1');
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('存储到“文件”'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await repository.close();
    },
  );
}

class PageRepository implements DownloadRepository {
  PageRepository(this.tasks);
  final List<DownloadTask> tasks;
  final changes = StreamController<List<DownloadTask>>.broadcast();
  String? published;
  final removed = <String>[];
  final deleted = <String>[];
  @override
  Future<void> remove(String id) async {
    removed.add(id);
    tasks.removeWhere((task) => task.id == id);
    changes.add(List.of(tasks));
  }

  @override
  Future<void> deleteFile(String id) async {
    deleted.add(id);
    final index = tasks.indexWhere((task) => task.id == id);
    tasks[index] = tasks[index].copyWith(
      state: DownloadState.missing,
      fileLocation: null,
    );
    changes.add(List.of(tasks));
  }

  @override
  Future<List<DownloadTask>> loadTasks() async => tasks;
  @override
  Stream<List<DownloadTask>> watchTasks() async* {
    yield tasks;
    yield* changes.stream;
  }

  @override
  Future<void> publish(String id) async {
    published = id;
  }

  @override
  Future<void> reconcile() async {}
  @override
  Future<bool> exportFile(String id) async => false;
  @override
  Future<void> dispose() async {}
  Future<void> close() => changes.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
