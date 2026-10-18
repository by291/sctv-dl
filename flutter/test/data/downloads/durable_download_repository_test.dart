import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/downloads/durable_download_repository.dart';
import 'package:sctv_dl_mobile/data/downloads/sqlite_download_task_store.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_repository.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/downloads/file_gateway.dart';
import 'package:sctv_dl_mobile/domain/downloads/transfer_gateway.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

const selection = ProgrammeSelection(
  programme: Programme(id: '1', name: '四川新闻'),
  broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
  content: ProgrammeContent(
    id: '3',
    title: '四川新闻20261016',
    video: 'https://fscgc.scgchc.com/video/example.mp4',
  ),
);

void main() {
  late RecordDatabase database;
  late SqliteDownloadTaskStore store;
  late FakeTransfers transfers;
  late FakeFiles files;
  late DurableDownloadRepository repository;
  var serial = 0;

  setUp(() {
    database = RecordDatabase.memory();
    store = SqliteDownloadTaskStore(database);
    transfers = FakeTransfers();
    files = FakeFiles();
    repository = DurableDownloadRepository(
      store: store,
      transfers: transfers,
      files: files,
      createId: () => 'id-${serial++}',
    );
  });
  tearDown(() async {
    await repository.dispose();
    await transfers.controller.close();
    await database.close();
  });

  Future<DownloadTask> start() async {
    final result = await repository.start(
      [selection],
      VideoQuality.standard,
      wifiOnly: true,
    );
    expect(result.failures, isEmpty);
    return (await repository.loadTasks()).singleWhere(
      (task) => task.id == result.taskIds.single,
    );
  }

  Future<void> event(
    DownloadTask task,
    DownloadState state, {
    int received = 0,
    int? total,
    bool canResume = false,
  }) async {
    transfers.emit(
      TransferSnapshot(
        attemptId: task.attemptId,
        state: state,
        receivedBytes: received,
        totalBytes: total,
        canResume: canResume,
        fileLocation: state == DownloadState.finalizing
            ? 'support:downloads/${task.filename}'
            : null,
      ),
    );
    await repository.loadTasks();
    if (state == DownloadState.finalizing) {
      await repository.watchTasks().firstWhere((tasks) {
        final current = tasks.singleWhere((value) => value.id == task.id);
        return current.attemptId != task.attemptId ||
            current.state != DownloadState.finalizing &&
                (current.privateLocation == null || current.error != null) ||
            current.state == DownloadState.finalizing && current.error != null;
      });
      // Observe claim release after the final durable state notification.
      await repository.loadTasks();
    }
  }

  test(
    'new observers and concurrent loads recover a failed store bootstrap once',
    () async {
      final task = await start();
      await repository.dispose();
      final recovering = FailOnceStore(store)..readFailures = 1;
      repository = DurableDownloadRepository(
        store: recovering,
        transfers: transfers,
        files: files,
      );
      await expectLater(repository.loadTasks(), throwsStateError);
      final snapshots = await Future.wait([
        repository.loadTasks(),
        repository.loadTasks(),
        repository.watchTasks().first,
      ]);
      expect(snapshots.every((tasks) => tasks.single.id == task.id), isTrue);
      expect(recovering.reads, 2);
      expect(transfers.enqueued, hasLength(1));
      expect(transfers.eventStreamAccesses, 2);
    },
  );

  test('native terminal events received before storage recovery survive a stale snapshot', () async {
    final task = await start();
    await repository.dispose();
    repository = DurableDownloadRepository(
      store: FailOnceStore(store)..readFailures = 1,
      transfers: transfers,
      files: files,
    );
    await expectLater(repository.loadTasks(), throwsStateError);
    transfers.emit(
      TransferSnapshot(
        attemptId: task.attemptId,
        state: DownloadState.failed,
        error: 'native terminal failure',
      ),
    );
    transfers.snapshots[task.attemptId] = TransferSnapshot(
      attemptId: task.attemptId,
      state: DownloadState.queued,
    );
    await Future<void>.delayed(Duration.zero);
    expect((await repository.loadTasks()).single.state, DownloadState.failed);
  });

  test('a failed recovery write keeps its buffered terminal event for the next retry', () async {
    final task = await start();
    await repository.dispose();
    final failing = FailOnceStore(store)
      ..readFailures = 1
      ..saveFailureState = DownloadState.failed;
    repository = DurableDownloadRepository(
      store: failing,
      transfers: transfers,
      files: files,
    );
    await expectLater(repository.loadTasks(), throwsStateError);
    transfers.emit(
      TransferSnapshot(attemptId: task.attemptId, state: DownloadState.failed),
    );
    transfers.snapshots[task.attemptId] = TransferSnapshot(
      attemptId: task.attemptId,
      state: DownloadState.queued,
    );
    await Future<void>.delayed(Duration.zero);
    await expectLater(repository.loadTasks(), throwsStateError);
    expect((await repository.loadTasks()).single.state, DownloadState.failed);
    expect(failing.reads, 2);
  });

  test('reconciliation retries a failed native bootstrap query without resubmitting', () async {
    final task = await start();
    await repository.dispose();
    transfers.queryFailures = 1;
    repository = DurableDownloadRepository(
      store: store,
      transfers: transfers,
      files: files,
    );
    await expectLater(repository.loadTasks(), throwsStateError);
    await repository.reconcile();
    expect((await repository.watchTasks().first).single.id, task.id);
    expect(transfers.enqueued, hasLength(1));
    expect(transfers.eventStreamAccesses, 2);
  });

  test(
    'publication keeps its private source until completed state commits',
    () async {
      final task = await start();
      await repository.dispose();
      final failing = FailOnceStore(store)
        ..saveFailureState = DownloadState.completed;
      repository = DurableDownloadRepository(
        store: failing,
        transfers: transfers,
        files: files,
      );
      await repository.loadTasks();
      await event(task, DownloadState.finalizing);
      expect((await store.load()).single.state, DownloadState.finalizing);
      expect((await store.load()).single.privateLocation, isNotNull);
      expect(files.deletedLocations, isEmpty);
      await repository.publish(task.id);
      final completed = (await store.load()).single;
      expect(completed.state, DownloadState.completed);
      expect(completed.privateLocation, isNull);
      expect(files.deletedLocations, ['support:downloads/${task.filename}']);
      expect(transfers.enqueued, hasLength(1));
    },
  );

  test(
    'cleanup failure retains completed URI and retries only the private copy',
    () async {
      final task = await start();
      files.deletionFailure = StateError('private cleanup failed');
      await event(task, DownloadState.finalizing);
      var current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.completed);
      expect(current.privateLocation, isNotNull);
      expect(current.fileLocation, startsWith('content:'));
      files.deletionFailure = null;
      await repository.reconcile();
      current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.completed);
      expect(current.privateLocation, isNull);
      expect(files.deletedLocations, ['support:downloads/${task.filename}']);
      expect((await files.inspect(current.fileLocation!)).exists, isTrue);
    },
  );

  test('iOS completed location clears the private pointer without deleting its video', () async {
    final task = await start();
    files.publishInPlace = true;
    await event(task, DownloadState.finalizing);
    final current = (await repository.loadTasks()).single;
    expect(current.state, DownloadState.completed);
    expect(current.privateLocation, isNull);
    expect(files.deletedLocations, isEmpty);
    expect((await files.inspect(current.fileLocation!)).exists, isTrue);
  });

  test(
    'disposal waits for initialization before releasing shared dependencies',
    () async {
      await repository.dispose();
      final entered = Completer<void>();
      final release = Completer<void>();
      transfers.initializationEntered = entered;
      transfers.initializationGate = release;
      repository = DurableDownloadRepository(
        store: store,
        transfers: transfers,
        files: files,
      );
      await entered.future;
      var disposed = false;
      final disposal = repository.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      release.complete();
      await disposal;
      expect(disposed, isTrue);
    },
  );

  test(
    'reserves before enqueue and rejects concurrent duplicate actual quality',
    () async {
      transfers.onEnqueue = (task) async {
        expect((await store.load()).single.attemptId, task.attemptId);
      };
      final results = await Future.wait([
        repository.start([selection], VideoQuality.standard, wifiOnly: true),
        repository.start([selection], VideoQuality.smooth, wifiOnly: false),
      ]);
      expect(results.expand((r) => r.taskIds), hasLength(1));
      expect(results.fold(0, (n, r) => n + r.duplicates), 1);
      expect((await repository.loadTasks()).single.wifiOnly, isTrue);
    },
  );

  test('preserves accepted members when one batch item has no media', () async {
    const unavailable = ProgrammeSelection(
      programme: Programme(id: '1', name: 'Test'),
      broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
      content: ProgrammeContent(id: '4', title: 'Unavailable'),
    );
    final result = await repository.start(
      [selection, unavailable],
      VideoQuality.smooth,
      wifiOnly: false,
    );
    expect(result.taskIds, hasLength(1));
    expect(result.fallbacks, 1);
    expect(result.failures.single.contentId, '4');
  });

  test(
    'a media preparation failure leaves other batch members accepted',
    () async {
      const other = ProgrammeSelection(
        programme: Programme(id: '1', name: 'Test'),
        broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
        content: ProgrammeContent(
          id: '4',
          title: 'Other',
          video: 'https://fscgc.scgchc.com/other.mp4',
        ),
      );
      transfers.onEnqueue = (task) async {
        if (task.selection.content.id == '3') {
          throw StateError('media probe failed');
        }
      };
      final result = await repository.start(
        [selection, other],
        VideoQuality.standard,
        wifiOnly: false,
      );
      expect(result.taskIds, hasLength(1));
      expect(result.failures.single.contentId, '3');
      final tasks = await repository.loadTasks();
      expect(
        tasks.singleWhere((task) => task.selection.content.id == '3').state,
        DownloadState.failed,
      );
      expect(
        tasks.singleWhere((task) => task.selection.content.id == '4').state,
        DownloadState.queued,
      );
    },
  );

  test(
    'ambiguous enqueue joins the existing native attempt without resubmitting',
    () async {
      transfers.onEnqueue = (task) async {
        transfers.snapshots[task.attemptId] = TransferSnapshot(
          attemptId: task.attemptId,
          state: DownloadState.running,
          receivedBytes: 12,
          totalBytes: 120,
        );
        throw const TransferEnqueueException('platform reply was lost');
      };
      final result = await repository.start(
        [selection],
        VideoQuality.standard,
        wifiOnly: false,
      );
      expect(result.failures, isEmpty);
      expect(result.taskIds, hasLength(1));
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.running,
      );
      expect(transfers.enqueued, hasLength(1));
    },
  );

  test(
    'cancellation during enqueue never revives the cancelled task',
    () async {
      final release = Completer<void>();
      final entered = Completer<void>();
      transfers.onEnqueue = (_) async {
        entered.complete();
        await release.future;
      };
      final submitted = repository.start(
        [selection],
        VideoQuality.standard,
        wifiOnly: true,
      );
      await entered.future;
      final task = (await repository.loadTasks()).single;
      await repository.cancel(task.id);
      release.complete();
      await submitted;
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.cancelled,
      );
      expect(transfers.cancelled, contains(task.attemptId));
    },
  );

  test(
    'retry changes identity and rejects completion from an older attempt',
    () async {
      final original = await start();
      await event(original, DownloadState.failed);
      await repository.retry(original.id);
      final replacement = (await repository.loadTasks()).single;
      expect(replacement.attemptId, isNot(original.attemptId));
      await event(original, DownloadState.finalizing);
      expect((await repository.loadTasks()).single.state, DownloadState.queued);
    },
  );

  test('failed retry cleanup preserves the attempt that still owns native artifacts', () async {
    final original = await start();
    await event(original, DownloadState.failed);
    files.cleanupFailure = StateError('disk unavailable');
    await expectLater(repository.retry(original.id), throwsStateError);
    final current = (await repository.loadTasks()).single;
    expect(current.attemptId, original.attemptId);
    expect(current.state, DownloadState.failed);
    expect(transfers.enqueued, hasLength(1));
  });

  test(
    'terminal completion cannot regress to a late running callback',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing, received: 120);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );
      await event(task, DownloadState.running, received: 10, total: 120);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );
    },
  );

  test(
    'unknown totals stay unknown and completion uses actual file size',
    () async {
      final task = await start();
      await event(task, DownloadState.running, received: 34);
      expect((await repository.loadTasks()).single.totalBytes, isNull);
      await event(task, DownloadState.finalizing);
      final complete = (await repository.loadTasks()).single;
      expect(complete.receivedBytes, 120);
      expect(complete.totalBytes, 120);
    },
  );

  test(
    'publication failure retains staging file and retries without enqueue',
    () async {
      final task = await start();
      files.publicationFailure = StateError('disk full');
      await event(task, DownloadState.finalizing);
      var current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.finalizing);
      expect(current.privateLocation, isNotNull);
      expect(current.error, contains('disk full'));
      files.publicationFailure = null;
      await repository.publish(task.id);
      current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.completed);
      expect(transfers.enqueued, hasLength(1));
    },
  );

  test(
    'snapshot cannot overwrite a newer event that arrived during query',
    () async {
      final task = await start();
      final release = Completer<Map<String, TransferSnapshot>>();
      transfers.pendingQuery = release;
      final reconciliation = repository.reconcile();
      await Future<void>.delayed(Duration.zero);
      await event(task, DownloadState.running, received: 80, total: 120);
      release.complete({
        task.attemptId: TransferSnapshot(
          attemptId: task.attemptId,
          state: DownloadState.queued,
        ),
      });
      await reconciliation;
      final current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.running);
      expect(current.receivedBytes, 80);
    },
  );

  test(
    'unowned missing native tasks become interrupted without reenqueuing',
    () async {
      await start();
      transfers.snapshots.clear();
      await repository.reconcile();
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.interrupted,
      );
      expect(transfers.enqueued, hasLength(1));
    },
  );

  test(
    'recovery joins a persisted preallocated attempt instead of reenqueuing',
    () async {
      final task = await start();
      await repository.dispose();
      repository = DurableDownloadRepository(
        store: store,
        transfers: transfers,
        files: files,
      );
      expect((await repository.loadTasks()).single.attemptId, task.attemptId);
      expect(transfers.enqueued, hasLength(1));
    },
  );

  test(
    'unsupported resume reports interruption without pretending success',
    () async {
      final task = await start();
      await event(task, DownloadState.paused, received: 25, canResume: true);
      transfers.resumeAccepted = false;
      await expectLater(repository.resume(task.id), throwsStateError);
      final current = (await repository.loadTasks()).single;
      expect(current.state, DownloadState.interrupted);
      expect(current.error, isNotNull);
    },
  );

  test(
    'externally removed videos become missing before file actions',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      files.exists = false;
      await expectLater(repository.openFile(task.id), throwsStateError);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.missing,
      );
    },
  );

  test(
    'removing records keeps files while failed deletion retains truthful state',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      files.deletionFailure = StateError('permission denied');
      await expectLater(repository.deleteFile(task.id), throwsStateError);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );
      await repository.remove(task.id);
      expect(await repository.loadTasks(), isEmpty);
      expect(files.exists, isTrue);
    },
  );

  test(
    'explicit reconciliation joins an outstanding file inspection',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      final entered = Completer<void>();
      final gate = Completer<FileDetails>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete(const FileDetails(exists: false));
      });
      files.onInspect = (_) {
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };

      final first = repository.reconcile();
      await entered.future;
      var secondFinished = false;
      final second = repository.reconcile().then((_) => secondFinished = true);
      await Future<void>.delayed(Duration.zero);
      expect(secondFinished, isFalse);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );

      gate.complete(const FileDetails(exists: false));
      await Future.wait([first, second]);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.missing,
      );
    },
  );

  test(
    'concurrent reconciliations share file work without stream errors',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      final errors = <Object>[];
      final observation = repository.watchTasks().listen(
        (_) {},
        onError: errors.add,
      );
      addTearDown(observation.cancel);
      final entered = Completer<void>();
      final gate = Completer<FileDetails>();
      addTearDown(() {
        if (!gate.isCompleted) {
          gate.complete(const FileDetails(exists: true, bytes: 120));
        }
      });
      var inspections = 0;
      files.onInspect = (_) {
        inspections++;
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      transfers.pendingQuery = Completer<Map<String, TransferSnapshot>>();

      final first = repository.reconcile();
      final second = repository.reconcile();
      final joined = Future.wait([first, second]);
      unawaited(joined.catchError((Object _) => <void>[]));
      await Future<void>.delayed(Duration.zero);
      transfers.pendingQuery!.complete(Map.of(transfers.snapshots));
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
      gate.complete(const FileDetails(exists: true, bytes: 120));
      await joined;
      expect(inspections, 1);
    },
  );

  test('export picker does not block task observation', () async {
    final task = await start();
    await event(task, DownloadState.finalizing);
    files.exportEntered = Completer<void>();
    files.exportGate = Completer<bool>();
    addTearDown(() {
      if (!files.exportGate!.isCompleted) files.exportGate!.complete(false);
    });
    final exporting = repository.exportFile(task.id);
    await files.exportEntered!.future;
    var observed = false;
    final loading = repository.loadTasks().then((_) => observed = true);
    await Future<void>.delayed(Duration.zero);
    final observedWhileExporting = observed;
    files.exportGate!.complete(false);
    expect(await exporting, isFalse);
    await loading;
    expect(observedWhileExporting, isTrue);
  });

  test('publication does not block task observation', () async {
    final task = await start();
    files.publicationEntered = Completer<void>();
    files.publicationGate = Completer<void>();
    addTearDown(() {
      if (!files.publicationGate!.isCompleted) {
        files.publicationGate!.complete();
      }
    });
    transfers.emit(
      TransferSnapshot(
        attemptId: task.attemptId,
        state: DownloadState.finalizing,
        fileLocation: 'support:downloads/${task.filename}',
      ),
    );
    await files.publicationEntered!.future;
    var observed = false;
    final loading = repository.loadTasks().then((tasks) {
      observed = true;
      return tasks;
    });
    await Future<void>.delayed(Duration.zero);
    final observedWhilePublishing = observed;
    files.publicationGate!.complete();
    final tasks = await loading;
    expect(observedWhilePublishing, isTrue);
    expect(tasks.single.state, DownloadState.finalizing);
  });

  test(
    'file claims reject removal and conflicting actions until export ends',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      files.exportEntered = Completer<void>();
      files.exportGate = Completer<bool>();
      addTearDown(() {
        if (!files.exportGate!.isCompleted) files.exportGate!.complete(false);
      });
      final exporting = repository.exportFile(task.id);
      await files.exportEntered!.future;
      var removalRejected = false;
      final removing = repository.remove(task.id).catchError((Object _) {
        removalRejected = true;
      });
      var deletionRejected = false;
      final deleting = repository.deleteFile(task.id).catchError((Object _) {
        deletionRejected = true;
      });
      await Future<void>.delayed(Duration.zero);
      final rejectedWhileExporting = removalRejected && deletionRejected;
      files.exportGate!.complete(false);
      await exporting;
      await Future.wait([removing, deleting]);
      expect(rejectedWhileExporting, isTrue);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );
      await repository.remove(task.id);
      expect(await repository.loadTasks(), isEmpty);
    },
  );

  test(
    'disposal drains native export effects before dependencies close',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      files.exportEntered = Completer<void>();
      files.exportGate = Completer<bool>();
      addTearDown(() {
        if (!files.exportGate!.isCompleted) files.exportGate!.complete(false);
      });
      final exporting = repository.exportFile(task.id);
      await files.exportEntered!.future;
      var disposed = false;
      final disposal = repository.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      files.exportGate!.complete(false);
      await exporting;
      await disposal;
      expect(disposed, isTrue);
    },
  );

  test(
    'a stalled publication leaves unrelated native progress observable',
    () async {
      final publishing = await start();
      const other = ProgrammeSelection(
        programme: Programme(id: '1', name: 'Test'),
        broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
        content: ProgrammeContent(
          id: '4',
          title: 'Other',
          video: 'https://fscgc.scgchc.com/other.mp4',
        ),
      );
      await repository.start([other], VideoQuality.standard, wifiOnly: false);
      final running = (await repository.loadTasks()).singleWhere(
        (task) => task.id != publishing.id,
      );
      files.publicationEntered = Completer<void>();
      files.publicationGate = Completer<void>();
      addTearDown(() {
        if (!files.publicationGate!.isCompleted) {
          files.publicationGate!.complete();
        }
      });
      transfers.emit(
        TransferSnapshot(
          attemptId: publishing.attemptId,
          state: DownloadState.finalizing,
          fileLocation: 'support:downloads/${publishing.filename}',
        ),
      );
      await files.publicationEntered!.future;
      final observation = repository.watchTasks().firstWhere(
        (tasks) => tasks.any(
          (task) => task.id == running.id && task.receivedBytes == 48,
        ),
      );
      transfers.emit(
        TransferSnapshot(
          attemptId: running.attemptId,
          state: DownloadState.running,
          receivedBytes: 48,
        ),
      );
      final observed = await observation.timeout(const Duration(seconds: 2));
      expect(
        observed.singleWhere((task) => task.id == publishing.id).state,
        DownloadState.finalizing,
      );
      await expectLater(repository.publish(publishing.id), throwsStateError);
      files.publicationGate!.complete();
    },
  );

  test(
    'bootstrap exposes persisted finalization while publication is stalled',
    () async {
      final task = await start();
      files.publicationFailure = StateError('disk full');
      await event(task, DownloadState.finalizing);
      await repository.dispose();
      files.publicationFailure = null;
      files.publicationEntered = Completer<void>();
      files.publicationGate = Completer<void>();
      addTearDown(() {
        if (!files.publicationGate!.isCompleted) {
          files.publicationGate!.complete();
        }
      });
      repository = DurableDownloadRepository(
        store: store,
        transfers: transfers,
        files: files,
      );
      await files.publicationEntered!.future;
      final tasks = await repository.loadTasks().timeout(
        const Duration(seconds: 2),
      );
      expect(tasks.single.state, DownloadState.finalizing);
      files.publicationGate!.complete();
    },
  );

  test('retry cleanup claims prevent removal and a second retry', () async {
    final task = await start();
    await event(task, DownloadState.failed);
    final entered = Completer<void>();
    final release = Completer<void>();
    files.onCleanPartial = (_) async {
      entered.complete();
      await release.future;
    };
    final retrying = repository.retry(task.id);
    await entered.future;
    await expectLater(repository.remove(task.id), throwsStateError);
    await expectLater(repository.retry(task.id), throwsStateError);
    expect((await repository.loadTasks()).single.attemptId, task.attemptId);
    release.complete();
    await retrying;
    final replacement = (await repository.loadTasks()).single;
    expect(replacement.attemptId, isNot(task.attemptId));
    await event(task, DownloadState.finalizing);
    expect(
      (await repository.loadTasks()).single.attemptId,
      replacement.attemptId,
    );
  });

  test(
    'cancellation cleanup claims prevent retry from reusing owned artifacts',
    () async {
      final task = await start();
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onCleanPartial = (_) async {
        entered.complete();
        await release.future;
      };
      final cancelling = repository.cancel(task.id);
      await entered.future;
      await expectLater(repository.retry(task.id), throwsStateError);
      await expectLater(repository.remove(task.id), throwsStateError);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.cancelled,
      );
      release.complete();
      await cancelling;
      files.onCleanPartial = null;
      await repository.retry(task.id);
      expect(
        (await repository.loadTasks()).single.attemptId,
        isNot(task.attemptId),
      );
    },
  );

  test(
    'delete claims keep the record stable and release after failure',
    () async {
      final task = await start();
      await event(task, DownloadState.finalizing);
      final entered = Completer<void>();
      final release = Completer<void>();
      files.onDelete = (_) async {
        entered.complete();
        await release.future;
        throw StateError('permission denied');
      };
      final deleting = repository.deleteFile(task.id);
      final failure = expectLater(deleting, throwsStateError);
      await entered.future;
      await expectLater(repository.remove(task.id), throwsStateError);
      await expectLater(repository.shareFile(task.id), throwsStateError);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.completed,
      );
      release.complete();
      await failure;
      expect(
        (await repository.loadTasks()).single.error,
        contains('permission denied'),
      );
      files.onDelete = null;
      await repository.deleteFile(task.id);
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.missing,
      );
    },
  );

  test(
    'disposal drains publication and durable cleanup before returning',
    () async {
      final task = await start();
      files.publicationEntered = Completer<void>();
      files.publicationGate = Completer<void>();
      addTearDown(() {
        if (!files.publicationGate!.isCompleted) {
          files.publicationGate!.complete();
        }
      });
      transfers.emit(
        TransferSnapshot(
          attemptId: task.attemptId,
          state: DownloadState.finalizing,
          fileLocation: 'support:downloads/${task.filename}',
        ),
      );
      await files.publicationEntered!.future;
      var disposed = false;
      final disposal = repository.dispose().then((_) => disposed = true);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isFalse);
      files.publicationGate!.complete();
      await disposal;
      final saved = (await store.load()).single;
      expect(saved.state, DownloadState.completed);
      expect(saved.privateLocation, isNull);
      expect(files.deletedLocations, ['support:downloads/${task.filename}']);
    },
  );

  test(
    'cancellation commits intent before a callback can revise its claimed task',
    () async {
      final task = await start();
      await event(task, DownloadState.running, received: 1);
      final cancelling = repository.cancel(task.id);
      scheduleMicrotask(
        () => transfers.emit(
          TransferSnapshot(
            attemptId: task.attemptId,
            state: DownloadState.running,
            receivedBytes: 20,
          ),
        ),
      );
      await cancelling;
      expect(
        (await repository.loadTasks()).single.state,
        DownloadState.cancelled,
      );
      expect(transfers.cancelled, contains(task.attemptId));
    },
  );

  test('export cancellation keeps the local file and returns false', () async {
    final task = await start();
    await event(task, DownloadState.finalizing);
    expect(await repository.exportFile(task.id), isFalse);
    expect(
      (await repository.loadTasks()).single.state,
      DownloadState.completed,
    );
    expect(files.exists, isTrue);
  });
}

