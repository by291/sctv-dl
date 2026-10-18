import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'record_database.g.dart';

@DataClassName('StoredRecord')
class StoredRecords extends Table {
  TextColumn get collection => text()();
  TextColumn get key => text()();
  TextColumn get payload => text()();

  @override
  Set<Column<Object>> get primaryKey => {collection, key};
}

/// A transactional JSON index. Use distinct files for user and runtime state.
@DriftDatabase(tables: [StoredRecords])
class RecordDatabase extends _$RecordDatabase {
  RecordDatabase(super.executor);

  RecordDatabase.open(File file)
    : super(NativeDatabase.createInBackground(file));

  RecordDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  Future<Map<String, Object?>?> read(String collection, String key) async {
    final row =
        await (select(storedRecords)..where(
              (row) => row.collection.equals(collection) & row.key.equals(key),
            ))
            .getSingleOrNull();

    return row == null ? null : _decode(row.payload);
  }

  Future<Map<String, Map<String, Object?>>> all(String collection) async =>
      _decodeRows(await _collection(collection).get());

  Future<void> write(
    String collection,
    String key,
    Map<String, Object?> value,
  ) async {
    await into(storedRecords).insertOnConflictUpdate(
      StoredRecordsCompanion.insert(
        collection: collection,
        key: key,
        payload: jsonEncode(value),
      ),
    );
  }

  Future<void> remove(String collection, String key) async {
    await (delete(storedRecords)..where(
          (row) => row.collection.equals(collection) & row.key.equals(key),
        ))
        .go();
  }

  Future<void> clearCollection(String collection) async {
    await (delete(
      storedRecords,
    )..where((row) => row.collection.equals(collection))).go();
  }

  Stream<Map<String, Map<String, Object?>>> watch(String collection) =>
      _collection(collection).watch().map(_decodeRows);

  SimpleSelectStatement<StoredRecords, StoredRecord> _collection(
    String collection,
  ) => select(storedRecords)..where((row) => row.collection.equals(collection));

  Map<String, Map<String, Object?>> _decodeRows(List<StoredRecord> rows) => {
    for (final row in rows) row.key: _decode(row.payload),
  };

  Map<String, Object?> _decode(String value) =>
      Map<String, Object?>.from(jsonDecode(value) as Map);
}
