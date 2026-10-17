import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sctv_dl_mobile/app/providers.dart';
import 'package:sctv_dl_mobile/app/router.dart';
import 'package:sctv_dl_mobile/app/services.dart';
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

  Future<void> mount(WidgetTester tester, String location) async {
    addTearDown(() => close(tester));
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          restorationScopeId: 'route-tests',
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
