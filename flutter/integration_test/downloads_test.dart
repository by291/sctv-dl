import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/downloads/transfer_gateway.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/platform/downloads/background_transfer_gateway.dart';
import 'package:sctv_dl_mobile/platform/files/native_download_files.dart';

/// Run only on a disposable Android/iOS runtime. Loopback rewriting exists in
/// this test, after production URL validation; it is not a product URL escape.
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
      await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final engine = native.FileDownloader();
        final gateway = BackgroundTransferGateway(downloader: engine);
        final files = NativeDownloadFiles(downloader: engine);
        final events = <TransferSnapshot>[];
        final subscription = gateway.events.listen(events.add);
        final firstTwo = Completer<void>();
        final release = Completer<void>();
        final requests = <HttpRequest>[];
        var concurrent = 0;
        var maximum = 0;
        final bytes = Uint8List.fromList(
          List.generate(256 * 1024, (index) => index % 251),
        );
        server.listen((request) async {
          requests.add(request);
          concurrent++;
          if (concurrent > maximum) maximum = concurrent;
          if (requests.length == 2 && !firstTwo.isCompleted) {
            firstTwo.complete();
          }
          try {
            request.response.headers.contentType = ContentType('video', 'mp4');
            if (!request.uri.path.contains('unknown')) {
              request.response.contentLength = bytes.length;
            }
            await release.future;
            request.response.add(bytes);
            await request.response.close();
          } finally {
            concurrent--;
          }
        });
        final tasks = List.generate(
          3,
          (index) =>
              _task('fixture-${DateTime.now().microsecondsSinceEpoch}-$index'),
        );
        final nativeTasks = tasks
            .map(
              (task) => gateway
                  .buildNativeTask(task)
                  .copyWith(
                    url:
                        'http://127.0.0.1:${server.port}/${task.id == tasks.last.id ? 'unknown' : 'known'}.mp4',
                  ),
            )
            .toList();
        try {
          await gateway.initialize();
          final completions = nativeTasks
              .map(
                (task) => gateway.events
                    .firstWhere(
                      (event) =>
                          event.attemptId == task.taskId &&
                          {
                            DownloadState.finalizing,
                            DownloadState.failed,
                          }.contains(event.state),
                    )
                    .timeout(const Duration(seconds: 60)),
              )
              .toList();
          for (final task in nativeTasks) {
            expect(await engine.enqueue(task), isTrue);
          }
          await firstTwo.future.timeout(const Duration(seconds: 30));
          expect(requests.length, 2);
          release.complete();
          final completed = await Future.wait(completions);
          expect(maximum, lessThanOrEqualTo(2));
          for (var index = 0; index < completed.length; index++) {
            final event = completed[index];
            expect(event.state, DownloadState.finalizing, reason: event.error);
            final local = event.fileLocation!;
            expect((await files.inspect(local)).bytes, bytes.length);
            final published = await files.publish(tasks[index], local);
            expect((await files.inspect(published)).bytes, bytes.length);
            expect(
              published,
              Platform.isIOS
                  ? startsWith('documents:Downloads/')
                  : startsWith('content://'),
            );
            await files.delete(published);
            expect((await files.inspect(published)).exists, isFalse);
          }
          expect(
            events
                .where(
                  (event) =>
                      event.attemptId == tasks.last.attemptId &&
                      event.state == DownloadState.running,
                )
                .every((event) => event.totalBytes == null),
            isTrue,
          );
          for (final request in requests) {
            expect(
              request.headers.value('referer'),
              'https://scgc.video.play/',
            );
            expect(request.headers.value('user-agent'), 'okhttp/4.12.0');
            expect(request.headers.value('authorization'), isNull);
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await engine.cancelTasksWithIds(tasks.map((task) => task.attemptId));
          for (final task in tasks) {
            await files.cleanPartial(task);
            await engine.database.deleteRecordWithId(task.attemptId);
          }
          await subscription.cancel();
          await gateway.dispose();
          await server.close(force: true);
        }
      });
    },
  );
  testWidgets(
    'ignored resume Range restarts cleanly or reports a transfer failure',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Resume fixture'))),
      );
      await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final engine = native.FileDownloader();
        final gateway = BackgroundTransferGateway(downloader: engine);
        final files = NativeDownloadFiles(downloader: engine);
        final bytes = Uint8List.fromList(
          List.generate(8 * 1024 * 1024, (index) => index % 251),
        );
        final task = _task('resume-${DateTime.now().microsecondsSinceEpoch}');
        final nativeTask = gateway
            .buildNativeTask(task)
            .copyWith(url: 'http://127.0.0.1:${server.port}/ignore-range.mp4');
        var ranges = 0;
        server.listen((request) async {
          if (request.headers.value('range') != null) ranges++;
          request.response.headers.contentType = ContentType('video', 'mp4');
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.headers.set('ETag', '"fixture-v1"');
          request.response.contentLength = bytes.length;
          try {
            for (var start = 0; start < bytes.length; start += 65536) {
              request.response.add(bytes.sublist(start, start + 65536));
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 40));
            }
          } catch (_) {
            // Pausing intentionally interrupts the fixture response.
          } finally {
            await request.response.close().catchError((_) {});
          }
        });
        try {
          await gateway.initialize();
          final resumable = gateway.events
              .firstWhere(
                (event) =>
                    event.attemptId == task.attemptId &&
                    event.state == DownloadState.running &&
                    event.receivedBytes > 0 &&
                    event.canResume,
              )
              .timeout(const Duration(seconds: 30));
          expect(await engine.enqueue(nativeTask), isTrue);
          await resumable;
          final paused = gateway.events
              .firstWhere(
                (event) =>
                    event.attemptId == task.attemptId &&
                    event.state == DownloadState.paused,
              )
              .timeout(const Duration(seconds: 30));
          expect(await gateway.pause(task.attemptId), isTrue);
          await paused;
          final resumed = await gateway.resume(task.attemptId);
          if (resumed) {
            final terminal = gateway.events
                .firstWhere(
                  (event) =>
                      event.attemptId == task.attemptId &&
                      {
                        DownloadState.finalizing,
                        DownloadState.failed,
                      }.contains(event.state),
                )
                .timeout(const Duration(seconds: 60));
            final result = await terminal;
            expect(ranges, greaterThan(0));
            if (result.state == DownloadState.finalizing) {
              expect(
                (await files.inspect(result.fileLocation!)).bytes,
                bytes.length,
              );
              expect(
                await File(await nativeTask.filePath()).readAsBytes(),
                bytes,
              );
            } else {
              expect(result.error, isNotEmpty);
            }
          }
        } finally {
          await engine.cancelTaskWithId(task.attemptId);
          await files.cleanPartial(task);
          await engine.database.deleteRecordWithId(task.attemptId);
          await gateway.dispose();
          await server.close(force: true);
        }
      });
    },
  );
}

DownloadTask _task(String id) => DownloadTask(
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