class FakeTransfers implements TransferGateway {
  final controller = StreamController<TransferSnapshot>.broadcast(sync: true);
  final snapshots = <String, TransferSnapshot>{};
  final enqueued = <DownloadTask>[];
  final cancelled = <String>[];
  Future<void> Function(DownloadTask)? onEnqueue;
  Completer<Map<String, TransferSnapshot>>? pendingQuery;
  bool resumeAccepted = true;
  int queryFailures = 0;
  int eventStreamAccesses = 0;
  Completer<void>? initializationEntered;
  Completer<void>? initializationGate;
  @override
  Stream<TransferSnapshot> get events {
    eventStreamAccesses++;
    return controller.stream;
  }

  @override
  Stream<String> get notificationTaps => const Stream.empty();
  @override
  Future<void> initialize() async {
    initializationEntered?.complete();
    await initializationGate?.future;
  }

  @override
  Future<bool> enqueue(DownloadTask task) async {
    enqueued.add(task);
    await onEnqueue?.call(task);
    snapshots[task.attemptId] = TransferSnapshot(
      attemptId: task.attemptId,
      state: DownloadState.queued,
    );
    return true;
  }

  void emit(TransferSnapshot snapshot) {
    snapshots[snapshot.attemptId] = snapshot;
    controller.add(snapshot);
  }

