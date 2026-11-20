import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/app/resource_cleanup.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/downloads/transfer_gateway.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/platform/downloads/background_transfer_gateway.dart';
import 'package:sctv_dl_mobile/platform/files/native_download_files.dart';

const _queueLimit = 2;
const _requestTimeout = Duration(seconds: 30);
const _transferTimeout = Duration(seconds: 60);
const _sampleSize = 256 * 1024;
const _resumeSampleSize = 8 * 1024 * 1024;
const _androidRetryResumeFloor = 1024 * 1024;
const _resumeChunkSize = 64 * 1024;
const _resumeChunkInterval = Duration(milliseconds: 40);
const _bytePatternPeriod = 251;

final _resumeRange = RegExp(r'^bytes=([1-9]\d*)-(\d*)$');

/// Run on a disposable runtime. Loopback rewriting follows production URL validation.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native holding queue, unknown lengths, headers and owned publication',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native download fixture')),
        ),
      );
      await tester.runAsync(_verifyNativeQueue);
    },
  );

  final resumeDescription = Platform.isIOS
      ? 'native iOS resume restores exact bytes from a partial HTTP response'
      : 'native Android retry restarts with exact bytes when the server ignores Range';
  testWidgets(resumeDescription, (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Resume fixture'))),
    );
    await tester.runAsync(_verifyNativeResume);
  });
}

Future<void> _verifyNativeQueue() async {
  final fixture = _NativeFixture();
  final tasks = [_task('known-first'), _task('known-second'), _task('unknown')];
  final unknownTask = tasks.last;
  final attemptIds = tasks.map((task) => task.attemptId).toSet();
  final events = <TransferSnapshot>[];
  final terminalEvents = <String, TransferSnapshot>{};
  final allTerminal = Completer<void>();
  final subscription = fixture.gateway.events.listen((event) {
    if (!attemptIds.contains(event.attemptId)) {
      return;
    }
    events.add(event);

    if (_isTerminal(event)) {
      terminalEvents.putIfAbsent(event.attemptId, () => event);
    }
    if (terminalEvents.length == tasks.length && !allTerminal.isCompleted) {
      allTerminal.complete();
    }
  });

  final bytes = _fixtureBytes(_sampleSize);
  final firstRequests = Completer<void>();
  final release = Completer<void>();
  final requests = <HttpRequest>[];
  var concurrent = 0;
  var maximum = 0;
  try {
    await fixture.serve((request) async {
      requests.add(request);
      concurrent++;
      if (concurrent > maximum) {
        maximum = concurrent;
      }
      if (requests.length == _queueLimit) {
        firstRequests.complete();
      }

      try {
        request.response.headers.contentType = ContentType('video', 'mp4');
        if (request.uri.path != '/unknown.mp4') {
          request.response.contentLength = bytes.length;
        }
        await release.future;
        request.response.add(bytes);
        await request.response.close();
      } finally {
        concurrent--;
      }
    });

    await fixture.gateway.initialize();
    for (final task in tasks) {
      final path = task == unknownTask ? 'unknown.mp4' : 'known.mp4';
      final nativeTask = fixture.nativeTask(task, path);
      expect(await fixture.engine.enqueue(nativeTask), isTrue);
    }
    await firstRequests.future.timeout(_requestTimeout);
    expect(requests, hasLength(_queueLimit));

    release.complete();
    await allTerminal.future.timeout(_transferTimeout);
    await fixture.waitForResponses();
    expect(maximum, lessThanOrEqualTo(_queueLimit));
    for (final task in tasks) {
      final event = terminalEvents[task.attemptId]!;
      expect(event.state, DownloadState.finalizing, reason: event.error);
      await fixture.verifyPublication(task, event.fileLocation!, bytes.length);
    }

    final unknownProgress = events.where(
      (event) =>
          event.attemptId == unknownTask.attemptId &&
          event.state == DownloadState.running,
    );
    expect(unknownProgress, isNotEmpty);
    expect(
      unknownProgress.map((event) => event.totalBytes),
      everyElement(isNull),
    );
    for (final request in requests) {
      expect(request.headers.value('referer'), 'https://scgc.video.play/');
      expect(request.headers.value('user-agent'), 'okhttp/4.12.0');
      expect(request.headers.value('authorization'), isNull);
    }
  } finally {
    if (!release.isCompleted) {
      release.complete();
    }
    await closeAppResources([subscription.cancel, () => fixture.close(tasks)]);
  }
}

