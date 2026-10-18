import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter/services.dart';

import '../../domain/downloads/download_task.dart';
import '../../domain/downloads/file_gateway.dart';
import '../../domain/downloads/media_probe.dart';
import '../../domain/downloads/transfer_gateway.dart';
import '../../domain/programmes/programme_policy.dart';
import '../../domain/programmes/programme_repository.dart';
import 'dio_media_probe.dart';
import 'notification_inbox.dart';

/// background_downloader owns all scheduling, including its native holding
/// queue. No Dart queue is involved when the application is suspended.
class BackgroundTransferGateway implements TransferGateway {
  BackgroundTransferGateway({
    required this.appVersion,
    native.FileDownloader? downloader,
    bool? isIOS,
    DownloadMediaProbe? mediaProbe,
  }) : _providedDownloader = downloader,
       _isIOS = isIOS ?? Platform.isIOS,
       _mediaProbe = mediaProbe ?? DioMediaProbe(appVersion: appVersion);

  final String appVersion;
  final DownloadMediaProbe _mediaProbe;
  final _preparing = <String, RequestScope>{};

  final native.FileDownloader? _providedDownloader;
  final bool _isIOS;

  native.FileDownloader get _downloader =>
      _providedDownloader ?? native.FileDownloader();

  static const group = 'sctv-downloads';

  final _events = StreamController<TransferSnapshot>.broadcast(sync: true);
  final _notificationTaps = NotificationInbox();
  final _latest = <String, TransferSnapshot>{};
  final _nativeTasks = <String, native.DownloadTask>{};

  Future<void>? _initialization;
  bool _disposed = false;

  @override
  Stream<TransferSnapshot> get events => _events.stream;

  @override
  Stream<String> get notificationTaps => _notificationTaps.events;

  native.DownloadTask buildNativeTask(DownloadTask task) {
    if (!isAllowedMediaUrl(task.url)) {
      throw ArgumentError.value(task.url, 'url', 'Unsupported media target');
    }
    if (task.filename.contains(RegExp(r'[/\\\x00-\x1f]')) ||
        task.filename.isEmpty ||
        task.filename == '.' ||
        task.filename == '..' ||
        utf8.encode(task.filename).length > 255 ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(task.attemptId)) {
      throw ArgumentError('Unsafe download destination');
    }
    if (appVersion.isEmpty || appVersion.contains(RegExp(r'[\r\n]'))) {
      throw ArgumentError('Invalid application version');
    }

    return native.DownloadTask(
      taskId: task.attemptId,
      url: task.url,
      filename: task.filename,
      headers: {
        'Referer': 'https://scgc.video.play/',
        'User-Agent': 'sctv-dl/$appVersion',
      },
      baseDirectory: _isIOS
          ? native.BaseDirectory.applicationDocuments
          : native.BaseDirectory.applicationSupport,
      directory: _isIOS ? 'Downloads' : 'downloads/${task.attemptId}',
      group: group,
      updates: native.Updates.statusAndProgress,
      requiresWiFi: task.wifiOnly,
      retries: 2,
      allowPause: true,
      // API 34+ uses UIDT when permitted; foreground mode covers older Android.
      priority: 0,
      metaData: jsonEncode({'id': task.id, 'attemptId': task.attemptId}),
      displayName: task.selection.content.title,
    );
  }

