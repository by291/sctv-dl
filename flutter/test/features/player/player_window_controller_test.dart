import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sctv_dl_mobile/features/player/player_window_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed orientation restoration still restores system UI', () async {
    final requests = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          requests.add(call.method);
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            throw PlatformException(code: 'orientation');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final window = PlayerWindowController();

    await expectLater(
      window.setFullscreen(false),
      throwsA(isA<PlatformException>()),
    );

    expect(requests, [
      'SystemChrome.setPreferredOrientations',
      'SystemChrome.setEnabledSystemUIMode',
    ]);
  });
}