  @override
  Future<Map<String, TransferSnapshot>> query() async {
    if (queryFailures > 0) {
      queryFailures--;
      throw StateError('native query unavailable');
    }
    return pendingQuery?.future ?? Map.of(snapshots);
  }

  @override
  Future<bool> cancel(String attemptId) async {
    cancelled.add(attemptId);
    snapshots.remove(attemptId);
    return true;
  }

  @override
  Future<bool> pause(String attemptId) async => true;
  @override
  Future<bool> resume(String attemptId) async => resumeAccepted;
  @override
  Future<void> dispose() async {}
}

class FakeFiles implements DownloadFileGateway {
  Future<void> Function(DownloadTask)? onCleanPartial;
  Future<void> Function(String)? onDelete;
  Completer<void>? exportEntered;
  Completer<bool>? exportGate;
  Completer<void>? publicationEntered;
  Completer<void>? publicationGate;
  Future<FileDetails> Function(String)? onInspect;
  bool exists = true;
  bool publishInPlace = false;
  final deletedLocations = <String>[];
  final missingLocations = <String>{};
  Object? publicationFailure;
  Object? deletionFailure;
  Object? cleanupFailure;
  @override
  bool get supportsExport => true;
  @override
  Future<FileDetails> inspect(String location) async =>
      await onInspect?.call(location) ??
      FileDetails(
        exists: exists && !missingLocations.contains(location),
        bytes: exists && !missingLocations.contains(location) ? 120 : null,
      );
  @override
  Future<String> publish(DownloadTask task, String privateLocation) async {
    publicationEntered?.complete();
    await publicationGate?.future;
    if (publicationFailure != null) throw publicationFailure!;
    return publishInPlace
        ? privateLocation
        : 'content://media/external/downloads/${task.attemptId}';
  }

