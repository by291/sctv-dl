import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/platform/files/native_download_files.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('download-files-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('publication uses owned pending-row recovery and retains private data until durable commit', () async {
    const channel = MethodChannel('test/publish-files');
    final source = File('${root.path}/downloads/attempt/video.mp4');
    await source.parent.create(recursive: true);
    await source.writeAsBytes([1, 2, 3, 4]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'publishRecoverable');
          expect(call.arguments, {
            'sourcePath': source.path,
            'filename': 'video.mp4',
          });
          return 'content://media/external/downloads/41';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final files = NativeDownloadFiles(
      channel: channel,
      isIOS: false,
      supportDirectory: () async => root,
    );
    final task = DownloadTask(
      id: 'record',
      attemptId: 'attempt',
      selection: const ProgrammeSelection(
        programme: Programme(id: '1', name: 'Test'),
        broadcast: BroadcastDate(id: '2', date: '2026-10-16'),
        content: ProgrammeContent(id: '3', title: 'Test'),
      ),
      requestedQuality: VideoQuality.standard,
      quality: VideoQuality.standard,
      url: 'https://fscgc.scgchc.com/video.mp4',
      filename: 'video.mp4',
      wifiOnly: true,
      state: DownloadState.finalizing,
      createdAt: DateTime(2026),
    );
    expect(
      await files.publish(task, 'support:downloads/attempt/video.mp4'),
      'content://media/external/downloads/41',
    );
    expect(await source.readAsBytes(), [1, 2, 3, 4]);
  });
  test(
    'resolves references against the current base and reads actual bytes',
    () async {
      final files = NativeDownloadFiles(
        supportDirectory: () async => root,
        documentsDirectory: () async => root,
      );
      final path = File('${root.path}/downloads/attempt/video.mp4');
      await path.parent.create(recursive: true);
      await path.writeAsBytes([1, 2, 3, 4, 5]);
      final details = await files.inspect(
        'support:downloads/attempt/video.mp4',
      );
      expect(details.exists, isTrue);
      expect(details.bytes, 5);
      await files.delete('support:downloads/attempt/video.mp4');
      expect(
        (await files.inspect('support:downloads/attempt/video.mp4')).exists,
        isFalse,
      );
    },
  );
  test(
    'content URIs use resolver metadata without buffering the file',
    () async {
      const channel = MethodChannel('test/files');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'stat');
            return {'exists': true, 'bytes': 8388608};
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = NativeDownloadFiles(channel: channel);
      final details = await files.inspect(
        'content://media/external/downloads/41',
      );
      expect(details.bytes, 8388608);
    },
  );
  test(
    'MediaStore deletion uses ContentResolver through the owned native channel',
    () async {
      const channel = MethodChannel('test/delete-files');
      var exists = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'delete') {
              exists = false;
              return true;
            }
            if (call.method == 'stat') {
              return {'exists': exists, 'bytes': exists ? 120 : null};
            }
            throw StateError('Unexpected file operation');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final files = NativeDownloadFiles(channel: channel);
      await files.delete('content://media/external/downloads/41');
      expect(
        (await files.inspect('content://media/external/downloads/41')).exists,
        isFalse,
      );
    },
  );
}