  @override
  Future<void> initialize() {
    if (_disposed) {
      return Future.error(StateError('Transfer gateway is disposed'));
    }

    final existing = _initialization;
    if (existing != null) return existing;

    late final Future<void> attempt;
    attempt = _initialize().then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        if (identical(_initialization, attempt)) {
          _initialization = null;
          // A failed initialization owns these callbacks until rollback. Retry
          // installs one fresh owner before recovering background observations.
          if (!_disposed) _downloader.unregisterCallbacks(group: group);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _initialization = attempt;

    return attempt;
  }

  Future<void> _initialize() async {
    if (_disposed) throw StateError('Transfer gateway is disposed');

    _downloader.registerCallbacks(
      group: group,
      taskStatusCallback: _status,
      taskProgressCallback: _progress,
      taskNotificationTapCallback: (task, _) {
        if (_disposed) return;

        try {
          final metadata = jsonDecode(task.metaData);
          if (metadata is Map && metadata['id'] is String) {
            _notificationTaps.add(metadata['id'] as String);
            if (!_isIOS) {
              // Navigation is already queued. Clearing the consumed launch
              // intent prevents activity recreation from delivering it again.
              unawaited(
                const MethodChannel('dev.sctvdl.flutter/files')
                    .invokeMethod<void>('consumeNotificationIntent', {
                      'taskId': task.taskId,
                    })
                    .catchError((Object error, StackTrace stack) {
                      developer.log(
                        'Could not consume notification launch intent',
                        error: error,
                        stackTrace: stack,
                      );
                    }),
              );
            }
          }
        } on FormatException {
          /* Unowned plugin notifications are ignored. */
        }
      },
    );

    _downloader.configureNotificationForGroup(
      group,
      running: const native.TaskNotification('正在下载', '{displayName}'),
      complete: const native.TaskNotification('视频传输完成', '打开应用确认文件发布'),
      error: const native.TaskNotification('下载失败', '{displayName}'),
      paused: const native.TaskNotification('下载已暂停', '{displayName}'),
      progressBar: true,
      tapOpensFile: false,
    );

    final configurations = await _downloader.configure(
      globalConfig: [
        (native.Config.holdingQueue, (2, 2, 2)),
        (native.Config.requestTimeout, const Duration(seconds: 30)),
        (native.Config.checkAvailableSpace, 32),
        (native.Config.skipExistingFiles, false),
      ],
      androidConfig: [
        (native.Config.runInForeground, native.Config.always),
        (native.Config.useCacheDir, native.Config.never),
      ],
      iOSConfig: [
        (native.Config.excludeFromCloudBackup, true),
        (native.Config.resourceTimeout, const Duration(days: 7)),
      ],
    );
    final failures = configurations
        .where((entry) => entry.$2.isNotEmpty)
        .toList();
    if (failures.isNotEmpty) {
      throw StateError('Downloader configuration failed: $failures');
    }

    // Do not call start(): its killed-task rescheduling could rerun unverified
    // runtime identities restored without their original native jobs.
    await _downloader.trackTasksInGroup(group, markDownloadedComplete: false);
    await _downloader.resumeFromBackground();
  }

  @override
  Future<bool> enqueue(DownloadTask task) async {
    final request = buildNativeTask(task);
    final scope = RequestScope();
    _preparing[task.attemptId] = scope;

    try {
      await _mediaProbe.validate(task.url, scope: scope);
      scope.throwIfCancelled();

      await initialize();
      scope.throwIfCancelled();

      final permission = await _downloader.permissions.status(
        native.PermissionType.notifications,
      );
      if (permission != native.PermissionStatus.granted) {
        await _downloader.permissions.request(
          native.PermissionType.notifications,
        );
      }
      scope.throwIfCancelled();

      _nativeTasks[request.taskId] = request;
      try {
        return await _downloader.enqueue(request);
      } catch (error) {
        throw TransferEnqueueException(error);
      }
    } finally {
      if (identical(_preparing[task.attemptId], scope)) {
        _preparing.remove(task.attemptId);
      }
    }
  }

  void _emit(TransferSnapshot snapshot) {
    if (_disposed) return;

    _latest[snapshot.attemptId] = snapshot;
    _events.add(snapshot);
  }

  String _location(native.DownloadTask task) => PrivateFileLocation(
    task.baseDirectory == native.BaseDirectory.applicationDocuments,
    '${task.directory}/${task.filename}',
  ).value;

  DownloadState _state(native.TaskStatus status) => switch (status) {
    native.TaskStatus.enqueued => DownloadState.queued,
    native.TaskStatus.running => DownloadState.running,
    native.TaskStatus.complete => DownloadState.finalizing,
    native.TaskStatus.notFound ||
    native.TaskStatus.failed => DownloadState.failed,
    native.TaskStatus.canceled => DownloadState.cancelled,
    native.TaskStatus.waitingToRetry => DownloadState.retrying,
    native.TaskStatus.paused => DownloadState.paused,
  };

  void _status(native.TaskStatusUpdate update) {
    final task = update.task;
    if (task is! native.DownloadTask || task.group != group || _disposed) {
      return;
    }

    _nativeTasks[task.taskId] = task;
    final previous = _latest[task.taskId];
    final state = _state(update.status);
    _emit(
      TransferSnapshot(
        attemptId: task.taskId,
        state: state,
        receivedBytes: previous?.receivedBytes ?? 0,
        totalBytes: previous?.totalBytes,
        fileLocation: state == DownloadState.finalizing
            ? _location(task)
            : null,
        error:
            update.exception?.description ??
            (update.responseStatusCode != null &&
                    update.responseStatusCode! >= 400
                ? 'HTTP ${update.responseStatusCode}'
                : null),
        canResume: previous?.canResume ?? false,
      ),
    );

    if (state == DownloadState.running || state == DownloadState.paused) {
      // This Future settles when native code has verified Range/resume support.
      unawaited(
        _downloader
            .taskCanResume(task)
            .then(
              (canResume) {
                final latest = _latest[task.taskId];
                if (_disposed ||
                    latest == null ||
                    (latest.state != DownloadState.running &&
                        latest.state != DownloadState.paused)) {
                  return;
                }

                _emit(
                  TransferSnapshot(
                    attemptId: task.taskId,
                    state: latest.state,
                    receivedBytes: latest.receivedBytes,
                    totalBytes: latest.totalBytes,
                    error: latest.error,
                    canResume: canResume,
                  ),
                );
              },
              onError: (Object error, StackTrace stack) {
                if (!_disposed) _events.addError(error, stack);
              },
            ),
      );
    }
  }

  void _progress(native.TaskProgressUpdate update) {
    if (update.task.group != group || _disposed || update.progress < 0) return;

    final previous = _latest[update.task.taskId];
    if (previous != null &&
        !{
          DownloadState.queued,
          DownloadState.running,
          DownloadState.paused,
          DownloadState.retrying,
          DownloadState.waiting,
        }.contains(previous.state)) {
      return;
    }

    // Unknown-length transfers provide no byte counter in the plugin. Keep the
    // last observed count and a nullable total; never invent percentage bytes.
    final hasTotal =
        update.expectedFileSize > 0 &&
        update.progress > 0 &&
        update.progress < 1;
    _emit(
      TransferSnapshot(
        attemptId: update.task.taskId,
        state: previous?.state ?? DownloadState.running,
        receivedBytes: hasTotal
            ? (update.progress * update.expectedFileSize).round()
            : previous?.receivedBytes ?? 0,
        totalBytes: hasTotal ? update.expectedFileSize : previous?.totalBytes,
        canResume: previous?.canResume ?? false,
      ),
    );
  }

  @override
  Future<Map<String, TransferSnapshot>> query() async {
    await initialize();

    final active = {
      for (final task in await _downloader.allTasks(group: group))
        task.taskId: task,
    };
    final records = await _downloader.database.allRecords(group: group);

    final result = <String, TransferSnapshot>{};
    for (final record in records) {
      final task = record.task;
      if (task is! native.DownloadTask || !isAllowedMediaUrl(task.url)) {
        continue;
      }

      _nativeTasks[task.taskId] = task;
      final nativeExists = active.containsKey(task.taskId);
      final state = record.status.isNotFinalState && !nativeExists
          ? DownloadState.interrupted
          : _state(record.status);
      final total = record.expectedFileSize > 0
          ? record.expectedFileSize
          : null;
      final observedBytes =
          total != null && record.progress > 0 && record.progress < 1
          ? (total * record.progress).round()
          : _latest[task.taskId]?.receivedBytes ?? 0;

      var canResume = false;
      if (nativeExists &&
          (state == DownloadState.running || state == DownloadState.paused)) {
        canResume = await _downloader
            .taskCanResume(task)
            .timeout(const Duration(milliseconds: 200), onTimeout: () => false);
      }

      result[task.taskId] = TransferSnapshot(
        attemptId: task.taskId,
        state: state,
        receivedBytes: observedBytes,
        totalBytes: total,
        canResume: canResume,
        fileLocation: state == DownloadState.finalizing
            ? _location(task)
            : null,
        error: state == DownloadState.interrupted
            ? '原生下载已不在调度队列中，请重试'
            : record.exception?.description,
      );
    }

    // A native task may already exist before its tracked database row is saved.
    for (final entry in active.entries) {
      final task = entry.value;
      if (task is! native.DownloadTask || !isAllowedMediaUrl(task.url)) {
        continue;
      }

      _nativeTasks[entry.key] = task;
      result.putIfAbsent(
        entry.key,
        () =>
            _latest[entry.key] ??
            TransferSnapshot(attemptId: entry.key, state: DownloadState.queued),
      );
    }

    return result;
  }

  Future<native.DownloadTask?> _find(String attemptId) async {
    await initialize();
    final task =
        _nativeTasks[attemptId] ??
        await _downloader.taskForId(attemptId) ??
        (await _downloader.database.recordForId(attemptId))?.task;

    return task is native.DownloadTask && task.group == group ? task : null;
  }

  @override
  Future<bool> pause(String attemptId) async {
    final task = await _find(attemptId);
    return task != null && await _downloader.pause(task);
  }

  @override
  Future<bool> resume(String attemptId) async {
    final task = await _find(attemptId);
    return task != null && await _downloader.resume(task);
  }

  @override
  Future<bool> cancel(String attemptId) async {
    final preparation = _preparing[attemptId];
    preparation?.cancel();
    if (preparation != null && !_nativeTasks.containsKey(attemptId)) {
      return true;
    }

    await initialize();
    return _downloader.cancelTaskWithId(attemptId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    for (final scope in _preparing.values) {
      scope.cancel();
    }

    _mediaProbe.dispose();
    if (_initialization != null) _downloader.unregisterCallbacks(group: group);

    await _events.close();
    await _notificationTaps.dispose();
    // Queued transfers remain native-owned after the UI observer is disposed.
  }
}
