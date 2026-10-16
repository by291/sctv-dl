import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/playback/drift_history_repository.dart';
import 'package:sctv_dl_mobile/domain/playback/history_repository.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';

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
  test(
    'history retains latest 500 entries with accepted metadata and completion',
    () async {
      final database = RecordDatabase.memory();
      final repository = DriftHistoryRepository(database);

      try {
        for (var id = 0; id < 502; id++) {
          await repository.save(entry(id));
        }
        final rows = await repository.loadHistory();
        expect(rows, hasLength(500));
        expect(rows.first.selection.content.id, '501');
        expect(rows.last.selection.content.id, '2');
        expect(rows.first.selection.content.title, 'Accepted title 501');
        await repository.save(entry(501, position: 95));
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
