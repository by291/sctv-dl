import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/programmes/programme_policy.dart';

class StrictCoverClient extends http.BaseClient {
  StrictCoverClient({required this._client});
  final http.Client _client;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!isAllowedCoverUrl(request.url.toString())) {
      throw const HttpException('Unsupported cover target');
    }
    request.followRedirects = false;
    final response = await _client.send(request);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      await response.stream.listen((_) {}).cancel();
      throw const HttpException('Cover redirects are not allowed');
    }
    return response;
  }

  @override
  void close() => _client.close();
}
