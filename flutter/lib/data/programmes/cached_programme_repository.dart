import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_repository.dart';
import '../database/record_database.dart';
import 'dio_programme_client.dart';
import 'programme_codec.dart';
import 'programme_parser.dart';

class CachedProgrammeRepository implements ProgrammeRepository {
  CachedProgrammeRepository({required this._database, required this._client});

  final RecordDatabase _database;
  final DioProgrammeClient _client;
  final Map<String, RequestScope> _requests = {};
  Future<void> _writes = Future<void>.value();

  @override
  Future<ProgrammeSnapshot<Programme>?> cachedProgrammes() => _cached(
    'catalogue',
    (items) => ProgrammeParser.programmes({'records': items}),
  );

  @override
  Future<ProgrammeSnapshot<Programme>> refreshProgrammes({
    RequestScope? scope,
  }) => _refresh(
    'catalogue',
    (request) => _client.programmes(scope: request),
    encodeProgramme,
    scope,
  );

  @override
  Future<ProgrammeSnapshot<BroadcastDate>?> cachedDates(String programmeId) =>
      _cached(
        'dates/${ProgrammeParser.id(programmeId)}',
        ProgrammeParser.dates,
      );

  @override
  Future<ProgrammeSnapshot<BroadcastDate>> refreshDates(
    String programmeId, {
    RequestScope? scope,
  }) => _refresh(
    'dates/${ProgrammeParser.id(programmeId)}',
    (request) => _client.dates(programmeId, scope: request),
    encodeBroadcast,
    scope,
  );

  @override
  Future<ProgrammeSnapshot<ProgrammeContent>?> cachedContents(
    String programmeId,
    String dateId,
  ) => _cached(
    'contents/${ProgrammeParser.id(programmeId)}/${ProgrammeParser.id(dateId)}',
    ProgrammeParser.contents,
  );

  @override
  Future<ProgrammeSnapshot<ProgrammeContent>> refreshContents(
    String programmeId,
    String dateId, {
    RequestScope? scope,
  }) => _refresh(
    'contents/${ProgrammeParser.id(programmeId)}/${ProgrammeParser.id(dateId)}',
    (request) => _client.contents(programmeId, dateId, scope: request),
    encodeContent,
    scope,
  );

  Future<ProgrammeSnapshot<T>?> _cached<T>(
    String key,
    List<T> Function(Object?) parse,
  ) async {
    try {
      final row = await _database.read('programme_snapshots', key);
      if (row == null) return null;
      return ProgrammeSnapshot(
        items: parse(row['items']),
        revision: row['revision'] as String,
        fetchedAt: DateTime.parse(row['fetchedAt'] as String),
      );
    } catch (error) {
      throw ProgrammeFailure(
        ProgrammeFailureKind.storage,
        '无法读取节目缓存',
        cause: error,
      );
    }
  }

  Future<ProgrammeSnapshot<T>> _refresh<T>(
    String key,
    Future<List<T>> Function(RequestScope) load,
    Map<String, Object?> Function(T) encode,
    RequestScope? parent,
  ) async {
    parent?.throwIfCancelled();
    _requests[key]?.cancel();
    final request = RequestScope();
    _requests[key] = request;
    final unsubscribe = parent?.onCancel(request.cancel);

    void ensureCurrent() {
      request.throwIfCancelled();
      if (!identical(_requests[key], request)) throw const RequestCancelled();
    }

    try {
      final items = await load(request);
      ensureCurrent();
      final serialized = items.map(encode).toList();
      final saved = _writes.then(
        (_) => _database.transaction(() async {
          // Checking inside the serialized write closes the response/write race.
          ensureCurrent();
          final existing = await _database.read('programme_snapshots', key);
          ensureCurrent();
          final revision =
              existing != null &&
                  jsonEncode(existing['items']) == jsonEncode(serialized)
              ? existing['revision'] as String
              : const Uuid().v4();
          final fetchedAt = DateTime.now().toUtc();
          await _database.write('programme_snapshots', key, {
            'version': 1,
            'items': serialized,
            'revision': revision,
            'fetchedAt': fetchedAt.toIso8601String(),
          });
          ensureCurrent();
          return ProgrammeSnapshot<T>(
            items: List.unmodifiable(items),
            revision: revision,
            fetchedAt: fetchedAt,
          );
        }),
      );
      _writes = saved.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      try {
        return await saved;
      } on RequestCancelled {
        rethrow;
      } catch (error) {
        throw ProgrammeFailure(
          ProgrammeFailureKind.storage,
          '无法保存节目缓存',
          cause: error,
        );
      }
    } catch (_) {
      // A superseded request must not expose its late failure to the new page.
      ensureCurrent();
      rethrow;
    } finally {
      unsubscribe?.call();
      if (identical(_requests[key], request)) _requests.remove(key);
    }
  }

  @override
  Future<void> clearCache() async {
    for (final request in _requests.values) {
      request.cancel();
    }
    _requests.clear();
    final cleared = _writes.then(
      (_) => _database.clearCollection('programme_snapshots'),
    );
    _writes = cleared.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      await cleared;
    } catch (error) {
      throw ProgrammeFailure(
        ProgrammeFailureKind.storage,
        '无法清理节目缓存',
        cause: error,
      );
    }
  }
}
