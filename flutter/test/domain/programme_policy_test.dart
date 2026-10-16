import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_policy.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';

void main() {
  test('media URLs follow the shared historical and current CDN policy', () {
    final cases = jsonDecode(
      File('../shared/fixtures/media-policy.json').readAsStringSync(),
    ) as List;
    for (final item in cases) {
      final fixture = item as Map<String, dynamic>;
      expect(
        isAllowedMediaUrl(fixture['url'] as String),
        fixture['allowed'],
        reason: fixture['url'] as String,
      );
    }
  });

  test('quality fallback reports actual quality and deduplicates sources', () {
    const item = ProgrammeContent(
      id: '7',
      title: 'Clip',
      video: 'https://fscgc.scgchc.com/a.mp4',
    );
    expect(
      resolveVideo(item, VideoQuality.smooth)?.quality,
      VideoQuality.standard,
    );
    expect(
      videoSources(
        const ProgrammeContent(
          id: '8',
          title: 'Duplicate',
          video: 'https://fscgc.scgchc.com/a.mp4',
          smoothVideo: 'https://fscgc.scgchc.com/a.mp4',
        ),
      ),
      hasLength(1),
    );
    expect(
      resolveVideo(
        const ProgrammeContent(id: '9', title: 'No video'),
        VideoQuality.standard,
      ),
      isNull,
    );
  });

  test('full episodes require the matching name and broadcast date', () {
    expect(isFullEpisode(' 四川新闻 （2026.10.16） ', '四川新闻', '2026-10-16'), isTrue);
    expect(isFullEpisode('四川新闻(2026.10.16)', '四川新闻', '2026-10-16'), isTrue);
    expect(isFullEpisode('四川新闻（2026.10.15）', '四川新闻', '2026-10-16'), isFalse);
    expect(isFullEpisode('四川新闻 今日片段', '四川新闻', '2026-10-16'), isFalse);
  });

  test(
    'clip ordering keeps ties stable and unknown times last in both directions',
    () {
      const items = [
        ProgrammeContent(id: '1', title: 'Unknown'),
        ProgrammeContent(
          id: '2',
          title: 'Later',
          publishedAt: '2026-10-16 18:30:01',
        ),
        ProgrammeContent(
          id: '3',
          title: 'Earlier',
          publishedAt: '2026-10-16T10:30:00Z',
        ),
        ProgrammeContent(
          id: '4',
          title: 'Tie',
          publishedAt: '2026-10-16 18:30:00',
        ),
      ];
      expect(orderClips(items).map((item) => item.id), ['3', '4', '2', '1']);
      expect(orderClips(items, ascending: false).map((item) => item.id), [
        '2',
        '3',
        '4',
        '1',
      ]);
      expect(publicationTime('2026-02-30 10:00:00'), isNull);
    },
  );

  test(
    'long Unicode filenames preserve quality and uniqueness within 255 bytes',
    () {
      final selection = ProgrammeSelection(
        programme: const Programme(id: '1', name: 'News'),
        broadcast: const BroadcastDate(id: '2', date: '2026-10-16'),
        content: ProgrammeContent(id: '3', title: '${'节目😀' * 100}:/'),
      );
      final filename = downloadFilename(
        selection,
        VideoQuality.smooth,
        suffix: 'abc123',
      );
      expect(utf8.encode(filename).length, lessThanOrEqualTo(255));
      expect(filename, endsWith('_流畅_abc123.mp4'));
      expect(filename, isNot(contains('/')));
      expect(filename, isNot(contains(':')));
      expect(utf8.decode(utf8.encode(filename)), filename);
    },
  );

  test(
    'completed request cancellation listeners can detach before cancellation',
    () {
      final scope = RequestScope();
      var completed = 0;
      var active = 0;
      final detach = scope.onCancel(() => completed++);
      scope.onCancel(() => active++);
      detach();
      scope.cancel();
      scope.cancel();
      expect(completed, 0);
      expect(active, 1);
      expect(scope.throwIfCancelled, throwsA(isA<RequestCancelled>()));
    },
  );
}
