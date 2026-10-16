import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/platform/storage/runtime_backup_policy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'runtime and native plugin state are excluded before transfers start',
    () async {
      final root = await Directory.systemTemp.createTemp('backup-policy-');
      addTearDown(() => root.delete(recursive: true));
      final support = Directory('${root.path}/Library/Application Support');
      final documents = Directory('${root.path}/Documents');
      final excluded = <String>[];
      const channel = MethodChannel('test/backup');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final path = (call.arguments as Map)['path'] as String;
            expect(await Directory(path).exists(), isTrue);
            excluded.add(path);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await excludeIOSRuntimeState(
        support: support,
        documents: documents,
        channel: channel,
      );
      expect(
        excluded,
        containsAll([
          '${support.path}/runtime',
          '${support.path}/backgroundDownloaderTaskRecords',
          '${support.path}/backgroundDownloaderResumeData',
          '${support.path}/backgroundDownloaderPausedTasks',
          '${support.path}/backgroundDownloaderDatabase',
          '${root.path}/Library/Preferences',
          '${documents.path}/Downloads',
        ]),
      );
      expect(excluded.any((path) => path.endsWith('user.sqlite')), isFalse);
    },
  );
}
