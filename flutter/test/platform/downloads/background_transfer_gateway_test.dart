import 'dart:async';

import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/downloads/media_probe.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';
import 'package:sctv_dl_mobile/platform/downloads/background_transfer_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const selection = ProgrammeSelection(
    programme: Programme(id: '1', name: 'Test'),
    broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
    content: ProgrammeContent(id: '3', title: 'Title'),
  );
  DownloadTask task(String url) => DownloadTask(
    id: 'record',
    attemptId: 'attempt',
    selection: selection,
    requestedQuality: VideoQuality.standard,
    quality: VideoQuality.standard,
    url: url,
    filename: 'Title-standard-attempt.mp4',
    wifiOnly: true,
    state: DownloadState.preparing,
    createdAt: DateTime(2026),
  );

  test('native request keeps preallocated identity, media headers and network policy', () {
    final gateway = BackgroundTransferGateway(isIOS: false);
    final request = gateway.buildNativeTask(
      task('https://fscgc.scgchc.com/video.mp4'),
    );
    expect(request.taskId, 'attempt');
    expect(request.headers['Referer'], 'https://scgc.video.play/');
    expect(request.headers['User-Agent'], 'okhttp/4.12.0');
    expect(request.headers.keys, unorderedEquals(['Referer', 'User-Agent']));
    expect(request.baseDirectory, native.BaseDirectory.applicationSupport);
    expect(request.requiresWiFi, isTrue);
    expect(request.priority, 0);
    expect(request.retries, 2);
    expect(request.allowPause, isTrue);
  });
  test('iOS destinations use relative Documents Downloads references', () {
    final gateway = BackgroundTransferGateway(isIOS: true);
    final request = gateway.buildNativeTask(
      task('https://fscgc.sctv-tf.com/video.mp4'),
    );
    expect(request.baseDirectory, native.BaseDirectory.applicationDocuments);
    expect(request.directory, 'Downloads');
  });
  test(
    'concurrent retry after configuration failure retains callback ownership',
    () async {
      final engine = FailOnceDownloader();
      final gateway = BackgroundTransferGateway(downloader: engine);
      final events = <Object>[];
      final listener = gateway.events.listen(events.add);
      await expectLater(gateway.initialize(), throwsStateError);
      await Future.wait([gateway.initialize(), gateway.initialize()]);
      final nativeTask = gateway.buildNativeTask(
        task('https://fscgc.scgchc.com/video.mp4'),
      );
      engine.statusCallback!(
        native.TaskStatusUpdate(nativeTask, native.TaskStatus.enqueued),
      );
      expect(events, hasLength(1));
      expect(engine.configureCalls, 2);
      expect(engine.resumeCalls, 1);
      await listener.cancel();
      await gateway.dispose();
      expect(engine.statusCallback, isNull);
    },
  );
  test(
    'initial transfers reject arbitrary hosts before reaching the plugin',
    () {
      final gateway = BackgroundTransferGateway();
      expect(
        () => gateway.buildNativeTask(task('https://example.com/video.mp4')),
        throwsArgumentError,
      );
    },
  );
  test(
    'all disposal callers wait for outstanding observers to close',
    () async {
      final gateway = BackgroundTransferGateway();
      final observation = gateway.events.listen((_) {});
      observation.pause();
      addTearDown(observation.cancel);

      final first = gateway.dispose();
      final second = gateway.dispose();
      var isFirstDone = false;
      var isSecondDone = false;
      unawaited(first.then((_) => isFirstDone = true));
      unawaited(second.then((_) => isSecondDone = true));
      await Future<void>.delayed(Duration.zero);

      final completedWhilePaused = [isFirstDone, isSecondDone];
      observation.resume();
      await Future.wait([first, second]);

      expect(completedWhilePaused, [false, false]);
    },
  );

  test(
    'notification observers close even if the media probe fails to close',
    () async {
      final failure = StateError('Media probe could not close');
      final probe = DelayedProbe()..disposalFailure = failure;
      final gateway = BackgroundTransferGateway(mediaProbe: probe);
      final eventsClosed = gateway.events.drain<void>();
      final notificationsClosed = gateway.notificationTaps.drain<void>();

      await expectLater(gateway.dispose(), throwsA(same(failure)));

      await Future.wait([eventsClosed, notificationsClosed])
          .timeout(const Duration(seconds: 2));
    },
  );

  test(
    'cancelled preflight ignores a late success without native enqueue',
    () async {
      final probe = DelayedProbe();
      final gateway = BackgroundTransferGateway(mediaProbe: probe);
      final pending = gateway.enqueue(
        task('https://fscgc.scgchc.com/video.mp4'),
      );
      final rejected = expectLater(pending, throwsA(isA<RequestCancelled>()));
      await probe.entered.future;
      expect(await gateway.cancel('attempt'), isTrue);
      probe.release.complete();
      await rejected;
      expect(probe.scope!.isCancelled, isTrue);
      await gateway.dispose();
    },
  );
}

class DelayedProbe implements DownloadMediaProbe {
  final entered = Completer<void>();
  final release = Completer<void>();
  RequestScope? scope;
  Object? disposalFailure;
  @override
  Future<void> validate(String url, {required RequestScope scope}) async {
    this.scope = scope;
    entered.complete();
    await release.future;
  }

  @override
  void dispose() {
    if (disposalFailure case final failure?) {
      throw failure;
    }
  }
}

class FailOnceDownloader implements native.FileDownloader {
  int configureCalls = 0;
  int resumeCalls = 0;
  native.TaskStatusCallback? statusCallback;
  @override
  native.FileDownloader registerCallbacks({
    String group = native.FileDownloader.defaultGroup,
    native.TaskStatusCallback? taskStatusCallback,
    native.TaskProgressCallback? taskProgressCallback,
    native.TaskNotificationTapCallback? taskNotificationTapCallback,
  }) {
    statusCallback = taskStatusCallback;
    return this;
  }

  @override
  native.FileDownloader unregisterCallbacks({
    String group = native.FileDownloader.defaultGroup,
    Function? callback,
  }) {
    statusCallback = null;
    return this;
  }

  @override
  native.FileDownloader configureNotificationForGroup(
    String group, {
    native.TaskNotification? running,
    native.TaskNotification? complete,
    native.TaskNotification? error,
    native.TaskNotification? paused,
    native.TaskNotification? canceled,
    bool progressBar = false,
    bool tapOpensFile = false,
    String groupNotificationId = '',
  }) => this;
  @override
  Future<List<(String, String)>> configure({
    dynamic globalConfig,
    dynamic androidConfig,
    dynamic iOSConfig,
    dynamic desktopConfig,
  }) async {
    configureCalls++;
    if (configureCalls == 1) {
      throw StateError('native configuration unavailable');
    }
    return [];
  }

  @override
  Future<native.FileDownloader> trackTasksInGroup(
    String group, {
    bool markDownloadedComplete = true,
  }) async => this;
  @override
  Future<void> resumeFromBackground() async {
    resumeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
