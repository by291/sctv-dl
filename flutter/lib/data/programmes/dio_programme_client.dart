import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../domain/programmes/programme.dart';
import '../../domain/programmes/programme_repository.dart';
import '../settings/installation_identity.dart';
import 'programme_parser.dart';

enum ProgrammeFailureKind {
  timeout,
  http,
  business,
  malformed,
  network,
  storage,
}

class ProgrammeFailure implements Exception {
  const ProgrammeFailure(this.kind, this.message, {this.cause});

  final ProgrammeFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Metadata-only transport. Media and image adapters must not reuse this client.
class DioProgrammeClient {
  DioProgrammeClient({
    required this._identity,
    Dio? dio,
    Uri? origin,
    this.timeout = const Duration(seconds: 20),
  }) : _dio = dio ?? Dio(),
       _ownsDio = dio == null,
       _origin = origin ?? Uri.parse('https://gw.scgchc.com') {
    _dio.options.connectTimeout = timeout;
  }

  static const maximumBodyBytes = 2 * 1024 * 1024;

  final InstallationIdentity _identity;
  final Dio _dio;
  final bool _ownsDio;
  final Uri _origin;
  final Duration timeout;

  final Set<CancelToken> _requests = {};
  bool _closed = false;

  Future<List<Programme>> programmes({RequestScope? scope}) async => _parse(
    ProgrammeParser.programmes,
    await _request('/app/v1/programs?page=0&size=100', scope),
  );

  Future<List<BroadcastDate>> dates(
    String programmeId, {
    RequestScope? scope,
  }) async => _parse(
    ProgrammeParser.dates,
    await _request(
      '/app/v1/programs/${ProgrammeParser.id(programmeId)}/dates/list',
      scope,
    ),
  );

  Future<List<ProgrammeContent>> contents(
    String programmeId,
    String dateId, {
    RequestScope? scope,
  }) async => _parse(
    ProgrammeParser.contents,
    await _request(
      '/app/v1/programs/${ProgrammeParser.id(programmeId)}/dates/${ProgrammeParser.id(dateId)}/contents/list',
      scope,
    ),
  );

  T _parse<T>(T Function(Object?) parse, Object? value) {
    try {
      return parse(value);
    } on FormatException catch (error) {
      throw ProgrammeFailure(
        ProgrammeFailureKind.malformed,
        '节目服务数据格式异常',
        cause: error,
      );
    }
  }

  Future<Object?> _request(String path, RequestScope? scope) async {
    if (_closed) throw StateError('Programme client is closed');
    scope?.throwIfCancelled();

    final cancel = CancelToken();
    _requests.add(cancel);
    final unsubscribe = scope?.onCancel(() => cancel.cancel());
    ResponseBody? body;

    try {
      Map<String, String> headers;
      try {
        headers = await _identity.headers();
      } catch (error) {
        throw ProgrammeFailure(
          ProgrammeFailureKind.storage,
          '无法保存安装信息',
          cause: error,
        );
      }
      scope?.throwIfCancelled();
      if (cancel.isCancelled) throw const RequestCancelled();

      final response = await _dio.getUri<ResponseBody>(
        _origin.resolve(path),
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          followRedirects: false,
          maxRedirects: 0,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (_) => true,
        ),
      );
      body = response.data;
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw ProgrammeFailure(
          ProgrammeFailureKind.http,
          '节目服务请求失败（HTTP ${response.statusCode}）',
        );
      }
      if (body == null) throw const FormatException('Missing response body');

      final bytes = await _readBody(body, cancel).timeout(
        timeout,
        onTimeout: () {
          cancel.cancel();
          throw const ProgrammeFailure(
            ProgrammeFailureKind.timeout,
            '节目服务响应超时，请稍后重试',
          );
        },
      );
      scope?.throwIfCancelled();

      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map<String, Object?> ||
          raw['rs'] is! num ||
          !raw.containsKey('data')) {
        throw const FormatException('Invalid programme envelope');
      }

      if (raw['rs'] != 200) {
        throw ProgrammeFailure(
          ProgrammeFailureKind.business,
          raw['error'] is String ? raw['error'] as String : '节目服务暂时不可用',
        );
      }

      return raw['data'];
    } on DioException catch (error) {
      if (cancel.isCancelled || error.type == DioExceptionType.cancel) {
        throw const RequestCancelled();
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        throw ProgrammeFailure(
          ProgrammeFailureKind.timeout,
          '节目服务响应超时，请稍后重试',
          cause: error,
        );
      }

      throw ProgrammeFailure(
        ProgrammeFailureKind.network,
        '无法连接节目服务，请稍后重试',
        cause: error,
      );
    } on FormatException catch (error) {
      throw ProgrammeFailure(
        ProgrammeFailureKind.malformed,
        '节目服务数据格式异常',
        cause: error,
      );
    } finally {
      // Cancelling the public token closes an unread/error response as well as
      // detaching Dio's body timers. Completed responses are already drained.
      cancel.cancel();
      unsubscribe?.call();
      _requests.remove(cancel);
    }
  }

  Future<Uint8List> _readBody(ResponseBody body, CancelToken cancel) async {
    if (body.contentLength > maximumBodyBytes) {
      cancel.cancel();
      throw const ProgrammeFailure(
        ProgrammeFailureKind.malformed,
        '节目服务数据超过大小限制',
      );
    }

    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maximumBodyBytes) {
        cancel.cancel();
        throw const ProgrammeFailure(
          ProgrammeFailureKind.malformed,
          '节目服务数据超过大小限制',
        );
      }

      bytes.add(chunk);
    }

    return bytes.takeBytes();
  }

  void close() {
    if (_closed) return;

    _closed = true;
    for (final request in _requests) {
      request.cancel();
    }

    if (_ownsDio) _dio.close(force: true);
  }
}
