// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'record_database.dart';

// ignore_for_file: type=lint
class $StoredRecordsTable extends StoredRecords
    with TableInfo<$StoredRecordsTable, StoredRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _collectionMeta = const VerificationMeta(
    'collection',
  );
  @override
  late final GeneratedColumn<String> collection = GeneratedColumn<String>(
    'collection',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [collection, key, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('collection')) {
      context.handle(
        _collectionMeta,
        collection.isAcceptableOrUnknown(data['collection']!, _collectionMeta),
      );
    } else if (isInserting) {
      context.missing(_collectionMeta);
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {collection, key};
  @override
  StoredRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredRecord(
      collection: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collection'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $StoredRecordsTable createAlias(String alias) {
    return $StoredRecordsTable(attachedDatabase, alias);
  }
}

class StoredRecord extends DataClass implements Insertable<StoredRecord> {
  final String collection;
  final String key;
  final String payload;
  const StoredRecord({
    required this.collection,
    required this.key,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['collection'] = Variable<String>(collection);
    map['key'] = Variable<String>(key);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  StoredRecordsCompanion toCompanion(bool nullToAbsent) {
    return StoredRecordsCompanion(
      collection: Value(collection),
      key: Value(key),
      payload: Value(payload),
    );
  }

  factory StoredRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredRecord(
      collection: serializer.fromJson<String>(json['collection']),
      key: serializer.fromJson<String>(json['key']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'collection': serializer.toJson<String>(collection),
      'key': serializer.toJson<String>(key),
      'payload': serializer.toJson<String>(payload),
    };
  }

  StoredRecord copyWith({String? collection, String? key, String? payload}) =>
      StoredRecord(
        collection: collection ?? this.collection,
        key: key ?? this.key,
        payload: payload ?? this.payload,
      );
  StoredRecord copyWithCompanion(StoredRecordsCompanion data) {
    return StoredRecord(
      collection: data.collection.present
          ? data.collection.value
          : this.collection,
      key: data.key.present ? data.key.value : this.key,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredRecord(')
          ..write('collection: $collection, ')
          ..write('key: $key, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(collection, key, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredRecord &&
          other.collection == this.collection &&
          other.key == this.key &&
          other.payload == this.payload);
}

class StoredRecordsCompanion extends UpdateCompanion<StoredRecord> {
  final Value<String> collection;
  final Value<String> key;
  final Value<String> payload;
  final Value<int> rowid;
  const StoredRecordsCompanion({
    this.collection = const Value.absent(),
    this.key = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredRecordsCompanion.insert({
    required String collection,
    required String key,
    required String payload,
    this.rowid = const Value.absent(),
  }) : collection = Value(collection),
       key = Value(key),
       payload = Value(payload);
  static Insertable<StoredRecord> custom({
    Expression<String>? collection,
    Expression<String>? key,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (collection != null) 'collection': collection,
      if (key != null) 'key': key,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredRecordsCompanion copyWith({
    Value<String>? collection,
    Value<String>? key,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return StoredRecordsCompanion(
      collection: collection ?? this.collection,
      key: key ?? this.key,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (collection.present) {
      map['collection'] = Variable<String>(collection.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredRecordsCompanion(')
          ..write('collection: $collection, ')
          ..write('key: $key, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$RecordDatabase extends GeneratedDatabase {
  _$RecordDatabase(QueryExecutor e) : super(e);
  $RecordDatabaseManager get managers => $RecordDatabaseManager(this);
  late final $StoredRecordsTable storedRecords = $StoredRecordsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [storedRecords];
}

typedef $$StoredRecordsTableCreateCompanionBuilder =
    StoredRecordsCompanion Function({
      required String collection,
      required String key,
      required String payload,
      Value<int> rowid,
    });
typedef $$StoredRecordsTableUpdateCompanionBuilder =
    StoredRecordsCompanion Function({
      Value<String> collection,
      Value<String> key,
      Value<String> payload,
      Value<int> rowid,
    });

class $$StoredRecordsTableFilterComposer
    extends Composer<_$RecordDatabase, $StoredRecordsTable> {
  $$StoredRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredRecordsTableOrderingComposer
    extends Composer<_$RecordDatabase, $StoredRecordsTable> {
  $$StoredRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredRecordsTableAnnotationComposer
    extends Composer<_$RecordDatabase, $StoredRecordsTable> {
  $$StoredRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get collection => $composableBuilder(
    column: $table.collection,
    builder: (column) => column,
  );

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$StoredRecordsTableTableManager
    extends
        RootTableManager<
          _$RecordDatabase,
          $StoredRecordsTable,
          StoredRecord,
          $$StoredRecordsTableFilterComposer,
          $$StoredRecordsTableOrderingComposer,
          $$StoredRecordsTableAnnotationComposer,
          $$StoredRecordsTableCreateCompanionBuilder,
          $$StoredRecordsTableUpdateCompanionBuilder,
          (
            StoredRecord,
            BaseReferences<_$RecordDatabase, $StoredRecordsTable, StoredRecord>,
          ),
          StoredRecord,
          PrefetchHooks Function()
        > {
  $$StoredRecordsTableTableManager(
    _$RecordDatabase db,
    $StoredRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> collection = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredRecordsCompanion(
                collection: collection,
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String collection,
                required String key,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => StoredRecordsCompanion.insert(
                collection: collection,
                key: key,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StoredRecordsTable, StoredRecord>(table),
                  BaseReferences<
                    _$RecordDatabase,
                    $StoredRecordsTable,
                    StoredRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$RecordDatabase,
      $StoredRecordsTable,
      StoredRecord,
      $$StoredRecordsTableFilterComposer,
      $$StoredRecordsTableOrderingComposer,
      $$StoredRecordsTableAnnotationComposer,
      $$StoredRecordsTableCreateCompanionBuilder,
      $$StoredRecordsTableUpdateCompanionBuilder,
      (
        StoredRecord,
        BaseReferences<_$RecordDatabase, $StoredRecordsTable, StoredRecord>,
      ),
      StoredRecord,
      PrefetchHooks Function()
    >;

class $RecordDatabaseManager {
  final _$RecordDatabase _db;
  $RecordDatabaseManager(this._db);
  $$StoredRecordsTableTableManager get storedRecords =>
      $$StoredRecordsTableTableManager(_db, _db.storedRecords);
}
