import 'package:integration_test/integration_test.dart';

import '../test/app/router_test.dart' show registerDownloadNoticeTests;

/// Real navigation and Snackbar timing on the device, with download/playback
/// boundaries stubbed so no user media is created or deleted by this regression.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerDownloadNoticeTests();
}
