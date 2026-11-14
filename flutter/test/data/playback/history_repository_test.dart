import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/playback/drift_history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/playback_backend.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/features/player/playback_history_writer.dart';

ViewingEntry entry(int id, {int position = 40, int duration = 100}) =>
    ViewingEntry(
      selection: ProgrammeSelection(
        programme: const Programme(id: '1', name: 'News'),
        broadcast: const BroadcastDate(id: '2', date: '2026-10-16'),
        content: ProgrammeContent(
          id: '$id',
          title: 'Accepted title $id',
          video: 'https://fscgc.scgchc.com/$id.mp4',
        ),
      ),
      position: Duration(seconds: position),
      duration: Duration(seconds: duration),
      viewedAt: DateTime.utc(2026, 10, 16).add(Duration(seconds: id)),
    );

void main() {
  for (final shouldClear in [false, true]) {
    final operation = shouldClear ? 'clearing history' : 'removing an entry';
    test(
      '$operation invalidates pending and future checkpoints from the old session',
      () async {
        final database = RecordDatabase.memory();
        addTearDown(database.close);
        final repository = DriftHistoryRepository(database);
        final selection = entry(1).selection;
        PlaybackHistoryWriter createWriter(ProgrammeSelection selected) =>
            PlaybackHistoryWriter(
              selection: selected,
              repository: repository,
              now: DateTime.now,
              onError: (error) => throw StateError('Checkpoint failed: $error'),
            );

        const initial = PlaybackSnapshot(
          initialized: true,
          position: Duration(seconds: 10),
        );
        const checkpoint = PlaybackSnapshot(
          initialized: true,
          position: Duration(seconds: 20),
        );
        const laterCheckpoint = PlaybackSnapshot(
          initialized: true,
          position: Duration(seconds: 30),
        );
        final oldWriter = createWriter(selection);
        final otherWriter = createWriter(entry(2).selection);
        oldWriter.save(initial);
        await oldWriter.flush();

        oldWriter.save(checkpoint);
        if (shouldClear) {
          await repository.clear();
        } else {
          await repository.remove(selection.ref);
        }
        oldWriter.save(laterCheckpoint);
        otherWriter.save(laterCheckpoint);
        await oldWriter.flush();
        await otherWriter.flush();

        final retained = await repository.loadHistory();
        expect(
          retained.map((entry) => entry.selection.content.id),
          shouldClear ? isEmpty : ['2'],
        );

        final newWriter = createWriter(selection);
        newWriter.save(initial);
        await newWriter.flush();

        final restored = await repository.loadHistory();
        final recorded = restored.singleWhere(
          (entry) => entry.selection.ref == selection.ref,
        );
        expect(recorded.position, initial.position);
      },
    );
  }

  test(
    'history retains latest 500 entries with accepted metadata and completion',
    () async {
      final database = RecordDatabase.memory();
      final repository = DriftHistoryRepository(database);

      try {
        for (var id = 0; id < 502; id++) {
          final viewed = entry(id);
          await repository.openSession(viewed.selection.ref)(viewed);
        }
        final rows = await repository.loadHistory();
        expect(rows, hasLength(500));
        expect(rows.first.selection.content.id, '501');
        expect(rows.last.selection.content.id, '2');
        expect(rows.first.selection.content.title, 'Accepted title 501');
        final finished = entry(501, position: 95);
        await repository.openSession(finished.selection.ref)(finished);
        expect((await repository.loadHistory()).first.completed, isTrue);
        await repository.remove(entry(501).selection.ref);
        expect(
          (await repository.loadHistory()).first.selection.content.id,
          '500',
        );
        final empty = repository.watchHistory().firstWhere(
          (rows) => rows.isEmpty,
        );
        await repository.clear();
        expect(await empty, isEmpty);
      } finally {
        await database.close();
      }
    },
  );
}