Future<void> _verifyNativeResume() async {
  final fixture = _NativeFixture();
  final bytes = _fixtureBytes(_resumeSampleSize);
  final task = _task('resume');
  final releaseInitial = Completer<void>();
  final resumedResponse = Completer<void>();

  var hasStarted = false;
  var isStoppingInitial = false;

  Future<void> sendPartialBody(IOSink writer) async {
    final cutoff = bytes.length ~/ 2;
    for (var start = 0; start < cutoff; start += _resumeChunkSize) {
      if (releaseInitial.isCompleted) {
        break;
      }
      writer.add(Uint8List.sublistView(bytes, start, start + _resumeChunkSize));
      await writer.flush();
      await Future<void>.delayed(_resumeChunkInterval);
    }

    // Keep the original response incomplete until the test triggers the interruption.
    await releaseInitial.future;
  }

  Future<void> sendInitial(HttpResponse response) async {
    response.contentLength = bytes.length;
    if (Platform.isAndroid) {
      // End the first response before its advertised length to trigger the native retry.
      final socket = await response.detachSocket(writeHeaders: true);
      socket.done.ignore();
      try {
        await sendPartialBody(socket);
      } finally {
        socket.destroy();
      }
      return;
    }

    // URLSession can close the original response as soon as pause begins.
    response.done.ignore();
    try {
      await sendPartialBody(response);
    } on IOException {
      if (!isStoppingInitial) {
        rethrow;
      }
    }
  }

  try {
    await fixture.serve((request) async {
      final response = request.response;
      response.headers.contentType = ContentType('video', 'mp4');
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.set(HttpHeaders.etagHeader, '"fixture-v1"');

      if (!hasStarted) {
        hasStarted = true;
        expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
        await sendInitial(response);
        return;
      }

      await _sendResumedDownload(request, bytes);
      if (!resumedResponse.isCompleted) {
        resumedResponse.complete();
      }
    });

    await fixture.gateway.initialize();
    final nativeTask = fixture.nativeTask(task, 'resume.mp4');
    final events = fixture.gateway.events.where(
      (event) => event.attemptId == task.attemptId,
    );

    // The Android downloader preserves retry data only above this native byte count.
    final resumeFloor = Platform.isAndroid ? _androidRetryResumeFloor : 0;
    await _actAndObserve(
      events.where(
        (event) =>
            event.state == DownloadState.running &&
            event.receivedBytes > resumeFloor &&
            event.canResume,
      ),
      () => fixture.engine.enqueue(nativeTask),
      description: 'Start a resumable native download',
    );
    final result = Platform.isAndroid
        ? await _retryInterruptedDownload(events, releaseInitial)
        : await _resumePausedDownload(
            events,
            pause: () {
              isStoppingInitial = true;
              return fixture.gateway.pause(task.attemptId);
            },
            resume: () {
              releaseInitial.complete();
              return fixture.gateway.resume(task.attemptId);
            },
          );
    expect(result.state, DownloadState.finalizing, reason: result.error);
    await resumedResponse.future.timeout(_requestTimeout);

    final downloaded = File(await nativeTask.filePath());
    expect(await downloaded.readAsBytes(), bytes);
  } finally {
    isStoppingInitial = true;
    if (!releaseInitial.isCompleted) {
      releaseInitial.complete();
    }
    await fixture.close([task]);
  }
}

Future<TransferSnapshot> _retryInterruptedDownload(
  Stream<TransferSnapshot> events,
  Completer<void> interrupt,
) async {
  final milestones = StreamIterator(
    events.where(
      (event) => event.state == DownloadState.retrying || _isTerminal(event),
    ),
  );
  try {
    // The plugin owns the retry and must keep the interrupted attempt's resume data.
    final retry = milestones.moveNext();
    interrupt.complete();
    expect(await retry.timeout(_requestTimeout), isTrue);
    expect(milestones.current.state, DownloadState.retrying);

    expect(await milestones.moveNext().timeout(_transferTimeout), isTrue);
    return milestones.current;
  } finally {
    await milestones.cancel();
  }
}

Future<TransferSnapshot> _resumePausedDownload(
  Stream<TransferSnapshot> events, {
  required Future<bool> Function() pause,
  required Future<bool> Function() resume,
}) async {
  await _actAndObserve(
    events.where((event) => event.state == DownloadState.paused),
    pause,
    description: 'Pause the native download',
  );

  return _actAndObserve(
    events.where(_isTerminal),
    resume,
    description: 'Resume a paused download to a terminal state',
  );
}

