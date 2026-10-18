import 'download_task.dart';

/// Persist a base-directory reference, never a changing sandbox absolute path.
sealed class DownloadFileLocation {
  const DownloadFileLocation();

  String get value;

  static DownloadFileLocation parse(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty) {
      throw FormatException('Invalid download file location', value);
    }

    if (uri.scheme == 'content' && uri.host.isNotEmpty) {
      return ContentFileLocation(uri);
    }

    if ((uri.scheme == 'support' || uri.scheme == 'documents') &&
        !uri.hasAuthority) {
      final segments = uri.pathSegments;
      if (segments.length < 2 ||
          segments.any(
            (s) =>
                s.isEmpty ||
                s == '.' ||
                s == '..' ||
                s.contains(RegExp(r'[/\\\x00-\x1f]')),
          ) ||
          uri.path.startsWith('/') ||
          (uri.scheme == 'support' && segments.first != 'downloads') ||
          (uri.scheme == 'documents' && segments.first != 'Downloads')) {
        throw FormatException('Invalid relative download path', value);
      }

      return PrivateFileLocation(uri.scheme == 'documents', segments.join('/'));
    }

    throw FormatException('Unsupported download location', value);
  }
}

final class PrivateFileLocation extends DownloadFileLocation {
  const PrivateFileLocation(this.documents, this.relativePath);

  final bool documents;
  final String relativePath;

  @override
  String get value => Uri(
    scheme: documents ? 'documents' : 'support',
    path: relativePath,
  ).toString();
}

final class ContentFileLocation extends DownloadFileLocation {
  const ContentFileLocation(this.uri);

  final Uri uri;

  @override
  String get value => uri.toString();
}

class FileDetails {
  const FileDetails({required this.exists, this.bytes});

  final bool exists;
  final int? bytes;
}

abstract interface class DownloadFileGateway {
  bool get supportsExport;

  Future<FileDetails> inspect(String location);

  /// Idempotently recover publication by the unique planned filename.
  Future<String> publish(DownloadTask task, String privateLocation);
  Future<void> cleanPartial(DownloadTask task);
  Future<void> delete(String location);
  Future<void> open(String location);
  Future<void> share(String location, String filename);
  Future<bool> export(String location, String filename);
}
