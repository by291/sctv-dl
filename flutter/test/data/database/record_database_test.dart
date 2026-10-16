import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';

void main() {
  test(
    'records survive reopening without crossing collection boundaries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'record-database-',
      );
      final file = File('${directory.path}/state.sqlite');
      var database = RecordDatabase.open(file);

      try {
        await database.write('user', 'same', {'value': 1});
        await database.write('runtime', 'same', {'value': 2});
        await database.close();
        database = RecordDatabase.open(file);

        expect(await database.read('user', 'same'), {'value': 1});
        await database.clearCollection('runtime');
        expect(await database.all('runtime'), isEmpty);
        expect(await database.all('user'), {
          'same': {'value': 1},
        });
        await database.remove('user', 'same');
        expect(await database.read('user', 'same'), isNull);
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'transactions roll back all writes and do not emit partial snapshots',
    () async {
      final database = RecordDatabase.memory();
      final snapshots = <Map<String, Map<String, Object?>>>[];
      final subscription = database.watch('tasks').listen(snapshots.add);

      try {
        await database.all('tasks');
        await expectLater(
          database.transaction(() async {
            await database.write('tasks', 'one', {'state': 'queued'});
            throw StateError('abort');
          }),
          throwsStateError,
        );
        expect(await database.all('tasks'), isEmpty);
        await database.transaction(() async {
          await database.write('tasks', 'one', {'state': 'queued'});
          await database.write('tasks', 'two', {'state': 'queued'});
        });
        await Future<void>.delayed(Duration.zero);

        expect(snapshots.where((value) => value.length == 1), isEmpty);
        expect(snapshots.last.keys, containsAll(['one', 'two']));
      } finally {
        await subscription.cancel();
        await database.close();
      }
    },
  );
}
