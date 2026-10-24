import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/domain/programmes/programme_repository.dart';
import 'package:sctv_dl_mobile/platform/downloads/dio_media_probe.dart';

void main() {
  late HttpServer server;
  late DioMediaProbe probe;
  final requests = <HttpRequest>[];
  final adapters = <LoopbackAdapter>[];
  setUp(() async {
    requests.clear();
    adapters.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    probe = DioMediaProbe(
      createClient: () {
        final adapter = LoopbackAdapter(server.port);
        adapters.add(adapter);
        return Dio()..httpClientAdapter = adapter;
      },
    );
  });
  tearDown(() async {
    probe.dispose();
    await server.close(force: true);
  });

  test('HEAD sends only media headers without fetching a video body', () async {
    server.listen((request) async {
      requests.add(request);
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 8192;
      await request.response.close();
    });
    await probe.validate(
      'https://fscgc.scgchc.com/video.mp4',
      scope: RequestScope(),
    );
    expect(requests.single.method, 'HEAD');
    expect(
      requests.single.headers.value('referer'),
      'https://scgc.video.play/',
    );
    expect(requests.single.headers.value('user-agent'), 'okhttp/4.12.0');
    expect(requests.single.headers.value('authorization'), isNull);
  });
  test('unsupported HEAD falls back to small Range and closes an ignored Range body', () async {
    var fixtureStopped = false;
    server.listen((request) async {
      requests.add(request);
      if (request.method == 'HEAD') {
        request.response.statusCode = 405;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.contentLength = 100 * 1024 * 1024;
      try {
        for (var index = 0; index < 1600 && !fixtureStopped; index++) {
          request.response.add(Uint8List(65536));
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      } catch (_) {
        // The client deliberately closes this oversized response.
      } finally {
        await request.response.close().catchError((_) {});
      }
    });
    await probe.validate(
      'https://fscgc.scgchc.com/video.mp4',
      scope: RequestScope(),
    );
    expect(requests.map((request) => request.method), ['HEAD', 'GET']);
    expect(requests.last.headers.value('range'), 'bytes=0-1023');
    expect(adapters, hasLength(2));
    expect(adapters.every((adapter) => adapter.closed), isTrue);
    expect(
      adapters.fold<int>(0, (count, adapter) => count + adapter.receivedBytes),
      lessThanOrEqualTo(65536),
    );
    fixtureStopped = true;
  });
  test('redirect and explicit non-video responses are rejected', () async {
    server.listen((request) async {
      requests.add(request);
      request.response.statusCode = request.uri.path == '/redirect.mp4'
          ? 302
          : 200;
      request.response.headers.set('location', '/video.mp4');
      request.response.headers.contentType = ContentType.html;
      await request.response.close();
    });
    for (final path in ['redirect.mp4', 'html.mp4']) {
      await expectLater(
        probe.validate('https://fscgc.scgchc.com/$path', scope: RequestScope()),
        throwsStateError,
      );
    }
    expect(requests, hasLength(2));
  });
  test('cancellation aborts an outstanding header request', () async {
    final entered = Completer<void>();
    server.listen((request) {
      entered.complete();
    });
    final scope = RequestScope();
    final result = probe.validate(
      'https://fscgc.scgchc.com/video.mp4',
      scope: scope,
    );
    final expectation = expectLater(result, throwsA(isA<RequestCancelled>()));
    await entered.future;
    scope.cancel();
    await expectation;
  });
}

/// Route an allowed production URL to a disposable loopback fixture. Production
/// validation remains enabled; only this test transport changes the socket URL.
class LoopbackAdapter implements HttpClientAdapter {
  LoopbackAdapter(this.port);
  final int port;
  final delegate = IOHttpClientAdapter();
  bool closed = false;
  int receivedBytes = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await delegate.fetch(
      options.copyWith(path: 'http://127.0.0.1:$port${options.uri.path}'),
      requestStream,
      cancelFuture,
    );
    response.stream = response.stream.map((chunk) {
      receivedBytes += chunk.length;
      return chunk;
    });
    return response;
  }

  @override
  void close({bool force = false}) {
    closed = true;
    delegate.close(force: force);
  }
}
