import 'dart:convert';

import '../../domain/downloads/download_task.dart';
import '../../domain/downloads/file_gateway.dart';
import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_policy.dart';

Map<String, Object?> encodeDownloadTask(DownloadTask task) => {
  'version': 1,
  'id': task.id,
  'attemptId': task.attemptId,
  'programme': {
    'id': task.selection.programme.id,
    'name': task.selection.programme.name,
    'cover': task.selection.programme.cover,
  },
  'broadcast': {
    'id': task.selection.broadcast.id,
    'date': task.selection.broadcast.date,
  },
  'content': {
    'id': task.selection.content.id,
    'title': task.selection.content.title,
    'cover': task.selection.content.cover,
    'video': task.selection.content.video,
    'smoothVideo': task.selection.content.smoothVideo,
    'publishedAt': task.selection.content.publishedAt,
  },
  'requestedQuality': task.requestedQuality.name,
  'quality': task.quality.name,
  'url': task.url,
  'filename': task.filename,
  'wifiOnly': task.wifiOnly,
  'state': task.state.name,
  'createdAt': task.createdAt.toIso8601String(),
  'receivedBytes': task.receivedBytes,
  'totalBytes': task.totalBytes,
  'fileLocation': task.fileLocation,
  'privateLocation': task.privateLocation,
  'error': task.error,
  'canResume': task.canResume,
  'revision': task.revision,
};

DownloadTask decodeDownloadTask(Map<String, Object?> json) {
  if (json['version'] != 1) {
    throw const FormatException('Unsupported download record version');
  }

  final programme = _map(json['programme']);
  final broadcast = _map(json['broadcast']);
  final content = _map(json['content']);

  final url = _string(json, 'url');
  final filename = _string(json, 'filename');
  if (!isAllowedMediaUrl(url) ||
      filename.isEmpty ||
      filename == '.' ||
      filename == '..' ||
      filename.contains(RegExp(r'[/\\\x00-\x1f]')) ||
      utf8.encode(filename).length > 255) {
    throw const FormatException('Invalid persisted media destination');
  }

  for (final key in ['fileLocation', 'privateLocation']) {
    if (json[key] != null) DownloadFileLocation.parse(json[key] as String);
  }

  return DownloadTask(
    id: _string(json, 'id'),
    attemptId: _string(json, 'attemptId'),
    selection: ProgrammeSelection(
      programme: Programme(
        id: _id(programme),
        name: _string(programme, 'name'),
        cover: programme['cover'] as String?,
      ),
      broadcast: BroadcastDate(
        id: _id(broadcast),
        date: _string(broadcast, 'date'),
      ),
      content: ProgrammeContent(
        id: _id(content),
        title: _string(content, 'title'),
        cover: content['cover'] as String?,
        video: content['video'] as String?,
        smoothVideo: content['smoothVideo'] as String?,
        publishedAt: content['publishedAt'] as String?,
      ),
    ),
    requestedQuality: VideoQuality.values.byName(
      _string(json, 'requestedQuality'),
    ),
    quality: VideoQuality.values.byName(_string(json, 'quality')),
    url: url,
    filename: filename,
    wifiOnly: json['wifiOnly'] as bool,
    state: DownloadState.values.byName(_string(json, 'state')),
    createdAt: DateTime.parse(_string(json, 'createdAt')),
    receivedBytes: _bytes(json['receivedBytes']),
    totalBytes: json['totalBytes'] == null ? null : _bytes(json['totalBytes']),
    fileLocation: json['fileLocation'] as String?,
    privateLocation: json['privateLocation'] as String?,
    error: json['error'] as String?,
    canResume: json['canResume'] as bool? ?? false,
    revision: _bytes(json['revision']),
  );
}

Map<String, Object?> _map(Object? value) =>
    Map<String, Object?>.from(value as Map);

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('Invalid download $key');
  }

  return value;
}

String _id(Map<String, Object?> json) {
  final value = _string(json, 'id');
  if (!RegExp(r'^\d+$').hasMatch(value)) {
    throw const FormatException('Invalid content identity');
  }

  return value;
}

int _bytes(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('Invalid download byte count or revision');
  }

  return value;
}
