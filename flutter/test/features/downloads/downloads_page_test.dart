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
  DownloadTask task(DownloadState state, {bool resume = false}) => DownloadTask(
    id: '1',
    attemptId: 'a1',
    selection: selection,
    requestedQuality: VideoQuality.standard,
    quality: VideoQuality.standard,
    url: 'https://fscgc.scgchc.com/video.mp4',
    filename: 'video-a1.mp4',
    wifiOnly: true,
    state: state,
    createdAt: DateTime(2026),
    canResume: resume,
    fileLocation: state == DownloadState.completed
        ? 'documents:Downloads/video.mp4'
        : null,
  );

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
