import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sctv_dl_mobile/platform/images/strict_cover_client.dart';

void main() {
  test(
    'cover redirects are rejected and cannot carry requests to another host',
    () async {
      bool? followed;
      final client = StrictCoverClient(
        client: MockClient((request) async {
          followed = request.followRedirects;
          return http.Response(
            '',
            302,
            headers: {'location': 'https://other.example/cover.jpg'},
          );
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('https://kscgc.sctv.com/cover.jpg')),
        throwsException,
      );
      expect(followed, isFalse);
    },
  );
  test(
    'unrecognized cover hosts are rejected before the network is called',
    () async {
      var requests = 0;
      final client = StrictCoverClient(
        client: MockClient((request) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.parse('https://other.example/cover.jpg')),
        throwsException,
      );
      expect(requests, 0);
    },
  );
}
