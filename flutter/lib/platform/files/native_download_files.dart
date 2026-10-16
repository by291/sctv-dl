import 'dart:io';
import 'dart:ui';

import 'package:background_downloader/background_downloader.dart' as native;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/downloads/download_task.dart';
import '../../domain/downloads/file_gateway.dart';

/// Resolves sandbox references afresh. The owning native host recovers pending
/// MediaStore publications and handles resolver/share/export capabilities.
class NativeDownloadFiles implements DownloadFileGateway {
  NativeDownloadFiles({
    native.FileDownloader? downloader,
    this._channel = const MethodChannel('dev.sctvdl.flutter/files'),
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? documentsDirectory,
    bool? isIOS,
  }) : _providedDownloader = downloader,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _isIOS = isIOS ?? Platform.isIOS;

  final native.FileDownloader? _providedDownloader;
  native.FileDownloader get _downloader =>
      _providedDownloader ?? native.FileDownloader();
  final MethodChannel _channel;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _documentsDirectory;
  final bool _isIOS;
  @override
  bool get supportsExport => _isIOS;

  Future<File> _privateFile(PrivateFileLocation location) async {
    // parse() validates segments, including decoded separators and traversal.
    final safe =
        DownloadFileLocation.parse(location.value) as PrivateFileLocation;
    final root = await (safe.documents
        ? _documentsDirectory()
        : _supportDirectory());
    return File('${root.path}/${safe.relativePath}');
  }

  Future<Uri> _uri(String location) async => switch (DownloadFileLocation.parse(
    location,
  )) {
    ContentFileLocation(:final uri) => uri,
    final PrivateFileLocation reference => (await _privateFile(reference)).uri,
  };
  @override
  Future<FileDetails> inspect(String location) async {
    final reference = DownloadFileLocation.parse(location);
    if (reference is ContentFileLocation) {
      final result = await _channel.invokeMapMethod<String, Object?>('stat', {
        'location': reference.value,
      });
      final bytes = result?['bytes'];
      return FileDetails(
        exists: result?['exists'] == true,
        bytes: bytes is int && bytes >= 0 ? bytes : null,
      );
    }
    final file = await _privateFile(reference as PrivateFileLocation);
    final stat = await file.stat();
    return FileDetails(
      exists: stat.type == FileSystemEntityType.file,
      bytes: stat.type == FileSystemEntityType.file ? stat.size : null,
    );
  }

  @override
  Future<String> publish(DownloadTask task, String privateLocation) async {
    final location = DownloadFileLocation.parse(privateLocation);
    if (location is! PrivateFileLocation) {
      throw ArgumentError('Publication requires an owned private file');
    }
    final file = await _privateFile(location);
    if (_isIOS) {
      if (!location.documents ||
          !location.relativePath.startsWith('Downloads/')) {
        throw StateError('iOS downloads must be in Documents/Downloads');
      }
      if (!(await inspect(privateLocation)).exists) {
        throw StateError('Downloaded file is missing');
      }
      return location.value;
    }
    if (!await file.exists()) throw StateError('Downloaded file is missing');
    // Native recovery distinguishes our pending rows from visible publications.
    // Keep the source until the repository durably commits the returned URI.
    final published = await _channel.invokeMethod<String>(
      'publishRecoverable',
      {'sourcePath': file.path, 'filename': task.filename},
    );
    if (published == null || Uri.tryParse(published)?.scheme != 'content') {
      throw StateError('Could not publish video to Downloads/sctv-dl');
    }
    return published;
  }

  @override
  Future<void> cleanPartial(DownloadTask task) async {
    final location = PrivateFileLocation(
      _isIOS,
      _isIOS
          ? 'Downloads/${task.filename}'
          : 'downloads/${task.attemptId}/${task.filename}',
    );
    final file = await _privateFile(location);
    if (await file.exists()) await file.delete();
    // Native cancellation owns the plugin's opaque partial/resume artifacts.
  }

  @override
  Future<void> delete(String location) async {
    final reference = DownloadFileLocation.parse(location);
    if (reference is PrivateFileLocation) {
      final file = await _privateFile(reference);
      if (await file.exists()) await file.delete();
    } else {
      // The plugin's DocumentFile deletion rejects MediaStore Downloads URIs.
      // The host instead invokes ContentResolver.delete for the owned URI.
      final deleted = await _channel.invokeMethod<bool>('delete', {
        'location': reference.value,
      });
      if (deleted != true) {
        throw StateError('Could not delete downloaded video');
      }
    }
    if ((await inspect(location)).exists) {
      throw StateError('Video still exists after deletion');
    }
  }

  @override
  Future<void> open(String location) async {
    if (!(await inspect(location)).exists) {
      throw StateError('Downloaded file is missing');
    }
    if (!await _downloader.uri.openFile(
      await _uri(location),
      mimeType: 'video/mp4',
    )) {
      throw StateError('No application could open this video');
    }
  }

  @override
  Future<void> share(String location, String filename) async {
    if (!(await inspect(location)).exists) {
      throw StateError('Downloaded file is missing');
    }
    final uri = await _uri(location);
    if (uri.scheme == 'content') {
      if (await _channel.invokeMethod<bool>('share', {
            'location': uri.toString(),
            'filename': filename,
          }) !=
          true) {
        throw StateError('Could not open sharing');
      }
      return;
    }
    final view = PlatformDispatcher.instance.views.firstOrNull;
    final size = view == null
        ? const Size(1, 1)
        : view.physicalSize / view.devicePixelRatio;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(uri.toFilePath(), mimeType: 'video/mp4', name: filename)],
        sharePositionOrigin: Rect.fromLTWH(
          size.width / 2,
          size.height / 2,
          1,
          1,
        ),
      ),
    );
  }

  @override
  Future<bool> export(String location, String filename) async {
    if (!supportsExport) {
      throw UnsupportedError('Save to Files is available on iOS');
    }
    if (!(await inspect(location)).exists) {
      throw StateError('Downloaded file is missing');
    }
    final uri = await _uri(location);
    if (uri.scheme != 'file') {
      throw ArgumentError('Save to Files requires an owned local file');
    }
    // A dismissed picker is an ordinary false result, and never deletes media.
    return await _channel.invokeMethod<bool>('export', {
          'path': uri.toFilePath(),
          'filename': filename,
        }) ??
        false;
  }
}
