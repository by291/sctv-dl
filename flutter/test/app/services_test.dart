import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/app/services.dart';
import 'package:sctv_dl_mobile/domain/settings/preferences.dart';

import '../support/fakes.dart';
import 'router_test.dart'
    show RouteDownloads, RouteHistory, CapturingBackend, UnusedCoverCache;

class FailingDownloadDisposal extends RouteDownloads {
  int calls = 0;

  @override
  Future<void> dispose() async {
    calls++;
    throw StateError('download cleanup failed');
  }
}

class TrackedCoverCache extends UnusedCoverCache {
  int calls = 0;

  @override
  Future<void> dispose() async {
    calls++;
  }
}

void main() {
  test(
    'failed resource disposal still closes independent resources exactly once',
    () async {
      final downloads = FailingDownloadDisposal();
      final covers = TrackedCoverCache();
      final user = FakeUserRepository();
      addTearDown(user.close);
      var remainingClosed = 0;
      final services = AppServices(
        programmes: FakeProgrammeRepository(),
        user: user,
        history: RouteHistory(),
        downloads: downloads,
        playback: CapturingBackend(),
        initialPreferences: const Preferences(),
        initialFavourites: {},
        version: 'test',
        coverCache: covers,
        closeResources: () async {
          remainingClosed++;
        },
      );

      await expectLater(services.dispose(), throwsA(anything));
      await expectLater(services.dispose(), throwsA(anything));

      expect(covers.calls, 1);
      expect(remainingClosed, 1);
      expect(downloads.calls, 1);
    },
  );
}
