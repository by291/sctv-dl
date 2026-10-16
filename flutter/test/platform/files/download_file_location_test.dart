import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/downloads/file_gateway.dart';

void main() {
  test(
    'relative references survive sandbox changes and encode Chinese names',
    () {
      final location = DownloadFileLocation.parse(
        'documents:Downloads/%E6%96%B0%E9%97%BB.mp4',
      );
      expect(location, isA<PrivateFileLocation>());
      expect(
        (location as PrivateFileLocation).relativePath,
        'Downloads/新闻.mp4',
      );
      expect(location.value, 'documents:Downloads/%E6%96%B0%E9%97%BB.mp4');
    },
  );
  test('rejects traversal, absolute and network locations', () {
    for (final location in [
      'support:downloads/../secret.mp4',
      'support:/downloads/file.mp4',
      'file:///tmp/file.mp4',
      'https://example.com/file.mp4',
      'documents:private/file.mp4',
      'support:downloads/%2fetc/passwd',
      'support:downloads/a%5cb.mp4',
    ]) {
      expect(
        () => DownloadFileLocation.parse(location),
        throwsFormatException,
        reason: location,
      );
    }
  });
}
