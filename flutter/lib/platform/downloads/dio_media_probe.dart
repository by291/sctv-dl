import 'dart:async';

import 'package:dio/dio.dart';

import '../../domain/downloads/media_probe.dart';
import '../../domain/programmes/programme_policy.dart';
import '../../domain/programmes/programme_repository.dart';

/// A separate media transport has no metadata identity or guest headers. Probe
/// responses are streamed and immediately closed, even if Range is ignored.
class DioMediaProbe implements DownloadMediaProbe {
  DioMediaProbe({required this.appVersion, Dio Function()? createClient})
    : _createClient =
          createClient ??
          (() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 15))));

  final String appVersion;
  final Dio Function() _createClient;

  final _clients = <Dio>{};

  @override
  Future<void> validate(String url, {required RequestScope scope}) async {
    if (!isAllowedMediaUrl(url)) {
      throw ArgumentError.value(url, 'url', 'Unsupported media target');
    }
    scope.throwIfCancelled();

    final head = await _request(url, 'HEAD', scope);
    if (head.statusCode == 405 || head.statusCode == 501) {
      final range = await _request(url, 'GET', scope);
      _validateResponse(range);
    } else {
      _validateResponse(head);
    }

    scope.throwIfCancelled();
  }

  Future<Response<ResponseBody>> _request(
    String url,
    String method,
    RequestScope scope,
  ) async {
    final client = _createClient();
    _clients.add(client);
    final token = CancelToken();
    final removeListener = scope.onCancel(
      () => token.cancel('Download preparation cancelled'),
    );
    Response<ResponseBody>? response;

    try {
      response = await client.request<ResponseBody>(
        url,
        cancelToken: token,
        options: Options(
          method: method,
          responseType: ResponseType.stream,
          followRedirects: false,
          maxRedirects: 0,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (_) => true,
          headers: {
            'Referer': 'https://scgc.video.play/',
            'User-Agent': 'sctv-dl/$appVersion',
            if (method == 'GET') 'Range': 'bytes=0-1023',
          },
        ),
      );
      scope.throwIfCancelled();
      return response;
    } on DioException {
      scope.throwIfCancelled();
      rethrow;
    } finally {
      removeListener();

      // Stream cancellation and transport cancellation both matter: the former
      // releases Dart listeners; the latter aborts an unread native response.
      await response?.data?.stream.listen((_) {}).cancel();
      if (!token.isCancelled) {
        token.cancel('Probe headers received; body is not needed');
      }

      client.close(force: true);
      _clients.remove(client);
    }
  }

  void _validateResponse(Response<ResponseBody> response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) throw StateError('媒体探测失败: HTTP $status');

    final type = response.headers
        .value(Headers.contentTypeHeader)
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (type != null &&
        type != 'video/mp4' &&
        type != 'application/octet-stream' &&
        type != 'binary/octet-stream') {
      throw StateError('视频源返回了不支持的内容类型: $type');
    }
  }

  @override
  void dispose() {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}
