import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_repository.dart';
import 'package:sctv_dl_mobile/domain/downloads/download_task.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/downloads/download_management.dart';

DownloadTask task(String id, DownloadState state, {bool resumable = false}) =>
    DownloadTask(
      id: id,
      attemptId: 'attempt-$id',
      selection: const ProgrammeSelection(
        programme: Programme(id: '1', name: 'News'),
        broadcast: BroadcastDate(id: '2', date: '2026-10-17'),
        content: ProgrammeContent(id: '3', title: 'News'),
      ),
      requestedQuality: VideoQuality.standard,
      quality: VideoQuality.standard,
      url: 'https://fscgc.scgchc.com/video.mp4',
      filename: '$id.mp4',
      wifiOnly: true,
      state: state,
      createdAt: DateTime(2026),
      canResume: resumable,
    );

void main() {
  test(
    'filters keep paused transfers active and publication errors unfinished',
    () {
      expect(
        DownloadFilter.active.includes(task('1', DownloadState.paused)),
        isTrue,
      );
      final publication = task(
        '2',
        DownloadState.finalizing,
      ).copyWith(error: 'full');
      expect(DownloadFilter.active.includes(publication), isFalse);
      expect(DownloadFilter.unfinished.includes(publication), isTrue);
      expect(
        DownloadFilter.unfinished.includes(task('3', DownloadState.missing)),
        isFalse,
      );
      expect(
        DownloadFilter.removed.includes(task('3', DownloadState.missing)),
        isTrue,
      );
    },
  );

  test(
    'batch actions respect native resume and file lifecycle capabilities',
    () {
      final running = task('1', DownloadState.running);
      expect(DownloadAction.pause.supports(running), isFalse);
      expect(
        DownloadAction.pause.supports(running.copyWith(canResume: true)),
        isTrue,
      );
      expect(DownloadAction.remove.supports(running), isFalse);
      expect(
        DownloadAction.cancel.supports(task('2', DownloadState.finalizing)),
        isFalse,
      );
      expect(
        DownloadAction.deleteFile.supports(task('3', DownloadState.missing)),
        isFalse,
      );
      expect(
        DownloadAction.remove.supports(task('3', DownloadState.missing)),
        isTrue,
      );
      expect(
        DownloadAction.retry.supports(task('4', DownloadState.completed)),
        isFalse,
      );
    },
  );

  test(
    'batch continues after a failure and skips changed attempts or states',
    () async {
      final selected = [
        for (var i = 1; i <= 5; i++) task('$i', DownloadState.failed),
      ];
      final repository = BatchRepository([
        selected[0],
        selected[1],
        selected[2],
        selected[3].copyWith(attemptId: 'replacement'),
        selected[4].copyWith(state: DownloadState.running),
      ]);
      final result = await runDownloadBatch(
        repository,
        DownloadAction.retry,
        selected,
      );
      expect(repository.calls, ['1', '2', '3']);
      expect(result.succeeded, ['1', '3']);
      expect(result.failures.keys, ['2']);
      expect(result.failures['2'], contains('offline'));
      expect(result.skipped, ['4', '5']);
    },
  );
}

class BatchRepository implements DownloadRepository {
  BatchRepository(this.tasks);
  final List<DownloadTask> tasks;
  final calls = <String>[];
  @override
  Future<List<DownloadTask>> loadTasks() async => tasks;
  @override
  Future<void> retry(String id) async {
    calls.add(id);
    if (id == '2') throw StateError('offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
