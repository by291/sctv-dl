import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/services.dart';

/// Excludes reconstructible data before the native downloader can write it.
/// User preferences, favourites and history live in the separate user.sqlite.
Future<void> excludeIOSRuntimeState({
  required Directory support,
  required Directory documents,
  MethodChannel channel = const MethodChannel('dev.sctvdl.flutter/files'),
}) async {
  final paths = [
    '${support.path}/runtime',
    '${support.path}/${LocalStorePersistentStorage.taskRecordsPath}',
    '${support.path}/${LocalStorePersistentStorage.resumeDataPath}',
    '${support.path}/${LocalStorePersistentStorage.pausedTasksPath}',
    // This metadata collection name belongs to the pinned plugin's Localstore.
    '${support.path}/backgroundDownloaderDatabase',
    // Native undelivered callbacks/resume maps use UserDefaults.standard.
    // All user-facing settings belong to user.sqlite, never this directory.
    '${support.parent.path}/Preferences',
    '${documents.path}/Downloads',
  ];
  for (final path in paths) {
    await Directory(path).create(recursive: true);
    final excluded = await channel.invokeMethod<bool>('excludeFromBackup', {
      'path': path,
    });
    if (excluded != true) {
      throw StateError('Could not exclude runtime data from backup');
    }
  }
}
