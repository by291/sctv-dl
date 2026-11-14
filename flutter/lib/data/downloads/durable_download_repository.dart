import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../domain/downloads/download_issue.dart';
import '../../domain/downloads/download_repository.dart';
import '../../domain/downloads/download_task.dart';
import '../../domain/downloads/file_gateway.dart';
import '../../domain/downloads/transfer_gateway.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';

typedef _ObservedAttempt = ({String id, int revision, int eventVersion});

/// Native operations stay outside the serialized transition lane so cancellation
/// can overtake a slow enqueue. This repository has one app-lifetime owner.
class DurableDownloadRepository implements DownloadRepository {
  DurableDownloadRepository({
    required this._store,
    required this._transfers,
    required this._files,
    String Function()? createId,
    DateTime Function()? now,
    this._revalidate,
  }) : _createId = createId ?? const Uuid().v4,
       _now = now ?? DateTime.now {
    // Native callbacks must be observed before storage and snapshot hydration.
    _subscription = _transfers.events.listen(_received, onError: _streamError);
    _ensureReady();
  }

  final DownloadTaskStore _store;
  final TransferGateway _transfers;
  final DownloadFileGateway _files;
  final String Function() _createId;
  final DateTime Function() _now;
  final Future<ProgrammeSelection> Function(ProgrammeSelection)? _revalidate;

  final _tasks = <String, DownloadTask>{};
  final _eventVersions = <String, int>{};
  final _changes = StreamController<List<DownloadTask>>.broadcast(sync: true);
  late final StreamSubscription<TransferSnapshot> _subscription;

  Future<void>? _ready;
  bool _loaded = false;
  final _bufferedEvents = <TransferSnapshot>[];
  Future<void> _lane = Future.value();

  // A claim owns one task's file/native cleanup while the transition lane stays
  // available to observation and unrelated tasks. Its snapshot advances only
  // after a durable commit made by that same owner.
  final _claims = <String, _TaskEffect>{};
  final _effects = <Future<void>>{};

  Future<void>? _disposal;
  bool _disposed = false;
  int _revision = 0;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _lane.then((_) => action());