Future<void> _sendResumedDownload(HttpRequest request, Uint8List bytes) async {
  final range = request.headers.value(HttpHeaders.rangeHeader);
  final match = _resumeRange.firstMatch(range ?? '');
  expect(
    match,
    isNotNull,
    reason: 'Resuming must request a positive byte offset',
  );

  final start = int.parse(match!.group(1)!);
  final lastByte = bytes.length - 1;
  expect(start, inInclusiveRange(1, lastByte));
  final requestedEnd = match.group(2)!;
  final end = requestedEnd.isEmpty ? lastByte : int.parse(requestedEnd);
  expect(end, inInclusiveRange(start, lastByte));

  final response = request.response;
  // Android restarts on 200. URLSession uses a valid 206 to resume the partial file.
  final isPartialResponse = Platform.isIOS;
  final bodyStart = isPartialResponse ? start : 0;
  final bodyEnd = isPartialResponse ? end + 1 : bytes.length;
  response.statusCode = isPartialResponse
      ? HttpStatus.partialContent
      : HttpStatus.ok;
  if (isPartialResponse) {
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/${bytes.length}',
    );
  }

  response.contentLength = bodyEnd - bodyStart;
  response.add(Uint8List.sublistView(bytes, bodyStart, bodyEnd));
  await response.close();
}

Future<TransferSnapshot> _actAndObserve(
  Stream<TransferSnapshot> expectedEvents,
  Future<bool> Function() action, {
  required String description,
}) async {
  final observation = StreamIterator(expectedEvents);
  try {
    // Subscribe before invoking a method that can synchronously emit the event.
    await Future.wait<void>([
      observation.moveNext().then((hasEvent) {
        expect(hasEvent, isTrue, reason: description);
      }),
      Future.sync(action).then((isAccepted) {
        expect(isAccepted, isTrue, reason: description);
      }),
    ], eagerError: true).timeout(_transferTimeout);
    return observation.current;
  } finally {
    await observation.cancel();
  }
}

bool _isTerminal(TransferSnapshot event) =>
    event.state == DownloadState.finalizing ||
    event.state == DownloadState.failed;

Uint8List _fixtureBytes(int size) => Uint8List.fromList(
  List.generate(size, (index) => index % _bytePatternPeriod),
);

DownloadTask _task(String name) {
  final id = 'fixture-$name-${DateTime.now().microsecondsSinceEpoch}';

  return DownloadTask(
    id: id,
    attemptId: id,
    selection: const ProgrammeSelection(
      programme: Programme(id: '1', name: 'Fixture'),
      broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
      content: ProgrammeContent(id: '3', title: 'Native fixture'),
    ),
    requestedQuality: VideoQuality.standard,
    quality: VideoQuality.standard,
    url: 'https://fscgc.scgchc.com/fixture.mp4',
    filename: '$id.mp4',
    wifiOnly: false,
    state: DownloadState.preparing,
    createdAt: DateTime.now(),
  );
}

class _NativeFixture {
  final engine = native.FileDownloader();
  late final gateway = BackgroundTransferGateway(downloader: engine);
  late final _files = NativeDownloadFiles(downloader: engine);
  final _responses = <Future<void>>[];
  HttpServer? _server;

  Future<void> serve(Future<void> Function(HttpRequest) respond) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((request) {
      final response = Future.sync(() => respond(request));
      _responses.add(response);
      // Cleanup joins the responses and reports unexpected handler errors.
      response.ignore();
    });
  }

  native.DownloadTask nativeTask(DownloadTask task, String path) {
    final validated = gateway.buildNativeTask(task);

    return validated.copyWith(url: 'http://127.0.0.1:${_server!.port}/$path');
  }

  Future<void> verifyPublication(
    DownloadTask task,
    String location,
    int expectedBytes,
  ) async {
    expect((await _files.inspect(location)).bytes, expectedBytes);
    final published = await _files.publish(task, location);
    try {
      expect((await _files.inspect(published)).bytes, expectedBytes);
      expect(
        published,
        Platform.isIOS
            ? startsWith('documents:Downloads/')
            : startsWith('content://'),
      );
    } finally {
      await _files.delete(published);
    }
    expect((await _files.inspect(published)).exists, isFalse);
  }

  Future<void> waitForResponses() async {
    await Future.wait(_responses).timeout(_requestTimeout);
  }

  Future<void> close(List<DownloadTask> tasks) async {
    await closeAppResources([
      () => _server?.close(force: true),
      waitForResponses,
      () => engine.cancelTasksWithIds(tasks.map((task) => task.attemptId)),
      for (final task in tasks) ...[
        () => _files.cleanPartial(task),
        () => engine.database.deleteRecordWithId(task.attemptId),
      ],
      gateway.dispose,
    ]);
  }
}
