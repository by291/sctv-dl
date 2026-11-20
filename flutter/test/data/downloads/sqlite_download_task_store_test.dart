import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/downloads/sqlite_download_task_store.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

// Version 1 before the download issue code field was introduced.
const _legacyFailedDownload = '''
{
  "version": 1,
  "id": "saved-download",
  "attemptId": "second-attempt",
  "programme": {"id": "1001", "name": "四川新闻", "cover": null},
  "broadcast": {"id": "2001", "date": "2026-10-16"},
  "content": {
    "id": "3001",
    "title": "四川新闻20261016",
    "cover": null,
    "video": "https://fscgc.scgchc.com/standard.mp4",
    "smoothVideo": "https://fscgc.scgchc.com/smooth.mp4",
    "publishedAt": "2026-10-16"
  },
  "requestedQuality": "standard",
  "quality": "smooth",
  "url": "https://fscgc.scgchc.com/smooth.mp4",
  "filename": "news.mp4",
  "wifiOnly": true,
  "state": "failed",
  "createdAt": "2026-10-16T02:03:04.000Z",
  "receivedBytes": 1024,
  "totalBytes": null,
  "fileLocation": null,
  "privateLocation": "support:downloads/second-attempt/news.mp4",
  "error": "The connection was lost.",
  "canResume": true,
  "revision": 7
}
''';

const _legacyPublishedDownload = '''
{
  "version": 1,
  "id": "published-download",
  "attemptId": "published-attempt",
  "programme": {"id": "1002", "name": "四川观察", "cover": null},
  "broadcast": {"id": "2002", "date": "2026-10-17"},
  "content": {
    "id": "3002",
    "title": "四川观察20261017",
    "cover": null,
    "video": "https://fscgc.scgchc.com/observation.mp4",
    "smoothVideo": null,
    "publishedAt": "2026-10-17"
  },
  "requestedQuality": "standard",
  "quality": "standard",
  "url": "https://fscgc.scgchc.com/observation.mp4",
  "filename": "observation.mp4",
  "wifiOnly": false,
  "state": "completed",
  "createdAt": "2026-10-17T02:03:04.000Z",
  "receivedBytes": 8192,
  "totalBytes": 8192,
  "fileLocation": "content://media/external/video/media/41",
  "privateLocation": null,
  "error": null,
  "canResume": false,
  "revision": 9
}
''';

void main() {
  test(
    'reopens legacy downloads with their private and published locations',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sctv-downloads-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final databaseFile = File('${directory.path}/runtime.sqlite');

      final seeded = RecordDatabase.open(databaseFile);
      try {
        for (final payload in [
          _legacyFailedDownload,
          _legacyPublishedDownload,
        ]) {
          final record = jsonDecode(payload) as Map<String, Object?>;
          await seeded.write('downloads', record['id'] as String, record);
        }
      } finally {
        await seeded.close();
      }

      final reopened = RecordDatabase.open(databaseFile);
      addTearDown(reopened.close);
      final records = await SqliteDownloadTaskStore(reopened).load();
      expect(records, hasLength(2));

      final restored = records.singleWhere(
        (task) => task.id == 'saved-download',
      );

      expect(restored.attemptId, 'second-attempt');
      expect(restored.selection.programme.id, '1001');
      expect(restored.selection.broadcast.id, '2001');
      expect(restored.selection.content.id, '3001');
      expect(restored.requestedQuality, VideoQuality.standard);
      expect(restored.quality, VideoQuality.smooth);
      expect(restored.url, 'https://fscgc.scgchc.com/smooth.mp4');
      expect(restored.filename, 'news.mp4');
      expect(restored.wifiOnly, isTrue);
      expect(restored.state, DownloadState.failed);
      expect(restored.createdAt, DateTime.utc(2026, 10, 16, 2, 3, 4));
      expect(restored.receivedBytes, 1024);
      expect(restored.totalBytes, isNull);
      expect(restored.fileLocation, isNull);
      expect(
        restored.privateLocation,
        'support:downloads/second-attempt/news.mp4',
      );
      expect(restored.error, 'The connection was lost.');
      expect(restored.issueCode, isNull);
      expect(restored.canResume, isTrue);
      expect(restored.revision, 7);

      final published = records.singleWhere(
        (task) => task.id == 'published-download',
      );
      expect(published.state, DownloadState.completed);
      expect(published.attemptId, 'published-attempt');
      expect(published.totalBytes, 8192);
      expect(published.fileLocation, 'content://media/external/video/media/41');
      expect(published.privateLocation, isNull);
      expect(published.error, isNull);
    },
  );
}