    // A rejected operation must not poison later transitions.
    _lane = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});

    return result;
  }

  Future<void> _initialize() async {
    await _serial(() async {
      if (!_loaded) {
        for (final task in await _store.load()) {
          _tasks[task.id] = task;
        }
        _loaded = true;
      }

      while (_bufferedEvents.isNotEmpty) {
        // Remove only after persistence succeeds. A failed recovery write
        // must not let a stale native snapshot replace this terminal event.
        await _apply(_bufferedEvents.first);
        _bufferedEvents.removeAt(0);
      }
    });

    await _transfers.initialize();
    await _reconcile(waitForFiles: false);
  }

  Future<void> _ensureReady() {
    _checkOpen();
    final existing = _ready;
    if (existing != null) {
      return existing;
    }

    final attempt = _initialize();
    _ready = attempt;

    // Keep one in-flight attempt for concurrent callers. Failure is observed
    // immediately, but only a later operation starts recovery. Successful
    // storage hydration and the original native subscription survive retries.
    unawaited(
      attempt.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_ready, attempt)) {
            _ready = null;
          }
          _streamError(error, stack);
        },
      ),
    );

    return attempt;
  }

  List<DownloadTask> _snapshot() {
    final tasks = _tasks.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return List.unmodifiable(tasks);
  }

  void _checkOpen() {
    if (_disposed) {
      throw StateError('Download repository is disposed');
    }
  }

  DownloadTask _task(String id) =>
      _tasks[id] ?? (throw StateError('Download task does not exist'));

  Future<void> _save(DownloadTask task) async {
    await _store.save(task);
    _recordSavedTask(task);
  }

  void _recordSavedTask(DownloadTask task) {
    _tasks[task.id] = task;
    _revision++;
    if (!_disposed) {
      _changes.add(_snapshot());
    }
  }

  Future<bool> _reserve(DownloadTask task) async {
    // Native callbacks can arrive during enqueue and need a durable attempt ID.
    if (_store case AtomicDownloadTaskStore store) {
      if (!await store.reserve(task)) {
        return false;
      }
      _recordSavedTask(task);
    } else {
      await _save(task);
    }

    return true;
  }

  bool _hasActiveDownload(
    ContentRef content,
    VideoQuality quality, {
    String? excludingId,
  }) => _tasks.values.any(
    (task) =>
        task.id != excludingId &&
        task.isActive &&
        task.selection.ref == content &&
        task.quality == quality,
  );

  void _requireUnclaimed(String id) {
    if (_claims.containsKey(id)) {
      throw DownloadIssue(DownloadIssueCode.fileBusy);
    }
  }

  Future<T> _track<T>(Future<T> Function() action) {
    final result = Future<T>.sync(action);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );

    _effects.add(settled);
    unawaited(settled.then((_) => _effects.remove(settled)));

    return result;
  }

  Future<T> _withTaskEffect<T>(
    String id,
    void Function(DownloadTask) validate,
    Future<T> Function(_TaskEffect) action, {
    DownloadTask Function(DownloadTask)? transition,
  }) => _track(() async {
    final effect = await _serial(() async {
      _checkOpen();
      _requireUnclaimed(id);

      final current = _task(id);
      validate(current);

      final task = transition?.call(current) ?? current;
      // Intent transitions share claim acquisition's lane turn, so a callback
      // cannot revise an active task between its capture and cancellation.
      if (transition != null) {
        await _save(task);
      }

      final effect = _TaskEffect(task);
      _claims[id] = effect;

      return effect;
    });

    return _runEffect(effect, action);
  });

  Future<T> _runEffect<T>(
    _TaskEffect effect,
    Future<T> Function(_TaskEffect) action,
  ) async {
    try {
      final result = await action(effect);

      await _releaseEffect(effect);
      effect.completion.complete();

      return result;
    } catch (error, stack) {
      await _releaseEffect(effect);
      effect.completion.completeError(error, stack);
      rethrow;
    }
  }

  Future<void> _releaseEffect(_TaskEffect effect) => _serial(() async {
    if (identical(_claims[effect.task.id], effect)) {
      _claims.remove(effect.task.id);
    }
  });

  // Called from a transition-lane turn: reserve before another reconciliation
  // can schedule the same work, and let explicit validation join its result.
  Future<void> _scheduleEffect(
    String id,
    Future<void> Function(_TaskEffect) action,
  ) {
    final existing = _claims[id];
    if (existing != null) {
      return existing.completion.future;
    }

    final effect = _TaskEffect(_task(id));
    _claims[id] = effect;
    final operation = _track(() => _runEffect(effect, action));
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        _streamError(error, stack);
      }),
    );

    return operation;
  }

  Future<void> _commitEffect(_TaskEffect effect, DownloadTask next) =>
      _serial(() async {
        final expected = effect.task;
        final current = _tasks[expected.id];
        if (!identical(_claims[expected.id], effect) ||
            current?.attemptId != expected.attemptId ||
            current?.revision != expected.revision) {
          throw DownloadIssue(DownloadIssueCode.taskChanged);
        }

        await _save(next);
        effect.task = next;
      });

  Future<void> _recordEffectIssue(_TaskEffect effect, DownloadIssue issue) {
    final task = effect.task;

    return _commitEffect(
      effect,
      task.copyWith(
        error: issue.message,
        issueCode: issue.code,
        revision: task.revision + 1,
      ),
    );
  }

  @override
  Future<List<DownloadTask>> loadTasks() async {
    _checkOpen();
    await _ensureReady();

    return _serial(() async => _snapshot());
  }

  @override
  Stream<List<DownloadTask>> watchTasks() => Stream.multi((controller) {
    var observedRevision = -1;
    final subscription = _changes.stream.listen(
      (tasks) {
        observedRevision = _revision;
        controller.add(tasks);
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    // Loading cannot lose an event because the listener is already attached.
    loadTasks().then((tasks) {
      if (observedRevision < _revision) {
        controller.add(tasks);
      }
    }, onError: controller.addError);
    controller.onCancel = subscription.cancel;
  });

  @override
  Future<DownloadBatchResult> start(
    List<ProgrammeSelection> selections,
    VideoQuality quality, {
    required bool wifiOnly,
  }) => _track(() async {
    _checkOpen();
    await _ensureReady();

    final unique = <String, ProgrammeSelection>{};
    for (final selection in selections) {
      unique.putIfAbsent(selection.ref.key, () => selection);
    }

    final attempts = await Future.wait(
      unique.values
          .take(downloadBatchLimit)
          .map(
            (selection) =>
                _startSelection(selection, quality, wifiOnly: wifiOnly),
          ),
    );

    final accepted = <String>[];
    final failures = <DownloadFailure>[];
    var duplicates = selections.length - unique.length;
    var fallbacks = 0;
    for (final (task, failure) in attempts) {
      if (failure != null) {
        failures.add(failure);
      } else if (task == null) {
        duplicates++;
      } else {
        accepted.add(task.id);
        if (task.quality != quality) {
          fallbacks++;
        }
      }
    }
    for (final selection in unique.values.skip(downloadBatchLimit)) {
      failures.add(
        DownloadFailure(
          contentId: selection.content.id,
          message: DownloadIssueCode.batchLimit.diagnostic,
          issueCode: DownloadIssueCode.batchLimit,
        ),
      );
    }

    return DownloadBatchResult(
      taskIds: List.unmodifiable(accepted),
      duplicates: duplicates,
      fallbacks: fallbacks,
      failures: List.unmodifiable(failures),
    );
  });

  Future<(DownloadTask?, DownloadFailure?)> _startSelection(
    ProgrammeSelection selection,
    VideoQuality quality, {
    required bool wifiOnly,
  }) async {
    try {
      final source = resolveVideo(selection.content, quality);
      if (source == null || !isAllowedMediaUrl(source.url)) {
        throw DownloadIssue(DownloadIssueCode.noSource);
      }

      final task = await _serial(() async {
        _checkOpen();
        if (_hasActiveDownload(selection.ref, source.quality)) {
          return null;
        }

        final attempt = _createId();
        final task = DownloadTask(
          id: _createId(),
          attemptId: attempt,
          selection: selection,
          requestedQuality: quality,
          quality: source.quality,
          url: source.url,
          filename: downloadFilename(
            selection,
            source.quality,
            suffix: attempt,
          ),
          wifiOnly: wifiOnly,
          state: DownloadState.preparing,
          createdAt: _now(),
        );

        return await _reserve(task) ? task : null;
      });
      if (task == null) {
        return (null, null);
      }

      if (await _enqueue(task)) {
        return (task, null);
      }

      final rejected = _tasks[task.id];
      return (
        null,
        DownloadFailure(
          contentId: selection.content.id,
          message:
              rejected?.error ?? DownloadIssueCode.enqueueFailed.diagnostic,
          issueCode: rejected?.issueCode ?? DownloadIssueCode.enqueueFailed,
        ),
      );
    } catch (error) {
      return (
        null,
        DownloadFailure(
          contentId: selection.content.id,
          message: error.toString(),
          issueCode: error is DownloadIssue
              ? error.code
              : DownloadIssueCode.downloadFailed,
        ),
      );
    }
  }

  Future<bool> _enqueue(DownloadTask task) => _track(() async {
    var enqueued = false;
    Object? failure;
    TransferSnapshot? recovered;

    try {
      enqueued = await _transfers.enqueue(task);
    } catch (error) {
      failure = error;
    }

    if (failure is TransferEnqueueException) {
      try {
        recovered = (await _transfers.query())[task.attemptId];
        enqueued = recovered != null;
      } catch (_) {
        // Preserve the ambiguous outcome. Only an explicit retry may cancel
        // this identity and replace it when native state cannot be verified.
      }
    }

    final shouldCancel = await _serial(() async {
      final current = _tasks[task.id];
      if (_disposed ||
          current == null ||
          current.attemptId != task.attemptId ||
          current.state == DownloadState.cancelled) {
        return true;
      }
      if (current.state != DownloadState.preparing) {
        return false;
      }

      if (recovered != null) {
        await _apply(recovered);
        return false;
      }

      final state = switch ((enqueued, failure)) {
        (true, _) => DownloadState.queued,
        (false, TransferEnqueueException()) => DownloadState.interrupted,
        _ => DownloadState.failed,
      };
      final issue = enqueued
          ? null
          : DownloadIssue(DownloadIssueCode.enqueueFailed, cause: failure);

      await _save(
        current.copyWith(
          state: state,
          error: issue?.message,
          issueCode: issue?.code,
          revision: current.revision + 1,
        ),
      );
      return false;
    });

    if (shouldCancel) {
      // Cancel again after enqueue: the first cancellation may have arrived
      // before native code created the job.
      await _transfers.cancel(task.attemptId);
      await _files.cleanPartial(task);
      return false;
    }

    return enqueued;
  });

  void _received(TransferSnapshot event) {
    if (_disposed) {
      return;
    }

    _eventVersions.update(
      event.attemptId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    unawaited(
      _serial(() async {
        if (!_loaded || _bufferedEvents.isNotEmpty) {
          _bufferedEvents.add(event);
          return;
        }

        await _apply(event);
      }).catchError((Object error, StackTrace stack) {
        _streamError(error, stack);
      }),
    );
  }

  void _streamError(Object error, [StackTrace? stack]) {
    if (!_disposed) {
      _changes.addError(error, stack);
    }
  }

  Future<void> _apply(TransferSnapshot event) async {
    if (_disposed) {
      return;
    }

    final matches = _tasks.values.where(
      (task) => task.attemptId == event.attemptId,
    );
    if (matches.isEmpty) {
      return;
    }

    final task = matches.first;
    // Attempt fencing and terminal guards protect separate callback races.
    if (task.transferFinished) {
      return;
    }

    final state = event.state == DownloadState.completed
        ? DownloadState.finalizing
        : event.state;
    var next = task.copyWith(
      state: state,
      receivedBytes: event.receivedBytes < 0
          ? task.receivedBytes
          : event.receivedBytes,
      totalBytes: event.totalBytes,
      canResume: event.canResume,
      error: event.error,
      issueCode: event.issueCode,
      revision: task.revision + 1,
    );

    if (state == DownloadState.finalizing) {
      final location = event.fileLocation;
      if (location == null) {
        await _save(
          next.copyWith(
            state: DownloadState.interrupted,
            error: DownloadIssueCode.missingPublication.diagnostic,
            issueCode: DownloadIssueCode.missingPublication,
          ),
        );
        return;
      }

      DownloadFileLocation.parse(location);
      next = next.copyWith(privateLocation: location, canResume: false);
    }

    await _save(next);
    if (state == DownloadState.finalizing) {
      unawaited(_schedulePublication(next.id));
    }
  }

  @override
  Future<void> reconcile() => _track(() async {
    _checkOpen();
    await _ensureReady();
    await _reconcile();
  });

  Future<void> _reconcile({bool waitForFiles = true}) async {
    final captured = await _serial<Map<String, _ObservedAttempt>>(
      () async => {
        for (final task in _tasks.values)
          task.id: (
            id: task.attemptId,
            revision: task.revision,
            eventVersion: _eventVersions[task.attemptId] ?? 0,
          ),
      },
    );

    final native = await _transfers.query();

    final fileEffects = <Future<void>>[];
    await _serial(() async {
      if (_disposed) {
        return;
      }

      for (final entry in captured.entries) {
        final current = _tasks[entry.key];
        if (current == null) {
          continue;
        }

        final pending = _claims[current.id];
        if (pending != null) {
          fileEffects.add(pending.completion.future);
          continue;
        }

        // The query ran outside the lane. Attempts can be replaced, durable
        // state can advance, and a callback can arrive before its commit.
        final observed = entry.value;
        if (current.attemptId != observed.id ||
            current.revision != observed.revision ||
            (_eventVersions[observed.id] ?? 0) != observed.eventVersion) {
          continue;
        }

        if (current.state == DownloadState.completed) {
          fileEffects.add(_scheduleEffect(current.id, _inspectCompleted));
        } else if (current.state == DownloadState.finalizing) {
          fileEffects.add(_schedulePublication(current.id));
        } else if (!current.transferFinished) {
          await _reconcileTransfer(current, native[observed.id]);
        }
      }
    });

    // Bootstrap must expose the durable snapshot even while a native picker,
    // inspection or publication is stalled. Explicit validation joins existing
    // ownership too, so it cannot report stale availability during file changes.
    if (waitForFiles) {
      await Future.wait(fileEffects);
    }
  }

  Future<void> _reconcileTransfer(
    DownloadTask current,
    TransferSnapshot? snapshot,
  ) async {
    if (snapshot != null) {
      await _apply(snapshot);
      return;
    }

    await _save(
      current.copyWith(
        state: DownloadState.interrupted,
        canResume: false,
        error: DownloadIssueCode.missingTransfer.diagnostic,
        issueCode: DownloadIssueCode.missingTransfer,
        revision: current.revision + 1,
      ),
    );
  }

  Future<void> _inspectCompleted(_TaskEffect effect) async {
    final task = effect.task;
    final location = task.fileLocation;
    if (location == null || !(await _files.inspect(location)).exists) {
      await _markFileMissing(effect);
      return;
    }

    await _cleanupCompleted(effect);
  }

  @override
  Future<void> pause(String id) => _track(() async {
    await _ensureReady();

    final task = await _serial(() async {
      final task = _task(id);
      if (task.state != DownloadState.running || !task.canResume) {
        throw DownloadIssue(DownloadIssueCode.cannotPause);
      }

      return task;
    });

    if (!await _transfers.pause(task.attemptId)) {
      throw DownloadIssue(DownloadIssueCode.pauseFailed);
    }
    // Only the native paused event confirms that the request succeeded.
  });

  @override
  Future<void> resume(String id) => _track(() async {
    await _ensureReady();

    final task = await _serial(() async {
      final task = _task(id);
      if (task.state != DownloadState.paused || !task.canResume) {
        throw DownloadIssue(DownloadIssueCode.cannotResume);
      }

      return task;
    });

    if (!await _transfers.resume(task.attemptId)) {
      await _serial(() async {
        final current = _task(id);
        if (current.attemptId == task.attemptId &&
            current.state == DownloadState.paused) {
          await _save(
            current.copyWith(
              state: DownloadState.interrupted,
              canResume: false,
              error: DownloadIssueCode.missingResumeData.diagnostic,
              issueCode: DownloadIssueCode.missingResumeData,
              revision: current.revision + 1,
            ),
          );
        }
      });

      throw DownloadIssue(DownloadIssueCode.missingResumeData);
    }
  });

  @override
  Future<void> cancel(String id) async {
    await _ensureReady();

    await _withTaskEffect(
      id,
      (task) {
        if (!task.isActive || task.state == DownloadState.finalizing) {
          throw DownloadIssue(DownloadIssueCode.transferFinished);
        }
      },
      (effect) async {
        final original = effect.task;
        // Terminal guards reject late completion while the claim prevents
        // retry from racing the partial-file cleanup owned by this attempt.
        try {
          if (!await _transfers.cancel(original.attemptId)) {
            throw DownloadIssue(DownloadIssueCode.cancelFailed);
          }

          await _files.cleanPartial(original);
        } catch (error) {
          final issue = DownloadIssue(
            DownloadIssueCode.cancelCleanupFailed,
            cause: error,
          );
          await _recordEffectIssue(effect, issue);
          throw issue;
        }
      },
      transition: (task) => task.copyWith(
        state: DownloadState.cancelled,
        canResume: false,
        error: null,
        revision: task.revision + 1,
      ),
    );
  }

  @override
  Future<void> retry(String id) => _track(() async {
    await _ensureReady();

    final task = await _withTaskEffect(id, (task) {
      if (task.isActive || task.state == DownloadState.completed) {
        throw DownloadIssue(DownloadIssueCode.cannotRetry);
      }
    }, _prepareRetry);

    try {
      if (!await _enqueue(task)) {
        throw DownloadIssue(DownloadIssueCode.enqueueFailed);
      }
    } catch (error) {
      await _serial(() async {
        final current = _task(id);
        if (current.attemptId == task.attemptId &&
            current.state == DownloadState.preparing) {
          await _save(
            current.copyWith(
              state: DownloadState.failed,
              error: error.toString(),
              issueCode: error is DownloadIssue ? error.code : null,
              revision: current.revision + 1,
            ),
          );
        }
      });
      rethrow;
    }
  });

  Future<DownloadTask> _prepareRetry(_TaskEffect effect) async {
    final original = effect.task;
    final ProgrammeSelection selection;
    try {
      selection =
          await _revalidate?.call(original.selection) ?? original.selection;
    } catch (error) {
      throw DownloadIssue(DownloadIssueCode.sourceUnavailable, cause: error);
    }

    final source = resolveVideo(selection.content, original.requestedQuality);
    if (source == null || !isAllowedMediaUrl(source.url)) {
      throw DownloadIssue(DownloadIssueCode.sourceUnavailable);
    }

    // Keep the old durable identity until cleanup succeeds. If cleanup fails,
    // it must still identify the native job and partial artifacts to clean.
    try {
      if (!await _transfers.cancel(original.attemptId)) {
        throw StateError('The native attempt could not be cancelled');
      }

      await _files.cleanPartial(original);
    } catch (error) {
      final issue = DownloadIssue(
        DownloadIssueCode.retryCleanupFailed,
        cause: error,
      );
      await _recordEffectIssue(effect, issue);
      throw issue;
    }

    return _serial(() async {
      final current = _task(original.id);
      if (current.attemptId != original.attemptId ||
          current.revision != original.revision ||
          current.isActive) {
        throw DownloadIssue(DownloadIssueCode.taskChanged);
      }
      if (_hasActiveDownload(
        selection.ref,
        source.quality,
        excludingId: current.id,
      )) {
        throw DownloadIssue(DownloadIssueCode.duplicate);
      }

      final attempt = _createId();
      final next = current.copyWith(
        attemptId: attempt,
        selection: selection,
        state: DownloadState.preparing,
        quality: source.quality,
        url: source.url,
        filename: downloadFilename(selection, source.quality, suffix: attempt),
        receivedBytes: 0,
        totalBytes: null,
        fileLocation: null,
        privateLocation: null,
        error: null,
        canResume: false,
        revision: current.revision + 1,
      );

      if (!await _reserve(next)) {
        throw DownloadIssue(DownloadIssueCode.duplicate);
      }

      return next;
    });
  }

  @override
  Future<void> publish(String id) async {
    await _ensureReady();
    await _publication(id);
  }

  Future<void> _schedulePublication(String id) => _scheduleEffect(
    id,
    (effect) => _publishEffect(effect, throwOnFailure: false),
  );

  Future<void> _publication(String id, {bool throwOnFailure = true}) =>
      _withTaskEffect(id, (task) {
        if (task.state != DownloadState.finalizing) {
          throw DownloadIssue(DownloadIssueCode.cannotPublish);
        }
      }, (effect) => _publishEffect(effect, throwOnFailure: throwOnFailure));

  Future<void> _publishEffect(
    _TaskEffect effect, {
    required bool throwOnFailure,
  }) async {
    final task = effect.task;
    try {
      final staging = task.privateLocation;
      if (staging == null) {
        throw StateError('No private file is available for publication');
      }

      final published = await _files.publish(task, staging);
      DownloadFileLocation.parse(published);

      final details = await _files.inspect(published);
      if (!details.exists || details.bytes == null) {
        throw StateError('Could not verify the published file');
      }

      // Keep the private recovery source until the published URI is durable.
      await _commitEffect(
        effect,
        task.copyWith(
          state: DownloadState.completed,
          fileLocation: published,
          receivedBytes: details.bytes,
          totalBytes: details.bytes,
          error: null,
          canResume: false,
          revision: task.revision + 1,
        ),
      );
    } catch (error) {
      final issue = DownloadIssue(
        DownloadIssueCode.publicationFailed,
        cause: error,
      );
      await _recordEffectIssue(effect, issue);

      if (throwOnFailure) {
        throw issue;
      }
      return;
    }

    await _cleanupCompleted(effect);
  }

  Future<void> _cleanupCompleted(_TaskEffect effect) async {
    final task = effect.task;
    final private = task.privateLocation;
    if (private == null) {
      return;
    }

    try {
      // iOS publishes in place: clearing the pointer must not delete the video.
      if (private != task.fileLocation) {
        await _files.delete(private);
      }

      await _commitEffect(
        effect,
        task.copyWith(
          privateLocation: null,
          error: null,
          revision: task.revision + 1,
        ),
      );
    } catch (error) {
      // Public playback remains valid; retain the recovery pointer for cleanup.
      await _recordEffectIssue(
        effect,
        DownloadIssue(DownloadIssueCode.privateCleanupFailed, cause: error),
      );
    }
  }

  @override
  Future<void> remove(String id) async {
    await _ensureReady();
    await _serial(() async {
      _checkOpen();
      _requireUnclaimed(id);
      final task = _task(id);
      if (task.isActive) {
        throw DownloadIssue(DownloadIssueCode.taskActive);
      }

      await _store.remove(id);

      _tasks.remove(id);
      _revision++;
      _changes.add(_snapshot());
    });
  }

  void _requireCompleted(DownloadTask task) {
    if (task.state != DownloadState.completed || task.fileLocation == null) {
      throw DownloadIssue(DownloadIssueCode.fileUnavailable);
    }
  }

  Future<void> _requireAvailable(_TaskEffect effect) async {
    final details = await _files.inspect(effect.task.fileLocation!);
    if (!details.exists) {
      await _markFileMissing(effect);
      throw DownloadIssue(DownloadIssueCode.fileMissing);
    }
  }

  Future<void> _markFileMissing(_TaskEffect effect) {
    final task = effect.task;
    const issue = DownloadIssueCode.fileMissing;

    return _commitEffect(
      effect,
      task.copyWith(
        state: DownloadState.missing,
        error: issue.diagnostic,
        issueCode: issue,
        canResume: false,
        revision: task.revision + 1,
      ),
    );
  }

  Future<T> _fileAction<T>(
    String id,
    Future<T> Function(DownloadTask) action,
  ) async {
    await _ensureReady();

    return _withTaskEffect(id, _requireCompleted, (effect) async {
      await _requireAvailable(effect);

      return action(effect.task);
    });
  }

  @override
  Future<void> deleteFile(String id) async {
    await _ensureReady();

    await _withTaskEffect(id, _requireCompleted, (effect) async {
      await _requireAvailable(effect);

      final task = effect.task;
      try {
        await _files.delete(task.fileLocation!);

        await _commitEffect(
          effect,
          task.copyWith(
            state: DownloadState.missing,
            fileLocation: null,
            error: DownloadIssueCode.fileDeleted.diagnostic,
            issueCode: DownloadIssueCode.fileDeleted,
            revision: task.revision + 1,
          ),
        );
      } catch (error) {
        final issue = DownloadIssue(
          DownloadIssueCode.deleteFailed,
          cause: error,
        );
        await _recordEffectIssue(effect, issue);
        throw issue;
      }
    });
  }

  @override
  Future<void> openFile(String id) =>
      _fileAction(id, (task) => _files.open(task.fileLocation!));

  @override
  Future<void> shareFile(String id) => _fileAction(
    id,
    (task) => _files.share(task.fileLocation!, task.filename),
  );

  @override
  Future<bool> exportFile(String id) {
    if (!_files.supportsExport) {
      throw UnsupportedError(DownloadIssueCode.exportUnsupported.diagnostic);
    }

    return _fileAction(
      id,
      (task) => _files.export(task.fileLocation!, task.filename),
    );
  }

  @override
  Future<void> dispose() {
    _disposed = true;

    return _disposal ??= Future<void>.microtask(_dispose);
  }

  Future<void> _dispose() async {
    (Object, StackTrace)? cancellationFailure;
    try {
      await _subscription.cancel();
    } catch (error, stack) {
      cancellationFailure = (error, stack);
    }

    try {
      await _ready;
    } catch (_) {
      // Bootstrap errors already belong to load/watch. Failed initialization
      // must still release the listener and allow the database owner to close.
    }
    await _lane;

    // Effects may enqueue their final durable commit and release after disposal
    // starts. Keep shared file/database owners alive until all of them settle.
    while (_effects.isNotEmpty) {
      await Future.wait(_effects.toList());
    }

    await _lane;
    await _changes.close();

    // The application can close shared owners after the repository drains.
    if (cancellationFailure case (final error, final stack)) {
      Error.throwWithStackTrace(error, stack);
    }
  }
}

class _TaskEffect {
  _TaskEffect(this.task) {
    // The initiating action owns errors even when no reconciliation joins it.
    unawaited(completion.future.catchError((Object _) {}));
  }

  DownloadTask task;
  final completion = Completer<void>();
}
