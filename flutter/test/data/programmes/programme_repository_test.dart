import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/data/database/record_database.dart';
import 'package:sctv_dl_mobile/data/programmes/cached_programme_repository.dart';
import 'package:sctv_dl_mobile/data/programmes/dio_programme_client.dart';
import 'package:sctv_dl_mobile/data/settings/installation_identity.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';

void main() {
  late RecordDatabase database;
  late HttpServer server;
  late DioProgrammeClient client;
  late CachedProgrammeRepository repository;
  late Future<void> Function(HttpRequest) respond;

  setUp(() async {
    database = RecordDatabase.memory();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    respond = (request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'rs': 200,
          'data': {'records': []},
        }),
      );
      await request.response.close();
    };
    server.listen((request) => unawaited(respond(request)));
    client = DioProgrammeClient(
      identity: InstallationIdentity(
        database,
        profile: const MetadataDeviceProfile.iosCompatibility(),
      ),
      origin: Uri.parse('http://${server.address.address}:${server.port}'),
      timeout: const Duration(seconds: 2),
    );
    repository = CachedProgrammeRepository(database: database, client: client);
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await database.close();
  });

  test(
    'successful empty snapshots are cached and failed refresh preserves them',
    () async {
      expect(await repository.cachedProgrammes(), isNull);
      final first = await repository.refreshProgrammes();
      expect(first.items, isEmpty);
      expect((await repository.cachedProgrammes())?.revision, first.revision);

      respond = (request) async {
        request.response.write(
          jsonEncode({'rs': 500, 'error': 'fixture unavailable', 'data': null}),
        );
        await request.response.close();
      };
      await expectLater(
        repository.refreshProgrammes(),
        throwsA(
          isA<ProgrammeFailure>().having(
            (failure) => failure.kind,
            'kind',
            ProgrammeFailureKind.business,
          ),
        ),
      );
      expect((await repository.cachedProgrammes())?.revision, first.revision);
    },
  );

  test(
    'metadata profile and exact endpoint are used without media headers',
    () async {
      final incoming = Completer<HttpRequest>();
      respond = (request) async {
        incoming.complete(request);
        request.response.write(
          jsonEncode({
            'rs': 200,
            'data': {'records': []},
          }),
        );
        await request.response.close();
      };

      await repository.refreshProgrammes();
      final request = await incoming.future;
      expect(request.uri.path, '/app/v1/programs');
      expect(request.uri.queryParameters, {'page': '0', 'size': '100'});
      expect(request.method, 'GET');
      expect(request.headers.value('deviceModel'), 'Pixel 8');
      expect(request.headers.value('User-Agent'), 'okhttp/4.12.0');
      expect(request.headers.value('Referer'), isNull);
    },
  );

  test('redirects are rejected without requesting their destination', () async {
    var requests = 0;
    respond = (request) async {
      requests++;
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(HttpHeaders.locationHeader, '/redirected');
      await request.response.close();
    };

    await expectLater(
      repository.refreshProgrammes(),
      throwsA(
        isA<ProgrammeFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProgrammeFailureKind.http,
        ),
      ),
    );
    expect(requests, 1);
  });

  test(
    'metadata connections are given a bounded connection deadline',
    () async {
      final transport = Dio();
      final bounded = DioProgrammeClient(
        identity: InstallationIdentity(
          database,
          profile: const MetadataDeviceProfile.iosCompatibility(),
        ),
        dio: transport,
        timeout: const Duration(milliseconds: 75),
      );
      try {
        // This is the request configuration our boundary hands to the adapter.
        expect(
          transport.options.connectTimeout,
          const Duration(milliseconds: 75),
        );
      } finally {
        bounded.close();
        transport.close(force: true);
      }
    },
  );

  test(
    'malformed JSON and impossible envelope shapes are distinguished',
    () async {
      for (final body in [
        'not json',
        '{"rs":"200","data":[]}',
        '{"rs":200}',
        '{"rs":200,"data":[]}',
      ]) {
        respond = (request) async {
          request.response.write(body);
          await request.response.close();
        };
        await expectLater(
          repository.refreshProgrammes(),
          throwsA(
            isA<ProgrammeFailure>().having(
              (failure) => failure.kind,
              'kind',
              ProgrammeFailureKind.malformed,
            ),
          ),
        );
      }
      expect(await repository.cachedProgrammes(), isNull);
    },
  );

  test('metadata body reception has a deadline after headers arrive', () async {
    client.close();
    client = DioProgrammeClient(
      identity: InstallationIdentity(
        database,
        profile: const MetadataDeviceProfile.iosCompatibility(),
      ),
      origin: Uri.parse('http://${server.address.address}:${server.port}'),
      timeout: const Duration(milliseconds: 75),
    );
    repository = CachedProgrammeRepository(database: database, client: client);
    respond = (request) async {
      request.response.write('{');
      await request.response.flush();
    };
    await expectLater(
      repository.refreshProgrammes(),
      throwsA(
        isA<ProgrammeFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProgrammeFailureKind.timeout,
        ),
      ),
    );
  });

  test('unchanged payloads retain revision while independent content keys stay separate', () async {
    respond = (request) async {
      request.response.write(
        jsonEncode({
          'rs': 200,
          'data': [
            {
              'id': request.uri.path.contains('/dates/2/') ? 20 : 30,
              'title': 'Clip',
            },
          ],
        }),
      );
      await request.response.close();
    };
    final first = await repository.refreshContents('1', '2');
    final again = await repository.refreshContents('1', '2');
    await repository.refreshContents('1', '3');
    expect(again.revision, first.revision);
    expect((await repository.cachedContents('1', '2'))?.items.single.id, '20');
    expect((await repository.cachedContents('1', '3'))?.items.single.id, '30');
  });

  for (final fixture in [
    (
      key: 'catalogue',
      rows: <Map<String, Object?>>[
        {
          'id': '1',
          'name': 'Programme',
          'cover': 'https://kscgc.sctv.com/a.jpg',
        },
        {'id': '2', 'name': 'Second'},
      ],
      refresh: () => repository.refreshProgrammes(),
    ),
    (
      key: 'dates/1',
      rows: <Map<String, Object?>>[
        {'id': '1', 'date': '2026-10-17'},
        {'id': '2', 'date': '2026-10-16'},
      ],
      refresh: () => repository.refreshDates('1'),
    ),
    (
      key: 'contents/1/2',
      rows: <Map<String, Object?>>[
        {
          'id': '1',
          'title': 'Clip',
          'cover': 'https://kscgc.sctv.com/a.jpg',
          'video': 'https://fscgc.scgchc.com/a.mp4',
          'videoStandard': 'https://fscgc.scgchc.com/b.mp4',
          'pubTime': '18:30:00',
        },
        {'id': '2', 'title': 'Second'},
      ],
      refresh: () => repository.refreshContents('1', '2'),
    ),
  ]) {
    test(
      '${fixture.key} compares effective fields rather than JSON encoding',
      () async {
        var rows = fixture.rows;
        respond = (request) async {
          request.response.write(
            jsonEncode({
              'rs': 200,
              'data': fixture.key == 'catalogue' ? {'records': rows} : rows,
            }),
          );
          await request.response.close();
        };
        final first = await fixture.refresh();
        final saved = (await database.read(
          'programme_snapshots',
          fixture.key,
        ))!;
        // Older writers may omit nulls, use numeric IDs or order keys differently.
        await database.write('programme_snapshots', fixture.key, {
          ...saved,
          'items': [
            for (final row in fixture.rows)
              <String, Object?>{
                'ignoredMetadata': 'old',
                for (final entry in row.entries.toList().reversed)
                  entry.key: entry.key == 'id'
                      ? int.parse(entry.value! as String)
                      : entry.value,
              },
          ],
        });
        expect((await fixture.refresh()).revision, first.revision);

        for (final field in fixture.rows.first.keys) {
          final before = await fixture.refresh();
          final original = fixture.rows.first[field]! as String;
          final changed = field == 'id'
              ? '3'
              : field == 'date'
              ? '2026-10-18'
              : '$original-changed';
          rows = [
            {...fixture.rows.first, field: changed},
            fixture.rows.last,
          ];
          final update = await fixture.refresh();
          expect(update.revision, isNot(before.revision), reason: field);
          rows = fixture.rows;
          final restored = await fixture.refresh();
          expect(restored.revision, isNot(update.revision), reason: field);
        }
        final beforeReorder = await fixture.refresh();
        rows = fixture.rows.reversed.toList();
        final reordered = await fixture.refresh();
        // Dates are normalized into descending display order before comparison.
        expect(
          reordered.revision,
          fixture.key.startsWith('dates/')
              ? beforeReorder.revision
              : isNot(beforeReorder.revision),
        );
        rows = [fixture.rows.first];
        final removed = await fixture.refresh();
        expect(removed.revision, isNot(reordered.revision));
        rows = fixture.rows;
        expect((await fixture.refresh()).revision, isNot(removed.revision));

        // A successful refresh must still repair an unreadable old snapshot.
        await database.write('programme_snapshots', fixture.key, {
          ...saved,
          'items': 'corrupt',
        });
        expect((await fixture.refresh()).items, hasLength(2));
      },
    );
  }

  test(
    'stale results are rejected even when the transport ignores cancellation',
    () async {
      final controlled = ControlledProgrammeClient(database);
      final guarded = CachedProgrammeRepository(
        database: database,
        client: controlled,
      );
      final first = guarded.refreshContents('1', '2');
      final rejected = expectLater(first, throwsA(isA<RequestCancelled>()));
      final second = guarded.refreshContents('1', '2');
      controlled.calls[1].complete([
        const ProgrammeContent(id: '20', title: 'new'),
      ]);
      await second;
      controlled.calls[0].complete([
        const ProgrammeContent(id: '10', title: 'old'),
      ]);
      await rejected;
      expect((await guarded.cachedContents('1', '2'))?.items.single.id, '20');
      controlled.close();
    },
  );

  test('an obsolete request failure is rejected as cancellation', () async {
    final controlled = ControlledProgrammeClient(database);
    final guarded = CachedProgrammeRepository(
      database: database,
      client: controlled,
    );
    final first = guarded.refreshContents('1', '2');
    final rejected = expectLater(first, throwsA(isA<RequestCancelled>()));
    final second = guarded.refreshContents('1', '2');
    controlled.calls[1].complete([
      const ProgrammeContent(id: '20', title: 'new'),
    ]);
    await second;
    controlled.calls[0].completeError(
      const ProgrammeFailure(
        ProgrammeFailureKind.business,
        'obsolete fixture failure',
      ),
    );
    await rejected;
    expect((await guarded.cachedContents('1', '2'))?.items.single.id, '20');
    controlled.close();
  });

  test('metadata bodies are bounded even without Content-Length', () async {
    respond = (request) async {
      request.response.write(' ' * (2 * 1024 * 1024 + 1));
      await request.response.close();
    };

    await expectLater(
      repository.refreshProgrammes(),
      throwsA(
        isA<ProgrammeFailure>().having(
          (failure) => failure.kind,
          'kind',
          ProgrammeFailureKind.malformed,
        ),
      ),
    );
    expect(await repository.cachedProgrammes(), isNull);
  });

  test(
    'newer requests win and late cancelled replies cannot replace cache',
    () async {
      final pending = <HttpRequest>[];
      final arrivals = StreamController<int>();
      respond = (request) async {
        pending.add(request);
        arrivals.add(pending.length);
      };
      final firstArrived = arrivals.stream.first;
      final first = repository.refreshContents('1', '2');
      final firstFailure = expectLater(first, throwsA(isA<RequestCancelled>()));
      await firstArrived;
      final second = repository.refreshContents('1', '2');
      while (pending.length < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      pending[1].response.write(
        jsonEncode({
          'rs': 200,
          'data': [
            {'id': 22, 'title': 'new'},
          ],
        }),
      );
      await pending[1].response.close();
      await second;
      pending[0].response.write(
        jsonEncode({
          'rs': 200,
          'data': [
            {'id': 11, 'title': 'old'},
          ],
        }),
      );
      await pending[0].response.close();
      await firstFailure;

      expect(
        (await repository.cachedContents('1', '2'))?.items.single.id,
        '22',
      );
      expect(await repository.cachedContents('1', '3'), isNull);
      await arrivals.close();
    },
  );

  test('scope cancellation rejects pending work and cache cleanup preserves user tasks', () async {
    final arrived = Completer<HttpRequest>();
    respond = (request) async => arrived.complete(request);
    final scope = RequestScope();
    final request = repository.refreshDates('7', scope: scope);
    final failure = expectLater(request, throwsA(isA<RequestCancelled>()));
    final incoming = await arrived.future;
    scope.cancel();
    await failure;
    incoming.response.write(jsonEncode({'rs': 200, 'data': []}));
    await incoming.response.close();

    await database.write('favourites', '1', {'id': '1'});
    await database.write('download_tasks', 'task', {'state': 'running'});
    await repository.clearCache();
    expect(await repository.cachedDates('7'), isNull);
    expect(await database.read('favourites', '1'), isNotNull);
    expect(await database.read('download_tasks', 'task'), isNotNull);
    expect(await database.read('installation', 'metadata_identity'), isNotNull);
  });
}

class ControlledProgrammeClient extends DioProgrammeClient {
  ControlledProgrammeClient(RecordDatabase database)
    : super(
        identity: InstallationIdentity(
          database,
          profile: const MetadataDeviceProfile.iosCompatibility(),
        ),
      );

  final calls = <Completer<List<ProgrammeContent>>>[];

  @override
  Future<List<ProgrammeContent>> contents(
    String programmeId,
    String dateId, {
    RequestScope? scope,
  }) {
    final result = Completer<List<ProgrammeContent>>();
    calls.add(result);
    return result.future;
  }
}
