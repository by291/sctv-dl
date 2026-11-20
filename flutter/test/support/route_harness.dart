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

import 'fakes.dart';

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

/// Creates a completed local download for route playback tests.
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

/// Supplies disposable dependencies for production routes and the app shell.
class RouteHarness {
  RouteHarness({this.notificationTaps = const Stream.empty()});

  final Stream<String> notificationTaps;

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
    notificationTaps: notificationTaps,
  );
  late final GoRouter router = createAppRouter(services);
  late final container = ProviderContainer(
    overrides: [servicesProvider.overrideWithValue(services)],
  );
  bool _closed = false;

  /// Mounts the router with a controllable presentation environment.
  Future<void> mount(
    WidgetTester tester,
    String location, {
    RouteLayout layout = const RouteLayout(),
  }) async {
    addTearDown(() => close(tester));
    router.go(location);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          restorationScopeId: 'route-tests',
          theme: ThemeData(
            platform: layout.platform,
            brightness: layout.brightness,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: layout.reducedMotion,
              textScaler: TextScaler.linear(layout.textScale),
            ),
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

  /// Unmounts the router before releasing the fake services.
  Future<void> close(WidgetTester tester) async {
    if (_closed) {
      return;
    }

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

/// Selects the platform, motion setting, brightness and text scaling for a route.
class RouteLayout {
  const RouteLayout({
    this.platform = TargetPlatform.android,
    this.reducedMotion = false,
    this.brightness = Brightness.light,
    this.textScale = 1,
  });

  final TargetPlatform platform;
  final bool reducedMotion;
  final Brightness brightness;
  final double textScale;
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
  final requests =
      <
        ({
          List<ProgrammeSelection> selections,
          VideoQuality quality,
          bool wifiOnly,
        })
      >[];
  final changes = StreamController<List<DownloadTask>>.broadcast();
  int subscriptions = 0;
  int reconciliations = 0;

  @override
  Future<List<DownloadTask>> loadTasks() async => tasks;

  @override
  Future<DownloadBatchResult> start(
    List<ProgrammeSelection> selections,
    VideoQuality quality, {
    required bool wifiOnly,
  }) async {
    requests.add((
      selections: selections,
      quality: quality,
      wifiOnly: wifiOnly,
    ));
    return const DownloadBatchResult(taskIds: ['new-task']);
  }

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
    if (loadError case final error?) {
      throw error;
    }

    return entries;
  }

  @override
  SaveViewingCheckpoint openSession(ContentRef ref) =>
      (entry) async => entries.add(entry);

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