  @override
  Future<void> cleanPartial(DownloadTask task) async {
    await onCleanPartial?.call(task);
    if (cleanupFailure != null) throw cleanupFailure!;
  }

  @override
  Future<void> delete(String location) async {
    await onDelete?.call(location);
    if (deletionFailure != null) throw deletionFailure!;
    deletedLocations.add(location);
    missingLocations.add(location);
    if (location.startsWith('content:')) exists = false;
  }

  @override
  Future<void> open(String location) async {}
  @override
  Future<void> share(String location, String filename) async {}
  @override
  Future<bool> export(String location, String filename) async {
    exportEntered?.complete();
    return exportGate?.future ?? false;
  }
}

class FailOnceStore implements DownloadTaskStore {
  FailOnceStore(this.inner);
  final DownloadTaskStore inner;
  int reads = 0;
  int readFailures = 0;
  DownloadState? saveFailureState;
  @override
  Future<List<DownloadTask>> load() async {
    reads++;
    if (readFailures > 0) {
      readFailures--;
      throw StateError('storage temporarily unavailable');
    }
    return inner.load();
  }

  @override
  Future<void> save(DownloadTask task) async {
    if (task.state == saveFailureState) {
      saveFailureState = null;
      throw StateError('commit failed');
    }
    await inner.save(task);
  }

  @override
  Future<void> remove(String id) => inner.remove(id);
}
